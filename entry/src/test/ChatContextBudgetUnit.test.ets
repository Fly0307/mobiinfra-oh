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
  CHAT_CONTEXT_COMPRESSION_NOTICE,
  CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS,
  CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS,
  CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT,
  CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS,
  buildChatContextBudgetSettings,
  buildCloudContextMessagesAfterExistingSummaryCoverage,
  buildCloudContextMessagesWithCurrentRequest,
  buildCompressedCloudContextMessages,
  buildContextSummarySystemMessage,
  buildLocalExtractiveFallbackSummary,
  buildLocalExtractiveChatSummary,
  estimateCloudChatMessagesTokens,
  contextSummaryMessageCountForCoverage,
  hasContextCompressionNotice,
  messagesAfterExistingContextSummaryCoverage,
  messagesAfterContextSummaryUntil,
  messagesAfterKnownContextSummaryCoverage,
  messagesWithoutCurrentRequest,
  nonRetreatingContextSummaryUntilMessageId,
  normalizeChatContextBudgetSettings,
  shouldAppendContextCompressionNotice,
  shouldCompressChatContext,
  splitChatMessagesForContextCompressionExact,
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

    it('doesNotRepeatOlderMessagesWhenExistingCoverageIsOutsideSplit', 0, () => {
      let olderMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001)
      ];

      let delta = messagesAfterKnownContextSummaryCoverage(olderMessages, 'u3');

      expect(delta.length).assertEqual(0);
    });

    it('detectsExistingContextCompressionNoticeAndAvoidsDuplicateAppend', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        contextNoticeMessage('notice1', CHAT_CONTEXT_COMPRESSION_NOTICE, 1001),
        contextNoticeMessage('notice2', '其他上下文提示', 1002)
      ];

      expect(hasContextCompressionNotice(messages)).assertTrue();
      expect(shouldAppendContextCompressionNotice(messages, true)).assertFalse();
      expect(shouldAppendContextCompressionNotice(messages, false)).assertFalse();
      expect(shouldAppendContextCompressionNotice([messages[0]], true)).assertTrue();
    });

    it('returnsMessagesAfterExistingSummaryCoverageTail', 0, () => {
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '第二轮问题', 1002),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第二轮回答', 1003)
      ];

      let delta = messagesAfterExistingContextSummaryCoverage(historyMessages, 'a1');

      expect(delta.length).assertEqual(2);
      expect(delta[0].id).assertEqual('u2');
      expect(delta[1].id).assertEqual('a2');
    });

    it('returnsEmptyMessagesWhenExistingSummaryCoverageIsEmpty', 0, () => {
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001)
      ];

      let delta = messagesAfterExistingContextSummaryCoverage(historyMessages, '');

      expect(delta.length).assertEqual(0);
    });

    it('returnsEmptyMessagesWhenExistingSummaryCoverageIsMissing', 0, () => {
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001)
      ];

      let delta = messagesAfterExistingContextSummaryCoverage(historyMessages, 'missing');

      expect(delta.length).assertEqual(0);
    });

    it('buildsCloudContextFromExistingSummaryCoverageTailAndCurrentRequest', 0, () => {
      let dateMessage: CloudChatMessage = {
        role: 'system',
        content: '当前日期: 2026-06-22'
      };
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '已摘要问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '已摘要回答', 1001),
        contextNoticeMessage('notice1', CHAT_CONTEXT_COMPRESSION_NOTICE, 1002),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '尾部问题', 1003),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '尾部回答', 1004)
      ];
      let currentRequest = createChatMessage('u3', 'user', CHAT_MESSAGE_KIND_CHAT, '当前请求', 1005);

      let context = buildCloudContextMessagesAfterExistingSummaryCoverage(dateMessage, '既有摘要', historyMessages,
        'a1', currentRequest);

      expect(context.length).assertEqual(4);
      expect(context[0].role).assertEqual('system');
      expect((context[0].content as string).indexOf('既有摘要') >= 0).assertTrue();
      expect(context[1].content as string).assertEqual('尾部问题');
      expect(context[2].content as string).assertEqual('尾部回答');
      expect(context[3].content as string).assertEqual('当前请求');
    });

    it('keepsLaterExistingCoverageAndMessageCountWhenCandidateWouldRetreat', 0, () => {
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮回答', 1001),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '第二轮问题', 1002),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第二轮回答', 1003),
        createChatMessage('u3', 'user', CHAT_MESSAGE_KIND_CHAT, '第三轮问题', 1004)
      ];

      let coverageId = nonRetreatingContextSummaryUntilMessageId(historyMessages, 'u3', 'a1');
      let messageCount = contextSummaryMessageCountForCoverage(historyMessages, coverageId, 2);

      expect(coverageId).assertEqual('u3');
      expect(messageCount).assertEqual(5);
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

      expect(context.length).assertEqual(3);
      expect(context[0].role).assertEqual('system');
      expect((context[0].content as string).indexOf('当前日期: 2026-06-22') >= 0).assertTrue();
      expect((context[0].content as string).indexOf('旧历史摘要') >= 0).assertTrue();
      expect(context[1].role).assertEqual('user');
      expect(context[1].content as string).assertEqual('最近问题');
      expect(context[2].role).assertEqual('assistant');
      expect(context[2].content as string).assertEqual('最近回答');
    });

    it('removesCurrentRequestFromHistoryBeforeCompression', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '历史问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '历史回答', 1001),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '本轮问题', 1002)
      ];

      let historyMessages = messagesWithoutCurrentRequest(messages, 'u2');

      expect(historyMessages.length).assertEqual(2);
      expect(historyMessages[0].id).assertEqual('u1');
      expect(historyMessages[1].id).assertEqual('a1');
    });

    it('placesCurrentRequestAtCompressedCloudContextTail', 0, () => {
      let dateMessage: CloudChatMessage = {
        role: 'system',
        content: '当前日期: 2026-06-22'
      };
      let retained: ChatMessage[] = [
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '最近历史问题', 1004),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '最近历史回答', 1005)
      ];
      let currentRequest = createChatMessage('u3', 'user', CHAT_MESSAGE_KIND_CHAT, '本轮必须回答的问题', 1006);

      let context = buildCloudContextMessagesWithCurrentRequest(dateMessage, '旧历史摘要', retained,
        currentRequest);

      expect(context.length).assertEqual(4);
      expect(context[0].role).assertEqual('system');
      expect((context[0].content as string).indexOf('旧历史摘要') >= 0).assertTrue();
      expect(context[context.length - 1].role).assertEqual('user');
      expect(context[context.length - 1].content as string).assertEqual('本轮必须回答的问题');
      expect(context[1].content as string).assertEqual('最近历史问题');
      expect(context[2].content as string).assertEqual('最近历史回答');
    });

    it('keepsCurrentRequestOutOfOlderMessagesWhenHistoryIsSplit', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '历史问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '历史回答', 1001),
        createChatMessage('trace1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '轨迹不进入上下文', 1002),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '本轮问题', 1003)
      ];

      let historyMessages = messagesWithoutCurrentRequest(messages, 'u2');
      let split = splitChatMessagesForContextCompressionExact(historyMessages, 0);

      expect(split.olderMessages.length).assertEqual(2);
      expect(split.olderMessages[0].id).assertEqual('u1');
      expect(split.olderMessages[1].id).assertEqual('a1');
      expect(split.summaryUntilMessageId).assertEqual('a1');
    });

    it('allowsZeroRecentRoundsAndStillKeepsOnlyCurrentRequestInCloudContext', 0, () => {
      let dateMessage: CloudChatMessage = {
        role: 'system',
        content: '当前日期: 2026-06-22'
      };
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '第一轮历史问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第一轮历史回答', 1001),
        contextNoticeMessage('notice1', '压缩提示不进入上下文', 1002),
        createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '第二轮历史问题', 1003),
        createChatMessage('a2', 'assistant', CHAT_MESSAGE_KIND_CHAT, '第二轮历史回答', 1004)
      ];
      let currentRequest = createChatMessage('u3', 'user', CHAT_MESSAGE_KIND_CHAT, '本轮问题', 1005);

      let split = splitChatMessagesForContextCompressionExact(historyMessages, 0);
      let context = buildCloudContextMessagesWithCurrentRequest(dateMessage, '历史摘要', split.retainedMessages,
        currentRequest);

      expect(split.olderMessages.length).assertEqual(4);
      expect(split.retainedMessages.length).assertEqual(0);
      expect(split.retainedRoundCount).assertEqual(0);
      expect(context.length).assertEqual(2);
      expect(context[0].role).assertEqual('system');
      expect((context[0].content as string).indexOf('历史摘要') >= 0).assertTrue();
      expect(context[context.length - 1].role).assertEqual('user');
      expect(context[context.length - 1].content as string).assertEqual('本轮问题');
    });

    it('buildsZeroRoundContextFromExistingAndDeltaSummariesWithCurrentTail', 0, () => {
      let dateMessage: CloudChatMessage = {
        role: 'system',
        content: '当前日期: 2026-06-22'
      };
      let existingSummary = '既有摘要：用户正在整理截图，已确认输出时间线。';
      let historyMessages: ChatMessage[] = [
        createChatMessage('u1', 'user', CHAT_MESSAGE_KIND_CHAT, '历史里新增的用户问题', 1000),
        createChatMessage('a1', 'assistant', CHAT_MESSAGE_KIND_CHAT, '历史里新增的助手回答', 1001)
      ];
      let currentRequest = createChatMessage('u2', 'user', CHAT_MESSAGE_KIND_CHAT, '本轮继续追问', 1002);

      let split = splitChatMessagesForContextCompressionExact(historyMessages, 0);
      let summary = buildLocalExtractiveChatSummary(existingSummary, split.olderMessages);
      let context = buildCloudContextMessagesWithCurrentRequest(dateMessage, summary, split.retainedMessages,
        currentRequest);
      let summaryContent = context[0].content as string;

      expect(context.length).assertEqual(2);
      expect(context[0].role).assertEqual('system');
      expect(summaryContent.indexOf(existingSummary) >= 0).assertTrue();
      expect(summaryContent.indexOf('历史里新增的用户问题') >= 0).assertTrue();
      expect(summaryContent.indexOf('历史里新增的助手回答') >= 0).assertTrue();
      expect(context[context.length - 1].role).assertEqual('user');
      expect(context[context.length - 1].content as string).assertEqual('本轮继续追问');
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
