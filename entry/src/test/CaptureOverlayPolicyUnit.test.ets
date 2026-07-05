import { describe, it, expect } from '@ohos/hypium';
import {
  captureOverlayWindowTransition,
  CAPTURE_OVERLAY_HIDDEN_STORAGE_KEY,
  FloatPanelManualMoveRect,
  resolveFloatPanelManualMoveRect
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

    it('movesFloatPanelByTouchDeltaWithoutLeavingDisplay', 0, () => {
      // 不可获焦浮窗不能依赖系统 startMoving，这里覆盖手动拖动的坐标换算和屏幕边界夹取。
      let moved: FloatPanelManualMoveRect = resolveFloatPanelManualMoveRect({
        startLeft: 900,
        startTop: 1800,
        width: 264,
        height: 216,
        startScreenX: 100,
        startScreenY: 100,
        currentScreenX: 300,
        currentScreenY: 400,
        touchScale: 1,
        displayWidth: 1080,
        displayHeight: 2340
      });

      expect(moved.left).assertEqual(816);
      expect(moved.top).assertEqual(2100);
    });

    it('clampsFloatPanelManualMoveAtDisplayOrigin', 0, () => {
      let moved: FloatPanelManualMoveRect = resolveFloatPanelManualMoveRect({
        startLeft: 12,
        startTop: 18,
        width: 264,
        height: 216,
        startScreenX: 240,
        startScreenY: 300,
        currentScreenX: 10,
        currentScreenY: 20,
        touchScale: 1,
        displayWidth: 1080,
        displayHeight: 2340
      });

      expect(moved.left).assertEqual(0);
      expect(moved.top).assertEqual(0);
    });

    it('scalesTouchDeltaFromVpToPxForFloatPanelManualMove', 0, () => {
      // 触摸事件坐标与窗口坐标单位不同；高密度屏上需要把 vp 位移转换为 px 位移，
      // 否则拖动会表现为灵敏度过低、像有明显阻力。
      let moved: FloatPanelManualMoveRect = resolveFloatPanelManualMoveRect({
        startLeft: 300,
        startTop: 600,
        width: 264,
        height: 216,
        startScreenX: 100,
        startScreenY: 100,
        currentScreenX: 160,
        currentScreenY: 180,
        touchScale: 3,
        displayWidth: 1080,
        displayHeight: 2340
      });

      expect(moved.left).assertEqual(480);
      expect(moved.top).assertEqual(840);
    });
  });
}
