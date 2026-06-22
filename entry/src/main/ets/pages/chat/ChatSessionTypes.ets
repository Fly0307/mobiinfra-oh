import { CloudChatMessage } from '../../utils/CloudModelClient';
import { CHAT_MODE_CLOUD_AGENT, CHAT_MODE_LOCAL_INFERENCE, chatModeLabel } from './ChatPageTypes';

export { CHAT_MODE_CLOUD_AGENT, CHAT_MODE_LOCAL_INFERENCE };

export type ChatMessageRole = 'user' | 'assistant' | 'system' | 'task';
export type ChatMessageKind = 'chat' | 'task_result' | 'task_trace';

export const CHAT_MESSAGE_KIND_CHAT: ChatMessageKind = 'chat';
export const CHAT_MESSAGE_KIND_TASK_RESULT: ChatMessageKind = 'task_result';
export const CHAT_MESSAGE_KIND_TASK_TRACE: ChatMessageKind = 'task_trace';

export interface ChatMessage {
  id: string;
  role: ChatMessageRole;
  kind: ChatMessageKind;
  content: string;
  thinkingContent: string;
  thinkingCollapsed: boolean;
  trace: string[];
  collapsed: boolean;
  createdAt: number;
  imagePath?: string;
}

export interface ChatAssistantThinkingParts {
  content: string;
  thinkingContent: string;
}

export interface ChatSessionSummary {
  id: string;
  title: string;
  mode: string;
  fileName: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
  lastMessagePreview: string;
}

export interface ChatSessionRecord {
  id: string;
  title: string;
  mode: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMessage[];
}

export interface ChatSessionIndex {
  sessions: ChatSessionSummary[];
}

export function defaultChatSessionTitle(mode: string): string {
  return chatModeLabel(mode) + '新会话';
}

export function normalizeChatMode(mode: string): string {
  return mode === CHAT_MODE_LOCAL_INFERENCE ? CHAT_MODE_LOCAL_INFERENCE : CHAT_MODE_CLOUD_AGENT;
}

export function createEmptyChatSession(id: string, mode: string, now: number): ChatSessionRecord {
  return {
    id: id,
    title: defaultChatSessionTitle(normalizeChatMode(mode)),
    mode: normalizeChatMode(mode),
    createdAt: now,
    updatedAt: now,
    messages: []
  };
}

export function splitAssistantThinkingContent(rawContent: string): ChatAssistantThinkingParts {
  let closeTag = '</think>';
  let openTag = '<think>';
  let lookup = rawContent.toLowerCase();
  let closeIndex = lookup.indexOf(closeTag);
  if (closeIndex < 0) {
    let partialOpenIndex = lookup.indexOf(openTag);
    if (partialOpenIndex >= 0) {
      let beforeThinking = rawContent.substring(0, partialOpenIndex).trim();
      let thinkingContent = rawContent.substring(partialOpenIndex + openTag.length).trim();
      return {
        content: beforeThinking,
        thinkingContent: thinkingContent
      };
    }
    return {
      content: rawContent,
      thinkingContent: ''
    };
  }

  let openIndex = lookup.lastIndexOf(openTag, closeIndex);
  let thinkingStart = openIndex >= 0 ? openIndex + openTag.length : 0;
  let beforeThinking = openIndex >= 0 ? rawContent.substring(0, openIndex).trim() : '';
  let thinkingContent = rawContent.substring(thinkingStart, closeIndex).trim();
  let afterThinking = rawContent.substring(closeIndex + closeTag.length).trim();
  let visibleContent = afterThinking;
  if (beforeThinking.length > 0) {
    visibleContent = afterThinking.length > 0 ? beforeThinking + '\n\n' + afterThinking : beforeThinking;
  }
  return {
    content: visibleContent,
    thinkingContent: thinkingContent
  };
}

function normalizeAssistantMessageContent(role: ChatMessageRole, kind: ChatMessageKind,
  content: string): ChatAssistantThinkingParts {
  if (role === 'assistant' && kind === CHAT_MESSAGE_KIND_CHAT) {
    return splitAssistantThinkingContent(content);
  }
  return {
    content: content,
    thinkingContent: ''
  };
}

