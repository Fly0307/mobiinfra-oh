import { ChatMessage, chatMessageRenderKey, chatMessageStableRenderKey } from './ChatSessionTypes';

export class ChatMessageDataSource implements IDataSource {
  private messages: ChatMessage[] = [];
  private listeners: DataChangeListener[] = [];

  setMessages(messages: ChatMessage[]): void {
    let previousMessages: ChatMessage[] = this.messages;
    this.messages = messages.slice();
    if (this.shouldReload(previousMessages, this.messages)) {
      this.notifyDataReloaded();
      return;
    }
    this.notifyChangedMessages(previousMessages, this.messages);
  }

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): ChatMessage {
    return this.messages[index];
  }

  keyFor(message: ChatMessage): string {
    return chatMessageRenderKey(message);
  }

  stableKeyFor(message: ChatMessage): string {
    return chatMessageStableRenderKey(message);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) >= 0) {
      return;
    }
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    let next: DataChangeListener[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  private notifyDataReloaded(): void {
    // LazyForEach 根据稳定 key 复用子组件，数据整体变更时统一触发重读。
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private shouldReload(previousMessages: ChatMessage[], nextMessages: ChatMessage[]): boolean {
    if (previousMessages.length !== nextMessages.length) {
      return true;
    }
    for (let i = 0; i < nextMessages.length; i++) {
      if (this.stableKeyFor(previousMessages[i]) !== this.stableKeyFor(nextMessages[i])) {
        return true;
      }
    }
    return false;
  }

  private notifyChangedMessages(previousMessages: ChatMessage[], nextMessages: ChatMessage[]): void {
    // 结构比较使用稳定 key；实际 LazyForEach key 带内容签名，保证流式内容更新能重建当前消息正文。
    for (let index = 0; index < nextMessages.length; index++) {
      if (previousMessages[index] === nextMessages[index]) {
        continue;
      }
      for (let listenerIndex = 0; listenerIndex < this.listeners.length; listenerIndex++) {
        this.listeners[listenerIndex].onDataChange(index);
      }
    }
  }
}
