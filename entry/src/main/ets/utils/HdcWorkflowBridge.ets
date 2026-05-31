import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { HdcBridgeResponse, WorkflowJsonMap } from './WorkflowTypes';

interface HdcBridgeRequest {
  action: string;
  payload: WorkflowJsonMap;
}

interface StartAppPayload {
  app_name: string;
  package_name: string;
}

interface ScreenshotPayload {
  factor: number;
}

interface ExecuteDeciderPayload {
  response: string;
  width: number;
  height: number;
}

interface LoadPromptPayload {
  prompt_name: string;
}

export class HdcWorkflowBridge {
  private baseUrl: string;
  private logHandler: (message: string) => void;

  constructor(baseUrl: string, logHandler: (message: string) => void) {
    this.baseUrl = baseUrl;
    this.logHandler = logHandler;
  }

  private workflowUrl(): string {
    let url = this.baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url + '/api/workflow';
  }

  async request(action: string, payload: WorkflowJsonMap = {}): Promise<HdcBridgeResponse> {
    let body: HdcBridgeRequest = {
      action: action,
      payload: payload
    };
    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: ArkJSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.STRING
      };
      let resp = await httpReq.request(this.workflowUrl(), options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return {
          status: 'error',
          message: 'HDC bridge HTTP ' + resp.responseCode + ': ' + String(resp.result)
        };
      }
      let parsed = ArkJSON.parse(resp.result as string) as HdcBridgeResponse;
      if (parsed.status !== 'ok') {
        this.logHandler('HDC bridge 返回失败：' + (parsed.message || parsed.status));
      }
      return parsed;
    } catch (e) {
      let err = e as Error;
      return {
        status: 'error',
        message: 'HDC bridge 请求失败：' + err.message
      };
    } finally {
      httpReq.destroy();
    }
  }

  async health(): Promise<boolean> {
    let response = await this.request('health');
    return response.status === 'ok';
  }

  async startApp(appName: string, packageName: string): Promise<void> {
    let payload: StartAppPayload = {
      app_name: appName,
      package_name: packageName
    };
    let response = await this.request('app_start', payload as Object as WorkflowJsonMap);
    if (response.status !== 'ok') {
      throw new Error(response.message || 'app_start failed');
    }
  }

  async screenshot(): Promise<HdcBridgeResponse> {
    let payload: ScreenshotPayload = {
      factor: 0.5
    };
    let response = await this.request('screenshot', payload as Object as WorkflowJsonMap);
    if (response.status !== 'ok' || !response.image_b64) {
      throw new Error(response.message || 'screenshot failed');
    }
    return response;
  }

  async executeModelAction(responseText: string, width: number, height: number): Promise<HdcBridgeResponse> {
    let payload: ExecuteDeciderPayload = {
      response: responseText,
      width: width,
      height: height
    };
    let response = await this.request('execute_decider_action', payload as Object as WorkflowJsonMap);
    if (response.status !== 'ok') {
      throw new Error(response.message || 'execute_decider_action failed');
    }
    return response;
  }

  async loadPromptTemplate(promptName: string): Promise<string> {
    let payload: LoadPromptPayload = {
      prompt_name: promptName
    };
    let response = await this.request('load_prompt_template', payload as Object as WorkflowJsonMap);
    if (response.status !== 'ok') {
      throw new Error(response.message || 'load_prompt_template failed');
    }
    return response.result || '';
  }

  async guiAction(payload: WorkflowJsonMap): Promise<HdcBridgeResponse> {
    let response = await this.request('gui_action', payload);
    if (response.status !== 'ok') {
      throw new Error(response.message || 'gui_action failed');
    }
    return response;
  }
}
