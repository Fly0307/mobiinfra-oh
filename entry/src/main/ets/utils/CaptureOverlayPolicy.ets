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
