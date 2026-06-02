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
  deciderModel: string;
}

export interface GalleryCloudModelConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
}

export interface EmbeddingCloudConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
}

export interface GalleryMonthSummaryResult {
  title: string;
  summary: string;
  suggestion: string;
  rawText: string;
}

interface CloudImageUrl {
  url: string;
}

interface CloudTextPart {
  type: string;
  text: string;
}

interface CloudImagePart {
  type: string;
  image_url: CloudImageUrl;
}

type CloudContentPart = CloudTextPart | CloudImagePart;

interface CloudChatMessage {
  role: string;
  content: string | CloudContentPart[];
}

interface CloudChatRequest {
  messages: CloudChatMessage[];
  temperature: number;
  stream: boolean;
  max_tokens: number;
  model?: string;
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

interface CloudEmbeddingRequest {
  model: string;
  input: string;
}

interface CloudEmbeddingItem {
  embedding: number[];
}

interface CloudEmbeddingResponse {
  data: CloudEmbeddingItem[];
}

export class CloudModelClient {
  private activeRequests: http.HttpRequest[] = [];

  private registerActiveRequest(request: http.HttpRequest): void {
    this.activeRequests.push(request);
  }

  private unregisterActiveRequest(request: http.HttpRequest): void {
    this.activeRequests = this.activeRequests.filter((item: http.HttpRequest) => item !== request);
  }

  cancelActiveRequests(): void {
    let pending = this.activeRequests.slice();
    this.activeRequests = [];
    for (let i = 0; i < pending.length; i++) {
      try {
        pending[i].destroy();
      } catch (e) {
        console.warn('[CloudModelClient] destroy pending request failed: ' + String(e));
      }
    }
  }

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

  private normalizeEmbeddingUrl(baseUrl: string): string {
    let url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/embeddings')) {
      return url;
    }
    if (url.endsWith('/v1')) {
      return url + '/embeddings';
    }
    return url + '/v1/embeddings';
  }

