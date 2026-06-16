import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import {
  CLOUD_DECIDER_CURRENT_STEP_PROMPT,
  CLOUD_DECIDER_SYSTEM_PROMPT,
  CLOUD_DECIDER_USER_PROMPT
} from './CloudDeciderPrompt';
import { AppLogger } from './AppLogger';
import { WorkflowJsonRepair } from './WorkflowJsonRepair';
import { GalleryModelJson } from './gallery/GalleryTypes';

// OpenAI-compatible 云端模型客户端。Planner 和 Decider 可以指向不同 base URL，
// 请求统一规范化到 /v1/chat/completions，并支持在任务取消时销毁未完成请求。
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

export interface GalleryQuestionAnswerResult {
  answer: string;
  matchedIds: string[];
  confidence: number;
  rawText: string;
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
  temperature: number;
  model?: string;
  maxTokens?: number;
  readTimeout?: number;
  chatTemplateKwargs?: CloudChatTemplateKwargs;
  top_p?: number;
  top_k?: number;
  min_p?: number;
  presence_penalty?: number;
  repetition_penalty?: number;
}

interface CloudChatRequest {
  messages: CloudChatMessage[];
  temperature: number;
  stream: boolean;
  max_tokens?: number;
  model?: string;
  top_p?: number;
  top_k?: number;
  min_p?: number;
  presence_penalty?: number;
  repetition_penalty?: number;
  chat_template_kwargs?: CloudChatTemplateKwargs;
}

interface CloudChatOptions {
  temperature?: number;
  top_p?: number;
  top_k?: number;
  min_p?: number;
  presence_penalty?: number;
  repetition_penalty?: number;
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

type JsonPayload = Record<string, Object | string | number | boolean | null>;
type GalleryFieldKey = 'title' | 'category' | 'summary' | 'details' | 'tags' | 'importance';

interface GalleryFieldAnalysisResult {
  key: GalleryFieldKey;
  rawText: string;
  parsed: GalleryModelJson;
}

interface GalleryFieldAnalysisBundle {
  json: GalleryModelJson;
  rawText: string;
}

export class CloudModelClient {
  private activeRequests: http.HttpRequest[] = [];
  private readonly galleryChatOptions: CloudChatOptions = {
    temperature: 0,
    top_p: 1,
    top_k: 1,
    min_p: 0.0,
    presence_penalty: 0,
    repetition_penalty: 1.05,
    chat_template_kwargs: {
      enable_thinking: false
    }
  };

  private registerActiveRequest(request: http.HttpRequest): void {
    this.activeRequests.push(request);
  }

  private unregisterActiveRequest(request: http.HttpRequest): void {
    this.activeRequests = this.activeRequests.filter((item: http.HttpRequest) => item !== request);
  }

  cancelActiveRequests(): void {
    // 浮窗终止任务时会调用这里，主动 destroy 当前 HTTP 请求，避免云端长推理阻塞收尾。
    let pending = this.activeRequests.slice();
    this.activeRequests = [];
    for (let i = 0; i < pending.length; i++) {
      try {
        pending[i].destroy();
      } catch (e) {
        AppLogger.warnCause('CloudModel', 'destroy pending request failed', e as Error);
      }
    }
  }

