import {
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage,
  buildCloudContextMessages
} from './ChatSessionTypes';
import {
  CloudChatMessage,
  CloudContentPart,
  CloudImagePart,
  CloudTextPart,
  CloudToolCall
} from '../../utils/CloudModelClient';

export const CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS: number = 256000;
export const CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT: number = 85;
export const CHAT_CONTEXT_BUDGET_MIN_THRESHOLD_PERCENT: number = 50;
export const CHAT_CONTEXT_BUDGET_MAX_THRESHOLD_PERCENT: number = 95;
export const CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS: number = 8;
export const CHAT_CONTEXT_BUDGET_MIN_KEEP_RECENT_TURNS: number = 2;
export const CHAT_CONTEXT_BUDGET_MAX_KEEP_RECENT_TURNS: number = 20;
export const CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS: number = 32768;
export const CHAT_CONTEXT_COMPRESSION_THRESHOLD_PERCENT_DEFAULT: number =
  CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT;
export const CHAT_CONTEXT_RECENT_ROUNDS_DEFAULT: number = CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS;
export const CHAT_CONTEXT_COMPRESSION_NOTICE: string = '历史过长，已自动压缩上下文';

const CLOUD_MESSAGE_STRUCTURE_TOKEN_OVERHEAD: number = 16;
const CLOUD_CONTENT_PART_STRUCTURE_TOKEN_OVERHEAD: number = 8;
const CLOUD_IMAGE_PART_TOKEN_OVERHEAD: number = 32;
const CLOUD_TOOL_CALL_TOKEN_OVERHEAD: number = 12;
const DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS: number = 4000;
const EXTRACTIVE_SUMMARY_HEADER: string = '较早对话摘要（本地抽取）:';

export interface ChatContextCompressionSplit {
  olderMessages: ChatMessage[];
  retainedMessages: ChatMessage[];
  summaryUntilMessageId: string;
  olderMessageCount: number;
  retainedRoundCount: number;
}

export interface ChatContextBudgetSettingsInput {
  maxContextTokens?: number;
  thresholdPercent?: number;
  keepRecentTurns?: number;
  reservedOutputTokens?: number;
}

export interface ChatContextBudgetSettings {
  maxContextTokens: number;
  thresholdPercent: number;
  keepRecentTurns: number;
  reservedOutputTokens: number;
}

export interface ChatContextBudgetDecision {
  estimatedInputTokens: number;
  thresholdTokens: number;
  usableInputTokens: number;
  shouldCompress: boolean;
}

export interface ChatContextHistorySplit {
  olderMessages: ChatMessage[];
  recentMessages: ChatMessage[];
  keptUserTurnCount: number;
  skippedMessageCount: number;
}

function clampNumber(value: number, minValue: number, maxValue: number): number {
  if (value < minValue) {
    return minValue;
  }
  if (value > maxValue) {
    return maxValue;
  }
  return value;
}

function normalizePositiveNumber(value: number | undefined, fallback: number): number {
  if (value === undefined || value <= 0) {
    return fallback;
  }
  return Math.floor(value);
}

function normalizeThresholdPercent(value: number | undefined): number {
  let raw = value === undefined ? CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT : Math.floor(value);
  return clampNumber(raw, CHAT_CONTEXT_BUDGET_MIN_THRESHOLD_PERCENT, CHAT_CONTEXT_BUDGET_MAX_THRESHOLD_PERCENT);
}

function normalizeKeepRecentTurns(value: number | undefined): number {
  let raw = value === undefined ? CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS : Math.floor(value);
  return clampNumber(raw, CHAT_CONTEXT_BUDGET_MIN_KEEP_RECENT_TURNS, CHAT_CONTEXT_BUDGET_MAX_KEEP_RECENT_TURNS);
}

function parseIntegerInput(value: string, fallback: number): number {
  let parsed = Number.parseInt(value.trim(), 10);
  if (Number.isNaN(parsed)) {
    return fallback;
  }
  return Math.floor(parsed);
}