export function createChatMessage(id: string, role: ChatMessageRole, kind: ChatMessageKind, content: string,
  createdAt: number, trace: string[] = [], imagePath: string = ''): ChatMessage {
  let parts = normalizeAssistantMessageContent(role, kind, content);
  return {
    id: id,
    role: role,
    kind: kind,
    content: parts.content,
    thinkingContent: parts.thinkingContent,
    thinkingCollapsed: true,
    trace: trace,
    collapsed: kind === CHAT_MESSAGE_KIND_TASK_TRACE,
    createdAt: createdAt,
    imagePath: imagePath
  };
}

export function chatMessageImagePath(message: ChatMessage): string {
  return message.imagePath === undefined ? '' : message.imagePath;
}

export function chatMessageThinkingContent(message: ChatMessage): string {
  return message.thinkingContent === undefined ? '' : message.thinkingContent;
}

export function chatMessageThinkingCollapsed(message: ChatMessage): boolean {
  return message.thinkingCollapsed === undefined ? true : message.thinkingCollapsed;
}

export function chatSessionPreview(messages: ChatMessage[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    let message = messages[i];
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      continue;
    }
    let text = message.content.trim().replace(/\s+/g, ' ');
    if (text.length > 0) {
      return text.length > 36 ? text.substring(0, 36) + '...' : text;
    }
  }
  return '暂无消息';
}

export function chatSessionTitleFromMessages(mode: string, messages: ChatMessage[]): string {
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    if (message.role === 'user' && message.content.trim().length > 0) {
      let text = message.content.trim().replace(/\s+/g, ' ');
      return text.length > 18 ? text.substring(0, 18) + '...' : text;
    }
  }
  return defaultChatSessionTitle(mode);
}

export function buildChatSessionSummary(session: ChatSessionRecord, fileName: string): ChatSessionSummary {
  return {
    id: session.id,
    title: chatSessionTitleFromMessages(session.mode, session.messages),
    mode: normalizeChatMode(session.mode),
    fileName: fileName,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    messageCount: session.messages.length,
    lastMessagePreview: chatSessionPreview(session.messages)
  };
}

export function toggleChatMessageCollapsed(messages: ChatMessage[], messageId: string): ChatMessage[] {
  let next: ChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    if (message.id === messageId && message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      next.push({
        id: message.id,
        role: message.role,
        kind: message.kind,
        content: message.content,
        thinkingContent: chatMessageThinkingContent(message),
        thinkingCollapsed: chatMessageThinkingCollapsed(message),
        trace: message.trace.slice(),
        collapsed: !message.collapsed,
        createdAt: message.createdAt,
        imagePath: chatMessageImagePath(message)
      });
    } else {
      next.push(message);
    }
  }
  return next;
}

export function toggleChatMessageThinkingCollapsed(messages: ChatMessage[], messageId: string): ChatMessage[] {
  let next: ChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    if (message.id === messageId && chatMessageThinkingContent(message).length > 0) {
      next.push({
        id: message.id,
        role: message.role,
        kind: message.kind,
        content: message.content,
        thinkingContent: chatMessageThinkingContent(message),
        thinkingCollapsed: !chatMessageThinkingCollapsed(message),
        trace: message.trace.slice(),
        collapsed: message.collapsed,
        createdAt: message.createdAt,
        imagePath: chatMessageImagePath(message)
      });
    } else {
      next.push(message);
    }
  }
  return next;
}

export function chatMessageRenderKey(message: ChatMessage): string {
  return message.id + ':' + message.kind + ':' + String(message.trace.length) + ':' +
    (message.collapsed ? '1' : '0') + ':' + String(message.content.length) + ':' +
    String(chatMessageThinkingContent(message).length) + ':' + (chatMessageThinkingCollapsed(message) ? '1' : '0') +
    ':' + chatMessageImagePath(message);
}

export function buildCloudContextMessages(messages: ChatMessage[]): CloudChatMessage[] {
  let context: CloudChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    let content = message.content.trim();
    if (content.length === 0 || message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      continue;
    }
    if (message.role === 'user' || message.role === 'assistant' || message.role === 'system') {
      context.push({
        role: message.role,
        content: content
      });
    } else if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
      context.push({
        role: 'assistant',
        content: content
      });
    }
  }
  return context;
}
