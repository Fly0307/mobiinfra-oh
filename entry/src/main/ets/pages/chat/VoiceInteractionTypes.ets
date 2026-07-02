export type VoiceInteractionStatus =
  'idle' | 'listening' | 'transcribing' | 'thinking' | 'synthesizing' | 'speaking' | 'paused' | 'error';
export type ChatVoiceInputKind = 'none' | 'asr' | 'tts';
export type ChatVoiceMetadataStatus = 'none' | 'transcribed' | 'synthesizing' | 'ready' | 'playing' | 'paused' |
  'error';
export type TtsVoiceRuntimeStatus = 'synthesizing' | 'ready' | 'playing' | 'paused';

export interface VoiceSessionSnapshot {
  status: VoiceInteractionStatus;
  turnId: string;
  partialTranscript: string;
  finalTranscript: string;
  activeMessageId: string;
  error: string;
}

export interface ChatVoiceMetadata {
  input: ChatVoiceInputKind;
  provider: string;
  status: ChatVoiceMetadataStatus;
  transcript: string;
  confidence: number;
  audioUri: string;
  voice: string;
  error: string;
  createdAt: number;
}

export function createEmptyVoiceSessionSnapshot(): VoiceSessionSnapshot {
  return {
    status: 'idle',
    turnId: '',
    partialTranscript: '',
    finalTranscript: '',
    activeMessageId: '',
    error: ''
  };
}

export function createEmptyChatVoiceMetadata(): ChatVoiceMetadata {
  return {
    input: 'none',
    provider: '',
    status: 'none',
    transcript: '',
    confidence: 0,
    audioUri: '',
    voice: '',
    error: '',
    createdAt: 0
  };
}

export function appendVoiceTranscriptToInput(currentInput: string, transcript: string): string {
  let normalizedTranscript = transcript.trim();
  if (normalizedTranscript.length === 0) {
    return currentInput;
  }
  if (currentInput.trim().length === 0) {
    return normalizedTranscript;
  }
  if (currentInput.endsWith('\n') || currentInput.endsWith(' ')) {
    return currentInput + normalizedTranscript;
  }
  return currentInput + '\n' + normalizedTranscript;
}

function normalizeVoiceInputKind(value: string): ChatVoiceInputKind {
  if (value === 'asr' || value === 'tts') {
    return value;
  }
  return 'none';
}

function normalizeVoiceMetadataStatus(value: string): ChatVoiceMetadataStatus {
  if (value === 'transcribed' || value === 'synthesizing' || value === 'ready' || value === 'playing' ||
    value === 'paused' || value === 'error') {
    return value;
  }
  return 'none';
}

