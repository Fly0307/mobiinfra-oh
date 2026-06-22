import {
  CloudChatCompletionOptions,
  CloudChatCompletionResult,
  CloudChatMessage,
  CloudChatToolDefinition,
  CloudModelClient,
  CloudModelConfig
} from './CloudModelClient';
import {
  ChatToolExecutionContext,
  ChatToolRegistry,
  createDefaultChatToolRegistry
} from './ChatToolRegistry';

export type ChatReactTraceHandler = (line: string) => void;
export type ChatReactContentDeltaHandler = (delta: string) => void;

export interface ChatReactAgentRunOptions {
  maxIterations?: number;
  filesDir?: string;
  sessionId?: string;
  userMessage?: string;
  enableThinking?: boolean;
  onTrace?: ChatReactTraceHandler;
  onContentDelta?: ChatReactContentDeltaHandler;
}

export interface ChatReactAgentResult {
  content: string;
  iterations: number;
  toolCallCount: number;
  reachedLimit: boolean;
}

const DEFAULT_MAX_REACT_ITERATIONS: number = 30;
const ITERATION_LIMIT_MESSAGE: string = '工具调用轮数已达到上限，未生成最终答案。';

export class ChatReactAgent {
  private client: CloudModelClient;
  private registry: ChatToolRegistry;

  constructor(client: CloudModelClient, registry: ChatToolRegistry = createDefaultChatToolRegistry()) {
    this.client = client;
    this.registry = registry;
  }

  async run(messages: CloudChatMessage[], config: CloudModelConfig,
    options: ChatReactAgentRunOptions = {}): Promise<ChatReactAgentResult> {
    let maxIterations = this.normalizeMaxIterations(options.maxIterations);
    let workingMessages = messages.slice();
    let tools = this.registry.getOpenAiTools();
    let toolCallCount = 0;

    for (let iteration = 1; iteration <= maxIterations; iteration++) {
      let completionOptions = this.buildCompletionOptions(workingMessages, config, tools,
        options.enableThinking === true);
      let result = await this.requestCompletion(completionOptions, options);
      if (result.toolCalls.length === 0) {
        let finalContent = result.content.trim();
        return {
          content: finalContent.length > 0 ? finalContent : '模型未返回有效内容。',
          iterations: iteration,
          toolCallCount: toolCallCount,
          reachedLimit: false
        };
      }

      workingMessages.push(result.assistantMessage);
      for (let i = 0; i < result.toolCalls.length; i++) {
        let toolCall = result.toolCalls[i];
        let toolContext: ChatToolExecutionContext = {
          filesDir: options.filesDir === undefined ? '' : options.filesDir,
          sessionId: options.sessionId === undefined ? '' : options.sessionId,
          userMessage: options.userMessage === undefined ? '' : options.userMessage
        };
        let toolResult = await this.registry.executeToolCall(toolCall, toolContext);
        toolCallCount += 1;
        if (options.onTrace !== undefined) {
          options.onTrace(toolResult.traceLine);
        }
        workingMessages.push({
          role: 'tool',
          content: toolResult.content,
          tool_call_id: toolResult.toolCallId,
          name: toolResult.toolName
        });
      }
    }

    return this.limitResult(maxIterations, toolCallCount);
  }

  private async requestCompletion(completionOptions: CloudChatCompletionOptions,
    options: ChatReactAgentRunOptions): Promise<CloudChatCompletionResult> {
    if (options.onContentDelta === undefined) {
      return this.client.chatCompletion(completionOptions);
    }
    return this.client.chatCompletionStream(completionOptions, {
      onContentDelta: options.onContentDelta
    });
  }

  private buildCompletionOptions(messages: CloudChatMessage[], config: CloudModelConfig,
    tools: CloudChatToolDefinition[], enableThinking: boolean): CloudChatCompletionOptions {
    let options: CloudChatCompletionOptions = {
      baseUrl: config.plannerBaseUrl,
      apiKey: config.apiKey,
      messages: messages,
      temperature: 0,
      chatTemplateKwargs: {
        enable_thinking: enableThinking
      }
    };
    if (tools.length > 0) {
      options.tools = tools;
      options.toolChoice = 'auto';
    }
    return options;
  }

  private normalizeMaxIterations(maxIterations?: number): number {
    if (maxIterations === undefined || maxIterations <= 0) {
      return DEFAULT_MAX_REACT_ITERATIONS;
    }
    return Math.floor(maxIterations);
  }

  private limitResult(iterations: number, toolCallCount: number): ChatReactAgentResult {
    return {
      content: ITERATION_LIMIT_MESSAGE,
      iterations: iterations,
      toolCallCount: toolCallCount,
      reachedLimit: true
    };
  }
}
