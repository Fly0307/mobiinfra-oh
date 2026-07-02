import { audio } from '@kit.AudioKit';
import { AppLogger } from '../AppLogger';

export interface PcmStreamPlaybackCallbacks {
  onStarted?: () => void;
  onCompleted?: () => void;
  onError?: (message: string) => void;
}

interface QueuedPcmChunk {
  bytes: Uint8Array;
  offset: number;
}

const PCM_SILENCE_DRAIN_LIMIT: number = 8;

// 专门播放 MiMO 流式 TTS 的 24kHz/mono/S16LE PCM chunk；缓存复播继续交给 AVPlayer 文件播放封装。
export class HarmonyPcmStreamPlayback {
  private renderer: audio.AudioRenderer | null = null;
  private callbacks: PcmStreamPlaybackCallbacks = {};
  private queue: QueuedPcmChunk[] = [];
  private ended: boolean = false;
  private started: boolean = false;
  private stopped: boolean = false;
  private completionScheduled: boolean = false;
  private silenceDrainCount: number = 0;
  private lifecycleSerial: number = 0;

  async start(callbacks: PcmStreamPlaybackCallbacks = {}): Promise<void> {
    this.lifecycleSerial++;
    let serial = this.lifecycleSerial;
    await this.releaseCurrentRenderer();
    this.callbacks = callbacks;
    this.queue = [];
    this.ended = false;
    this.started = false;
    this.stopped = false;
    this.completionScheduled = false;
    this.silenceDrainCount = 0;
    let renderer = await audio.createAudioRenderer({
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_24000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      rendererInfo: {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      }
    });
    if (!this.startStillCurrent(serial)) {
      await this.releaseDetachedRenderer(renderer);
      return;
    }
    this.renderer = renderer;
    renderer.on('writeData', (buffer: ArrayBuffer) => this.fillBuffer(buffer));
    await renderer.start();
    if (!this.startStillCurrent(serial)) {
      await this.releaseDetachedRenderer(renderer);
      return;
    }
    this.started = true;
    callbacks.onStarted?.();
  }

  appendChunk(chunk: Uint8Array): void {
    if (this.stopped || chunk.byteLength === 0) {
      return;
    }
    let exact = new Uint8Array(chunk.byteLength);
    for (let index = 0; index < chunk.byteLength; index++) {
      exact[index] = chunk[index];
    }
    this.queue.push({ bytes: exact, offset: 0 });
    this.silenceDrainCount = 0;
  }

  markEnded(): void {
    this.ended = true;
  }

  async pause(): Promise<void> {
    if (this.renderer === null || !this.started || this.stopped) {
      return;
    }
    await this.renderer.pause();
  }

  async resume(): Promise<void> {
    if (this.renderer === null || !this.started || this.stopped) {
      return;
    }
    await this.renderer.start();
  }

  async stop(): Promise<void> {
    this.lifecycleSerial++;
    await this.releaseCurrentRenderer();
  }

  private startStillCurrent(serial: number): boolean {
    return serial === this.lifecycleSerial && !this.stopped;
  }

  private async releaseCurrentRenderer(): Promise<void> {
    let renderer = this.renderer;
    this.renderer = null;
    this.stopped = true;
    this.queue = [];
    if (renderer !== null) {
      try {
        renderer.off('writeData');
      } catch (e) {
      }
      try {
        await renderer.stop();
      } catch (e) {
      }
      try {
        await renderer.release();
      } catch (e) {
        AppLogger.warnCause('Voice.PcmPlayback', 'release renderer failed', e as Error);
      }
    }
  }

  private async releaseDetachedRenderer(renderer: audio.AudioRenderer): Promise<void> {
    try {
      renderer.off('writeData');
    } catch (e) {
    }
    try {
      await renderer.stop();
    } catch (e) {
    }
    try {
      await renderer.release();
    } catch (e) {
      AppLogger.warnCause('Voice.PcmPlayback', 'release detached renderer failed', e as Error);
    }
  }

  private fillBuffer(buffer: ArrayBuffer): audio.AudioDataCallbackResult {
    let output = new Uint8Array(buffer);
    let written = 0;
    while (written < output.byteLength && this.queue.length > 0) {
      let chunk = this.queue[0];
      let available = chunk.bytes.byteLength - chunk.offset;
      let writable = Math.min(output.byteLength - written, available);
      for (let index = 0; index < writable; index++) {
        output[written + index] = chunk.bytes[chunk.offset + index];
      }
      written += writable;
      chunk.offset += writable;
      if (chunk.offset >= chunk.bytes.byteLength) {
        this.queue.shift();
      }
    }
    for (let index = written; index < output.byteLength; index++) {
      output[index] = 0;
    }
    if (this.ended && this.queue.length === 0) {
      this.silenceDrainCount++;
      if (this.silenceDrainCount >= PCM_SILENCE_DRAIN_LIMIT) {
        this.scheduleCompletion();
      }
    }
    return audio.AudioDataCallbackResult.VALID;
  }

  private scheduleCompletion(): void {
    if (this.completionScheduled || this.stopped) {
      return;
    }
    this.completionScheduled = true;
    setTimeout(() => {
      if (this.stopped) {
        return;
      }
      this.callbacks.onCompleted?.();
      this.stop().catch((e: Error) => {
        AppLogger.warnCause('Voice.PcmPlayback', 'stop after stream completion failed', e);
      });
    }, 0);
  }
}