function normalizeConfidence(value: number): number {
  if (value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

export function normalizeChatVoiceMetadata(raw?: ChatVoiceMetadata): ChatVoiceMetadata {
  if (raw === undefined) {
    return createEmptyChatVoiceMetadata();
  }
  return {
    input: normalizeVoiceInputKind(raw.input),
    provider: raw.provider === undefined ? '' : raw.provider.trim(),
    status: normalizeVoiceMetadataStatus(raw.status),
    transcript: raw.transcript === undefined ? '' : raw.transcript.trim(),
    confidence: raw.confidence === undefined ? 0 : normalizeConfidence(raw.confidence),
    audioUri: raw.audioUri === undefined ? '' : raw.audioUri.trim(),
    voice: raw.voice === undefined ? '' : raw.voice.trim(),
    error: raw.error === undefined ? '' : raw.error.trim(),
    createdAt: raw.createdAt === undefined ? 0 : raw.createdAt
  };
}

export function chatVoiceMetadataPresent(metadata: ChatVoiceMetadata): boolean {
  return metadata.input !== 'none' || metadata.provider.length > 0 || metadata.status !== 'none' ||
    metadata.transcript.length > 0 || metadata.audioUri.length > 0 || metadata.voice.length > 0 ||
    metadata.error.length > 0;
}

export function optionalChatVoiceMetadata(raw?: ChatVoiceMetadata): ChatVoiceMetadata | undefined {
  let metadata = normalizeChatVoiceMetadata(raw);
  return chatVoiceMetadataPresent(metadata) ? metadata : undefined;
}

export function createAsrVoiceMetadata(provider: string, transcript: string, confidence: number,
  createdAt: number): ChatVoiceMetadata {
  return normalizeChatVoiceMetadata({
    input: 'asr',
    provider: provider,
    status: 'transcribed',
    transcript: transcript,
    confidence: confidence,
    audioUri: '',
    voice: '',
    error: '',
    createdAt: createdAt
  });
}

export function createTtsVoiceMetadata(provider: string, voice: string, audioUri: string,
  createdAt: number): ChatVoiceMetadata {
  return createTtsVoiceRuntimeMetadata(provider, voice, audioUri, audioUri.trim().length > 0 ? 'ready' : 'synthesizing',
    createdAt);
}

export function createTtsVoiceRuntimeMetadata(provider: string, voice: string, audioUri: string,
  status: TtsVoiceRuntimeStatus, createdAt: number): ChatVoiceMetadata {
  return normalizeChatVoiceMetadata({
    input: 'tts',
    provider: provider,
    status: status,
    transcript: '',
    confidence: 0,
    audioUri: audioUri,
    voice: voice,
    error: '',
    createdAt: createdAt
  });
}

export function createVoiceErrorMetadata(input: ChatVoiceInputKind, provider: string, error: string,
  createdAt: number): ChatVoiceMetadata {
  return normalizeChatVoiceMetadata({
    input: input,
    provider: provider,
    status: 'error',
    transcript: '',
    confidence: 0,
    audioUri: '',
    voice: '',
    error: error,
    createdAt: createdAt
  });
}

export function voiceStatusLabel(status: VoiceInteractionStatus): string {
  if (status === 'listening') {
    return '正在聆听...';
  }
  if (status === 'transcribing') {
    return '正在转写...';
  }
  if (status === 'thinking') {
    return '正在思考...';
  }
  if (status === 'synthesizing') {
    return '正在合成语音...';
  }
  if (status === 'speaking') {
    return '正在朗读...';
  }
  if (status === 'paused') {
    return '已暂停朗读';
  }
  if (status === 'error') {
    return '语音出错';
  }
  return '';
}

export function voiceReplayAvailable(audioUri: string, globalStatus: VoiceInteractionStatus,
  currentMessageSynthesizing: boolean, globalReplayBlocked: boolean = false): boolean {
  if (audioUri.trim().length === 0) {
    return false;
  }
  // 流式 TTS 生成期间不能触发任何气泡重播，否则会取消当前请求并截断后续 PCM 缓存。
  if (globalStatus === 'synthesizing' || globalReplayBlocked) {
    return false;
  }
  return !currentMessageSynthesizing;
}

export function voiceReplayGlobalBlockNeeded(globalStatus: VoiceInteractionStatus, activeMessageId: string,
  activeMessageVisible: boolean, activeVoiceStatus: ChatVoiceMetadataStatus, activeAudioUri: string): boolean {
  if (globalStatus === 'synthesizing') {
    return true;
  }
  if (activeMessageId.length === 0) {
    return false;
  }
  if (!activeMessageVisible) {
    return globalStatus === 'speaking' || globalStatus === 'paused';
  }
  // 流式 TTS 首批 PCM 到达后会进入 speaking，但缓存 audioUri 还没落盘前仍不能重播。
  return (activeVoiceStatus === 'synthesizing' || activeVoiceStatus === 'playing' || activeVoiceStatus === 'paused') &&
    activeAudioUri.length === 0;
}

export class VoiceSessionController {
  private state: VoiceSessionSnapshot = createEmptyVoiceSessionSnapshot();

  snapshot(): VoiceSessionSnapshot {
    return {
      status: this.state.status,
      turnId: this.state.turnId,
      partialTranscript: this.state.partialTranscript,
      finalTranscript: this.state.finalTranscript,
      activeMessageId: this.state.activeMessageId,
      error: this.state.error
    };
  }

  isBusy(): boolean {
    return this.state.status !== 'idle' && this.state.status !== 'error';
  }

  beginListening(turnId: string): VoiceSessionSnapshot {
    this.state = {
      status: 'listening',
      turnId: turnId,
      partialTranscript: '',
      finalTranscript: '',
      activeMessageId: '',
      error: ''
    };
    return this.snapshot();
  }

  updatePartialTranscript(transcript: string): VoiceSessionSnapshot {
    if (this.state.status !== 'listening' && this.state.status !== 'transcribing') {
      return this.snapshot();
    }
    this.state.partialTranscript = transcript;
    return this.snapshot();
  }

  completeTranscript(transcript: string): VoiceSessionSnapshot {
    if (this.state.status !== 'listening' && this.state.status !== 'transcribing') {
      return this.snapshot();
    }
    this.state.status = 'transcribing';
    this.state.finalTranscript = transcript.trim();
    this.state.partialTranscript = transcript.trim();
    return this.snapshot();
  }

  markTranscribing(): VoiceSessionSnapshot {
    if (this.state.status !== 'listening' && this.state.status !== 'transcribing') {
      return this.snapshot();
    }
    this.state.status = 'transcribing';
    this.state.error = '';
    return this.snapshot();
  }

  completeWithoutTranscript(): VoiceSessionSnapshot {
    // 空识别不是语音服务异常：回到 idle，避免 UI 继续展示错误状态或状态占位。
    this.state = createEmptyVoiceSessionSnapshot();
    return this.snapshot();
  }

  markThinking(): VoiceSessionSnapshot {
    this.state.status = 'thinking';
    this.state.error = '';
    return this.snapshot();
  }

  beginSynthesizing(messageId: string): VoiceSessionSnapshot {
    this.state.status = 'synthesizing';
    this.state.activeMessageId = messageId;
    this.state.error = '';
    return this.snapshot();
  }

  beginSpeaking(messageId: string): VoiceSessionSnapshot {
    this.state.status = 'speaking';
    this.state.activeMessageId = messageId;
    this.state.error = '';
    return this.snapshot();
  }

  pauseSpeaking(messageId: string): VoiceSessionSnapshot {
    // 暂停只影响 TTS 播放态，保留 activeMessageId 让气泡能继续定位当前可恢复的消息。
    this.state.status = 'paused';
    this.state.activeMessageId = messageId;
    this.state.error = '';
    return this.snapshot();
  }

  finishSpeaking(): VoiceSessionSnapshot {
    this.state = createEmptyVoiceSessionSnapshot();
    return this.snapshot();
  }

  fail(message: string): VoiceSessionSnapshot {
    this.state.status = 'error';
    this.state.error = message.trim();
    return this.snapshot();
  }

  reset(): VoiceSessionSnapshot {
    this.state = createEmptyVoiceSessionSnapshot();
    return this.snapshot();
  }
}
