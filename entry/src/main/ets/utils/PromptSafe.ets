import { promptAction } from '@kit.ArkUI';
import { AppLogger } from './AppLogger';

export function showToastSafely(message: string, duration: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: duration });
  } catch (e) {
    let err = e as Error;
    AppLogger.warn('Prompt', 'showToast failed: ' + err.message);
  }
}
