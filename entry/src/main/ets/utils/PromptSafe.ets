import { promptAction } from '@kit.ArkUI';
import { AppLogger } from './AppLogger';

export function showToastSafely(message: string, duration: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: duration });
  } catch (e) {
    AppLogger.warnCause('Prompt', 'showToast failed', e as Error);
  }
}
