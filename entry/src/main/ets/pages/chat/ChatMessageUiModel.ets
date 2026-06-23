import {
  ChatMessage,
  ChatMessageKind,
  ChatMessageRole,
  chatMessageImagePath,
  chatMessageStableRenderKey,
  chatMessageThinkingCollapsed,
  chatMessageThinkingContent
} from './ChatSessionTypes';

@Observed
export class ChatMessageDetailUiModel {
  content: string = '';
  thinkingContent: string = '';
  thinkingCollapsed: boolean = true;
  trace: string[] = [];
  collapsed: boolean = false;
  imagePath: string = '';

  apply(message: ChatMessage): void {
    if (this.content !== message.content) {
      this.content = message.content;
    }
    let nextThinkingContent = chatMessageThinkingContent(message);
    if (this.thinkingContent !== nextThinkingContent) {
      this.thinkingContent = nextThinkingContent;
    }
    let nextThinkingCollapsed = chatMessageThinkingCollapsed(message);
    if (this.thinkingCollapsed !== nextThinkingCollapsed) {
      this.thinkingCollapsed = nextThinkingCollapsed;
    }
    if (this.shouldReplaceTrace(message.trace)) {
      this.trace = message.trace.slice();
    }
    if (this.collapsed !== message.collapsed) {
      this.collapsed = message.collapsed;
    }
    let nextImagePath = chatMessageImagePath(message);
    if (this.imagePath !== nextImagePath) {
      this.imagePath = nextImagePath;
    }
  }

  private shouldReplaceTrace(nextTrace: string[]): boolean {
    if (this.trace.length !== nextTrace.length) {
      return true;
    }
    for (let i = 0; i < nextTrace.length; i++) {
      if (this.trace[i] !== nextTrace[i]) {
        return true;
      }
    }
    return false;
  }
}

@Observed
export class ChatMessageUiModel {
  id: string = '';
  role: ChatMessageRole = 'assistant';
  kind: ChatMessageKind = 'chat';
  createdAt: number = 0;
  detail: ChatMessageDetailUiModel = new ChatMessageDetailUiModel();

  constructor(message: ChatMessage) {
    this.id = message.id;
    this.role = message.role;
    this.kind = message.kind;
    this.createdAt = message.createdAt;
    this.detail.apply(message);
  }

  stableKey(): string {
    return this.id + ':' + this.kind;
  }

  apply(message: ChatMessage): void {
    if (this.id !== message.id) {
      this.id = message.id;
    }
    if (this.role !== message.role) {
      this.role = message.role;
    }
    if (this.kind !== message.kind) {
      this.kind = message.kind;
    }
    if (this.createdAt !== message.createdAt) {
      this.createdAt = message.createdAt;
    }
    this.detail.apply(message);
  }

  toChatMessage(): ChatMessage {
    return {
      id: this.id,
      role: this.role,
      kind: this.kind,
      content: this.detail.content,
      thinkingContent: this.detail.thinkingContent,
      thinkingCollapsed: this.detail.thinkingCollapsed,
      trace: this.detail.trace.slice(),
      collapsed: this.detail.collapsed,
      createdAt: this.createdAt,
      imagePath: this.detail.imagePath
    };
  }
}

export function chatMessageUiModelStableKey(model: ChatMessageUiModel): string {
  return model.stableKey();
}

export function chatMessageUiModelRawStableKey(message: ChatMessage): string {
  return chatMessageStableRenderKey(message);
}