export function normalizeChatContextCompressionThresholdPercent(value: string): number {
  return normalizeThresholdPercent(parseIntegerInput(value, CHAT_CONTEXT_BUDGET_DEFAULT_THRESHOLD_PERCENT));
}

export function normalizeChatContextRecentRounds(value: string): number {
  return normalizeKeepRecentTurns(parseIntegerInput(value, CHAT_CONTEXT_BUDGET_DEFAULT_KEEP_RECENT_TURNS));
}

export function buildChatContextBudgetSettings(thresholdPercentInput: string,
  recentRoundsInput: string): ChatContextBudgetSettings {
  return normalizeChatContextBudgetSettings({
    thresholdPercent: normalizeChatContextCompressionThresholdPercent(thresholdPercentInput),
    keepRecentTurns: normalizeChatContextRecentRounds(recentRoundsInput)
  });
}

export function normalizeChatContextBudgetSettings(
  input: ChatContextBudgetSettingsInput = {}): ChatContextBudgetSettings {
  return {
    maxContextTokens: normalizePositiveNumber(input.maxContextTokens, CHAT_CONTEXT_BUDGET_DEFAULT_MAX_TOKENS),
    thresholdPercent: normalizeThresholdPercent(input.thresholdPercent),
    keepRecentTurns: normalizeKeepRecentTurns(input.keepRecentTurns),
    reservedOutputTokens: normalizePositiveNumber(input.reservedOutputTokens,
      CHAT_CONTEXT_BUDGET_RESERVED_OUTPUT_TOKENS)
  };
}

function estimateTextTokens(text: string): number {
  // 粗估策略：按字符数近似 token 数，避免在端侧引入 tokenizer 依赖。
  return text.length;
}

function estimateCloudContentPartTokens(part: CloudContentPart): number {
  if (part.type === 'text') {
    let textPart = part as CloudTextPart;
    return CLOUD_CONTENT_PART_STRUCTURE_TOKEN_OVERHEAD + estimateTextTokens(textPart.text);
  }
  if (part.type === 'image_url') {
    let imagePart = part as CloudImagePart;
    return CLOUD_CONTENT_PART_STRUCTURE_TOKEN_OVERHEAD + CLOUD_IMAGE_PART_TOKEN_OVERHEAD +
      estimateTextTokens(imagePart.image_url.url);
  }
  return CLOUD_CONTENT_PART_STRUCTURE_TOKEN_OVERHEAD + estimateTextTokens(part.type);
}

function estimateCloudToolCallTokens(toolCall: CloudToolCall): number {
  return CLOUD_TOOL_CALL_TOKEN_OVERHEAD +
    estimateTextTokens(toolCall.id) +
    estimateTextTokens(toolCall.type) +
    estimateTextTokens(toolCall.function.name) +
    estimateTextTokens(toolCall.function.arguments);
}

function estimateCloudMessageContentTokens(message: CloudChatMessage): number {
  if (typeof message.content === 'string') {
    return estimateTextTokens(message.content);
  }

  let parts = message.content as CloudContentPart[];
  let total = 0;
  for (let i = 0; i < parts.length; i++) {
    total += estimateCloudContentPartTokens(parts[i]);
  }
  return total;
}

export function estimateCloudChatMessagesTokens(messages: CloudChatMessage[]): number {
  let total = 0;
  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    total += CLOUD_MESSAGE_STRUCTURE_TOKEN_OVERHEAD + estimateTextTokens(message.role) +
      estimateCloudMessageContentTokens(message);
    if (message.name !== undefined) {
      total += estimateTextTokens(message.name);
    }
    if (message.tool_call_id !== undefined) {
      total += estimateTextTokens(message.tool_call_id);
    }
    if (message.tool_calls !== undefined) {
      for (let j = 0; j < message.tool_calls.length; j++) {
        total += estimateCloudToolCallTokens(message.tool_calls[j]);
      }
    }
  }
  return total;
}

