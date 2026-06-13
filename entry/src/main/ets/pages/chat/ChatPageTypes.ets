export const CHAT_MODE_CLOUD_AGENT: string = 'cloud_agent';
export const CHAT_MODE_LOCAL_INFERENCE: string = 'local_inference';
export const CLOUD_AGENT_DEFAULT_OUTPUT: string = '请先配置 Planner 和 Decider 云端服务';

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

export function chatInputAfterAcceptedSend(currentInput: string, accepted: boolean): string {
  return accepted ? '' : currentInput;
}

export function chatModeSwitcherVisibleAfterScroll(currentVisible: boolean, yOffset: number,
  threshold: number = 4): boolean {
  if (yOffset > threshold) {
    return false;
  }
  if (yOffset < -threshold) {
    return true;
  }
  return currentVisible;
}

export function hasCloudAgentDisplayOutput(output: string): boolean {
  let text = output.trim();
  return text.length > 0 && text !== CLOUD_AGENT_DEFAULT_OUTPUT && text !== '云端智能体准备就绪';
}

export function cloudAgentDisplayText(output: string): string {
  let text = output.trim();
  if (!hasCloudAgentDisplayOutput(text)) {
    return '';
  }
  let markers: string[] = [
    'Planner 手动返回：\n',
    'Planner 测试返回：\n'
  ];
  for (let i = 0; i < markers.length; i++) {
    let marker = markers[i];
    let idx = text.lastIndexOf(marker);
    if (idx >= 0) {
      return text.substring(idx + marker.length).trim();
    }
  }
  return text;
}
