// 云端流式输出的 UI/持久化刷新策略。
// 模型可能在一次长文生成中连续推送大量小片段，不能每个片段都写会话文件和刷新 @State。
export const CHAT_STREAM_FLUSH_INTERVAL_MS: number = 250;
export const CHAT_STREAM_FLUSH_CHAR_DELTA: number = 8192;

export interface ChatStreamUpdateFlushState {
  lastFlushAt: number;
  lastFlushedLength: number;
  timerScheduled: boolean;
}

export function chatStreamUpdateStateAfterFlush(now: number, contentLength: number,
  timerScheduled: boolean = false): ChatStreamUpdateFlushState {
  return {
    lastFlushAt: now,
    lastFlushedLength: contentLength,
    timerScheduled: timerScheduled
  };
}

export function shouldFlushChatStreamUpdate(now: number, contentLength: number,
  state: ChatStreamUpdateFlushState): boolean {
  if (state.lastFlushAt <= 0) {
    return true;
  }
  if (now - state.lastFlushAt >= CHAT_STREAM_FLUSH_INTERVAL_MS) {
    return true;
  }
  if (!state.timerScheduled && contentLength - state.lastFlushedLength >= CHAT_STREAM_FLUSH_CHAR_DELTA) {
    return true;
  }
  return false;
}

export function chatStreamUpdateDelayMs(now: number, state: ChatStreamUpdateFlushState): number {
  if (state.lastFlushAt <= 0) {
    return 0;
  }
  let elapsed = now - state.lastFlushAt;
  if (elapsed >= CHAT_STREAM_FLUSH_INTERVAL_MS) {
    return 0;
  }
  return CHAT_STREAM_FLUSH_INTERVAL_MS - elapsed;
}
