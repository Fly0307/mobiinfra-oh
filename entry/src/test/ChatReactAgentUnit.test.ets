import { describe, it, expect } from '@ohos/hypium';
import { ChatReactAgent, ChatReactAgentRunOptions } from '../main/ets/utils/ChatReactAgent';
import {
  ChatTool,
  ChatToolExecutionContext,
  ChatToolRegistry
} from '../main/ets/utils/ChatToolRegistry';
import {
  CloudChatCompletionOptions,
  CloudChatCompletionResult,
  CloudChatCompletionStreamCallbacks,
  CloudChatMessage,
  CloudModelClient,
  CloudModelConfig,
  CloudToolCall
} from '../main/ets/utils/CloudModelClient';

class FakeReactModelClient extends CloudModelClient {
  private responses: CloudChatCompletionResult[];
  callToolCounts: number[] = [];
  callMessages: CloudChatMessage[][] = [];
  callThinkingFlags: boolean[] = [];
  callOptions: CloudChatCompletionOptions[] = [];
  streamCallCount: number = 0;

  constructor(responses: CloudChatCompletionResult[]) {
    super();
    this.responses = responses;
  }

  async chatCompletion(options: CloudChatCompletionOptions): Promise<CloudChatCompletionResult> {
    this.callToolCounts.push(options.tools === undefined ? 0 : options.tools.length);
    this.callMessages.push(this.cloneMessages(options.messages));
    this.callThinkingFlags.push(options.chatTemplateKwargs === undefined ? false :
      options.chatTemplateKwargs.enable_thinking);
    this.callOptions.push(options);
    let index = this.callMessages.length - 1;
    if (index >= this.responses.length) {
      return completion('fallback');
    }
    return this.responses[index];
  }

  async chatCompletionStream(options: CloudChatCompletionOptions,
    callbacks: CloudChatCompletionStreamCallbacks = {}): Promise<CloudChatCompletionResult> {
    this.streamCallCount += 1;
    this.callToolCounts.push(options.tools === undefined ? 0 : options.tools.length);
    this.callMessages.push(this.cloneMessages(options.messages));
    this.callThinkingFlags.push(options.chatTemplateKwargs === undefined ? false :
      options.chatTemplateKwargs.enable_thinking);
    this.callOptions.push(options);
    let index = this.callMessages.length - 1;
    let response = index >= this.responses.length ? completion('fallback') : this.responses[index];
    if (callbacks.onContentDelta !== undefined && response.content.length > 0) {
      let splitIndex = response.content.length > 1 ? 1 : response.content.length;
      callbacks.onContentDelta(response.content.substring(0, splitIndex));
      callbacks.onContentDelta(response.content.substring(splitIndex));
    }
    return response;
  }

  private cloneMessages(messages: CloudChatMessage[]): CloudChatMessage[] {
    let cloned: CloudChatMessage[] = [];
    for (let i = 0; i < messages.length; i++) {
      let message = messages[i];
      cloned.push({
        role: message.role,
        content: message.content,
        tool_call_id: message.tool_call_id,
        tool_calls: message.tool_calls === undefined ? undefined : message.tool_calls.slice(),
        name: message.name
      });
    }
    return cloned;
  }
}

interface TestStringSchema {
  type: string;
}

interface TestLookupProperties {
  query: TestStringSchema;
}

interface TestToolParameters {
  type: string;
  properties?: TestLookupProperties;
  required?: string[];
}

interface TestThinkingRunOptions extends ChatReactAgentRunOptions {
  enableThinking: boolean;
}

function testConfig(): CloudModelConfig {
  return {
    plannerBaseUrl: 'http://localhost:8000',
    deciderBaseUrl: 'http://localhost:8000',
    apiKey: 'test-key',
    deciderModel: 'test-model'
  };
}

function lookupToolParameters(): Object {
  let query: TestStringSchema = {
    type: 'string'
  };
  let properties: TestLookupProperties = {
    query: query
  };
  let parameters: TestToolParameters = {
    type: 'object',
    properties: properties,
    required: ['query']
  };
  return parameters as Object;
}

function emptyToolParameters(): Object {
  let parameters: TestToolParameters = {
    type: 'object'
  };
  return parameters as Object;
}

function thinkingRunOptions(enableThinking: boolean): ChatReactAgentRunOptions {
  let options: TestThinkingRunOptions = {
    enableThinking: enableThinking
  };
  return options;
}

function toolCall(id: string, name: string, args: string): CloudToolCall {
  return {
    id: id,
    type: 'function',
    function: {
      name: name,
      arguments: args
    }
  };
}

