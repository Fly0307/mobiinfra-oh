import {
  CHAT_MESSAGE_KIND_CHAT,
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage
} from './ChatSessionTypes';

export type DigitalAvatarVisualState = 'idle' | 'thinking';
export type DigitalAvatarSize = 'message';

export interface ChatAvatarRenderModel {
  useDigitalAvatar: boolean;
  fallbackText: string;
  fallbackColor: string;
  visualState: DigitalAvatarVisualState;
}

export const DIGITAL_AVATAR_MESSAGE_WIDTH: number = 42;
export const DIGITAL_AVATAR_MESSAGE_HEIGHT: number = 54;
export const TEXT_AVATAR_SIZE: number = 34;

export function useDigitalAvatarForMessage(message: ChatMessage): boolean {
  return message.role === 'assistant' && message.kind === CHAT_MESSAGE_KIND_CHAT;
}

export function chatAvatarRenderModel(message: ChatMessage, modeMark: string,
  visualState: DigitalAvatarVisualState): ChatAvatarRenderModel {
  if (message.role === 'user') {
    return {
      useDigitalAvatar: false,
      fallbackText: '我',
      fallbackColor: '#111827',
      visualState: visualState
    };
  }
  if (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
    return {
      useDigitalAvatar: false,
      fallbackText: '压',
      fallbackColor: '#F59E0B',
      visualState: visualState
    };
  }
  if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
    return {
      useDigitalAvatar: false,
      fallbackText: '任',
      fallbackColor: '#059669',
      visualState: visualState
    };
  }
  if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
    return {
      useDigitalAvatar: false,
      fallbackText: '任',
      fallbackColor: '#7C3AED',
      visualState: visualState
    };
  }
  let assistantText = modeMark.length > 0 ? modeMark : '助';
  return {
    useDigitalAvatar: useDigitalAvatarForMessage(message),
    fallbackText: assistantText,
    fallbackColor: '#5968FF',
    visualState: visualState
  };
}
