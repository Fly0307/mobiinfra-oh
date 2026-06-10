import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatModeActionLabel,
  chatModeLabel,
  chatModePlaceholder,
  isSupportedChatMode
} from '../main/ets/pages/chat/ChatPageTypes';

export default function chatPageTypesUnitTest() {
  describe('chatPageTypesUnitTest', () => {
    it('defaultsToCloudAgentLabels', 0, () => {
      expect(chatModeLabel(CHAT_MODE_CLOUD_AGENT)).assertEqual('云端智能体');
      expect(chatModePlaceholder(CHAT_MODE_CLOUD_AGENT)).assertEqual('发消息或输入任务...');
      expect(chatModeActionLabel(CHAT_MODE_CLOUD_AGENT)).assertEqual('发送');
    });

    it('keepsLocalInferenceAsSecondaryMode', 0, () => {
      expect(chatModeLabel(CHAT_MODE_LOCAL_INFERENCE)).assertEqual('本地推理');
      expect(isSupportedChatMode(CHAT_MODE_LOCAL_INFERENCE)).assertTrue();
      expect(isSupportedChatMode('unknown')).assertFalse();
    });
  });
}
