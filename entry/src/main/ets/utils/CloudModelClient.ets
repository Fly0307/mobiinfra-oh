import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import {
  CLOUD_DECIDER_CURRENT_STEP_PROMPT,
  CLOUD_DECIDER_SYSTEM_PROMPT,
  CLOUD_DECIDER_USER_PROMPT
} from './CloudDeciderPrompt';

export interface CloudModelConfig {
  plannerBaseUrl: string;
  deciderBaseUrl: string;
  apiKey: string;
}

export interface CloudImageUrl {
  url: string;
}

export interface CloudTextPart {
  type: string;
  text: string;
}

export interface CloudImagePart {
  type: string;
  image_url: CloudImageUrl;
}

export type CloudContentPart = CloudTextPart | CloudImagePart;

export interface CloudChatMessage {
  role: string;
  content: string | CloudContentPart[];
}

export interface CloudChatTemplateKwargs {
  enable_thinking: boolean;
}

export interface CloudChatCompletionOptions {
  baseUrl: string;
  apiKey: string;
  messages: CloudChatMessage[];
  maxTokens?: number;
  temperature: number;
  chatTemplateKwargs?: CloudChatTemplateKwargs;
}

interface CloudChatRequest {
  messages: CloudChatMessage[];
  temperature: number;
  stream: boolean;
  max_tokens?: number;
  chat_template_kwargs?: CloudChatTemplateKwargs;
}

interface CloudChatMessageResult {
  content: string;
}

interface CloudChatChoice {
  message: CloudChatMessageResult;
}

interface CloudChatResponse {
  choices: CloudChatChoice[];
}

export class CloudModelClient {
  private buildQwenHistoryText(historyItems: string[]): string {
    if (historyItems.length === 0) {
      return '(No history)';
    }

    let lines: string[] = [];
    for (let i = 0; i < historyItems.length; i++) {
      lines.push(`${i + 1}. ${historyItems[i]}`);
    }
    return lines.join('\n');
  }

  private buildQwenContextText(task: string, historyItems: string[]): string {
    return CLOUD_DECIDER_USER_PROMPT
      .replace('{task}', task)
      .replace('{history}', this.buildQwenHistoryText(historyItems));
  }

  formatQwenDeciderPromptForLog(task: string, historyItems: string[], imageBase64: string): string {
    let imagePrefixLength = imageBase64.length > 48 ? 48 : imageBase64.length;
    let imagePrefix = imageBase64.substring(0, imagePrefixLength);
    return '[0] role=system\n' +
      CLOUD_DECIDER_SYSTEM_PROMPT +
      '\n\n[1] role=user / content[0] type=text\n' +
      this.buildQwenContextText(task, historyItems) +
      '\n\n[1] role=user / content[1] type=image_url\n' +
      'data:image/jpeg;base64,' + imagePrefix + '... (base64 chars=' + imageBase64.length + ')' +
      '\n\n[1] role=user / content[2] type=text\n' +
      CLOUD_DECIDER_CURRENT_STEP_PROMPT;
  }

  private normalizeChatUrl(baseUrl: string): string {
    let url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/chat/completions')) {
      return url;
    }
    if (url.endsWith('/v1')) {
      return url + '/chat/completions';
    }
    return url + '/v1/chat/completions';
  }

  async chatCompletionText(options: CloudChatCompletionOptions): Promise<string> {
    let requestBody: CloudChatRequest = {
      messages: options.messages,
      temperature: options.temperature,
      stream: false
    };
    if (options.maxTokens !== undefined) {
      requestBody.max_tokens = options.maxTokens;
    }
    if (options.chatTemplateKwargs !== undefined) {
      requestBody.chat_template_kwargs = options.chatTemplateKwargs;
    }
    let headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + (options.apiKey.length > 0 ? options.apiKey : 'EMPTY')
    };
    let requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(requestBody),
      connectTimeout: 10000,
      readTimeout: 120000,
      expectDataType: http.HttpDataType.STRING
    };

    let httpReq = http.createHttp();
    try {
      let response = await httpReq.request(this.normalizeChatUrl(options.baseUrl), requestOptions);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Cloud HTTP ${response.responseCode}: ${response.result}`);
      }
      let parsed: CloudChatResponse;
      try {
        parsed = ArkJSON.parse(response.result as string) as CloudChatResponse;
      } catch (e) {
        let err = e as Error;
        throw new Error('Cloud response JSON parse failed: ' + err.message);
      }
      if (parsed.choices.length === 0) {
        throw new Error('Cloud response has no choices');
      }
      return parsed.choices[0].message.content;
    } finally {
      httpReq.destroy();
    }
  }

  private async chatMessages(baseUrl: string, messages: CloudChatMessage[], apiKey: string): Promise<string> {
    try {
      return await this.chatCompletionText({
        baseUrl: baseUrl,
        apiKey: apiKey,
        messages: messages,
        maxTokens: 2048,
        temperature: 0
      });
    } catch (e) {
      let err = e as Error;
      return ArkJSON.stringify({ action: 'error', reason: err.message });
    }
  }

  private async chat(baseUrl: string, content: CloudContentPart[], apiKey: string): Promise<string> {
    let message: CloudChatMessage = {
      role: 'user',
      content: content
    };
    return this.chatMessages(baseUrl, [message], apiKey);
  }

  async chatPlanner(prompt: string, config: CloudModelConfig): Promise<string> {
    let textPart: CloudTextPart = {
      type: 'text',
      text: prompt
    };
    return this.chat(config.plannerBaseUrl, [textPart], config.apiKey);
  }

  async chatDecider(prompt: string, imageBase64: string, config: CloudModelConfig): Promise<string> {
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let textPart: CloudTextPart = {
      type: 'text',
      text: prompt
    };
    return this.chat(config.deciderBaseUrl, [imagePart, textPart], config.apiKey);
  }

  async chatQwenDecider(task: string, historyItems: string[], imageBase64: string, config: CloudModelConfig): Promise<string> {
    let contextText = this.buildQwenContextText(task, historyItems);
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let contextPart: CloudTextPart = {
      type: 'text',
      text: contextText
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let stepPart: CloudTextPart = {
      type: 'text',
      text: CLOUD_DECIDER_CURRENT_STEP_PROMPT
    };
    let systemMessage: CloudChatMessage = {
      role: 'system',
      content: CLOUD_DECIDER_SYSTEM_PROMPT
    };
    let userMessage: CloudChatMessage = {
      role: 'user',
      content: [contextPart, imagePart, stepPart]
    };
    let messages: CloudChatMessage[] = [systemMessage, userMessage];
    return this.chatMessages(config.deciderBaseUrl, messages, config.apiKey);
  }
}