  private buildQwenHistoryText(historyItems: string[]): string {
    // Qwen Decider 的历史只保留结构化动作摘要，避免把整段模型输出反复塞回上下文。
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
    // 日志中只展示 base64 前缀，既能确认图像被传入，又不会把完整截图刷进日志。
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
    // 兼容三种用户输入：host、host/v1、host/v1/chat/completions。
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

  async chatCompletionText(options: CloudChatCompletionOptions): Promise<string> {
    let requestBody: CloudChatRequest = {
      messages: options.messages,
      temperature: options.temperature,
      stream: false
    };
    if (options.maxTokens !== undefined) {
      requestBody.max_tokens = options.maxTokens;
    }
    if (options.model !== undefined && options.model.trim().length > 0) {
      requestBody.model = options.model.trim();
    }
    if (options.top_p !== undefined) {
      requestBody.top_p = options.top_p;
    }
    if (options.top_k !== undefined) {
      requestBody.top_k = options.top_k;
    }
    if (options.min_p !== undefined) {
      requestBody.min_p = options.min_p;
    }
    if (options.presence_penalty !== undefined) {
      requestBody.presence_penalty = options.presence_penalty;
    }
    if (options.repetition_penalty !== undefined) {
      requestBody.repetition_penalty = options.repetition_penalty;
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
      readTimeout: options.readTimeout === undefined ? 120000 : options.readTimeout,
      expectDataType: http.HttpDataType.STRING
    };

    let httpReq = http.createHttp();
    this.registerActiveRequest(httpReq);
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
    } catch (e) {
      let err = e as Error;
      throw err;
    } finally {
      this.unregisterActiveRequest(httpReq);
      httpReq.destroy();
    }
  }

  private async chatMessages(baseUrl: string, messages: CloudChatMessage[], apiKey: string,
    model?: string, maxTokens?: number, readTimeout?: number,
    chatOptions?: CloudChatOptions): Promise<string> {
    // 这里返回 string 而不是直接抛业务错误，是为了让 PC Agent 仍能收到 action=error 的 JSON。
    let options: CloudChatCompletionOptions = {
      baseUrl: baseUrl,
      apiKey: apiKey,
      messages: messages,
      temperature: chatOptions?.temperature === undefined ? 0 : chatOptions.temperature,
      model: model,
      maxTokens: maxTokens,
      readTimeout: readTimeout
    };
    if (chatOptions !== undefined) {
      if (chatOptions.top_p !== undefined) {
        options.top_p = chatOptions.top_p;
      }
      if (chatOptions.top_k !== undefined) {
        options.top_k = chatOptions.top_k;
      }
      if (chatOptions.min_p !== undefined) {
        options.min_p = chatOptions.min_p;
      }
      if (chatOptions.presence_penalty !== undefined) {
        options.presence_penalty = chatOptions.presence_penalty;
      }
      if (chatOptions.repetition_penalty !== undefined) {
        options.repetition_penalty = chatOptions.repetition_penalty;
      }
      if (chatOptions.chat_template_kwargs !== undefined) {
        options.chatTemplateKwargs = chatOptions.chat_template_kwargs;
      }
    }
    try {
      return await this.chatCompletionText(options);
    } catch (e) {
      let err = e as Error;
      return ArkJSON.stringify({ action: 'error', reason: err.message });
    }
  }

  private async chat(baseUrl: string, content: CloudContentPart[], apiKey: string,
    chatTemplateKwargs?: CloudChatTemplateKwargs): Promise<string> {
    let message: CloudChatMessage = {
      role: 'user',
      content: content
    };
    let chatOptions: CloudChatOptions | undefined = chatTemplateKwargs === undefined ? undefined : {
      chat_template_kwargs: chatTemplateKwargs
    };
    return this.chatMessages(baseUrl, [message], apiKey, undefined, undefined, undefined, chatOptions);
  }

