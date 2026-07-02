import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLogger } from '../AppLogger';

export interface AsrRecognitionCallbacks {
  onStart?: (sessionId: string) => void;
  onPartialTranscript?: (transcript: string) => void;
  onFinalTranscript?: (transcript: string, isLast: boolean) => void;
  onComplete?: (transcript: string) => void;
  onError?: (message: string) => void;
}

export interface HarmonyAsrStartOptions {
  language: string;
  sessionId: string;
}

// 参考官方 VoiceToTextForChatDemo：聊天语音输入使用 long 模式，让识别服务按停顿输出更自然的分句结果。
export function buildHarmonyAsrCreateEngineParams(language: string): speechRecognizer.CreateEngineParams {
  return {
    language: language.length > 0 ? language : 'zh-CN',
    online: 1,
    extraParams: {
      'locate': 'CN',
      'recognizerMode': 'long'
    }
  };
}

function normalizeHarmonyAsrText(text: string): string {
  return text.trim();
}

function isHarmonyAsrBoundaryChar(char: string): boolean {
  return char === '，' || char === '。' || char === '、' || char === '！' || char === '？' ||
    char === ',' || char === '.' || char === '!' || char === '?' || char === ';' || char === '；' ||
    char === ':' || char === '：' || char === ' ' || char === '\n' || char === '\t';
}

function compactHarmonyAsrText(text: string): string {
  let compact = '';
  for (let i = 0; i < text.length; i++) {
    let char = text.charAt(i);
    if (!isHarmonyAsrBoundaryChar(char)) {
      compact += char;
    }
  }
  return compact;
}

function isLongerCumulativeTranscript(committed: string, next: string): boolean {
  if (next.length <= committed.length) {
    return false;
  }
  if (next.startsWith(committed)) {
    return true;
  }
  let committedCompact = compactHarmonyAsrText(committed);
  let nextCompact = compactHarmonyAsrText(next);
  return committedCompact.length > 0 && nextCompact.length > committedCompact.length &&
    nextCompact.startsWith(committedCompact);
}

function joinHarmonyAsrText(committedText: string, nextText: string): string {
  let committed = normalizeHarmonyAsrText(committedText);
  let next = normalizeHarmonyAsrText(nextText);
  if (committed.length === 0) {
    return next;
  }
  if (next.length === 0) {
    return committed;
  }
  if (isLongerCumulativeTranscript(committed, next)) {
    return next;
  }
  return committed + next;
}

// ASR final 通常是“当前分句”；少数实现会回传“已累计全文”，此时用累计全文替换，避免重复前文。
export function mergeHarmonyAsrFinalTranscript(committedText: string, finalText: string, _isLast: boolean): string {
  return joinHarmonyAsrText(committedText, finalText);
}

export function mergeHarmonyAsrPartialTranscript(committedText: string, partialText: string): string {
  return joinHarmonyAsrText(committedText, partialText);
}

export function shouldSkipDuplicateHarmonyAsrFinalCallback(lastFinalText: string, lastFinalIsLast: boolean,
  currentFinalText: string, currentFinalIsLast: boolean): boolean {
  return normalizeHarmonyAsrText(lastFinalText).length > 0 &&
    normalizeHarmonyAsrText(lastFinalText) === normalizeHarmonyAsrText(currentFinalText) &&
    lastFinalIsLast === currentFinalIsLast;
}

export function buildHarmonyAsrStartParams(sessionId: string): speechRecognizer.StartParams {
  return {
    sessionId: sessionId,
    audioInfo: {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16
    },
    extraParams: {
      'recognitionMode': 0,
      'vadBegin': 500,
      'vadEnd': 10000,
      'maxAudioDuration': 60000
    }
  };
}

export class HarmonySpeechRecognizerAsrProvider {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private latestTranscript: string = '';
  private finalTranscript: string = '';
  private lastFinalCallbackTranscript: string = '';
  private lastFinalCallbackIsLast: boolean = false;

  private shouldAcceptCallback(sessionId: string, activeSessionId: string): boolean {
    return sessionId.length > 0 && sessionId === activeSessionId && this.sessionId === activeSessionId;
  }

