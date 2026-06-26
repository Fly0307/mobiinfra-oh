import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { parseJsonCompat } from '../JsonCompat';

export type MimoAudioFormat = 'wav' | 'pcm16';
export type MimoAsrAudioFormat = 'wav' | 'mp3';
export type MimoAsrLanguage = 'auto' | 'zh' | 'en';

export interface MimoVoiceMessage {
  role: string;
  content: string;
}

export interface MimoTtsAudioOptions {
  format: MimoAudioFormat;
  voice: string;
}

export interface MimoTtsRequest {
  model: string;
  messages: MimoVoiceMessage[];
  audio: MimoTtsAudioOptions;
  stream: boolean;
}

export interface MimoTtsBuildOptions {
  model: string;
  voice: string;
  format: MimoAudioFormat;
  stylePrompt?: string;
  stream?: boolean;
}

export interface MimoAsrInputAudio {
  data: string;
}

export interface MimoAsrContentPart {
  type: string;
  input_audio: MimoAsrInputAudio;
}

export interface MimoAsrMessage {
  role: string;
  content: MimoAsrContentPart[];
}

export interface MimoAsrOptions {
  language: MimoAsrLanguage;
}

export interface MimoAsrRequest {
  model: string;
  messages: MimoAsrMessage[];
  asr_options: MimoAsrOptions;
  stream: boolean;
}

export interface MimoVoiceConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
  voice: string;
  readTimeoutMs?: number;
}

export interface MimoTtsSynthesisResult {
  audioBase64: string;
  model: string;
  voice: string;
  format: MimoAudioFormat;
}

interface MimoTtsAudioResponse {
  data?: string;
}

interface MimoTtsMessageResponse {
  role?: string;
  content?: string | null;
  audio?: MimoTtsAudioResponse | null;
}

interface MimoTtsChoice {
  message?: MimoTtsMessageResponse;
}

interface MimoTtsResponse {
  choices?: MimoTtsChoice[];
}

interface MimoAsrMessageResponse {
  role?: string;
  content?: string | null;
}

interface MimoAsrChoice {
  message?: MimoAsrMessageResponse;
}

interface MimoAsrOpenAiResponse {
  choices?: MimoAsrChoice[];
}

interface MimoTextContentPart {
  type?: string;
  text?: string;
}

interface MimoAsrContentResponse {
  content?: MimoTextContentPart[];
  role?: string;
}

export class MimoVoiceClient {
  static buildTtsRequest(text: string, options: MimoTtsBuildOptions): MimoTtsRequest {
    let messages: MimoVoiceMessage[] = [];
    if (options.stylePrompt !== undefined && options.stylePrompt.trim().length > 0) {
      messages.push({
        role: 'user',
        content: options.stylePrompt.trim()
      });
    }
    messages.push({
      role: 'assistant',
      content: text
    });
    return {
      model: options.model,
      messages: messages,
      audio: {
        format: options.format,
        voice: options.voice
      },
      stream: options.stream === true
    };
  }

  static buildAsrRequest(audioBase64: string, format: MimoAsrAudioFormat, language: MimoAsrLanguage,
    stream: boolean): MimoAsrRequest {
    let mimeType = format === 'mp3' ? 'audio/mpeg' : 'audio/wav';
    return {
      model: 'mimo-v2.5-asr',
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'input_audio',
              input_audio: {
                data: 'data:' + mimeType + ';base64,' + audioBase64
              }
            }
          ]
        }
      ],
      asr_options: {
        language: language
      },
      stream: stream
    };
  }

  static parseTtsAudioBase64(payload: string): string {
    let parsed = parseJsonCompat<MimoTtsResponse>(payload);
    let choices = parsed.choices === undefined ? [] : parsed.choices;
    if (choices.length === 0 || choices[0].message === undefined || choices[0].message?.audio === undefined ||
      choices[0].message?.audio === null) {
      throw new Error('MiMO TTS response has no audio data');
    }
    let audio = choices[0].message?.audio;
    let data = audio === undefined || audio.data === undefined ? '' : audio.data.trim();
    if (data.length === 0) {
      throw new Error('MiMO TTS response audio data is empty');
    }
    return data;
  }

  static parseAsrTranscript(payload: string): string {
    try {
      let parsed = parseJsonCompat<MimoAsrOpenAiResponse>(payload);
      let choices = parsed.choices === undefined ? [] : parsed.choices;
      if (choices.length > 0 && choices[0].message !== undefined &&
        typeof choices[0].message?.content === 'string') {
        return (choices[0].message?.content as string).trim();
      }
    } catch (e) {
    }
    let contentParsed = parseJsonCompat<MimoAsrContentResponse>(payload);
    let content = contentParsed.content === undefined ? [] : contentParsed.content;
    for (let i = 0; i < content.length; i++) {
      let part = content[i];
      let text = part.text;
      if (part.type === 'text' && text !== undefined) {
        return text.trim();
      }
    }
    return '';
  }

  static normalizeChatUrl(baseUrl: string): string {
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

  async synthesizeSpeech(text: string, config: MimoVoiceConfig): Promise<MimoTtsSynthesisResult> {
    let requestBody = MimoVoiceClient.buildTtsRequest(text, {
      model: config.model,
      voice: config.voice,
      format: 'wav',
      stream: false
    });
    let headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'api-key': config.apiKey.length > 0 ? config.apiKey : 'EMPTY',
      'Authorization': 'Bearer ' + (config.apiKey.length > 0 ? config.apiKey : 'EMPTY')
    };
    let requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: ArkJSON.stringify(requestBody),
      connectTimeout: 10000,
      readTimeout: config.readTimeoutMs === undefined ? 120000 : config.readTimeoutMs,
      expectDataType: http.HttpDataType.STRING
    };
    let httpReq = http.createHttp();
    try {
      let response = await httpReq.request(MimoVoiceClient.normalizeChatUrl(config.baseUrl), requestOptions);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('MiMO TTS HTTP ' + String(response.responseCode) + ': ' + String(response.result));
      }
      return {
        audioBase64: MimoVoiceClient.parseTtsAudioBase64(response.result as string),
        model: config.model,
        voice: config.voice,
        format: 'wav'
      };
    } finally {
      httpReq.destroy();
    }
  }
}
