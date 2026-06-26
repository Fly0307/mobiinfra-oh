import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLogger } from '../AppLogger';

export interface AudioPlaybackCallbacks {
  onStarted?: () => void;
  onCompleted?: () => void;
  onError?: (message: string) => void;
}

export class HarmonyAudioPlayback {
  private avPlayer: media.AVPlayer | null = null;
  private openedFile: fileIo.File | null = null;

  private static stripFileUri(path: string): string {
    let text = path.trim();
    if (text.indexOf('file://') === 0) {
      return text.substring('file://'.length);
    }
    return text;
  }

  async playFile(path: string, callbacks: AudioPlaybackCallbacks = {}): Promise<void> {
    await this.stop();
    let sourcePath = HarmonyAudioPlayback.stripFileUri(path);
    if (sourcePath.length === 0) {
      callbacks.onError?.('语音文件路径为空');
      return;
    }
    let file = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    this.openedFile = file;
    let player = await media.createAVPlayer();
    this.avPlayer = player;
    player.on('stateChange', async (state: string, _reason: media.StateChangeReason) => {
      if (this.avPlayer !== player) {
        return;
      }
      if (state === 'initialized') {
        try {
          await player.prepare();
        } catch (e) {
          if (this.avPlayer !== player) {
            return;
          }
          let err = e as BusinessError;
          callbacks.onError?.('准备语音播放失败：' + err.message);
        }
        return;
      }
      if (state === 'prepared') {
        try {
          await player.play();
          if (this.avPlayer !== player) {
            return;
          }
          callbacks.onStarted?.();
        } catch (e) {
          if (this.avPlayer !== player) {
            return;
          }
          let err = e as BusinessError;
          callbacks.onError?.('启动语音播放失败：' + err.message);
        }
        return;
      }
      if (state === 'completed') {
        if (this.avPlayer !== player) {
          return;
        }
        callbacks.onCompleted?.();
        await this.stop();
      }
    });
    player.on('error', (err: BusinessError) => {
      if (this.avPlayer !== player) {
        return;
      }
      callbacks.onError?.('语音播放失败：' + err.message);
    });
    player.url = 'fd://' + String(file.fd);
  }

  async pause(): Promise<void> {
    let player = this.avPlayer;
    if (player === null) {
      return;
    }
    try {
      await player.pause();
    } catch (e) {
      AppLogger.warnCause('Voice.Audio', 'pause player failed', e as Error);
    }
  }

  async resume(): Promise<void> {
    let player = this.avPlayer;
    if (player === null) {
      return;
    }
    try {
      await player.play();
    } catch (e) {
      AppLogger.warnCause('Voice.Audio', 'resume player failed', e as Error);
    }
  }

  async stop(): Promise<void> {
    let player = this.avPlayer;
    this.avPlayer = null;
    if (player !== null) {
      try {
        await player.stop();
      } catch (e) {
      }
      try {
        await player.release();
      } catch (e) {
        AppLogger.warnCause('Voice.Audio', 'release player failed', e as Error);
      }
    }
    let file = this.openedFile;
    this.openedFile = null;
    if (file !== null) {
      try {
        fileIo.close(file);
      } catch (e) {
      }
    }
  }
}
