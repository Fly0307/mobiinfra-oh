// 云端流式输出的持久化兜底策略。
// UI 打字节奏由 ChatStreamDisplayPacer 控制；这里只限制会话文件写入频率。
export const CHAT_STREAM_FLUSH_INTERVAL_MS: number = 1200;
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