function completion(content: string, toolCalls: CloudToolCall[] = []): CloudChatCompletionResult {
  return {
    content: content,
    toolCalls: toolCalls,
    finishReason: toolCalls.length > 0 ? 'tool_calls' : 'stop',
    assistantMessage: {
      role: 'assistant',
      content: content,
      tool_calls: toolCalls
    }
  };
}

function completionWithFinishReason(content: string, finishReason: string): CloudChatCompletionResult {
  return {
    content: content,
    toolCalls: [],
    finishReason: finishReason,
    assistantMessage: {
      role: 'assistant',
      content: content
    }
  };
}

function userMessage(content: string): CloudChatMessage {
  return {
    role: 'user',
    content: content
  };
}

function repeatedToolResponses(count: number): CloudChatCompletionResult[] {
  let responses: CloudChatCompletionResult[] = [];
  for (let i = 0; i < count; i++) {
    responses.push(completion('', [toolCall('call-' + String(i + 1), 'lookup_note', '{}')]));
  }
  return responses;
}

function repeatedText(unit: string, count: number): string {
  let value = '';
  for (let i = 0; i < count; i++) {
    value += unit;
  }
  return value;
}

function fakeLookupTool(output: string): ChatTool {
  return {
    name: 'lookup_note',
    description: 'Lookup a note by query.',
    parameters: lookupToolParameters(),
    strict: true,
    execute: async (_argsText: string, _context: ChatToolExecutionContext): Promise<string> => {
      return output;
    }
  };
}