  private async chatMessages(baseUrl: string, messages: CloudChatMessage[], apiKey: string,
    model?: string, maxTokens: number = 2048, readTimeout: number = 120000): Promise<string> {
    let requestBody: CloudChatRequest = {
      messages: messages,
      temperature: 0,
      stream: false,
      max_tokens: maxTokens
    };
    if (model && model.trim().length > 0) {
      requestBody.model = model.trim();
    }
    let headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + (apiKey.length > 0 ? apiKey : 'EMPTY')
    };
    let requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(requestBody),
      connectTimeout: 10000,
      readTimeout: readTimeout,
      expectDataType: http.HttpDataType.STRING
    };

    let httpReq = http.createHttp();
    this.registerActiveRequest(httpReq);
    try {
      let response = await httpReq.request(this.normalizeChatUrl(baseUrl), requestOptions);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return `{"action":"error","reason":"Cloud HTTP ${response.responseCode}: ${response.result}"}`;
      }
      let parsed = ArkJSON.parse(response.result as string) as CloudChatResponse;
      if (parsed.choices.length === 0) {
        return '{"action":"error","reason":"Cloud response has no choices"}';
      }
      return parsed.choices[0].message.content;
    } finally {
      this.unregisterActiveRequest(httpReq);
      httpReq.destroy();
    }
  }

  private async chat(baseUrl: string, content: CloudContentPart[], apiKey: string): Promise<string> {
    let message: CloudChatMessage = {
      role: 'user',
      content: content
    };
    return this.chatMessages(baseUrl, [message], apiKey);
  }

  async summarizeGalleryMonth(config: GalleryCloudModelConfig, monthAggregateText: string): Promise<GalleryMonthSummaryResult> {
    let prompt = '你是一个图库月度洞察助手。' +
      '\n\n请根据用户提供的月度图库聚合数据和图片摘要清单，判断这个月用户大概做了什么，并生成一个适合展示在“图库洞察”页的月度总结。' +
      '\n严格基于输入数据，不要编造具体人名、地点、城市、店名或未出现的事件。' +
      '\n如果只能推测，请使用“可能”“疑似”“看起来像”。' +
      '\n不要使用“人生高光”“最重要”等强判断。' +
      '\nsummary 必须包含 2 到 3 个具体观察，优先引用输入里的时间、类别、数量、平台、活动或事项线索；不要只写“内容丰富”“记录较多”这类笼统表述。' +
      '\n\n输出 JSON，不要输出 Markdown，格式如下：' +
      '\n{' +
      '\n  "title": "最多14个字的标题",' +
      '\n  "summary": "80到140字的月度总结，说明这个月大概做了什么",' +
      '\n  "suggestion": "一句可执行整理建议"' +
      '\n}' +
      '\n\n月度图库聚合数据：\n' + monthAggregateText;
    let message: CloudChatMessage = {
      role: 'user',
      content: prompt
    };
    let content = await this.chatMessages(config.baseUrl, [message], config.apiKey, config.model, 1024, 90000);
    let payloadText = this.extractJsonObject(content);
    let payload: Record<string, Object> = {};
    try {
      payload = ArkJSON.parse(payloadText) as Record<string, Object>;
    } catch (e) {
      return {
        title: '',
        summary: content.trim(),
        suggestion: '',
        rawText: content
      };
    }
    let title = this.getPayloadString(payload, 'title');
    if (title.length === 0) {
      title = this.getPayloadString(payload, '标题');
    }
    let summary = this.getPayloadString(payload, 'summary');
    if (summary.length === 0) {
      summary = this.getPayloadString(payload, '摘要');
    }
    let suggestion = this.getPayloadString(payload, 'suggestion');
    if (suggestion.length === 0) {
      suggestion = this.getPayloadString(payload, 'suggestions');
    }
    if (suggestion.length === 0) {
      suggestion = this.getPayloadString(payload, '建议');
    }
    let reason = this.getPayloadString(payload, 'reason');
    if (summary.length === 0 && title.length === 0 && suggestion.length === 0) {
      throw new Error(reason.length > 0 ? reason : 'AI 月度总结返回缺少 title/summary/suggestion');
    }
    return {
      title: title,
      summary: summary.length > 0 ? summary : content.trim(),
      suggestion: suggestion,
      rawText: content
    };
  }

  private getPayloadString(payload: Record<string, Object>, key: string): string {
    let value = payload[key];
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  }

  private extractJsonObject(raw: string): string {
    let text = raw.trim();
    if (text.startsWith('```')) {
      let first = text.indexOf('\n');
      let last = text.lastIndexOf('```');
      if (first >= 0 && last > first) {
        text = text.substring(first + 1, last).trim();
      }
    }
    let start = text.indexOf('{');
    let end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
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
    return this.chatMessages(config.deciderBaseUrl, [{ role: 'user', content: [imagePart, textPart] }],
      config.apiKey, config.deciderModel, 256);
  }

  async chatImageQuestion(question: string, imageBase64: string, config: CloudModelConfig): Promise<string> {
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let textPart: CloudTextPart = {
      type: 'text',
      text: question
    };
    return this.chatMessages(config.deciderBaseUrl, [{ role: 'user', content: [imagePart, textPart] }],
      config.apiKey, config.deciderModel, 1024, 60000);
  }

  async analyzeGalleryImage(imageBase64: string, ocrText: string, config: GalleryCloudModelConfig): Promise<string> {
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let textPart: CloudTextPart = {
      type: 'text',
      text: '你是图库采集分析器。请结合图片和本地 OCR 文本，提取可入库的生活记忆。' +
        '\n只返回 JSON，不要 Markdown。字段：title, category, summary, details, tags, importance。' +
        '\ntitle、summary、details、tags 都必须使用中文；除非图片里原文就是英文品牌或专有名词，否则不要输出英文。' +
        '\ncategory 必须从 聊天、文档、餐饮、购物、出行、健康、工作、其他 中选择，不要输出英文。' +
        '\nsummary 用 1 句概括这张图的核心信息。' +
        '\ndetails 输出 3 到 8 条具体细节数组，尽量记录可核查的信息，例如人物/商户/地点/商品/金额/时间/订单号/聊天事项/待办/文档标题；看不清不要编造。' +
        '\ntags 输出 3 到 8 个中文短标签，每个标签尽量 2 到 6 个汉字，不要输出英文标签。' +
        '\nimportance 是 0 到 1 的数字。' +
        '\n本地 OCR 文本：\n' + (ocrText.length > 0 ? ocrText : '(空)')
    };
    return this.chatMessages(config.baseUrl, [{ role: 'user', content: [imagePart, textPart] }],
      config.apiKey, config.model, 1024, 90000);
  }

  async createEmbedding(input: string, config: EmbeddingCloudConfig): Promise<number[]> {
    let requestBody: CloudEmbeddingRequest = {
      model: config.model,
      input: input
    };
    let headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + (config.apiKey.length > 0 ? config.apiKey : 'EMPTY')
    };
    let requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(requestBody),
      connectTimeout: 10000,
      readTimeout: 90000,
      expectDataType: http.HttpDataType.STRING
    };

    let httpReq = http.createHttp();
    this.registerActiveRequest(httpReq);
    try {
      let response = await httpReq.request(this.normalizeEmbeddingUrl(config.baseUrl), requestOptions);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Embedding HTTP ${response.responseCode}: ${response.result}`);
      }
      let parsed = ArkJSON.parse(response.result as string) as CloudEmbeddingResponse;
      if (parsed.data.length === 0) {
        throw new Error('Embedding response has no vectors');
      }
      return parsed.data[0].embedding;
    } finally {
      this.unregisterActiveRequest(httpReq);
      httpReq.destroy();
    }
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
    return this.chatMessages(config.deciderBaseUrl, messages, config.apiKey, config.deciderModel, 256);
  }
}