export function estimateCloudContextTokens(messages: CloudChatMessage[]): number {
  return estimateCloudChatMessagesTokens(messages);
}

export function shouldCompressChatContext(messages: CloudChatMessage[],
  input: ChatContextBudgetSettingsInput = {}): ChatContextBudgetDecision {
  let settings = normalizeChatContextBudgetSettings(input);
  let estimatedInputTokens = estimateCloudChatMessagesTokens(messages);
  let thresholdTokens = Math.floor(settings.maxContextTokens * settings.thresholdPercent / 100);
  let usableInputTokens = thresholdTokens - settings.reservedOutputTokens;
  if (usableInputTokens < 0) {
    usableInputTokens = 0;
  }
  return {
    estimatedInputTokens: estimatedInputTokens,
    thresholdTokens: thresholdTokens,
    usableInputTokens: usableInputTokens,
    shouldCompress: estimatedInputTokens >= usableInputTokens
  };
}

export function shouldCompressCloudContext(messages: CloudChatMessage[],
  settings: ChatContextBudgetSettings): boolean {
  let input: ChatContextBudgetSettingsInput = {
    maxContextTokens: settings.maxContextTokens,
    thresholdPercent: settings.thresholdPercent,
    keepRecentTurns: settings.keepRecentTurns,
    reservedOutputTokens: settings.reservedOutputTokens
  };
  return shouldCompressChatContext(messages, input).shouldCompress;
}

function isSkippedContextMessage(message: ChatMessage): boolean {
  // task_trace 只用于 UI 展示执行轨迹；context_notice 是上下文维护提示。
  // 两者都不应进入压缩历史，避免污染摘要和后续上下文。
  return message.kind === CHAT_MESSAGE_KIND_TASK_TRACE || message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE;
}

export function hasContextCompressionNotice(messages: ChatMessage[]): boolean {
  // 只识别系统自动插入的固定压缩提示，避免其他 context_notice 被误判为已提示。
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE &&
      messages[i].content === CHAT_CONTEXT_COMPRESSION_NOTICE) {
      return true;
    }
  }
  return false;
}

export function shouldAppendContextCompressionNotice(messages: ChatMessage[], noticeNeeded: boolean): boolean {
  return noticeNeeded && !hasContextCompressionNotice(messages);
}

export function splitChatHistoryByRecentTurns(messages: ChatMessage[], keepRecentTurns?: number):
  ChatContextHistorySplit {
  let normalizedTurns = normalizeKeepRecentTurns(keepRecentTurns);
  let usableMessages: ChatMessage[] = [];
  let skippedMessageCount = 0;

  for (let i = 0; i < messages.length; i++) {
    if (isSkippedContextMessage(messages[i])) {
      skippedMessageCount += 1;
    } else {
      usableMessages.push(messages[i]);
    }
  }

  let userTurnCount = 0;
  let boundaryIndex = 0;
  for (let i = usableMessages.length - 1; i >= 0; i--) {
    if (usableMessages[i].role === 'user') {
      userTurnCount += 1;
      if (userTurnCount === normalizedTurns) {
        boundaryIndex = i;
        break;
      }
    }
  }

  if (userTurnCount === 0) {
    return {
      olderMessages: [],
      recentMessages: usableMessages.slice(),
      keptUserTurnCount: 0,
      skippedMessageCount: skippedMessageCount
    };
  }

  if (userTurnCount < normalizedTurns) {
    boundaryIndex = 0;
  }

  return {
    olderMessages: usableMessages.slice(0, boundaryIndex),
    recentMessages: usableMessages.slice(boundaryIndex),
    keptUserTurnCount: userTurnCount < normalizedTurns ? userTurnCount : normalizedTurns,
    skippedMessageCount: skippedMessageCount
  };
}