  async summarizeGalleryMonth(config: GalleryCloudModelConfig, monthAggregateText: string): Promise<GalleryMonthSummaryResult> {
    let prompt = '你是一个图库月度洞察助手。' +
      '\n\n请根据用户提供的月度图库聚合数据和图片摘要清单，判断这个月用户大概做了什么，并生成一个适合展示在“图库洞察”页的月度总结。' +
      '\n不要思考，不要输出思考过程、推理过程或分析步骤。' +
      '\n严格基于输入数据，不要编造具体人名、地点、城市、店名或未出现的事件。' +
      '\n如果只能推测，请使用“可能”“疑似”“看起来像”。' +
      '\n不要使用“人生高光”“最重要”等强判断。' +
      '\nsummary 必须包含 2 到 3 个具体观察，优先引用输入里的时间、类别、数量、平台、活动或事项线索；不要只写“内容丰富”“记录较多”这类笼统表述。' +
      '\n\n只输出 JSON，格式如下：' +
      '\n{' +
      '\n  "title": "最多14个字的标题",' +
      '\n  "summary": "80到140字的月度总结，说明这个月大概做了什么",' +
      '\n  "suggestion": "一句可执行整理建议"' +
      '\n}' +
      '\n\n月度图库聚合数据：\n' + monthAggregateText +
      '\n\n只输出 JSON，不要思考。';
    let message: CloudChatMessage = {
      role: 'user',
      content: prompt
    };
    let content = await this.chatMessages(config.baseUrl, [message], config.apiKey, config.model, 1024, 90000,
      this.galleryChatOptions);
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

  async answerGalleryQuestion(config: GalleryCloudModelConfig, question: string,
    candidateText: string): Promise<GalleryQuestionAnswerResult> {
    let prompt = '你是图库问答助手。' +
      '\n不要思考，不要输出思考过程、推理过程或分析步骤。' +
      '\n只基于给定的候选图片记录回答用户问题，不要编造候选记录中没有的事实。' +
      '\n如果候选记录证据不足，请直接说明没有找到明确记录。' +
      '\n只输出 JSON，不要输出 Markdown、解释、前后缀或思考过程，格式如下：' +
      '\n{' +
      '\n  "answer": "基于候选图片的简短回答",' +
      '\n  "matchedIds": ["相关图片 id"],' +
      '\n  "confidence": 0.0' +
      '\n}' +
      '\n\n用户问题：\n' + question +
      '\n\n候选图片记录：\n' + candidateText;
    let message: CloudChatMessage = {
      role: 'user',
      content: prompt
    };
    let content = await this.chatMessages(config.baseUrl, [message], config.apiKey, config.model, 1024, 90000,
      this.galleryChatOptions);
    let payloadText = this.extractJsonObject(content);
    let payload: Record<string, Object> = {};
    try {
      payload = ArkJSON.parse(payloadText) as Record<string, Object>;
    } catch (e) {
      return {
        answer: content.trim(),
        matchedIds: [],
        confidence: 0,
        rawText: content
      };
    }
    let answer = this.getPayloadString(payload, 'answer');
    if (answer.length === 0) {
      answer = this.getPayloadString(payload, '回答');
    }
    let matchedIds = this.getPayloadStringArray(payload, 'matchedIds');
    if (matchedIds.length === 0) {
      matchedIds = this.getPayloadStringArray(payload, 'matched_ids');
    }
    let confidence = this.getPayloadNumber(payload, 'confidence');
    return {
      answer: answer.length > 0 ? answer : content.trim(),
      matchedIds: matchedIds,
      confidence: confidence,
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

  private getPayloadStringArray(payload: Record<string, Object>, key: string): string[] {
    let value = payload[key];
    if (value === undefined || value === null) {
      return [];
    }
    if (Array.isArray(value)) {
      let items = value as Object[];
      let result: string[] = [];
      for (let i = 0; i < items.length; i++) {
        let text = String(items[i]).trim();
        if (text.length > 0) {
          result.push(text);
        }
      }
      return result;
    }
    let textValue = String(value).trim();
    if (textValue.length === 0) {
      return [];
    }
    return [textValue];
  }

  private getPayloadNumber(payload: Record<string, Object>, key: string): number {
    let value = payload[key];
    if (value === undefined || value === null) {
      return 0;
    }
    let parsed = parseFloat(String(value));
    if (isNaN(parsed)) {
      return 0;
    }
    return parsed;
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
    // Planner 只吃纯文本，用来选择目标 App 或做一次性任务分解。
    let textPart: CloudTextPart = {
      type: 'text',
      text: prompt
    };
    return this.chat(config.plannerBaseUrl, [textPart], config.apiKey, { enable_thinking: false });
  }

  async chatPlannerMessages(messages: CloudChatMessage[], config: CloudModelConfig): Promise<string> {
    return this.chatMessages(config.plannerBaseUrl, messages, config.apiKey, undefined, undefined, undefined, {
      chat_template_kwargs: { enable_thinking: false }
    });
  }

  async chatDecider(prompt: string, imageBase64: string, config: CloudModelConfig): Promise<string> {
    // 通用图文 Decider：完整 prompt 与当前截图作为同一条 user 消息发送。
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
    // workflow 中的图片问答步骤可能比动作 JSON 更长，因此使用更大的 max_tokens 和较短超时。
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

  async analyzeGalleryImage(imageBase64: string, ocrText: string, exifText: string, config: GalleryCloudModelConfig): Promise<string> {
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let textPart: CloudTextPart = {
      type: 'text',
      text: this.galleryAnalysisBasePrompt(ocrText, exifText) +
        '\n只输出一个紧凑 JSON 对象，不要 Markdown，不要解释，不要思考过程，不要代码块。' +
        '\n必须严格使用这个结构：{"title":"","category":"其他","summary":"","details":["",""],"tags":[],"importance":0.5}' +
        '\n现在只返回 JSON 对象。'
    };
    return this.chatMessages(config.baseUrl, [{ role: 'user', content: [imagePart, textPart] }],
      config.apiKey, config.model, 4096, 90000, this.galleryChatOptions);
  }

  async analyzeGalleryImageByFields(imageBase64: string, ocrText: string, exifText: string,
    config: GalleryCloudModelConfig): Promise<GalleryFieldAnalysisBundle> {
    let keys: GalleryFieldKey[] = ['title', 'category', 'summary', 'details', 'tags', 'importance'];
    let results = await Promise.all(keys.map(async (key: GalleryFieldKey) => {
      return await this.analyzeGalleryImageField(imageBase64, ocrText, exifText, config, key);
    }));
    let merged: GalleryModelJson = {};
    let rawParts: string[] = [];
    for (let i = 0; i < results.length; i++) {
      let result = results[i];
      rawParts.push(result.key + ': ' + result.rawText);
      if (result.key === 'title' && result.parsed.title !== undefined) {
        merged.title = result.parsed.title;
      } else if (result.key === 'category' && result.parsed.category !== undefined) {
        merged.category = result.parsed.category;
      } else if (result.key === 'summary' && result.parsed.summary !== undefined) {
        merged.summary = result.parsed.summary;
      } else if (result.key === 'details' && result.parsed.details !== undefined) {
        merged.details = result.parsed.details;
      } else if (result.key === 'tags' && result.parsed.tags !== undefined) {
        merged.tags = result.parsed.tags;
      } else if (result.key === 'importance' && result.parsed.importance !== undefined) {
        merged.importance = result.parsed.importance;
      }
    }
    let bundle: GalleryFieldAnalysisBundle = {
      json: merged,
      rawText: rawParts.join('\n')
    };
    return bundle;
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
    } catch (e) {
      let err = e as Error;
      throw err;
    } finally {
      this.unregisterActiveRequest(httpReq);
      httpReq.destroy();
    }
  }

  async chatQwenDecider(task: string, historyItems: string[], imageBase64: string, config: CloudModelConfig): Promise<string> {
    // Qwen 专用 Decider：system、任务/历史、截图、当前步输出约束分开组织，输出更稳定。
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

  private galleryAnalysisBasePrompt(ocrText: string, exifText: string): string {
    return '你是图库采集分析器。结合图片、OCR、拍摄信息，提取可入库的生活记忆，只返回json。' +
      '\n字段简述：title是图片主题；category是分类；summary是1句核心概括；details是可核查细节列表；tags是便于检索的短标签；importance是重要度。' +
      '\n只输出一个紧凑 JSON 对象，不要 Markdown，不要解释，不要思考过程，不要代码块。' +
      '\n必须严格使用这个结构：{"title":"","category":"其他","summary":"","details":["",""],"tags":[],"importance":0.5}' +
      '\n字段要求：title不超过18字；summary用1句话概括这张图最核心的信息，不超过60字，尽量写清人物/事项/场景，信息不确定时用“疑似”“可能”“看起来像”等保守表达，不要编造。' +
      '\ndetails优先输出3到8条具体细节；如果图片里可核查信息确实很少，可以少于3条。每条尽量记录人物、商户、地点、商品、金额、时间、订单号、聊天事项、待办、文档标题等可识别信息；看不清就不要写。' +
      '\ntags输出1到5个短标签，优先用中文，通常2到4字。' +
      '\n可用tags：聊天、待办、会议、工作、项目、客户、通知、截图、账单、消费、外卖、餐饮、购物、快递、售后、健康、体检、用药、运动、睡眠、饮食、医疗、文档、合同、笔记、课程、作业、证件、资料、发票、家庭、朋友、聚会、亲子、节日、纪念、账号、安全、配置、报错、登录、密码。你最好这些tags中挑选，也可以自己补充。' +
      '\nimportance是0到1之间的数字，代表重要程度，比如说0.5。' +
      '\ntitle、summary、details、tags 的内容都必须使用中文，除非是英文专有名词。所有字符串不能包含换行或未转义双引号。' +
      '\ncategory 只能是以下之一：聊天、文档、餐饮、购物、出行、健康、工作、其他。' +
      '\n本地 OCR 文本：\n' + (ocrText.length > 0 ? ocrText : '空') +
      '\n拍摄信息：\n' + (exifText.length > 0 ? exifText : '空');
  }

  private gallerySingleFieldPrompt(key: GalleryFieldKey, ocrText: string, exifText: string): string {
    let context = '你是图库采集分析器。结合图片、OCR、拍摄信息，提取可入库的生活记忆。' +
      '\n本地 OCR 文本：\n' + (ocrText.length > 0 ? ocrText : '空') +
      '\n拍摄信息：\n' + (exifText.length > 0 ? exifText : '空') +
      '\n通用要求：只基于图片、OCR 和拍摄信息，不要编造；不确定时使用“疑似”“可能”“看起来像”等保守表达。' +
      '\n所有字符串优先使用中文，除非是英文专有名词；字符串不能包含换行或未转义双引号。';
    let outputRule = '\n输出要求：不要 Markdown，不要解释，不要思考过程，不要代码块。现在只返回 JSON 对象。';
    if (key === 'title') {
      return context + outputRule +
        '\n本次只生成 title。title 是图片主题，不超过18字，要概括“这是什么/在做什么/属于什么事项”。' +
        '\n优先使用图片和 OCR 中最明确的主体，例如聊天事项、订单/账单、文档标题、餐饮/购物/出行/健康场景。' +
        '\n不要写“图片”“截图”“一张图”这类空泛标题，除非确实无法识别具体内容。' +
        '\n只返回一个 JSON 对象，并且只包含一个 key：{"title":""}。不要返回其他字段。';
    }
    if (key === 'category') {
      return context + outputRule +
        '\n本次只生成 category。category 必须从聊天、文档、餐饮、购物、出行、健康、工作、其他中选择一个。' +
        '\n分类规则：聊天=聊天记录/消息/群通知；文档=合同/笔记/课程/证件/资料/发票等文档；餐饮=外卖/菜单/餐厅/饮食；购物=订单/快递/售后/商品/账单消费；出行=机票/火车/酒店/地图/行程；健康=体检/医疗/用药/运动/睡眠；工作=会议/项目/客户/办公事项；无法明确时用其他。' +
        '\n只返回一个 JSON 对象，并且只包含一个 key：{"category":""}。不要返回其他字段。';
    }
    if (key === 'summary') {
      return context + outputRule +
        '\n本次只生成 summary。summary 是给用户回看图库时直接可读的一句话核心概括，不超过60字。' +
        '\n必须优先说明图片最重要的事实：人物/对象、事项、平台或场景，以及 OCR 中可确认的时间、金额、地点、商户、订单、待办、文档标题等关键信息。' +
        '\n如果信息不确定，使用“疑似”“可能”“看起来像”等保守表达；不要编造图片和 OCR 中没有的事实。' +
        '\n不要只写“这是一张聊天截图/文档截图/购物截图”这类泛化描述，要尽量说清截图记录了什么事。' +
        '\n只返回一个 JSON 对象，并且只包含一个 key：{"summary":""}。不要返回其他字段。';
    }
    if (key === 'details') {
      return context + outputRule +
        '\n本次只生成 details。details 是可核查细节数组，优先输出3到8条，信息很少时可以少于3条。' +
        '\n每条只写图片或 OCR 能支持的事实，优先抽取人物、商户、地点、商品、金额、时间、订单号、聊天事项、待办、文档标题、账号/登录/报错等线索。' +
        '\n不要把同一事实重复拆成多条；看不清或不能确认的内容不要写，必要时用“疑似/可能”。' +
        '\n只返回一个 JSON 对象，并且只包含一个 key：{"details":["",""]}。不要返回其他字段。';
    }
    if (key === 'tags') {
      return context + outputRule +
        '\n本次只生成 tags。tags 是便于检索的短标签，输出1到5个，优先中文，通常2到4字。' +
        '\n可用标签：聊天、待办、会议、工作、项目、客户、通知、截图、账单、消费、外卖、餐饮、购物、快递、售后、健康、体检、用药、运动、睡眠、饮食、医疗、文档、合同、笔记、课程、作业、证件、资料、发票、家庭、朋友、聚会、亲子、节日、纪念、账号、安全、配置、报错、登录、密码。' +
        '\n优先从可用标签中选择，也可以补充 OCR 中明确出现且适合检索的短词。标签应覆盖类别、事项类型和关键主题，例如“账单”“快递”“会议”“体检”“登录”。' +
        '\n不要输出长句、重复标签、过泛标签；如果只有一个明确主题，少量标签即可。' +
        '\n只返回一个 JSON 对象，并且只包含一个 key：{"tags":[]}。不要返回其他字段。';
    }
    return context + outputRule +
      '\n本次只生成 importance。importance 是0到1的数字，表示这张图作为生活记忆的保留价值。' +
      '\n评分参考：重要证件/合同/医疗/订单售后/明确待办/高价值账单接近0.8到1；普通聊天/日常消费/一般资料约0.4到0.7；无明确信息、重复截图、低价值内容约0到0.3。' +
      '\n只返回一个 JSON 对象，并且只包含一个 key：{"importance":0.5}。不要返回其他字段。';
  }

  private async analyzeGalleryImageField(imageBase64: string, ocrText: string, exifText: string,
    config: GalleryCloudModelConfig, key: GalleryFieldKey): Promise<GalleryFieldAnalysisResult> {
    let imageUrl: CloudImageUrl = {
      url: 'data:image/jpeg;base64,' + imageBase64
    };
    let imagePart: CloudImagePart = {
      type: 'image_url',
      image_url: imageUrl
    };
    let textPart: CloudTextPart = {
      type: 'text',
      text: this.gallerySingleFieldPrompt(key, ocrText, exifText)
    };
    let rawText = await this.chatMessages(config.baseUrl, [{ role: 'user', content: [imagePart, textPart] }],
      config.apiKey, config.model, 2048, 90000, this.galleryChatOptions);
    return {
      key: key,
      rawText: rawText,
      parsed: this.parseGalleryFieldJson(key, rawText)
    };
  }

  private parseGalleryFieldJson(key: GalleryFieldKey, rawText: string): GalleryModelJson {
    let raw = rawText.trim();
    let rawParsed = this.tryParseGalleryFieldJson(raw);
    if (rawParsed) {
      return this.normalizeGalleryFieldJson(key, rawParsed);
    }
    let cleaned = WorkflowJsonRepair.normalizeJsonText(rawText);
    let cleanedParsed = this.tryParseGalleryFieldJson(cleaned);
    if (cleanedParsed) {
      AppLogger.info('CloudModel', 'gallery field json normalized key=' + key);
      return this.normalizeGalleryFieldJson(key, cleanedParsed);
    }
    let candidates: string[] = [];
    let repairedCandidates = WorkflowJsonRepair.repairCandidates(cleaned);
    for (let i = 0; i < repairedCandidates.length; i++) {
      if (candidates.indexOf(repairedCandidates[i]) < 0) {
        candidates.push(repairedCandidates[i]);
      }
    }
    for (let i = 0; i < candidates.length; i++) {
      let parsed = this.tryParseGalleryFieldJson(candidates[i]);
      if (parsed) {
        AppLogger.info('CloudModel', 'gallery field json repaired key=' + key +
          ' candidate=' + (i + 1).toString() + '/' + candidates.length.toString());
        return this.normalizeGalleryFieldJson(key, parsed);
      }
    }
    AppLogger.warn('CloudModel', 'gallery field json parse failed key=' + key +
      ' rawTail=' + this.debugTail(rawText));
    return this.fallbackGalleryFieldFromText(key, rawText);
  }

  private normalizeGalleryFieldJson(key: GalleryFieldKey, parsed: GalleryModelJson): GalleryModelJson {
    let result: GalleryModelJson = {};
    let payload = parsed as JsonPayload;
    if (key === 'title') {
      let title = this.galleryFieldString(payload['title']);
      if (title.length > 0) {
        result.title = title;
      }
    } else if (key === 'category') {
      let category = this.normalizeGalleryCategory(this.galleryFieldString(payload['category']));
      if (category.length > 0) {
        result.category = category;
      }
    } else if (key === 'summary') {
      let summary = this.galleryFieldString(payload['summary']);
      if (summary.length > 0) {
        result.summary = summary;
      }
    } else if (key === 'details') {
      result.details = this.galleryFieldStringArray(payload['details'], true);
    } else if (key === 'tags') {
      result.tags = this.galleryFieldStringArray(payload['tags'], true);
    } else if (key === 'importance') {
      let importance = this.galleryFieldNumber(payload['importance']);
      if (!isNaN(importance)) {
        result.importance = Math.max(0, Math.min(1, importance));
      }
    }
    return result;
  }

  private fallbackGalleryFieldFromText(key: GalleryFieldKey, text: string): GalleryModelJson {
    let trimmed = text.replace(/```(?:json)?/g, '').replace(/```/g, '').trim();
    let loose = this.looseGalleryFieldText(key, trimmed);
    let result: GalleryModelJson = {};
    if (key === 'title' && loose.length > 0) {
      result.title = loose;
    } else if (key === 'category') {
      let category = this.normalizeGalleryCategory(loose);
      if (category.length === 0) {
        category = this.normalizeGalleryCategory(trimmed);
      }
      if (category.length > 0) {
        result.category = category;
      }
    } else if (key === 'summary' && loose.length > 0) {
      result.summary = loose;
    } else if (key === 'details') {
      result.details = this.looseGalleryFieldArray(key, trimmed);
    } else if (key === 'tags') {
      result.tags = this.looseGalleryFieldArray(key, trimmed);
    } else if (key === 'importance') {
      let importance = this.looseGalleryImportance(trimmed);
      if (!isNaN(importance)) {
        result.importance = Math.max(0, Math.min(1, importance));
      }
    }
    return result;
  }

  private looseGalleryFieldText(key: GalleryFieldKey, text: string): string {
    let cleaned = text.replace(/```(?:json)?/g, '')
      .replace(/```/g, '')
      .replace(/[“”]/g, '"')
      .replace(/[‘’]/g, "'")
      .replace(/，/g, ',')
      .replace(/[：:]/g, '')
      .replace(/[()（）]/g, '')
      .replace(/[“”"'‘’`]+/g, '')
      .replace(/[{}]/g, '')
      .replace(/\s+/g, '');
    cleaned = this.stripLooseGalleryFieldName(cleaned, key);
    return cleaned.replace(/^[\[:,，、;；]+/, '').replace(/[\],，、;；]+$/, '');
  }

  private looseGalleryFieldArrayText(key: GalleryFieldKey, text: string): string {
    return this.looseGalleryFieldText(key, text).replace(/[\[\]]/g, '');
  }

  private looseGalleryFieldArray(key: GalleryFieldKey, text: string): string[] {
    let markdownItems = this.markdownListItems(text);
    if (markdownItems.length > 0) {
      return markdownItems;
    }
    return this.galleryFieldStringArray(this.looseGalleryFieldArrayText(key, text), true);
  }

  private markdownListItems(text: string): string[] {
    let lines = text.replace(/\r/g, '\n').split('\n');
    let result: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      let match = lines[i].match(/^\s*(?:[-*+]|[0-9]+[.)、])\s+(.+)$/);
      if (match && match.length > 1) {
        let value = match[1].trim().replace(/[“”"'‘’`]+/g, '');
        if (value.length > 0 && result.indexOf(value) < 0) {
          result.push(value);
        }
      }
    }
    return result;
  }

  private looseGalleryImportance(text: string): number {
    let normalized = text.replace(/％/g, '%');
    let percent = normalized.match(/([0-9]+(?:\.[0-9]+)?)\s*%/);
    if (percent && percent.length > 1) {
      return Number(percent[1]) / 100;
    }
    let number = normalized.match(/([0-9]+(?:\.[0-9]+)?)/);
    if (!number || number.length <= 1) {
      return NaN;
    }
    let value = Number(number[1]);
    return value > 1 ? value / 100 : value;
  }

  private stripLooseGalleryFieldName(text: string, key: GalleryFieldKey): string {
    let cleaned = text;
    let markers: string[] = [key + ':'];
    for (let i = 0; i < markers.length; i++) {
      cleaned = cleaned.split(markers[i]).join('');
    }
    if (cleaned.startsWith(key)) {
      cleaned = cleaned.substring(key.length);
    }
    return cleaned;
  }

  private galleryFieldString(value: Object | string | number | boolean | null | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim().replace(/[\r\n\t]+/g, ' ');
  }

  private galleryFieldStringArray(value: Object | string | number | boolean | null | undefined,
    splitText: boolean): string[] {
    if (value === undefined || value === null) {
      return [];
    }
    let rawItems: string[] = [];
    if (Array.isArray(value)) {
      let items = value as Object[];
      for (let i = 0; i < items.length; i++) {
        rawItems.push(String(items[i]));
      }
    } else {
      let text = String(value);
      rawItems = splitText ? text.split(/[\n\r,，、;；]/) : [text];
    }
    let result: string[] = [];
    for (let i = 0; i < rawItems.length; i++) {
      let item = rawItems[i].trim().replace(/[\r\n\t]+/g, ' ');
      if (item.length > 0 && result.indexOf(item) < 0) {
        result.push(item);
      }
    }
    return result;
  }

  private galleryFieldNumber(value: Object | string | number | boolean | null | undefined): number {
    if (value === undefined || value === null) {
      return NaN;
    }
    return Number(String(value).trim());
  }

  private normalizeGalleryCategory(value: string): string {
    let categories: string[] = ['聊天', '文档', '餐饮', '购物', '出行', '健康', '工作', '其他'];
    for (let i = 0; i < categories.length; i++) {
      if (value.indexOf(categories[i]) >= 0) {
        return categories[i];
      }
    }
    return '';
  }

  private debugTail(text: string): string {
    let normalized = text.replace(/[\r\n\t]+/g, ' ');
    if (normalized.length <= 240) {
      return normalized;
    }
    return normalized.substring(normalized.length - 240);
  }

  private tryParseGalleryFieldJson(text: string): GalleryModelJson | null {
    try {
      return ArkJSON.parse(text) as GalleryModelJson;
    } catch (e) {
      return null;
    }
  }
}
