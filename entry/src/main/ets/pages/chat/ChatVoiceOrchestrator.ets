import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { ChatSessionController, ChatSessionViewState } from './ChatSessionController';
import {
  ChatVoiceMetadata,
  VoiceSessionController,
  VoiceSessionSnapshot,
  appendVoiceTranscriptToInput,
  createTtsVoiceMetadata,
  createTtsVoiceRuntimeMetadata,
  createVoiceErrorMetadata
} from './VoiceInteractionTypes';
import { ChatSessionStorage } from '../../utils/ChatSessionStorage';
import { HarmonyAudioPlayback } from '../../utils/voice/HarmonyAudioPlayback';
import { HarmonySpeechRecognizerAsrProvider } from '../../utils/voice/HarmonySpeechRecognizerAsrProvider';
import { MimoVoiceClient } from '../../utils/voice/MimoVoiceClient';
import { showToastSafely } from '../../utils/PromptSafe';

export interface ChatVoiceTtsConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  voice: string;
}

export interface ChatVoiceInputDraftTarget {
  id: string;
  text: string;
}

export interface ChatVoiceOrchestratorHost {
  filesDir: () => string;
  abilityContext: () => common.UIAbilityContext;
  activeSessionId: () => string;
  isBusy: () => boolean;
  activeInputDraftTarget: () => ChatVoiceInputDraftTarget;
  setInputDraftForTarget: (targetId: string, text: string) => void;
  currentChatSessionViewState: () => ChatSessionViewState;
  applyChatSessionViewState: (state: ChatSessionViewState) => void;
  ttsConfig: () => ChatVoiceTtsConfig;
  onSnapshot: (snapshot: VoiceSessionSnapshot) => void;
}

export function nextVoiceInputStartGeneration(currentGeneration: number): number {
  return currentGeneration + 1;
}

export function voiceInputStopGeneration(latestStartGeneration: number, previousStoppedGeneration: number): number {
  return Math.max(latestStartGeneration, previousStoppedGeneration);
}

export function voiceInputStartCanProceed(startGeneration: number, latestStartGeneration: number,
  stoppedGeneration: number): boolean {
  return startGeneration === latestStartGeneration && startGeneration > stoppedGeneration;
}

const VOICE_INPUT_STOP_FALLBACK_MS: number = 1500;

export class ChatVoiceOrchestrator {
  private host: ChatVoiceOrchestratorHost;
  private voiceController: VoiceSessionController = new VoiceSessionController();
  private asrProvider: HarmonySpeechRecognizerAsrProvider = new HarmonySpeechRecognizerAsrProvider();
  private voiceTtsClient: MimoVoiceClient = new MimoVoiceClient();
  private voiceAudioPlayback: HarmonyAudioPlayback = new HarmonyAudioPlayback();
  private handledVoiceTurnId: string = '';
  private voiceDraftTargetId: string = '';
  private voiceDraftBaseInput: string = '';
  private voicePlaybackGeneration: number = 0;
  private voicePlaybackSessionId: string = '';
  private voicePlaybackAudioUri: string = '';
  private voicePlaybackVoice: string = '';
  private voiceInputStartGeneration: number = 0;
  private voiceInputStoppedGeneration: number = 0;
  private voiceInputStopFallbackTimerId: number = -1;

  constructor(host: ChatVoiceOrchestratorHost) {
    this.host = host;
  }

  snapshot(): VoiceSessionSnapshot {
    return this.voiceController.snapshot();
  }

  private emitSnapshot(): void {
    this.host.onSnapshot(this.voiceController.snapshot());
  }

  private failVoiceInteraction(message: string): void {
    this.clearVoiceInputStopFallbackTimer();
    this.voiceController.fail(message);
    this.emitSnapshot();
    showToastSafely(message, 1800);
  }

  async toggleVoiceInput(): Promise<void> {
    let status = this.voiceController.snapshot().status;
    if (status === 'listening' || status === 'transcribing') {
      await this.stopVoiceInput();
      return;
    }
    if (status === 'speaking' || status === 'synthesizing') {
      await this.stopVoicePlayback();
      return;
    }
    if (this.host.isBusy()) {
      showToastSafely('当前正在处理消息，稍后再使用语音', 1600);
      return;
    }
    await this.startVoiceInput();
  }

  async stopVoiceInput(): Promise<void> {
    this.voiceInputStoppedGeneration = voiceInputStopGeneration(this.voiceInputStartGeneration,
      this.voiceInputStoppedGeneration);
    let snapshot = this.voiceController.snapshot();
    let status = snapshot.status;
    if (status === 'listening' || status === 'transcribing') {
      this.voiceController.markTranscribing();
      this.emitSnapshot();
      this.scheduleVoiceInputStopFallback(snapshot.turnId);
      this.asrProvider.finish();
    }
  }