export function buildContextSummarySystemMessage(summaryText: string): CloudChatMessage {
  let summary = summaryText.trim();
  let content = summary.length > 0 ? summary : '较早对话已被压缩，但没有可用摘要。';
  let prefix = '以下是较早对话的压缩摘要，用于延续上下文；' +
    '请将其视为历史背景，不要逐字重复：\n';
  return {
    role: 'system',
    content: prefix + content
  };
}

export function splitChatMessagesForContextCompression(messages: ChatMessage[],
  recentRounds: number): ChatContextCompressionSplit {
  let split = splitChatHistoryByRecentTurns(messages, recentRounds);
  let summaryUntilMessageId = split.olderMessages.length > 0 ?
    split.olderMessages[split.olderMessages.length - 1].id : '';
  return {
    olderMessages: split.olderMessages,
    retainedMessages: split.recentMessages,
    summaryUntilMessageId: summaryUntilMessageId,
    olderMessageCount: split.olderMessages.length,
    retainedRoundCount: split.keptUserTurnCount
  };
}

export function messagesWithoutCurrentRequest(messages: ChatMessage[], currentMessageId: string): ChatMessage[] {
  let historyMessages: ChatMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id !== currentMessageId) {
      historyMessages.push(messages[i]);
    }
  }
  return historyMessages;
}

export function splitChatMessagesForContextCompressionExact(messages: ChatMessage[],
  recentRounds: number): ChatContextCompressionSplit {
  let normalizedRounds = recentRounds <= 0 ? 0 : Math.floor(recentRounds);
  let usableMessages: ChatMessage[] = [];

  for (let i = 0; i < messages.length; i++) {
    if (!isSkippedContextMessage(messages[i])) {
      usableMessages.push(messages[i]);
    }
  }

  if (normalizedRounds === 0) {
    let summaryUntilMessageId = usableMessages.length > 0 ? usableMessages[usableMessages.length - 1].id : '';
    return {
      olderMessages: usableMessages.slice(),
      retainedMessages: [],
      summaryUntilMessageId: summaryUntilMessageId,
      olderMessageCount: usableMessages.length,
      retainedRoundCount: 0
    };
  }

  let userTurnCount = 0;
  let boundaryIndex = 0;
  for (let i = usableMessages.length - 1; i >= 0; i--) {
    if (usableMessages[i].role === 'user') {
      userTurnCount += 1;
      if (userTurnCount === normalizedRounds) {
        boundaryIndex = i;
        break;
      }
    }
  }

  if (userTurnCount === 0) {
    return {
      olderMessages: [],
      retainedMessages: usableMessages.slice(),
      summaryUntilMessageId: '',
      olderMessageCount: 0,
      retainedRoundCount: 0
    };
  }

  if (userTurnCount < normalizedRounds) {
    boundaryIndex = 0;
  }

  let olderMessages = usableMessages.slice(0, boundaryIndex);
  let summaryUntilMessageId = olderMessages.length > 0 ? olderMessages[olderMessages.length - 1].id : '';
  return {
    olderMessages: olderMessages,
    retainedMessages: usableMessages.slice(boundaryIndex),
    summaryUntilMessageId: summaryUntilMessageId,
    olderMessageCount: olderMessages.length,
    retainedRoundCount: userTurnCount < normalizedRounds ? userTurnCount : normalizedRounds
  };
}

export function messagesAfterContextSummaryUntil(messages: ChatMessage[], untilMessageId: string): ChatMessage[] {
  if (untilMessageId.length === 0) {
    return messages.slice();
  }
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id === untilMessageId) {
      return messages.slice(i + 1);
    }
  }
  return messages.slice();
}

function messageIndexById(messages: ChatMessage[], messageId: string): number {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id === messageId) {
      return i;
    }
  }
  return -1;
}

