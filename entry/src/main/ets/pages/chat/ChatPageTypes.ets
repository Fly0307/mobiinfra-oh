export const CHAT_MODE_CLOUD_AGENT: string = 'cloud_agent';
export const CHAT_MODE_LOCAL_INFERENCE: string = 'local_inference';

export function isSupportedChatMode(mode: string): boolean {
  return mode === CHAT_MODE_CLOUD_AGENT || mode === CHAT_MODE_LOCAL_INFERENCE;
}

export function chatModeLabel(mode: string): string {
  if (mode === CHAT_MODE_LOCAL_INFERENCE) {
    return '本地推理';
  }
  return '云端智能体';
}

export function chatModePlaceholder(mode: string): string {
  if (mode === CHAT_MODE_LOCAL_INFERENCE) {
    return '输入本地模型消息...';
  }
  return '发消息或输入任务...';
}

export function chatModeActionLabel(mode: string): string {
  if (mode === CHAT_MODE_LOCAL_INFERENCE) {
    return '发送';
  }
  return '发送';
}
