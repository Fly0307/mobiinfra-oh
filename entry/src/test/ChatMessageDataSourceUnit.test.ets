import { describe, it, expect } from '@ohos/hypium';
import { ChatMessageDataSource } from '../main/ets/pages/chat/ChatMessageDataSource';
import { ChatMessage, chatMessageStableRenderKey, createChatMessage } from '../main/ets/pages/chat/ChatSessionTypes';

class ChatMessageDataChangeRecorder implements DataChangeListener {
  reloadCount: number = 0;
  changedIndexes: number[] = [];

  onDataReloaded(): void {
    this.reloadCount += 1;
  }

  onDatasetChange(): void {
    this.reloadCount += 1;
  }

  onDataAdd(_index: number): void {
  }

  onDataAdded(_index: number): void {
  }

  onDataMove(_from: number, _to: number): void {
  }

  onDataMoved(_from: number, _to: number): void {
  }

  onDataDelete(_index: number): void {
  }

  onDataDeleted(_index: number): void {
  }

  onDataChange(index: number): void {
    this.changedIndexes.push(index);
  }

  onDataChanged(index: number): void {
    this.changedIndexes.push(index);
  }
}

export default function chatMessageDataSourceUnitTest() {
  describe('chatMessageDataSourceUnitTest', () => {
    it('setMessagesExposesTotalCountAndIndexedData', 0, () => {
      let first: ChatMessage = createChatMessage('m1', 'user', 'chat', 'hello', 1000);
      let second: ChatMessage = createChatMessage('m2', 'assistant', 'chat', 'world', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();

      source.setMessages([first, second]);

      expect(source.totalCount()).assertEqual(2);
      expect(source.getData(0).id).assertEqual('m1');
      expect(source.getData(1).id).assertEqual('m2');
    });

    it('stableKeyIgnoresStreamingContentChanges', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理', 1001);
      let streamed: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理更多内容', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();

      source.setMessages([initial]);

      expect(source.stableKeyFor(initial)).assertEqual(chatMessageStableRenderKey(initial));
      expect(source.stableKeyFor(initial)).assertEqual(source.stableKeyFor(streamed));
      expect(source.keyFor(initial) === source.keyFor(streamed)).assertFalse();
    });

    it('notifiesDataChangeWhenStreamingContentUpdatesWithStableKey', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '', 1001);
      let streamed: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理更多内容', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([initial]);
      source.setMessages([streamed]);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(1);
      expect(recorder.changedIndexes[0]).assertEqual(0);
    });

    it('reloadsWhenMessageCountOrStableKeyOrderChanges', 0, () => {
      let first: ChatMessage = createChatMessage('m1', 'user', 'chat', 'hello', 1000);
      let second: ChatMessage = createChatMessage('m2', 'assistant', 'chat', 'world', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([first]);
      source.setMessages([first, second]);
      source.setMessages([second, first]);

      expect(recorder.reloadCount).assertEqual(3);
      expect(recorder.changedIndexes.length).assertEqual(0);
    });

    it('doesNotNotifyUnregisteredListener', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理', 1001);
      let streamed: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理更多内容', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);
      source.setMessages([initial]);

      source.unregisterDataChangeListener(recorder);
      source.setMessages([streamed]);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(0);
    });
  });
}
