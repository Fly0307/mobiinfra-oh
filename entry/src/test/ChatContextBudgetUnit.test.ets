import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_CHAT,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage,
  createChatMessage
} from '../main/ets/pages/chat/ChatSessionTypes';
import {
  CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS,
  CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS,
  CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT,
  CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS,
  buildChatContextBudgetSettings,
  buildCompressedCloudContextMessages,
  buildContextSummarySystemMessage,
  buildLocalExtractiveFallbackSummary,
  estimateCloudChatMessagesTokens,
  messagesAfterContextSummaryUntil,
  normalizeChatContextBudgetSettings,
  shouldCompressChatContext,
  splitChatHistoryByRecentTurns
} from '../main/ets/pages/chat/ChatContextBudget';
import { CloudChatMessage } from '../main/ets/utils/CloudModelClient';

function repeatedText(unit: string, count: number): string {
  let value = '';
  for (let i = 0; i < count; i++) {
    value += unit;
  }
  return value;
}

function contextNoticeMessage(id: string, content: string, createdAt: number): ChatMessage {
  return createChatMessage(id, 'system', CHAT_MESSAGE_KIND_CONTEXT_NOTICE, content, createdAt);
}

export default function chatContextBudgetUnitTest() {
  describe('chatContextBudgetUnitTest', () => {
    it('normalizesSettingsWithDefaultsAndClampsRanges', 0, () => {
      let defaults = normalizeChatContextBudgetSettings();
      expect(defaults.maxContextTokens).assertEqual(CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS);
      expect(defaults.thresholdPercent).assertEqual(CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT);
      expect(defaults.keepRecentTurns).assertEqual(CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS);
      expect(defaults.reservedOutputTokens).assertEqual(CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS);

      let low = normalizeChatContextBudgetSettings({
        maxContextTokens: 0,
        thresholdPercent: 30,
        keepRecentTurns: 1,
        reservedOutputTokens: -1
      });
      expect(low.maxContextTokens).assertEqual(CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS);
      expect(low.thresholdPercent).assertEqual(50);
      expect(low.keepRecentTurns).assertEqual(2);
      expect(low.reservedOutputTokens).assertEqual(CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS);

      let high = normalizeChatContextBudgetSettings({
        maxContextTokens: 4096,
        thresholdPercent: 99,
        keepRecentTurns: 99,
        reservedOutputTokens: 256
      });
      expect(high.maxContextTokens).assertEqual(4096);
      expect(high.thresholdPercent).assertEqual(95);
      expect(high.keepRecentTurns).assertEqual(20);
      expect(high.reservedOutputTokens).assertEqual(256);
    });

    it('normalizesStringInputsForSettingsPage', 0, () => {
      let settings = buildChatContextBudgetSettings('99', '1');

      expect(settings.thresholdPercent).assertEqual(95);
      expect(settings.keepRecentTurns).assertEqual(2);
      expect(settings.maxContextTokens).assertEqual(CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS);
      expect(settings.reservedOutputTokens).assertEqual(CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS);
    });

    it('estimatesCloudMessagesWithTextAndStructureOverhead', 0, () => {
      let messages: CloudChatMessage[] = [
        { role: 'system', content: '规则' },
        { role: 'user', content: '你好' },
        {
          role: 'assistant',
          content: [
            { type: 'text', text: '图片说明' },
            { type: 'image_url', image_url: { url: 'data:image/png;base64,abc' } }
          ]
        },
        {
          role: 'assistant',
          content: '',
          tool_calls: [{
            id: 'call-1',
            type: 'function',
            function: {
              name: 'lookup_note',
              arguments: '{"query":"咖啡"}'
            }
          }]
        }
      ];

      let estimated = estimateCloudChatMessagesTokens(messages);

      expect(estimated > '规则你好图片说明'.length).assertTrue();
      expect(estimated >= 4 * 16).assertTrue();
      expect(estimated >= '{"query":"咖啡"}'.length).assertTrue();
    });

    it('decidesCompressionAgainstThresholdAfterReservedOutputTokens', 0, () => {
      let messages: CloudChatMessage[] = [
        { role: 'user', content: repeatedText('问', 760) }
      ];

      let decision = shouldCompressChatContext(messages, {
        maxContextTokens: 1000,
        thresholdPercent: 85,
        keepRecentTurns: 4,
        reservedOutputTokens: 100
      });

      expect(decision.thresholdTokens).assertEqual(850);
      expect(decision.usableInputTokens).assertEqual(750);
      expect(decision.shouldCompress).assertTrue();
    });

    it('splitsHistoryByRecentUserTurnsAndSkipsTraceNotices', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001),
        createChatMessage('trace1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '工具轨迹', 1002),
        contextNoticeMessage('notice1', '上下文提示', 1003),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '第二轮问题', 1004),
        createChatMessage('r2', 'task', CHAT_MESSAGE_KIND_TASK_RESULT, '工具结果', 1005),
        createChatMessage('u3', 'user', CHAT_MESSAGE_KIND_CHAT, '第三轮问题', 1006),
        createChatMessage('a3', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第三轮回答', 1007)
      ];

      let split = splitChatHistoryByRecentTurns(messages, 2);

      expect(split.olderMessages.length).assertEqual(2);
      expect(split.olderMessages[0].id).assertEqual('u1');
      expect(split.olderMessages[1].id).assertEqual('a1');
      expect(split.recentMessages.length).assertEqual(4);
      expect(split.recentMessages[0].id).assertEqual('u2');
      expect(split.recentMessages[1].id).assertEqual('r2');
      expect(split.recentMessages[2].id).assertEqual('u3');
      expect(split.recentMessages[3].id).assertEqual('a3');
      expect(split.keptUserTurnCount).assertEqual(2);
      expect(split.skippedMessageCount).assertEqual(2);
    });

    it('selectsOnlyNewOlderMessagesAfterPreviousSummaryCoverage', 0, () => {
      let olderMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '第二轮问题', 1002),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第二轮回答', 1003)
      ];

      let delta = messagesAfterContextSummaryUntil(olderMessages, 'a1');

      expect(delta.length).assertEqual(2);
      expect(delta[0].id).assertEqual('u2');
      expect(delta[1].id).assertEqual('a2');
    });

    it('buildsContextSummarySystemMessageFromSummaryText', 0, () => {
      let summaryText = '用户想整理今天截图，助手已建议按时间线输出。';
      let message = buildContextSummarySystemMessage(summaryText);

      expect(message.role).assertEqual('system');
      expect((message.content as string).indexOf('较早对话') >= 0).assertTrue();
      expect((message.content as string).indexOf('用户想整理今天截图') >= 0).assertTrue();
    });

    it('buildsCompressedCloudContextFromDateSummaryAndRecentMessages', 0, () => {
      let dateMessage: CloudChatMessage = {
        role: 'system',
        content: '当前日期: 2026-06-22'
      };
      let retained: ChatMessage[] = [
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '最近问题', 1004),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '最近回答', 1005)
      ];

      let context = buildCompressedCloudContextMessages(dateMessage, '旧历史摘要', retained);

      expect(context.length).assertEqual(4);
      expect(context[0].content as string).assertEqual('当前日期: 2026-06-22');
      expect((context[1].content as string).indexOf('旧历史摘要') >= 0).assertTrue();
      expect(context[2].role).assertEqual('user');
      expect(context[2].content as string).assertEqual('最近问题');
      expect(context[3].role).assertEqual('assistant');
      expect(context[3].content as string).assertEqual('最近回答');
    });

    it('buildsLocalExtractiveFallbackSummaryAndDropsNonContextMessages', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '请总结今天的微信截图。', 1000),
        createChatMessage('trace1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '工具轨迹不进入摘要', 1001),
        contextNoticeMessage('notice1', '上下文提示不进入摘要', 1002),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, repeatedText('回答', 80), 1003)
      ];

      let summary = buildLocalExtractiveFallbackSummary(messages, 120);

      expect(summary.indexOf('用户: 请总结今天的微信截图。') >= 0).assertTrue();
      expect(summary.indexOf('工具轨迹不进入摘要')).assertEqual(-1);
      expect(summary.indexOf('上下文提示不进入摘要')).assertEqual(-1);
      expect(summary.length <= 120).assertTrue();
    });
  });
}
