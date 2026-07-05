export const CAPTURE_OVERLAY_HIDDEN_STORAGE_KEY: string = 'agentCaptureOverlayHidden';

// 截图 overlay 切换的纯策略：隐藏时保留已有窗口，只隐藏内容并禁触；
// 恢复时重新显示内容并恢复触摸。窗口销毁只允许发生在任务结束/回前台的清理流程。
export interface CaptureOverlayWindowTransition {
  applied: boolean;
  shouldCreateWindow: boolean;
  shouldDestroyWindow: boolean;
  contentHidden: boolean;
  windowTouchable: boolean;
}

export interface FloatPanelManualMoveInput {
  startLeft: number;
  startTop: number;
  width: number;
  height: number;
  startScreenX: number;
  startScreenY: number;
  currentScreenX: number;
  currentScreenY: number;
  touchScale: number;
  displayWidth: number;
  displayHeight: number;
}

export interface FloatPanelManualMoveRect {
  left: number;
  top: number;
}

export function captureOverlayWindowTransition(hidden: boolean,
  hasFloatWindow: boolean): CaptureOverlayWindowTransition {
  if (hidden) {
    return {
      applied: hasFloatWindow,
      shouldCreateWindow: false,
      shouldDestroyWindow: false,
      contentHidden: hasFloatWindow,
      windowTouchable: false
    };
  }

  return {
    applied: true,
    shouldCreateWindow: !hasFloatWindow,
    shouldDestroyWindow: false,
    contentHidden: false,
    windowTouchable: true
  };
}

// 不可获焦浮窗不能稳定依赖系统 startMoving。ArkUI 触摸坐标按 vp 语义上报，
// window.moveWindowTo 使用 px，因此手动拖动需要按屏幕密度换算位移后再夹取边界。
export function resolveFloatPanelManualMoveRect(input: FloatPanelManualMoveInput): FloatPanelManualMoveRect {
  let maxLeft = Math.max(0, input.displayWidth - input.width);
  let maxTop = Math.max(0, input.displayHeight - input.height);
  let scale = input.touchScale > 0 ? input.touchScale : 1;
  let nextLeft = Math.round(input.startLeft + (input.currentScreenX - input.startScreenX) * scale);
  let nextTop = Math.round(input.startTop + (input.currentScreenY - input.startScreenY) * scale);
  return {
    left: clampNumber(nextLeft, 0, maxLeft),
    top: clampNumber(nextTop, 0, maxTop)
  };
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