export function messagesAfterKnownContextSummaryCoverage(messages: ChatMessage[],
  untilMessageId: string): ChatMessage[] {
  if (untilMessageId.length === 0) {
    return messages.slice();
  }
  let coverageIndex = messageIndexById(messages, untilMessageId);
  if (coverageIndex < 0) {
    return [];
  }
  return messages.slice(coverageIndex + 1);
}

export function messagesAfterExistingContextSummaryCoverage(historyMessages: ChatMessage[],
  coverageId: string): ChatMessage[] {
  // 既有摘要缺少覆盖点或覆盖点找不到时，保守返回空数组，避免把旧原文再次发送给云端。
  if (coverageId.length === 0) {
    return [];
  }
  return messagesAfterKnownContextSummaryCoverage(historyMessages, coverageId);
}

export function buildCloudContextMessagesAfterExistingSummaryCoverage(dateSystemMessage: CloudChatMessage,
  summary: string, historyMessages: ChatMessage[], coverageId: string,
  currentUserMessage: ChatMessage): CloudChatMessage[] {
  // 复用既有摘要时，只携带摘要覆盖点之后的原始尾部消息；当前请求仍固定追加到末尾。
  let tailMessages = messagesAfterExistingContextSummaryCoverage(historyMessages, coverageId);
  return buildCloudContextMessagesWithCurrentRequest(dateSystemMessage, summary, tailMessages, currentUserMessage);
}

export function nonRetreatingContextSummaryUntilMessageId(historyMessages: ChatMessage[],
  previousUntilMessageId: string, candidateUntilMessageId: string): string {
  if (previousUntilMessageId.length === 0) {
    return candidateUntilMessageId;
  }
  if (candidateUntilMessageId.length === 0) {
    return previousUntilMessageId;
  }

  let previousIndex = messageIndexById(historyMessages, previousUntilMessageId);
  let candidateIndex = messageIndexById(historyMessages, candidateUntilMessageId);
  if (previousIndex < 0) {
    return candidateUntilMessageId;
  }
  if (candidateIndex < 0) {
    return previousUntilMessageId;
  }
  return previousIndex > candidateIndex ? previousUntilMessageId : candidateUntilMessageId;
}

export function contextSummaryMessageCountForCoverage(historyMessages: ChatMessage[], coverageMessageId: string,
  fallbackCount: number): number {
  let normalizedFallback = fallbackCount <= 0 ? 0 : Math.floor(fallbackCount);
  if (coverageMessageId.length === 0) {
    return normalizedFallback;
  }
  let coverageIndex = messageIndexById(historyMessages, coverageMessageId);
  if (coverageIndex < 0) {
    return normalizedFallback;
  }
  return coverageIndex + 1;
}

export function buildCompressedCloudContextMessages(dateSystemMessage: CloudChatMessage, summary: string,
  retainedMessages: ChatMessage[]): CloudChatMessage[] {
  let systemMessage = mergeSummaryIntoInitialSystemMessage(dateSystemMessage, summary);
  let compressed: CloudChatMessage[] = [systemMessage];
  let retainedContext = buildCloudContextMessages(retainedMessages);
  for (let i = 0; i < retainedContext.length; i++) {
    let message = retainedContext[i];
    if (message.role === 'system' && typeof message.content === 'string' && message.content.trim().length > 0) {
      // 部分 OpenAI-compatible 服务只允许 system 消息出现在第 0 条。
      // 历史里的系统内容合并进首条 system，避免压缩会话触发 400。
      compressed[0] = appendTextToSystemMessage(compressed[0], '历史系统上下文：\n' + message.content.trim());
      continue;
    }
    compressed.push(message);
  }
  return compressed;
}

function appendTextToSystemMessage(systemMessage: CloudChatMessage, appendedText: string): CloudChatMessage {
  let baseContent = typeof systemMessage.content === 'string' ? systemMessage.content.trim() : '';
  let normalizedText = appendedText.trim();
  let mergedContent = baseContent.length > 0 ? baseContent : '';
  if (normalizedText.length > 0) {
    mergedContent = mergedContent.length > 0 ? mergedContent + '\n\n' + normalizedText : normalizedText;
  }
  return {
    role: 'system',
    content: mergedContent
  };
}