export default function chatReactAgentUnitTest() {
  describe('chatReactAgentUnitTest', () => {
    it('returnsFinalAnswerWithoutTools', 0, async () => {
      let client = new FakeReactModelClient([completion('你好，我可以帮你。')]);
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      let result = await agent.run([userMessage('你好')], testConfig());

      expect(result.content).assertEqual('你好，我可以帮你。');
      expect(result.finishReason).assertEqual('stop');
      expect(result.toolCallCount).assertEqual(0);
      expect(client.callMessages.length).assertEqual(1);
      expect(client.callToolCounts[0]).assertEqual(0);
      expect(client.callThinkingFlags[0]).assertFalse();
    });

    it('returnsFallbackTextAndFinishReasonForEmptyFinalResponse', 0, async () => {
      let client = new FakeReactModelClient([completionWithFinishReason('', 'length')]);
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      let result = await agent.run([userMessage('请回答')], testConfig());

      expect(result.content).assertEqual('模型未返回有效内容。');
      expect(result.finishReason).assertEqual('length');
      expect(result.reachedLimit).assertFalse();
    });

    it('passesThinkingFlagToCloudChatTemplateKwargs', 0, async () => {
      let client = new FakeReactModelClient([completion('深度思考回答。')]);
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      let result = await agent.run([userMessage('需要深入分析')], testConfig(), thinkingRunOptions(true));

      expect(result.content).assertEqual('深度思考回答。');
      expect(client.callThinkingFlags.length).assertEqual(1);
      expect(client.callThinkingFlags[0]).assertTrue();
    });

    it('usesQwenThinkingSamplingPresetForThinkingChat', 0, async () => {
      let client = new FakeReactModelClient([completion('深度思考回答。')]);
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      await agent.run([userMessage('需要深入分析')], testConfig(), thinkingRunOptions(true));

      expect(client.callOptions[0].temperature).assertEqual(1.0);
      expect(client.callOptions[0].top_p).assertEqual(0.95);
      expect(client.callOptions[0].top_k).assertEqual(20);
      expect(client.callOptions[0].min_p).assertEqual(0.0);
      expect(client.callOptions[0].presence_penalty).assertEqual(1.5);
      expect(client.callOptions[0].repetition_penalty).assertEqual(1.0);
      expect(client.callOptions[0].maxTokens).assertEqual(32768);
    });

    it('usesQwenInstructSamplingPresetForNonThinkingChat', 0, async () => {
      let client = new FakeReactModelClient([completion('普通回答。')]);
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      await agent.run([userMessage('请回答')], testConfig());

      expect(client.callOptions[0].temperature).assertEqual(0.7);
      expect(client.callOptions[0].top_p).assertEqual(0.8);
      expect(client.callOptions[0].top_k).assertEqual(20);
      expect(client.callOptions[0].min_p).assertEqual(0.0);
      expect(client.callOptions[0].presence_penalty).assertEqual(1.5);
      expect(client.callOptions[0].repetition_penalty).assertEqual(1.0);
      expect(client.callOptions[0].maxTokens).assertEqual(32768);
    });

    it('executesRegisteredToolAndContinuesToFinalAnswer', 0, async () => {
      let calls = [toolCall('call-1', 'lookup_note', '{"query":"咖啡"}')];
      let client = new FakeReactModelClient([
        completion('', calls),
        completion('已找到咖啡记录。')
      ]);
      let registry = new ChatToolRegistry();
      registry.registerTool(fakeLookupTool('{"ok":true,"text":"咖啡记录"}'));
      let traces: string[] = [];
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('查一下咖啡')], testConfig(), {
        onTrace: (line: string) => {
          traces.push(line);
        }
      });

      expect(result.content).assertEqual('已找到咖啡记录。');
      expect(result.toolCallCount).assertEqual(1);
      expect(client.callMessages.length).assertEqual(2);
      expect(client.callToolCounts[0]).assertEqual(1);
      expect(client.callMessages[1].length).assertEqual(3);
      expect(client.callMessages[1][2].role).assertEqual('tool');
      expect(client.callMessages[1][2].tool_call_id).assertEqual('call-1');
      expect(traces.length).assertEqual(1);
      expect(traces[0].indexOf('lookup_note') >= 0).assertTrue();
    });

    it('streamsFinalAnswerDeltasWhenCallbackProvided', 0, async () => {
      let client = new FakeReactModelClient([completion('流式回答')]);
      let deltas: string[] = [];
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      let result = await agent.run([userMessage('你好')], testConfig(), {
        onContentDelta: (delta: string) => {
          deltas.push(delta);
        }
      });

      expect(result.content).assertEqual('流式回答');
      expect(client.streamCallCount).assertEqual(1);
      expect(deltas.join('')).assertEqual('流式回答');
    });

    it('keepsFullToolTraceForChatSession', 0, async () => {
      let longArgs = '{"query":"' + repeatedText('keyword-', 40) + 'TRACE_ARGUMENT_TAIL"}';
      let longOutput = '{"ok":true,"text":"' + repeatedText('result-', 80) + 'TRACE_RESULT_TAIL"}';
      let client = new FakeReactModelClient([
        completion('', [toolCall('call-long', 'lookup_note', longArgs)]),
        completion('已读取完整工具结果。')
      ]);
      let registry = new ChatToolRegistry();
      registry.registerTool(fakeLookupTool(longOutput));
      let traces: string[] = [];
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('查长结果')], testConfig(), {
        onTrace: (line: string) => {
          traces.push(line);
        }
      });

      expect(result.content).assertEqual('已读取完整工具结果。');
      expect(result.toolCallCount).assertEqual(1);
      expect(traces.length).assertEqual(1);
      expect(traces[0].indexOf('TRACE_ARGUMENT_TAIL') >= 0).assertTrue();
      expect(traces[0].indexOf('TRACE_RESULT_TAIL') >= 0).assertTrue();
    });

    it('returnsUnknownToolResultToModel', 0, async () => {
      let client = new FakeReactModelClient([
        completion('', [toolCall('call-missing', 'missing_tool', '{}')]),
        completion('这个工具暂不可用。')
      ]);
      let traces: string[] = [];
      let agent = new ChatReactAgent(client, new ChatToolRegistry());

      let result = await agent.run([userMessage('调用不存在工具')], testConfig(), {
        onTrace: (line: string) => {
          traces.push(line);
        }
      });

      expect(result.content).assertEqual('这个工具暂不可用。');
      expect(result.toolCallCount).assertEqual(1);
      expect(client.callMessages[1][2].content as string).assertContain('does not exist');
      expect(traces[0].indexOf('does not exist') >= 0).assertTrue();
    });

    it('handlesInvalidToolArgumentsWithoutExecutingTool', 0, async () => {
      let executedCount = 0;
      let tool: ChatTool = {
        name: 'lookup_note',
        description: 'Lookup a note by query.',
        parameters: emptyToolParameters(),
        execute: async (_argsText: string, _context: ChatToolExecutionContext): Promise<string> => {
          executedCount += 1;
          return 'should-not-run';
        }
      };
      let registry = new ChatToolRegistry();
      registry.registerTool(tool);
      let client = new FakeReactModelClient([
        completion('', [toolCall('call-bad-json', 'lookup_note', '{"query":')]),
        completion('参数格式不正确。')
      ]);
      let traces: string[] = [];
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('坏参数')], testConfig(), {
        onTrace: (line: string) => {
          traces.push(line);
        }
      });

      expect(result.content).assertEqual('参数格式不正确。');
      expect(executedCount).assertEqual(0);
      expect(client.callMessages[1][2].content as string).assertContain('JSON parse failed');
      expect(traces[0].indexOf('JSON parse failed') >= 0).assertTrue();
    });

    it('stopsAfterMaxIterations', 0, async () => {
      let client = new FakeReactModelClient([
        completion('', [toolCall('call-1', 'lookup_note', '{}')]),
        completion('', [toolCall('call-2', 'lookup_note', '{}')])
      ]);
      let registry = new ChatToolRegistry();
      registry.registerTool(fakeLookupTool('{"ok":true}'));
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('循环调用')], testConfig(), { maxIterations: 2 });

      expect(result.reachedLimit).assertTrue();
      expect(result.toolCallCount).assertEqual(2);
      expect(result.content).assertEqual('工具调用轮数已达到上限，未生成最终答案。');
      expect(client.callMessages.length).assertEqual(2);
    });

    it('defaultsToThirtyIterations', 0, async () => {
      let client = new FakeReactModelClient(repeatedToolResponses(30));
      let registry = new ChatToolRegistry();
      registry.registerTool(fakeLookupTool('{"ok":true}'));
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('默认上限')], testConfig());

      expect(result.reachedLimit).assertTrue();
      expect(result.toolCallCount).assertEqual(30);
      expect(client.callMessages.length).assertEqual(30);
    });

    it('executesMultipleToolCallsSequentially', 0, async () => {
      let client = new FakeReactModelClient([
        completion('', [
          toolCall('call-1', 'lookup_note', '{"query":"早餐"}'),
          toolCall('call-2', 'lookup_note', '{"query":"晚餐"}')
        ]),
        completion('早餐和晚餐都已查询。')
      ]);
      let registry = new ChatToolRegistry();
      registry.registerTool(fakeLookupTool('{"ok":true}'));
      let traces: string[] = [];
      let agent = new ChatReactAgent(client, registry);

      let result = await agent.run([userMessage('查两条')], testConfig(), {
        onTrace: (line: string) => {
          traces.push(line);
        }
      });

      expect(result.content).assertEqual('早餐和晚餐都已查询。');
      expect(result.toolCallCount).assertEqual(2);
      expect(traces.length).assertEqual(2);
      expect(client.callMessages[1].length).assertEqual(4);
      expect(client.callMessages[1][2].tool_call_id).assertEqual('call-1');
      expect(client.callMessages[1][3].tool_call_id).assertEqual('call-2');
    });

    it('parsesCloudToolCallResponses', 0, () => {
      let parsed = CloudModelClient.parseChatCompletionResponseText('{"choices":[{"finish_reason":"tool_calls",' +
        '"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-1","type":"function",' +
        '"function":{"name":"lookup_note","arguments":"{}"}}]}}]}');

      expect(parsed.content).assertEqual('');
      expect(parsed.finishReason).assertEqual('tool_calls');
      expect(parsed.toolCalls.length).assertEqual(1);
      expect(parsed.toolCalls[0].function.name).assertEqual('lookup_note');
    });

    it('parsesCloudStreamingContentAndToolCallDeltas', 0, () => {
      let contentChunk = CloudModelClient.parseChatCompletionStreamDataLine(
        'data: {"choices":[{"delta":{"content":"你"}}]}');
      let toolChunk = CloudModelClient.parseChatCompletionStreamDataLine('data: {"choices":[{"finish_reason":' +
        '"tool_calls","delta":{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":' +
        '{"name":"lookup_note","arguments":"{\\"query\\":"}}]}}]}');
      let doneChunk = CloudModelClient.parseChatCompletionStreamDataLine('data: [DONE]');

      expect(contentChunk.contentDelta).assertEqual('你');
      expect(toolChunk.finishReason).assertEqual('tool_calls');
      expect(toolChunk.toolCallDeltas.length).assertEqual(1);
      expect(toolChunk.toolCallDeltas[0].id).assertEqual('call-1');
      expect(doneChunk.done).assertTrue();
    });

    it('mergesCloudStreamingToolCallDeltasWithNullFields', 0, () => {
      let toolChunk = CloudModelClient.parseChatCompletionStreamDataLine('data: {"choices":[{"delta":' +
        '{"tool_calls":[{"index":0,"id":null,"type":null,"function":{"name":null,' +
        '"arguments":"{\\"range\\":\\""}}]}}]}');
      let toolCalls: CloudToolCall[] = [];

      CloudModelClient.applyStreamToolCallDeltas(toolCalls, toolChunk.toolCallDeltas);

      expect(toolCalls.length).assertEqual(1);
      expect(toolCalls[0].id).assertEqual('');
      expect(toolCalls[0].type).assertEqual('function');
      expect(toolCalls[0].function.name).assertEqual('');
      expect(toolCalls[0].function.arguments).assertEqual('{"range":"');
    });

    it('throwsOnEmptyCloudChoices', 0, () => {
      let message = '';
      try {
        CloudModelClient.parseChatCompletionResponseText('{"choices":[]}');
      } catch (e) {
        let err = e as Error;
        message = err.message;
      }
      expect(message).assertEqual('Cloud response has no choices');
    });
  });
}
