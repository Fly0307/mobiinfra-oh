import { promptAction } from '@kit.ArkUI';

export function showToastSafely(message: string, duration: number = 1500): void {
  try {
    promptAction.showToast({ message: message, duration: duration });
  } catch (e) {
    let err = e as Error;
    console.warn('showToast failed: ' + err.message);
  }
}