  async playAssistantMessageVoice(messageId: string, text: string): Promise<void> {
    let sessionId = this.host.activeSessionId();
    await this.playAssistantMessageVoiceInSession(sessionId, messageId, text);
  }

  shutdown(): void {
    this.clearVoiceInputStopFallbackTimer();
    this.asrProvider.shutdown();
    this.voicePlaybackGeneration++;
    this.voiceAudioPlayback.stop().catch(() => {});
    this.voiceController.reset();
    this.voiceDraftTargetId = '';
    this.voiceDraftBaseInput = '';
    this.voiceInputStoppedGeneration = voiceInputStopGeneration(this.voiceInputStartGeneration,
      this.voiceInputStoppedGeneration);
    this.clearVoicePlaybackContext();
    this.emitSnapshot();
  }

  private async ensureMicrophonePermission(): Promise<boolean> {
    try {
      let permissions: Permissions[] = ['ohos.permission.MICROPHONE'];
      let result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.host.abilityContext(),
        permissions);
      for (let i = 0; i < result.permissions.length; i++) {
        if (result.permissions[i] === 'ohos.permission.MICROPHONE' && result.authResults[i] === 0) {
          return true;
        }
      }
      showToastSafely('需要麦克风权限才能语音输入', 1800);
      return false;
    } catch (e) {
      let err = e as Error;
      showToastSafely('麦克风权限请求失败：' + err.message, 1800);
      return false;
    }
  }

  private async startVoiceInput(): Promise<void> {
    this.clearVoiceInputStopFallbackTimer();
    let startGeneration = nextVoiceInputStartGeneration(this.voiceInputStartGeneration);
    this.voiceInputStartGeneration = startGeneration;
    let granted = await this.ensureMicrophonePermission();
    if (!granted) {
      return;
    }
    if (!this.voiceInputStartActive(startGeneration)) {
      return;
    }
    let turnId = 'voice-' + String(new Date().getTime());
    this.handledVoiceTurnId = '';
    let draftTarget = this.host.activeInputDraftTarget();
    this.voiceDraftTargetId = draftTarget.id;
    this.voiceDraftBaseInput = draftTarget.text;
    this.voiceController.beginListening(turnId);
    this.emitSnapshot();
    try {
      await this.asrProvider.start({
        onStart: (sessionId: string) => {
          if (sessionId !== turnId || !this.voiceTurnActive(turnId)) {
            return;
          }
          this.voiceController.beginListening(turnId);
          this.emitSnapshot();
        },
        onPartialTranscript: (transcript: string) => {
          if (!this.voiceTurnActive(turnId)) {
            return;
          }
          this.voiceController.updatePartialTranscript(transcript);
          this.applyVoiceTranscriptDraft(transcript);
          this.emitSnapshot();
        },
        onFinalTranscript: (transcript: string, isLast: boolean) => {
          if (!this.voiceTurnActive(turnId)) {
            return;
          }
          this.voiceController.completeTranscript(transcript);
          this.applyVoiceTranscriptDraft(transcript);
          this.emitSnapshot();
          if (isLast) {
            this.handleVoiceTranscriptComplete(transcript).catch((e: Error) => {
              this.failVoiceInteraction(e.message);
            });
          }
        },
        onComplete: (transcript: string) => {
          if (!this.voiceTurnActive(turnId)) {
            return;
          }
          this.handleVoiceTranscriptComplete(transcript).catch((e: Error) => {
            this.failVoiceInteraction(e.message);
          });
        },
        onError: (message: string) => {
          if (!this.voiceTurnActive(turnId)) {
            return;
          }
          this.failVoiceInteraction(message);
        }
      }, {
        language: 'zh-CN',
        sessionId: turnId
      });
      if (!this.voiceInputStartActive(startGeneration)) {
        if (this.voiceTurnActive(turnId)) {
          this.asrProvider.finish();
        }
      }
    } catch (e) {
      let err = e as Error;
      this.failVoiceInteraction(err.message);
    }
  }

  private voiceTurnActive(turnId: string): boolean {
    return this.voiceController.snapshot().turnId === turnId;
  }

  private voiceInputStartActive(startGeneration: number): boolean {
    return voiceInputStartCanProceed(startGeneration, this.voiceInputStartGeneration,
      this.voiceInputStoppedGeneration);
  }

  private clearVoiceInputStopFallbackTimer(): void {
    if (this.voiceInputStopFallbackTimerId !== -1) {
      clearTimeout(this.voiceInputStopFallbackTimerId);
      this.voiceInputStopFallbackTimerId = -1;
    }
  }

  private scheduleVoiceInputStopFallback(turnId: string): void {
    if (turnId.length === 0) {
      return;
    }
    this.clearVoiceInputStopFallbackTimer();
    // finish() 依赖系统 ASR 回调；部分设备静默或取消时可能不回调，用短超时防止 UI 长时间停在转写态。
    this.voiceInputStopFallbackTimerId = setTimeout(() => {
      this.voiceInputStopFallbackTimerId = -1;
      let snapshot = this.voiceController.snapshot();
      if (snapshot.turnId !== turnId) {
        return;
      }
      if (snapshot.status !== 'listening' && snapshot.status !== 'transcribing') {
        return;
      }
      let transcript = snapshot.finalTranscript.trim().length > 0 ? snapshot.finalTranscript : snapshot.partialTranscript;
      if (transcript.trim().length > 0) {
        this.handleVoiceTranscriptComplete(transcript).catch((e: Error) => {
          this.failVoiceInteraction(e.message);
        });
        return;
      }
      this.finishVoiceInputWithoutTranscript();
    }, VOICE_INPUT_STOP_FALLBACK_MS);
  }

  private shouldHandleVoiceTranscriptComplete(snapshot: VoiceSessionSnapshot): boolean {
    if (snapshot.turnId.length === 0) {
      return false;
    }
    if (this.handledVoiceTurnId === snapshot.turnId) {
      return false;
    }
    this.handledVoiceTurnId = snapshot.turnId;
    return true;
  }

  private applyVoiceTranscriptDraft(transcript: string): void {
    if (transcript.trim().length === 0) {
      return;
    }
    if (this.voiceDraftTargetId.length === 0) {
      return;
    }
    this.host.setInputDraftForTarget(this.voiceDraftTargetId,
      appendVoiceTranscriptToInput(this.voiceDraftBaseInput, transcript));
  }

  private async handleVoiceTranscriptComplete(transcript: string): Promise<void> {
    let snapshot = this.voiceController.snapshot();
    if (!this.shouldHandleVoiceTranscriptComplete(snapshot)) {
      return;
    }
    this.clearVoiceInputStopFallbackTimer();
    let finalTranscript = transcript.trim().length > 0 ? transcript.trim() : snapshot.finalTranscript.trim();
    if (finalTranscript.length === 0) {
      this.finishVoiceInputWithoutTranscript();
      return;
    }
    this.voiceController.completeTranscript(finalTranscript);
    this.applyVoiceTranscriptDraft(finalTranscript);
    this.emitSnapshot();
    this.voiceController.reset();
    this.voiceDraftTargetId = '';
    this.voiceDraftBaseInput = '';
    this.voiceInputStoppedGeneration = voiceInputStopGeneration(this.voiceInputStartGeneration,
      this.voiceInputStoppedGeneration);
    this.emitSnapshot();
    showToastSafely('语音已转写到输入框', 1200);
  }

  private finishVoiceInputWithoutTranscript(): void {
    this.clearVoiceInputStopFallbackTimer();
    this.voiceController.completeWithoutTranscript();
    this.voiceDraftTargetId = '';
    this.voiceDraftBaseInput = '';
    this.voiceInputStoppedGeneration = voiceInputStopGeneration(this.voiceInputStartGeneration,
      this.voiceInputStoppedGeneration);
    this.emitSnapshot();
    showToastSafely('没有识别到语音内容', 1200);
  }

  private ttsConfigReady(): boolean {
    let config = this.host.ttsConfig();
    return config.baseUrl.trim().length > 0 && config.apiKey.trim().length > 0 &&
      config.model.trim().length > 0 && config.voice.trim().length > 0;
  }

  private updateMessageVoiceMetadataForSession(sessionId: string, messageId: string,
    voice?: ChatVoiceMetadata): void {
    let state = ChatSessionController.updateMessageVoiceMetadataInSession(this.host.filesDir(),
      this.host.currentChatSessionViewState(), sessionId, messageId, voice);
    this.host.applyChatSessionViewState(state);
  }

  private voiceTtsAssetPath(sessionId: string, messageId: string): string {
    return ChatSessionStorage.sessionAssetPath(this.host.filesDir(), sessionId, messageId + '-tts.wav');
  }

  private saveVoiceTtsAudio(sessionId: string, messageId: string, audioBase64: string): string {
    ChatSessionStorage.ensureSessionAssetsDir(this.host.filesDir(), sessionId);
    let helper = new util.Base64Helper();
    let bytes = helper.decodeSync(audioBase64);
    let path = this.voiceTtsAssetPath(sessionId, messageId);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer);
    } finally {
      fs.closeSync(file);
    }
    return 'file://' + path;
  }

  private nextVoicePlaybackGeneration(): number {
    this.voicePlaybackGeneration++;
    return this.voicePlaybackGeneration;
  }

  private voicePlaybackGenerationActive(generation: number): boolean {
    return generation === this.voicePlaybackGeneration;
  }

  private clearVoicePlaybackContext(): void {
    this.voicePlaybackSessionId = '';
    this.voicePlaybackAudioUri = '';
    this.voicePlaybackVoice = '';
  }

  private async playAssistantMessageVoiceInSession(sessionId: string, messageId: string, text: string): Promise<void> {
    if (sessionId.length === 0 || messageId.length === 0 || text.trim().length === 0) {
      return;
    }
    if (!this.ttsConfigReady()) {
      showToastSafely('请先在设置中配置语音合成服务和 API Key', 1800);
      return;
    }
    let snapshot = this.voiceController.snapshot();
    if ((snapshot.status === 'speaking' || snapshot.status === 'synthesizing') &&
      snapshot.activeMessageId === messageId) {
      await this.stopVoicePlayback();
      return;
    }
    await this.stopVoicePlayback();
    let config = this.host.ttsConfig();
    let generation = this.nextVoicePlaybackGeneration();
    this.voicePlaybackSessionId = sessionId;
    this.voicePlaybackVoice = config.voice;
    this.voicePlaybackAudioUri = '';
    this.voiceController.beginSynthesizing(messageId);
    this.emitSnapshot();
    this.updateMessageVoiceMetadataForSession(sessionId, messageId,
      createTtsVoiceMetadata('mimo', config.voice, '', new Date().getTime()));
    try {
      let result = await this.voiceTtsClient.synthesizeSpeech(text.trim(), {
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
        voice: config.voice
      });
      if (!this.voicePlaybackGenerationActive(generation)) {
        return;
      }
      let audioUri = this.saveVoiceTtsAudio(sessionId, messageId, result.audioBase64);
      this.voicePlaybackAudioUri = audioUri;
      this.voicePlaybackVoice = result.voice;
      if (!this.voicePlaybackGenerationActive(generation)) {
        return;
      }
      this.updateMessageVoiceMetadataForSession(sessionId, messageId,
        createTtsVoiceMetadata('mimo', result.voice, audioUri, new Date().getTime()));
      await this.voiceAudioPlayback.playFile(audioUri, {
        onStarted: () => {
          if (!this.voicePlaybackGenerationActive(generation)) {
            return;
          }
          this.voiceController.beginSpeaking(messageId);
          this.updateMessageVoiceMetadataForSession(sessionId, messageId,
            createTtsVoiceRuntimeMetadata('mimo', result.voice, audioUri, 'playing', new Date().getTime()));
          this.emitSnapshot();
        },
        onCompleted: () => {
          if (!this.voicePlaybackGenerationActive(generation)) {
            return;
          }
          this.updateMessageVoiceMetadataForSession(sessionId, messageId,
            createTtsVoiceMetadata('mimo', result.voice, audioUri, new Date().getTime()));
          this.clearVoicePlaybackContext();
          this.voiceController.finishSpeaking();
          this.emitSnapshot();
        },
        onError: (message: string) => {
          if (!this.voicePlaybackGenerationActive(generation)) {
            return;
          }
          this.updateMessageVoiceMetadataForSession(sessionId, messageId,
            createVoiceErrorMetadata('tts', 'mimo', message, new Date().getTime()));
          this.clearVoicePlaybackContext();
          this.failVoiceInteraction(message);
        }
      });
    } catch (e) {
      if (!this.voicePlaybackGenerationActive(generation)) {
        return;
      }
      let err = e as Error;
      this.updateMessageVoiceMetadataForSession(sessionId, messageId,
        createVoiceErrorMetadata('tts', 'mimo', err.message, new Date().getTime()));
      this.clearVoicePlaybackContext();
      this.failVoiceInteraction('语音合成失败：' + err.message);
    }
  }

  private async stopVoicePlayback(): Promise<void> {
    let snapshot = this.voiceController.snapshot();
    let voiceOutputActive = snapshot.status === 'speaking' || snapshot.status === 'synthesizing';
    let sessionId = this.voicePlaybackSessionId;
    let audioUri = this.voicePlaybackAudioUri;
    let voice = this.voicePlaybackVoice;
    this.voicePlaybackGeneration++;
    await this.voiceAudioPlayback.stop();
    if (voiceOutputActive && sessionId.length > 0 && snapshot.activeMessageId.length > 0) {
      if (audioUri.length > 0) {
        this.updateMessageVoiceMetadataForSession(sessionId, snapshot.activeMessageId,
          createTtsVoiceMetadata('mimo', voice, audioUri, new Date().getTime()));
      } else if (snapshot.status === 'synthesizing') {
        this.updateMessageVoiceMetadataForSession(sessionId, snapshot.activeMessageId, undefined);
      }
    }
    this.clearVoicePlaybackContext();
    if (voiceOutputActive) {
      this.voiceController.finishSpeaking();
      this.emitSnapshot();
    }
  }
}
