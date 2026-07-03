import { describe, it, expect } from '@ohos/hypium';
import {
  captureOverlayWindowTransition,
  CAPTURE_OVERLAY_HIDDEN_STORAGE_KEY
} from '../main/ets/utils/CaptureOverlayPolicy';

export default function captureOverlayPolicyUnitTest() {
  describe('captureOverlayPolicyUnitTest', () => {
    it('hidesPanelForCaptureWithoutDestroyingExistingFloatWindow', 0, () => {
      let transition = captureOverlayWindowTransition(true, true);

      expect(transition.applied).assertTrue();
      expect(transition.shouldCreateWindow).assertFalse();
      expect(transition.shouldDestroyWindow).assertFalse();
      expect(transition.contentHidden).assertTrue();
      expect(transition.windowTouchable).assertFalse();
    });

    it('restoresPanelContentAndTouchAfterCapture', 0, () => {
      let transition = captureOverlayWindowTransition(false, true);

      expect(transition.applied).assertTrue();
      expect(transition.shouldCreateWindow).assertFalse();
      expect(transition.shouldDestroyWindow).assertFalse();
      expect(transition.contentHidden).assertFalse();
      expect(transition.windowTouchable).assertTrue();
    });

    it('keepsStorageKeyStableForFloatWindowBinding', 0, () => {
      expect(CAPTURE_OVERLAY_HIDDEN_STORAGE_KEY).assertEqual('agentCaptureOverlayHidden');
    });
  });
}
