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
      expect(source.keyFor(initial)).assertEqual(source.keyFor(streamed));
    });

    it('reusesUiModelWhenStreamingContentUpdatesWithStableKey', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '', 1001);
      let streamed: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理更多内容', 1001);
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([initial]);
      let initialModel = source.getData(0);
      source.setMessages([streamed]);
      let streamedModel = source.getData(0);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(0);
      expect(initialModel === streamedModel).assertTrue();
      expect(streamedModel.detail.content).assertEqual('正在整理更多内容');
    });

    it('reusesUiModelWhenObservedDetailFieldsUpdateWithStableKey', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '', 1001, [], '');
      let streamed: ChatMessage = createChatMessage('m2', 'assistant', 'chat',
        '<think>先分析问题</think>最终回答', 1001, ['工具调用完成'], '/tmp/snapshot.png');
      streamed.thinkingCollapsed = false;
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([initial]);
      let initialModel = source.getData(0);
      source.setMessages([streamed]);
      let streamedModel = source.getData(0);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(0);
      expect(initialModel === streamedModel).assertTrue();
      expect(streamedModel.detail.content).assertEqual('最终回答');
      expect(streamedModel.detail.thinkingContent).assertEqual('先分析问题');
      expect(streamedModel.detail.thinkingCollapsed).assertFalse();
      expect(streamedModel.detail.trace.length).assertEqual(1);
      expect(streamedModel.detail.trace[0]).assertEqual('工具调用完成');
      expect(streamedModel.detail.imagePath).assertEqual('/tmp/snapshot.png');
      expect(streamedModel.detail.imagePaths.length).assertEqual(1);
      expect(streamedModel.detail.imagePaths[0]).assertEqual('/tmp/snapshot.png');
    });

    it('reusesUiModelWhenMultipleImageAttachmentsUpdateWithStableKey', 0, () => {
      let initial: ChatMessage = createChatMessage('m3', 'user', 'chat', '看看这些图片', 1002, [], '', []);
      let withImages: ChatMessage = createChatMessage('m3', 'user', 'chat', '看看这些图片', 1002, [],
        'photo://image/1', ['photo://image/1', 'photo://image/2']);
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([initial]);
      let initialModel = source.getData(0);
      source.setMessages([withImages]);
      let withImagesModel = source.getData(0);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(0);
      expect(initialModel === withImagesModel).assertTrue();
      expect(withImagesModel.detail.imagePath).assertEqual('photo://image/1');
      expect(withImagesModel.detail.imagePaths.length).assertEqual(2);
      expect(withImagesModel.detail.imagePaths[1]).assertEqual('photo://image/2');
    });

    it('reusesUiModelWhenStreamingRenderPhaseChangesWithStableKey', 0, () => {
      let initial: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理', 1001);
      initial.streamingActive = true;
      initial.streamingVersion = 1;
      let completed: ChatMessage = createChatMessage('m2', 'assistant', 'chat', '正在整理完成', 1001);
      completed.streamingActive = false;
      completed.streamingVersion = 2;
      let source: ChatMessageDataSource = new ChatMessageDataSource();
      let recorder: ChatMessageDataChangeRecorder = new ChatMessageDataChangeRecorder();
      source.registerDataChangeListener(recorder);

      source.setMessages([initial]);
      let initialModel = source.getData(0);
      source.setMessages([completed]);
      let completedModel = source.getData(0);

      expect(recorder.reloadCount).assertEqual(1);
      expect(recorder.changedIndexes.length).assertEqual(0);
      expect(initialModel === completedModel).assertTrue();
      expect(completedModel.detail.content).assertEqual('正在整理完成');
      expect(completedModel.detail.streamingActive).assertFalse();
      expect(completedModel.detail.streamingVersion).assertEqual(2);
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
