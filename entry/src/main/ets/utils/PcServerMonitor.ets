import { http, webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { AppLogger } from './AppLogger';

export const PC_SERVER_DEFAULT_URL: string = 'http://127.0.0.1:15001';
const PC_SERVER_STATUS_PATH: string = '/status';
const PC_SERVER_EVENTS_PATH: string = '/events';
const PC_SERVER_CHECK_INTERVAL_MS: number = 2000;
const PC_SERVER_CONNECT_TIMEOUT_MS: number = 1200;
const PC_SERVER_READ_TIMEOUT_MS: number = 1800;
const PC_SERVER_DISCONNECT_FAILURE_THRESHOLD: number = 3;

export type PcServerConnectionState = 'checking' | 'connected' | 'disconnected';

export interface PcServerState {
  state: PcServerConnectionState;
  url: string;
  message: string;
}

export type PcServerStateHandler = (state: PcServerState, becameConnected: boolean) => void;

interface PcServerStatusPayload {
  ok?: boolean;
  status?: string;
  message?: string;
  server?: string;
  version?: string;
}

interface PcServerEventPayload {
  type?: string;
  message?: string;
  server_url?: string;
}

export class PcServerMonitor {
  private baseUrl: string;
  private stateHandler: PcServerStateHandler;
  private running: boolean = false;
  private connected: boolean = false;
  private checkTimerId: number = -1;
  private wsClient: webSocket.WebSocket | null = null;
  private wsConnecting: boolean = false;
  private consecutiveStatusFailures: number = 0;

  constructor(baseUrl: string, stateHandler: PcServerStateHandler) {
    this.baseUrl = this.normalizeHttpUrl(baseUrl);
    this.stateHandler = stateHandler;
  }

  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.publish('checking', '正在连接 PC Server', false);
    this.checkNow();
    this.checkTimerId = setInterval(() => {
      this.checkNow();
    }, PC_SERVER_CHECK_INTERVAL_MS);
  }

  stop(): void {
    this.running = false;
    this.consecutiveStatusFailures = 0;
    if (this.checkTimerId >= 0) {
      clearInterval(this.checkTimerId);
      this.checkTimerId = -1;
    }
    this.closeWebSocket();
  }

  async checkNow(): Promise<void> {
    if (!this.running) {
      return;
    }
    try {
      let status = await this.fetchStatus();
      this.consecutiveStatusFailures = 0;
      let message = this.statusMessage(status);
      this.markConnected(message.length > 0 ? message : 'PC Server 已连接');
      this.ensureWebSocket();
    } catch (e) {
      let err = e as Error;
      this.consecutiveStatusFailures += 1;
      AppLogger.debug('PcServer', 'status check failed #' + String(this.consecutiveStatusFailures) + ': ' +
        (err.message || String(e)));
      if (this.consecutiveStatusFailures >= PC_SERVER_DISCONNECT_FAILURE_THRESHOLD) {
        this.markDisconnected('PC Server 未连接');
      }
    }
  }

  private async fetchStatus(): Promise<PcServerStatusPayload> {
    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: PC_SERVER_CONNECT_TIMEOUT_MS,
        readTimeout: PC_SERVER_READ_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };
      let response = await httpReq.request(this.statusUrl(), options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('HTTP ' + String(response.responseCode));
      }
      let body = String(response.result);
      if (body.trim().length === 0) {
        return { ok: true };
      }
      let parsed = ArkJSON.parse(body) as PcServerStatusPayload;
      if (parsed.ok === false || parsed.status === 'error' || parsed.status === 'failed') {
        throw new Error(parsed.message && parsed.message.length > 0 ? parsed.message : 'status not ok');
      }
      return parsed;
    } finally {
      httpReq.destroy();
    }
  }

  private ensureWebSocket(): void {
    if (!this.running || this.wsClient !== null || this.wsConnecting) {
      return;
    }
    this.wsConnecting = true;
    let client = webSocket.createWebSocket();
    this.wsClient = client;
    client.on('open', (error) => {
      if (error) {
        this.wsConnecting = false;
        AppLogger.warn('PcServer', 'websocket open error: ' + this.errorText(error));
        return;
      }
      this.wsConnecting = false;
      AppLogger.debug('PcServer', 'websocket open');
    });
    client.on('message', (error, value: string | ArrayBuffer) => {
      if (error) {
        AppLogger.warn('PcServer', 'websocket message error: ' + this.errorText(error));
        return;
      }
      this.handleEventMessage(value);
    });
    client.on('close', (error) => {
      this.wsConnecting = false;
      this.wsClient = null;
      if (error) {
        AppLogger.warn('PcServer', 'websocket close error: ' + this.errorText(error));
      }
      if (!this.running) {
        return;
      }
    });
    client.on('error', (error) => {
      this.wsConnecting = false;
      this.wsClient = null;
      AppLogger.debug('PcServer', 'websocket error: ' + this.errorText(error));
      if (!this.running) {
        return;
      }
    });
    client.connect(this.eventsUrl(), {
      proxy: 'no-proxy'
    }).then(() => {
      AppLogger.debug('PcServer', 'websocket connect promise resolved');
      this.wsConnecting = false;
    }).catch((error: BusinessError) => {
      this.wsConnecting = false;
      this.wsClient = null;
      AppLogger.warn('PcServer', 'websocket connect failed: ' + this.errorText(error));
    });
  }

  private handleEventMessage(value: string | ArrayBuffer): void {
    let text = typeof value === 'string' ? value : '';
    if (text.length === 0) {
      return;
    }
    try {
      let event = ArkJSON.parse(text) as PcServerEventPayload;
      if (event.type && event.type.length > 0) {
        AppLogger.debug('PcServer', 'websocket event=' + event.type);
      }
    } catch (e) {
    }
  }

  private closeWebSocket(): void {
    let client = this.wsClient;
    this.wsClient = null;
    this.wsConnecting = false;
    if (client === null) {
      return;
    }
    try {
      client.close({ code: 1000, reason: 'normal' });
    } catch (e) {
    }
  }

  private markConnected(message: string): void {
    let becameConnected = !this.connected;
    this.connected = true;
    this.publish('connected', message, becameConnected);
  }

  private markDisconnected(message: string): void {
    let wasConnected = this.connected;
    this.connected = false;
    if (this.wsClient !== null || this.wsConnecting) {
      this.closeWebSocket();
    }
    this.publish('disconnected', message, false);
    if (wasConnected) {
      AppLogger.info('PcServer', 'connection lost');
    }
  }

  private publish(state: PcServerConnectionState, message: string, becameConnected: boolean): void {
    this.stateHandler({
      state: state,
      url: this.baseUrl,
      message: message
    }, becameConnected);
  }

  private statusMessage(status: PcServerStatusPayload): string {
    let parts: string[] = [];
    if (status.server && status.server.length > 0) {
      parts.push(status.server);
    }
    if (status.version && status.version.length > 0) {
      parts.push(status.version);
    }
    if (parts.length > 0) {
      return parts.join(' · ');
    }
    if (status.message && status.message.length > 0) {
      return status.message;
    }
    return '';
  }

  private statusUrl(): string {
    return this.baseUrl + PC_SERVER_STATUS_PATH;
  }

  private eventsUrl(): string {
    return this.baseUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:') + PC_SERVER_EVENTS_PATH;
  }

  private errorText(error: Object): string {
    let maybeBusiness = error as BusinessError;
    if (maybeBusiness.message !== undefined && maybeBusiness.message.length > 0) {
      return 'code=' + String(maybeBusiness.code) + ', message=' + maybeBusiness.message;
    }
    return String(error);
  }

  private normalizeHttpUrl(url: string): string {
    let trimmed = url.trim();
    if (trimmed.length === 0) {
      trimmed = PC_SERVER_DEFAULT_URL;
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
