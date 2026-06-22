import { CloudChatMessage } from '../../utils/CloudModelClient';
import { CHAT_MODE_CLOUD_AGENT, CHAT_MODE_LOCAL_INFERENCE, chatModeLabel } from './ChatPageTypes';

export { CHAT_MODE_CLOUD_AGENT, CHAT_MODE_LOCAL_INFERENCE };

export type ChatMessageRole = 'user' | 'assistant' | 'system' | 'task';
export type ChatMessageKind = 'chat' | 'task_result' | 'task_trace' | 'context_notice';

export const CHAT_MESSAGE_KIND_CHAT: ChatMessageKind = 'chat';
export const CHAT_MESSAGE_KIND_TASK_RESULT: ChatMessageKind = 'task_result';
export const CHAT_MESSAGE_KIND_TASK_TRACE: ChatMessageKind = 'task_trace';
export const CHAT_MESSAGE_KIND_CONTEXT_NOTICE: ChatMessageKind = 'context_notice';

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
  customTitle?: string;
  pinned?: boolean;
  pinnedAt?: number;
}

export interface ChatSessionRecord {
  id: string;
  title: string;
  mode: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMessage[];
  contextSummary?: string;
  contextSummaryUpdatedAt?: number;
  contextSummaryUntilMessageId?: string;
  contextSummaryMessageCount?: number;
  customTitle?: string;
  pinned?: boolean;
  pinnedAt?: number;
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
    messages: [],
    contextSummary: '',
    contextSummaryUpdatedAt: 0,
    contextSummaryUntilMessageId: '',
    contextSummaryMessageCount: 0,
    customTitle: '',
    pinned: false,
    pinnedAt: 0
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

export function chatMessageCopyContent(message: ChatMessage): string {
  // 复制整条消息时使用当前可见正文；assistant 的 think 内容在 createChatMessage 阶段已拆出。
  return message.content;
}

function isCompactPreviewWhitespace(ch: string): boolean {
  return ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' || ch === '\f' || ch === '\v';
}

export function compactChatPreviewText(content: string, maxLength: number): string {
  if (maxLength <= 0 || content.length === 0) {
    return '';
  }
  let scanLimit = Math.min(content.length, 4096);
  let result = '';
  let pendingSpace = false;
  for (let i = 0; i < scanLimit; i++) {
    let ch = content.charAt(i);
    if (isCompactPreviewWhitespace(ch)) {
      if (result.length > 0) {
        pendingSpace = true;
      }
      continue;
    }
    if (pendingSpace && result.length > 0) {
      result += ' ';
      if (result.length > maxLength) {
        break;
      }
    }
    result += ch;
    pendingSpace = false;
    if (result.length > maxLength) {
      break;
    }
  }
  if (result.length > maxLength) {
    return result.substring(0, maxLength) + '...';
  }
  return result;
}

export function chatSessionPreview(messages: ChatMessage[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    let message = messages[i];
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      continue;
    }
    let text = compactChatPreviewText(message.content, 36);
    if (text.length > 0) {
      return text;
    }
  }
  return '暂无消息';
}

export function chatSessionTitleFromMessages(mode: string, messages: ChatMessage[]): string {
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    if (message.role === 'user') {
      let text = compactChatPreviewText(message.content, 18);
      if (text.length > 0) {
        return text;
      }
    }
  }
  return defaultChatSessionTitle(mode);
}

function normalizedSessionCustomTitle(value?: string): string {
  return value === undefined ? '' : value.trim();
}

function chatSessionDisplayTitle(session: ChatSessionRecord): string {
  let customTitle = normalizedSessionCustomTitle(session.customTitle);
  if (customTitle.length > 0) {
    return customTitle;
  }
  return chatSessionTitleFromMessages(session.mode, session.messages);
}

export function buildChatSessionSummary(session: ChatSessionRecord, fileName: string): ChatSessionSummary {
  let customTitle = normalizedSessionCustomTitle(session.customTitle);
  let pinned = session.pinned === true;
  return {
    id: session.id,
    title: chatSessionDisplayTitle(session),
    mode: normalizeChatMode(session.mode),
    fileName: fileName,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    messageCount: session.messages.length,
    lastMessagePreview: chatSessionPreview(session.messages),
    customTitle: customTitle,
    pinned: pinned,
    pinnedAt: pinned && session.pinnedAt !== undefined ? session.pinnedAt : 0
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

export function chatSessionRenderKey(session: ChatSessionSummary): string {
  // ForEach 只用会话 id 作为 key 时会复用旧列表项，导致重命名/置顶后抽屉内展示不能立即刷新。
  return session.id + ':' + session.title + ':' + (session.pinned === true ? '1' : '0') + ':' +
    String(session.pinnedAt === undefined ? 0 : session.pinnedAt) + ':' + String(session.updatedAt) + ':' +
    String(session.messageCount) + ':' + session.lastMessagePreview;
}

export function chatMessagesAutoScrollKey(sessionId: string, messages: ChatMessage[], thinking: boolean): string {
  let normalizedSessionId = sessionId.length > 0 ? sessionId : 'no-session';
  let latestMessageKey = messages.length > 0 ? chatMessageRenderKey(messages[messages.length - 1]) : 'empty';
  return normalizedSessionId + ':' + String(messages.length) + ':' + latestMessageKey + ':' +
    (thinking ? 'thinking' : 'idle');
}

export function buildCloudContextMessages(messages: ChatMessage[]): CloudChatMessage[] {
  let context: CloudChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    let content = message.content.trim();
    if (content.length === 0 || message.kind === CHAT_MESSAGE_KIND_TASK_TRACE ||
      message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
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