  private async ensureEngine(language: string): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.engine !== null) {
      return this.engine;
    }
    let initParamsInfo = buildHarmonyAsrCreateEngineParams(language);
    return new Promise<speechRecognizer.SpeechRecognitionEngine>((resolve, reject) => {
      speechRecognizer.createEngine(initParamsInfo, (err: BusinessError,
        speechRecognitionEngine: speechRecognizer.SpeechRecognitionEngine) => {
        if (!err) {
          this.engine = speechRecognitionEngine;
          resolve(speechRecognitionEngine);
          return;
        }
        reject(new Error('创建语音识别引擎失败：' + err.message));
      });
    });
  }

  async start(callbacks: AsrRecognitionCallbacks, options: HarmonyAsrStartOptions): Promise<void> {
    let engine = await this.ensureEngine(options.language);
    this.sessionId = options.sessionId;
    this.latestTranscript = '';
    this.finalTranscript = '';
    this.lastFinalCallbackTranscript = '';
    this.lastFinalCallbackIsLast = false;
    let activeSessionId = options.sessionId;
    let listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, _eventMessage: string) => {
        if (!this.shouldAcceptCallback(sessionId, activeSessionId)) {
          return;
        }
        callbacks.onStart?.(sessionId);
      },
      onEvent: (_sessionId: string, eventCode: number, eventMessage: string) => {
        AppLogger.debug('Voice.ASR', 'event code=' + String(eventCode) + ' message=' + eventMessage);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (!this.shouldAcceptCallback(sessionId, activeSessionId)) {
          return;
        }
        let transcript = result.result === undefined ? '' : result.result.trim();
        if (transcript.length === 0) {
          return;
        }
        if (result.isFinal || result.isLast) {
          if (shouldSkipDuplicateHarmonyAsrFinalCallback(this.lastFinalCallbackTranscript,
            this.lastFinalCallbackIsLast, transcript, result.isLast)) {
            return;
          }
          this.lastFinalCallbackTranscript = transcript;
          this.lastFinalCallbackIsLast = result.isLast;
          this.finalTranscript = mergeHarmonyAsrFinalTranscript(this.finalTranscript, transcript, result.isLast);
          this.latestTranscript = this.finalTranscript;
          callbacks.onFinalTranscript?.(this.finalTranscript, result.isLast);
          return;
        }
        this.latestTranscript = mergeHarmonyAsrPartialTranscript(this.finalTranscript, transcript);
        callbacks.onPartialTranscript?.(this.latestTranscript);
      },
      onComplete: (sessionId: string, _eventMessage: string) => {
        if (!this.shouldAcceptCallback(sessionId, activeSessionId)) {
          return;
        }
        callbacks.onComplete?.(this.latestTranscript);
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        if (!this.shouldAcceptCallback(sessionId, activeSessionId)) {
          return;
        }
        callbacks.onError?.('语音识别失败：' + String(errorCode) + ' ' + errorMessage);
      }
    };
    try {
      engine.setListener(listener);
      engine.startListening(buildHarmonyAsrStartParams(this.sessionId));
    } catch (e) {
      let err = e as Error;
      throw new Error('启动语音识别失败：' + err.message);
    }
  }

  finish(): void {
    if (this.engine === null || this.sessionId.length === 0) {
      return;
    }
    try {
      this.engine.finish(this.sessionId);
    } catch (e) {
      AppLogger.warnCause('Voice.ASR', 'finish failed', e as Error);
    }
  }

  cancel(): void {
    if (this.engine === null || this.sessionId.length === 0) {
      return;
    }
    try {
      this.engine.cancel(this.sessionId);
    } catch (e) {
      AppLogger.warnCause('Voice.ASR', 'cancel failed', e as Error);
    }
  }

  shutdown(): void {
    if (this.engine === null) {
      return;
    }
    try {
      if (this.sessionId.length > 0) {
        this.engine.cancel(this.sessionId);
      }
      this.engine.shutdown();
    } catch (e) {
      AppLogger.warnCause('Voice.ASR', 'shutdown failed', e as Error);
    }
    this.engine = null;
    this.sessionId = '';
    this.latestTranscript = '';
    this.finalTranscript = '';
    this.lastFinalCallbackTranscript = '';
    this.lastFinalCallbackIsLast = false;
  }
}
