export const THINKING_OVERLAY_GAP: number = 12;
export const THINKING_OVERLAY_HEIGHT: number = 54;
export const BOTTOM_SPACER_EXTRA_GAP_RATIO: number = 0.18;
export const BOTTOM_SPACER_EXTRA_GAP_MIN: number = 12;
export const BOTTOM_SPACER_EXTRA_GAP_MAX: number = 32;

export type ChatBottomOverlayKind = 'none' | 'thinking' | 'back_to_bottom';

/**
 * 聊天列表的最后一条真实内容 index。处理中提示是固定 overlay，不参与 List index。
 */
export function chatLatestContentIndex(messageCount: number): number {
  return messageCount > 0 ? messageCount - 1 : -1;
}

/**
 * bottom spacer 永远跟在真实消息之后，供流式跟随和结构性滚动对齐底部。
 */
export function chatBottomSpacerIndex(messageCount: number): number {
  return Math.max(0, messageCount);
}

/**
 * 流式响应期间始终对齐 bottom spacer，避免用固定 offset 猜测真实新增高度。
 */
export function chatStreamFollowTargetIndex(messageCount: number): number {
  return chatBottomSpacerIndex(messageCount);
}

/**
 * 底部浮层互斥显示；用户离底时优先给“回到底部”入口。
 */
export function chatBottomOverlayKind(thinkingVisible: boolean, backToBottomVisible: boolean): ChatBottomOverlayKind {
  if (backToBottomVisible) {
    return 'back_to_bottom';
  }
  if (thinkingVisible) {
    return 'thinking';
  }
  return 'none';
}

/**
 * 额外底部间隔按底部浮层高度比例计算，并用上下限避免极端屏幕或输入框高度下失控。
 */
export function chatBottomSpacerExtraGap(bottomOverlayInset: number): number {
  let safeBottomInset: number = Math.max(0, bottomOverlayInset);
  let relativeGap: number = Math.round(safeBottomInset * BOTTOM_SPACER_EXTRA_GAP_RATIO);
  return Math.min(BOTTOM_SPACER_EXTRA_GAP_MAX, Math.max(BOTTOM_SPACER_EXTRA_GAP_MIN, relativeGap));
}

/**
 * 预留底部浮层安全空间。bottomOverlayInset 由 ChatPage 计算，已经包含输入框和快捷按钮区；
 * 只有处理中 overlay 可见时才额外加上 overlay 高度，避免空闲态浪费聊天区域。
 */
export function chatMessageListBottomSpacerHeight(bottomOverlayInset: number, thinkingVisible: boolean): number {
  let safeBottomInset: number = Math.max(0, bottomOverlayInset);
  let thinkingReserve: number = thinkingVisible ? THINKING_OVERLAY_GAP + THINKING_OVERLAY_HEIGHT : 0;
  return safeBottomInset + thinkingReserve + chatBottomSpacerExtraGap(safeBottomInset);
}
