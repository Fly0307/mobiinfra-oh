import { ChatMessage, chatMessageStableRenderKey } from './ChatSessionTypes';
import {
  ChatMessageUiModel,
  chatMessageUiModelRawStableKey,
  chatMessageUiModelStableKey
} from './ChatMessageUiModel';

export class ChatMessageDataSource implements IDataSource {
  private messages: ChatMessageUiModel[] = [];
  private listeners: DataChangeListener[] = [];

  setMessages(messages: ChatMessage[]): void {
    let previousMessages: ChatMessageUiModel[] = this.messages;
    let shouldReload = this.shouldReload(previousMessages, messages);
    this.messages = this.reconcileMessages(previousMessages, messages);
    if (shouldReload) {
      this.notifyDataReloaded();
    }
  }

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): ChatMessageUiModel {
    return this.messages[index];
  }

  keyFor(message: ChatMessage | ChatMessageUiModel): string {
    return message.id + ':' + message.kind;
  }

  stableKeyFor(message: ChatMessage | ChatMessageUiModel): string {
    return message.id + ':' + message.kind;
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

  private shouldReload(previousMessages: ChatMessageUiModel[], nextMessages: ChatMessage[]): boolean {
    if (previousMessages.length !== nextMessages.length) {
      return true;
    }
    for (let i = 0; i < nextMessages.length; i++) {
      if (chatMessageUiModelStableKey(previousMessages[i]) !== chatMessageStableRenderKey(nextMessages[i])) {
        return true;
      }
    }
    return false;
  }

  private reconcileMessages(previousMessages: ChatMessageUiModel[], nextMessages: ChatMessage[]): ChatMessageUiModel[] {
    let usedPreviousIndexes: boolean[] = [];
    for (let i = 0; i < previousMessages.length; i++) {
      usedPreviousIndexes.push(false);
    }
    let nextModels: ChatMessageUiModel[] = [];
    for (let index = 0; index < nextMessages.length; index++) {
      let message = nextMessages[index];
      let model = this.reusableModelForMessage(previousMessages, usedPreviousIndexes, message, index);
      model.apply(message);
      nextModels.push(model);
    }
    return nextModels;
  }

  private reusableModelForMessage(previousMessages: ChatMessageUiModel[], usedPreviousIndexes: boolean[],
    message: ChatMessage, preferredIndex: number): ChatMessageUiModel {
    let messageKey = chatMessageUiModelRawStableKey(message);
    if (preferredIndex < previousMessages.length && !usedPreviousIndexes[preferredIndex] &&
      chatMessageUiModelStableKey(previousMessages[preferredIndex]) === messageKey) {
      usedPreviousIndexes[preferredIndex] = true;
      return previousMessages[preferredIndex];
    }
    for (let index = 0; index < previousMessages.length; index++) {
      if (usedPreviousIndexes[index]) {
        continue;
      }
      if (chatMessageUiModelStableKey(previousMessages[index]) === messageKey) {
        usedPreviousIndexes[index] = true;
        return previousMessages[index];
      }
    }
    return new ChatMessageUiModel(message);
  }
}
