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

export class HarmonySpeechRecognizerAsrProvider {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private latestTranscript: string = '';

  private shouldAcceptCallback(sessionId: string, activeSessionId: string): boolean {
    return sessionId.length > 0 && sessionId === activeSessionId && this.sessionId === activeSessionId;
  }

  private async ensureEngine(language: string): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.engine !== null) {
      return this.engine;
    }
    let initParamsInfo: speechRecognizer.CreateEngineParams = {
      language: language.length > 0 ? language : 'zh-CN',
      online: 1,
      extraParams: {
        'locate': 'CN',
        'recognizerMode': 'short'
      }
    };
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
        this.latestTranscript = transcript;
        if (result.isFinal || result.isLast) {
          callbacks.onFinalTranscript?.(transcript, result.isLast);
          return;
        }
        callbacks.onPartialTranscript?.(transcript);
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
    engine.setListener(listener);
    let recognizerParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams: {
        'recognitionMode': 0,
        'vadBegin': 2000,
        'vadEnd': 3000,
        'maxAudioDuration': 20000
      }
    };
    engine.startListening(recognizerParams);
  }

  finish(): void {
    if (this.engine === null || this.sessionId.length === 0) {
      return;
    }
    this.engine.finish(this.sessionId);
  }

  cancel(): void {
    if (this.engine === null || this.sessionId.length === 0) {
      return;
    }
    this.engine.cancel(this.sessionId);
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
  }
}