function mergeSummaryIntoInitialSystemMessage(dateSystemMessage: CloudChatMessage, summary: string): CloudChatMessage {
  let mergedSystemMessage = appendTextToSystemMessage(dateSystemMessage, '');
  let trimmedSummary = summary.trim();
  if (trimmedSummary.length > 0) {
    let summaryMessage = buildContextSummarySystemMessage(trimmedSummary);
    let summaryContent = typeof summaryMessage.content === 'string' ? summaryMessage.content : trimmedSummary;
    mergedSystemMessage = appendTextToSystemMessage(mergedSystemMessage, summaryContent);
  }
  return mergedSystemMessage;
}

export function buildCloudContextMessagesWithCurrentRequest(dateSystemMessage: CloudChatMessage, summary: string,
  retainedHistoryMessages: ChatMessage[], currentUserMessage: ChatMessage): CloudChatMessage[] {
  // 当前请求不进入历史压缩链路，只在最终上下文末尾作为本轮 user 消息追加。
  let context = buildCompressedCloudContextMessages(dateSystemMessage, summary, retainedHistoryMessages);
  context.push({
    role: 'user',
    content: currentUserMessage.content.trim()
  });
  return context;
}

function compactTextForSummary(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

function chatMessageSummaryLabel(message: ChatMessage): string {
  if (message.role === 'user') {
    return '用户';
  }
  if (message.role === 'assistant') {
    return '助手';
  }
  if (message.role === 'system') {
    return '系统';
  }
  if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
    return '工具结果';
  }
  return '消息';
}

function appendSummaryLine(summary: string, line: string, maxChars: number): string {
  let candidate = summary.length === 0 ? line : summary + '\n' + line;
  if (candidate.length <= maxChars) {
    return candidate;
  }

  let separatorLength = summary.length === 0 ? 0 : 1;
  let remaining = maxChars - summary.length - separatorLength;
  if (remaining <= 3) {
    return summary;
  }

  let clipped = line.substring(0, remaining - 3) + '...';
  if (summary.length === 0) {
    return clipped;
  }
  return summary + '\n' + clipped;
}

export function buildLocalExtractiveFallbackSummary(messages: ChatMessage[],
  maxChars: number = DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS): string {
  let normalizedMaxChars = maxChars <= 0 ? DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS : Math.floor(maxChars);
  let summary = EXTRACTIVE_SUMMARY_HEADER;

  for (let i = 0; i < messages.length; i++) {
    let message = messages[i];
    if (isSkippedContextMessage(message)) {
      continue;
    }

    let content = compactTextForSummary(message.content);
    if (content.length === 0) {
      continue;
    }

    let line = '- ' + chatMessageSummaryLabel(message) + ': ' + content;
    let nextSummary = appendSummaryLine(summary, line, normalizedMaxChars);
    if (nextSummary === summary) {
      break;
    }
    summary = nextSummary;
    if (summary.length >= normalizedMaxChars) {
      break;
    }
  }

  if (summary === EXTRACTIVE_SUMMARY_HEADER) {
    return EXTRACTIVE_SUMMARY_HEADER + '\n- 无可抽取的早期对话内容。';
  }
  return summary;
}

export function buildLocalExtractiveChatSummary(previousSummary: string, messages: ChatMessage[]): string {
  let currentSummary = buildLocalExtractiveFallbackSummary(messages, DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS);
  let previous = previousSummary.trim();
  if (previous.length === 0) {
    return currentSummary;
  }
  let combined = '既有摘要：\n' + previous + '\n\n' + currentSummary;
  if (combined.length <= DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS) {
    return combined;
  }
  return combined.substring(0, DEFAULT_EXTRACTIVE_SUMMARY_MAX_CHARS) + '...';
}
