import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatModeActionLabel,
  chatInputAfterAcceptedSend,
  chatModeLabel,
  chatModePlaceholder,
  chatModeSwitcherVisibleAfterScroll,
  cloudAgentDisplayText,
  hasCloudAgentDisplayOutput,
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
      expect(chatModePlaceholder(CHAT_MODE_LOCAL_INFERENCE)).assertEqual('输入本地模型消息...');
      expect(isSupportedChatMode(CHAT_MODE_LOCAL_INFERENCE)).assertTrue();
      expect(isSupportedChatMode('unknown')).assertFalse();
    });

    it('keepsDefaultCloudStatusOutOfConversation', 0, () => {
      expect(hasCloudAgentDisplayOutput('请先配置 Planner 和 Decider 云端服务')).assertFalse();
      expect(hasCloudAgentDisplayOutput('')).assertFalse();
    });

    it('extractsPlannerResponseAsConversationText', 0, () => {
      let logs = '[23:00:19] 手动调用 Planner，任务：你好\n' +
        '[23:00:22] Planner 手动返回：\n你好！我是 MobiAgent。';
      expect(hasCloudAgentDisplayOutput(logs)).assertTrue();
      expect(cloudAgentDisplayText(logs)).assertEqual('你好！我是 MobiAgent。');
    });

    it('clearsDraftOnlyAfterAcceptedSend', 0, () => {
      expect(chatInputAfterAcceptedSend('请问您做什么呢？', true)).assertEqual('');
      expect(chatInputAfterAcceptedSend('请问您做什么呢？', false)).assertEqual('请问您做什么呢？');
    });

    it('updatesModeSwitcherVisibilityByScrollDirection', 0, () => {
      expect(chatModeSwitcherVisibleAfterScroll(true, 8)).assertFalse();
      expect(chatModeSwitcherVisibleAfterScroll(false, -8)).assertTrue();
      expect(chatModeSwitcherVisibleAfterScroll(true, 2)).assertTrue();
      expect(chatModeSwitcherVisibleAfterScroll(false, -2)).assertFalse();
    });
  });
}
