import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_MESSAGE_KIND_CHAT,
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  createChatMessage
} from '../main/ets/pages/chat/ChatSessionTypes';
import {
  chatAvatarRenderModel,
  useDigitalAvatarForMessage
} from '../main/ets/pages/chat/DigitalAvatarTypes';

export default function digitalAvatarTypesUnitTest() {
  describe('digitalAvatarTypesUnitTest', () => {
    it('assistantChatUsesDigitalAvatarWithModeFallback', 0, () => {
      let message = createChatMessage('assistant-1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '你好', 1);

      let model = chatAvatarRenderModel(message, '云', 'idle');

      expect(useDigitalAvatarForMessage(message)).assertTrue();
      expect(model.useDigitalAvatar).assertTrue();
      expect(model.fallbackText).assertEqual('云');
      expect(model.fallbackColor).assertEqual('#5968FF');
      expect(model.visualState).assertEqual('idle');
    });

    it('assistantThinkingStateIsPropagated', 0, () => {
      let message = createChatMessage('assistant-2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '', 2);

      let model = chatAvatarRenderModel(message, '本', 'thinking');

      expect(model.useDigitalAvatar).assertTrue();
      expect(model.fallbackText).assertEqual('本');
      expect(model.visualState).assertEqual('thinking');
    });

    it('userMessageKeepsTextAvatar', 0, () => {
      let message = createChatMessage('user-1', 'user', CHAT_MESSAGE_KIND_CHAT, '问题', 3);

      let model = chatAvatarRenderModel(message, '云', 'idle');

      expect(useDigitalAvatarForMessage(message)).assertFalse();
      expect(model.useDigitalAvatar).assertFalse();
      expect(model.fallbackText).assertEqual('我');
      expect(model.fallbackColor).assertEqual('#111827');
    });

    it('contextNoticeKeepsCompressionAvatar', 0, () => {
      let message = createChatMessage('context-1', 'system', CHAT_MESSAGE_KIND_CONTEXT_NOTICE, '上下文已压缩', 4);

      let model = chatAvatarRenderModel(message, '云', 'idle');

      expect(model.useDigitalAvatar).assertFalse();
      expect(model.fallbackText).assertEqual('压');
      expect(model.fallbackColor).assertEqual('#F59E0B');
    });

    it('taskMessagesKeepTaskAvatar', 0, () => {
      let taskResult = createChatMessage('task-result-1', 'task', CHAT_MESSAGE_KIND_TASK_RESULT, '完成', 5);
      let taskTrace = createChatMessage('task-trace-1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '过程', 6);

      let resultModel = chatAvatarRenderModel(taskResult, '云', 'idle');
      let traceModel = chatAvatarRenderModel(taskTrace, '云', 'idle');

      expect(resultModel.useDigitalAvatar).assertFalse();
      expect(resultModel.fallbackText).assertEqual('任');
      expect(resultModel.fallbackColor).assertEqual('#059669');
      expect(traceModel.useDigitalAvatar).assertFalse();
      expect(traceModel.fallbackText).assertEqual('任');
      expect(traceModel.fallbackColor).assertEqual('#7C3AED');
    });
  });
}
