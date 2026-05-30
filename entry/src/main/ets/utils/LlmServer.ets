import { socket } from '@kit.NetworkKit';
import { util, JSON as ArkJSON } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CloudModelClient, CloudModelConfig } from './CloudModelClient';
import { AgentExecutionController } from './AgentExecutionController';

type NativeApi = Record<string, Function>;
type RequestValue = Object | string | number | boolean | null;
type RequestMap = Record<string, RequestValue>;

interface TaskResponse {
  task: string;
}

interface StatusResponse {
  status: string;
  result?: string;
  message?: string;
}

interface ActionErrorResponse {
  action: string;
  reason: string;
}

interface ErrorResponse {
  error: string;
}

interface CloudDebugResponse {
  __cloud_debug_prompt: string;
  response: string;
}

export class LlmServer {
  private server: socket.TCPSocketServer | null = null;
  private isRunning: boolean = false;
  private cloudConnectLogged: boolean = false;
  private cloudActionHistory: string[] = [];
  private cloudTask: string = '';
  private cancellationRequested: boolean = false;
  private localApi: NativeApi | null = null;
  private cloudClientRef: CloudModelClient | null = null;
  private onLogHandler: ((msg: string) => void) | null = null;
  public currentTask: string = '';

  public running(): boolean {
    return this.isRunning;
  }

  public async requestTaskCancellation(): Promise<void> {
    this.cancellationRequested = true;
    this.currentTask = '';
    this.cloudActionHistory = [];
    this.cloudTask = '';
    this.onLogHandler?.('>> [Cancel] 用户点击悬浮窗，请求终止当前任务。');

    try {
      this.cloudClientRef?.cancelActiveRequests();
    } catch (e) {
    }

    if (this.localApi) {
      try {
        let agentReset = this.localApi['agentReset'];
        if (typeof agentReset === 'function') {
          await agentReset();
        }
      } catch (e) {
      }

      try {
        let reset = this.localApi['reset'];
        if (typeof reset === 'function') {
          reset();
        }
      } catch (e) {
      }
    }
  }

  private isCancellationRequested(): boolean {
    return this.cancellationRequested || AgentExecutionController.isCancelRequested();
  }

  private clearCancellationState(): void {
    this.cancellationRequested = false;
  }

  private sendTerminate(client: socket.TCPSocketConnection, reason: string): void {
    this.sendJson(client, ArkJSON.stringify({
      action: 'terminate',
      reasoning: reason,
      parameters: {
        status: 'cancelled',
        message: reason
      }
    }));
  }

  private finishExecution(reason?: string): void {
    this.clearCancellationState();
    AgentExecutionController.finishExecution(reason ?? 'AI Agent running...');
  }

  private extractCloudTask(prefix: string): string {
    let marker = '### Current Task';
    let start = prefix.indexOf(marker);
    if (start < 0) {
      return this.currentTask;
    }
    let rest = prefix.substring(start + marker.length).trim();
    let nextSection = rest.indexOf('\n### ');
    if (nextSection >= 0) {
      rest = rest.substring(0, nextSection).trim();
    }
    return rest.length > 0 ? rest : this.currentTask;
  }

  private cleanupSnapshots(filesDir: string): void {
    try {
      let files = fs.listFileSync(filesDir);
      for (let fileName of files) {
        if (fileName.startsWith('agent_snapshot_')) {
          fs.unlinkSync(filesDir + '/' + fileName);
        }
      }
    } catch (e) {
    }
  }

  private saveSnapshot(filesDir: string, imageBase64: string): string {
    this.cleanupSnapshots(filesDir);
    let ts = new Date().getTime();
    let imgPath = filesDir + '/agent_snapshot_' + ts + '.jpg';
    let base64Helper = new util.Base64Helper();
    let imgBuffer = base64Helper.decodeSync(imageBase64);
    let file = fs.openSync(imgPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, imgBuffer.buffer);
    fs.closeSync(file);
    return imgPath;
  }

  private getString(req: RequestMap, key: string): string {
    let value = req[key];
    return typeof value === 'string' ? value : '';
  }

  private sendJson(client: socket.TCPSocketConnection, payload: string): void {
    let sendOptions: socket.TCPSendOptions = {
      data: payload + '<<EOF>>'
    };
    client.send(sendOptions);
  }

  private sendStatus(client: socket.TCPSocketConnection, status: string, result?: string, message?: string): void {
    let response: StatusResponse = {
      status: status,
      result: result,
      message: message
    };
    this.sendJson(client, ArkJSON.stringify(response));
  }

  private sendTask(client: socket.TCPSocketConnection): void {
    let response: TaskResponse = {
      task: this.currentTask
    };
    this.sendJson(client, ArkJSON.stringify(response));
  }

  private sendActionError(client: socket.TCPSocketConnection, reason: string): void {
    let response: ActionErrorResponse = {
      action: 'error',
      reason: reason
    };
    this.sendJson(client, ArkJSON.stringify(response));
  }

  private sendError(client: socket.TCPSocketConnection, error: string): void {
    let response: ErrorResponse = {
      error: error
    };
    this.sendJson(client, ArkJSON.stringify(response));
  }

  private sendCloudDebugResponse(client: socket.TCPSocketConnection, debugPrompt: string, modelResponse: string): void {
    let response: CloudDebugResponse = {
      __cloud_debug_prompt: debugPrompt,
      response: modelResponse
    };
    this.sendJson(client, ArkJSON.stringify(response));
  }

  private normalizeCloudHistoryItem(response: string): string {
    let text = response.trim();
    let jsonStart = text.indexOf('{');
    let jsonEnd = text.lastIndexOf('}');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
      text = text.substring(jsonStart, jsonEnd + 1);
    }

    try {
      let parsed = ArkJSON.parse(text) as Object;
      return ArkJSON.stringify(parsed);
    } catch (e) {
      return response;
    }
  }

  start(port: number, filesDir: string, mnnllm: NativeApi, onLog: (msg: string) => void,
    onRequireApproval?: (response: string) => Promise<boolean>): void {
    if (this.isRunning) {
      onLog('Server is already running.');
      return;
    }

    this.localApi = mnnllm;
    this.cloudClientRef = null;
    this.onLogHandler = onLog;
    this.cancellationRequested = false;
    this.server = socket.constructTCPSocketServerInstance();
    let ipAddress: socket.NetAddress = { address: '0.0.0.0', port: port, family: 1 };

    this.server.listen(ipAddress, (err) => {
      if (err) {
        onLog('[ERROR] Local TCP server failed to start: ' + ArkJSON.stringify(err));
        return;
      }
      this.isRunning = true;
      onLog('====== Local PC control backend started ======\nTCP port: ' + port +
        '\nYou can now submit an Agent task in the app.');
    });

    this.server.on('connect', (client: socket.TCPSocketConnection) => {
      let bufferStr = '';

      client.on('message', async (data) => {
        let textDecoder = util.TextDecoder.create('utf-8');
        let str = textDecoder.decodeWithStream(new Uint8Array(data.message));
        bufferStr += str;

        let eofIdx = bufferStr.indexOf('<<EOF>>');
        if (eofIdx === -1) {
          return;
        }

        let payload = bufferStr.substring(0, eofIdx);
        bufferStr = bufferStr.substring(eofIdx + 7);

        try {
          let req = ArkJSON.parse(payload) as RequestMap;
          let reqType = this.getString(req, 'type');

          if (reqType === 'poll') {
            this.sendTask(client);
            return;
          }

          if (reqType === 'clear') {
            let preserveExecution = req['preserve_execution'] === true;
            this.currentTask = '';
            let agentReset = mnnllm['agentReset'];
            let reset = mnnllm['reset'];
            if (typeof agentReset === 'function') {
              try {
                await agentReset();
              } catch (e) {
              }
            } else if (typeof reset === 'function') {
              reset();
            }
            onLog('>> [Local Clear] Task cleared and model context reset.');
            if (!preserveExecution) {
              this.finishExecution();
            }
            this.sendStatus(client, 'ok');
            return;
          }

          if (reqType === 'error') {
            this.currentTask = '';
            this.finishExecution();
            onLog('>> [PC Error] ' + this.getString(req, 'message'));
            this.sendStatus(client, 'ok');
            return;
          }

          if (this.isCancellationRequested()) {
            onLog('>> [Local Cancel] cancellation intercepted before handling request: ' + reqType);
            this.sendTerminate(client, 'Task cancelled by user');
            return;
          }

          if (reqType === 'agent_prefill') {
            let prefix = this.getString(req, 'prefix');
            onLog('>> [Agent Prefill] prompt chars=' + prefix.length + '\n' + prefix);
            AppStorage.set('floatText', 'Prefill...');
            try {
              let agentPrefill = mnnllm['agentPrefill'];
              let result = await agentPrefill(prefix) as string;
              if (this.isCancellationRequested()) {
                onLog('>> [Agent Prefill] cancelled by user.');
                this.sendStatus(client, 'cancelled', '', 'Task cancelled by user');
                return;
              }
              AppStorage.set('floatText', 'AI Agent running...');
              onLog('>> [Agent Prefill Done] ' + result);
              this.sendStatus(client, 'ok', result);
            } catch (e) {
              let message = String(e);
              if (this.isCancellationRequested()) {
                onLog('>> [Agent Prefill] cancelled while running.');
                this.sendStatus(client, 'cancelled', '', 'Task cancelled by user');
                return;
              }
              onLog('>> [Agent Prefill ERROR] ' + message);
              this.sendStatus(client, 'error', '', message);
            }
            return;
          }

          if (reqType === 'agent_step') {
            let variable = this.getString(req, 'variable');
            let imageBase64 = this.getString(req, 'image_b64');
            if (imageBase64.length > 0) {
              let imgPath = this.saveSnapshot(filesDir, imageBase64);
              let w = req['width'];
              let h = req['height'];
              let imgTag = '<img>' + imgPath + '<hw>' + h + ',' + w + '</hw></img>';
              onLog('>> [Agent Step] image saved: ' + imgPath + ' (' + w + 'x' + h + ')');
              if (variable.indexOf('<image_placeholder>') !== -1) {
                variable = variable.replace('<image_placeholder>', imgTag);
              } else {
                variable = imgTag + variable;
              }
            }

            onLog('>> [Agent Step] variable prompt:\n' + variable);
            AppStorage.set('floatText', 'Thinking...');
            let streamedText = '';
            try {
              let agentStep = mnnllm['agentStep'];
              let response = await agentStep(variable, (token: string) => {
                if (this.isCancellationRequested()) {
                  throw new Error('__agent_cancelled__');
                }
                streamedText += token;
                AppStorage.set('floatText', streamedText);
              }) as string;
              if (this.isCancellationRequested()) {
                onLog('>> [Agent Step] cancelled after inferencing.');
                this.sendTerminate(client, 'Task cancelled by user');
                return;
              }
              AppStorage.set('floatText', 'AI Agent running...');
              onLog('>> [Agent Step] model response:\n' + response);

              if (onRequireApproval) {
                let isApproved = await onRequireApproval(response);
                if (this.isCancellationRequested()) {
                  onLog('>> [Agent Step] cancelled while waiting for approval.');
                  this.sendTerminate(client, 'Task cancelled by user');
                  return;
                }
                if (!isApproved) {
                  this.currentTask = '';
                  this.finishExecution();
                  this.sendActionError(client, 'User rejected');
                  return;
                }
              }

              if (response.indexOf('"done"') !== -1 || response.indexOf('"stop"') !== -1) {
                this.currentTask = '';
                this.finishExecution();
                onLog('>> [Agent] Task completed.');
              }

              this.sendJson(client, response);
            } catch (e) {
              let message = String(e);
              if (this.isCancellationRequested() || message.indexOf('__agent_cancelled__') !== -1) {
                onLog('>> [Agent Step] cancelled during inferencing.');
                this.sendTerminate(client, 'Task cancelled by user');
                return;
              }
              onLog('>> [Agent Step ERROR] ' + message);
              this.sendActionError(client, message);
            }
            return;
          }

          if (reqType === 'agent_reset') {
            try {
              let agentReset = mnnllm['agentReset'];
              if (typeof agentReset === 'function') {
                await agentReset();
              }
            } catch (e) {
            }
            this.currentTask = '';
            AppStorage.set('floatText', 'AI Agent running...');
            onLog('>> [Agent Reset] Local Agent context reset.');
            this.sendStatus(client, 'ok');
            return;
          }

          if (reqType === 'action') {
            let prompt = this.getString(req, 'prompt');
            let imageBase64 = this.getString(req, 'image_b64');
            if (imageBase64.length > 0) {
              let imgPath = this.saveSnapshot(filesDir, imageBase64);
              let w = req['width'];
              let h = req['height'];
              let imgTag = '<img>' + imgPath + '<hw>' + h + ',' + w + '</hw></img>';
              onLog('>> [Action] image saved: ' + imgPath + ' (' + w + 'x' + h + ')');
              if (prompt.indexOf('<image_placeholder>') !== -1) {
                prompt = prompt.replace('<image_placeholder>', imgTag);
              } else {
                prompt = imgTag + '\n' + prompt;
              }
            }

            onLog('>> [Action] full prompt:\n' + prompt);
            AppStorage.set('floatText', 'Inferencing...');
            let chat = mnnllm['chat'];
            let response = await chat(prompt) as string;
            if (this.isCancellationRequested()) {
              onLog('>> [Action] cancelled after inferencing.');
              this.sendTerminate(client, 'Task cancelled by user');
              return;
            }
            AppStorage.set('floatText', 'AI Agent running...');
            onLog('>> [Action] model response:\n' + response);

            if (onRequireApproval) {
              let isApproved = await onRequireApproval(response);
              if (this.isCancellationRequested()) {
                onLog('>> [Action] cancelled while waiting for approval.');
                this.sendTerminate(client, 'Task cancelled by user');
                return;
              }
              if (!isApproved) {
                this.currentTask = '';
                this.finishExecution();
                this.sendActionError(client, 'User rejected');
                return;
              }
            }

            if (response.indexOf('"done"') !== -1 || response.indexOf('"stop"') !== -1) {
              this.currentTask = '';
              this.finishExecution();
              onLog('>> [Action] Task completed.');
            }

            this.sendJson(client, response);
            return;
          }

          this.sendError(client, 'Unsupported request type: ' + reqType);
        } catch (e) {
          let message = String(e);
          if (this.isCancellationRequested()) {
            onLog('>> [Local Request] cancelled during in-flight request.');
            this.sendTerminate(client, 'Task cancelled by user');
            return;
          }
          onLog('[ERROR] Request handling failed: ' + message);
          this.sendError(client, 'Failed');
        }
      });
    });
  }

  startCloud(port: number, filesDir: string, cloudClient: CloudModelClient, cloudConfig: CloudModelConfig,
    onLog: (msg: string) => void, onRequireApproval?: (response: string) => Promise<boolean>): void {
    if (this.isRunning) {
      onLog('Server is already running.');
      return;
    }

    this.cloudConnectLogged = false;
    this.cloudActionHistory = [];
    this.cloudTask = '';
    this.localApi = null;
    this.cloudClientRef = cloudClient;
    this.onLogHandler = onLog;
    this.cancellationRequested = false;
    this.server = socket.constructTCPSocketServerInstance();
    let ipAddress: socket.NetAddress = { address: '0.0.0.0', port: port, family: 1 };

    this.server.listen(ipAddress, (err) => {
      if (err) {
        onLog('[ERROR] Cloud TCP server failed to start: ' + ArkJSON.stringify(err));
        return;
      }
      this.isRunning = true;
      onLog('====== Cloud PC control backend started ======\nTCP port: ' + port +
        '\nPlanner: ' + cloudConfig.plannerBaseUrl +
        '\nDecider: ' + cloudConfig.deciderBaseUrl +
        '\nYou can now submit a cloud Agent task.');
    });

    this.server.on('connect', (client: socket.TCPSocketConnection) => {
      let bufferStr = '';
      if (!this.cloudConnectLogged) {
        this.cloudConnectLogged = true;
        onLog('>> [Cloud Connect] PC client connected to App TCP server.');
      }

      client.on('message', async (data) => {
        let textDecoder = util.TextDecoder.create('utf-8');
        let str = textDecoder.decodeWithStream(new Uint8Array(data.message));
        bufferStr += str;

        let eofIdx = bufferStr.indexOf('<<EOF>>');
        if (eofIdx === -1) {
          return;
        }

        let payload = bufferStr.substring(0, eofIdx);
        bufferStr = bufferStr.substring(eofIdx + 7);

        try {
          let req = ArkJSON.parse(payload) as RequestMap;
          let reqType = this.getString(req, 'type');
          if (reqType !== 'poll') {
            onLog('>> [Cloud Request] type=' + reqType);
          }

          if (reqType === 'poll') {
            if (this.currentTask.length > 0) {
              onLog('>> [Cloud Poll] PC fetched task: ' + this.currentTask);
            }
            this.sendTask(client);
            return;
          }

          if (reqType === 'clear') {
            let preserveExecution = req['preserve_execution'] === true;
            this.currentTask = '';
            this.cloudActionHistory = [];
            this.cloudTask = '';
            onLog('>> [Cloud Clear] Task and cloud history cleared.');
            if (!preserveExecution) {
              this.finishExecution();
            }
            this.sendStatus(client, 'ok');
            return;
          }

          if (reqType === 'error') {
            this.currentTask = '';
            this.finishExecution();
            onLog('>> [PC Error] ' + this.getString(req, 'message'));
            this.sendStatus(client, 'ok');
            return;
          }

          if (this.isCancellationRequested()) {
            onLog('>> [Cloud Cancel] cancellation intercepted before handling request: ' + reqType);
            this.sendTerminate(client, 'Task cancelled by user');
            return;
          }

          if (reqType === 'cloud_history_append') {
            let response = this.getString(req, 'response');
            if (response.length > 0) {
              this.cloudActionHistory.push(this.normalizeCloudHistoryItem(response));
              onLog('>> [Cloud History] appended after PC execution success, history=' + this.cloudActionHistory.length);
            }
            this.sendStatus(client, 'ok');
            return;
          }

          if (reqType === 'agent_prefill') {
            let prefix = this.getString(req, 'prefix');
            this.cloudActionHistory = [];
            this.cloudTask = this.extractCloudTask(prefix);
            onLog('>> [Cloud Agent Prefill] Qwen prompt mode, task=' + this.cloudTask);
            if (this.isCancellationRequested()) {
              this.sendStatus(client, 'cancelled', '', 'Task cancelled by user');
              return;
            }
            this.sendStatus(client, 'ok', 'cloud qwen prompt mode');
            return;
          }

          if (reqType === 'agent_step') {
            let prompt = this.getString(req, 'variable');
            let imageBase64 = this.getString(req, 'image_b64');
            if (imageBase64.length > 0) {
              let imgPath = this.saveSnapshot(filesDir, imageBase64);
              onLog('>> [Cloud Agent Step] image saved: ' + imgPath);
            }

            AppStorage.set('floatText', 'Cloud thinking...');
            if (imageBase64.length > 0) {
              onLog('>> [Cloud Decider] sending Qwen messages, history=' + this.cloudActionHistory.length);
            } else {
              onLog('>> [Cloud Planner] sending agent_step text...');
            }

            let qwenTask = this.cloudTask.length > 0 ? this.cloudTask : this.currentTask;
            let debugPrompt = '';
            if (imageBase64.length > 0) {
              debugPrompt = cloudClient.formatQwenDeciderPromptForLog(qwenTask, this.cloudActionHistory, imageBase64);
              onLog('>> [Cloud Decider Prompt]\n' + debugPrompt);
            }
            let response = imageBase64.length > 0 ?
              await cloudClient.chatQwenDecider(qwenTask, this.cloudActionHistory, imageBase64, cloudConfig) :
              await cloudClient.chatPlanner(prompt, cloudConfig);
            if (this.isCancellationRequested()) {
              onLog('>> [Cloud Agent Step] cancelled after inferencing.');
              this.sendTerminate(client, 'Task cancelled by user');
              return;
            }
            AppStorage.set('floatText', 'AI Agent running...');
            onLog('>> [Cloud Agent Step] model response:\n' + response);

            if (onRequireApproval) {
              let isApproved = await onRequireApproval(response);
              if (this.isCancellationRequested()) {
                onLog('>> [Cloud Agent Step] cancelled while waiting for approval.');
                this.sendTerminate(client, 'Task cancelled by user');
                return;
              }
              if (!isApproved) {
                this.currentTask = '';
                this.finishExecution();
                this.sendActionError(client, 'User rejected');
                return;
              }
            }

            if (response.indexOf('"done"') !== -1 || response.indexOf('"stop"') !== -1) {
              this.currentTask = '';
              this.finishExecution();
              onLog('>> [Cloud Agent] Task completed.');
            }
            if (imageBase64.length > 0) {
              this.sendCloudDebugResponse(client, debugPrompt, response);
              return;
            }
            this.sendJson(client, response);
            return;
          }

          if (reqType === 'agent_reset') {
            this.currentTask = '';
            this.cloudActionHistory = [];
            this.cloudTask = '';
            AppStorage.set('floatText', 'AI Agent running...');
            onLog('>> [Cloud Agent Reset] Cloud Agent context reset.');
            this.sendStatus(client, 'ok');
            return;
          }

          if (reqType === 'action') {
            let prompt = this.getString(req, 'prompt');
            let imageBase64 = this.getString(req, 'image_b64');
            if (imageBase64.length > 0) {
              let imgPath = this.saveSnapshot(filesDir, imageBase64);
              onLog('>> [Cloud Action] image saved: ' + imgPath);
            }

            AppStorage.set('floatText', 'Cloud inferencing...');
            if (imageBase64.length > 0) {
              onLog('>> [Cloud Decider] sending action with screenshot...');
            } else {
              onLog('>> [Cloud Planner] sending action text...');
            }
            let response = imageBase64.length > 0 ?
              await cloudClient.chatDecider(prompt, imageBase64, cloudConfig) :
              await cloudClient.chatPlanner(prompt, cloudConfig);
            if (this.isCancellationRequested()) {
              onLog('>> [Cloud Action] cancelled after inferencing.');
              this.sendTerminate(client, 'Task cancelled by user');
              return;
            }
            AppStorage.set('floatText', 'AI Agent running...');
            onLog('>> [Cloud Action] model response:\n' + response);

            if (onRequireApproval) {
              let isApproved = await onRequireApproval(response);
              if (this.isCancellationRequested()) {
                onLog('>> [Cloud Action] cancelled while waiting for approval.');
                this.sendTerminate(client, 'Task cancelled by user');
                return;
              }
              if (!isApproved) {
                this.currentTask = '';
                this.finishExecution();
                this.sendActionError(client, 'User rejected');
                return;
              }
            }

            if (response.indexOf('"done"') !== -1 || response.indexOf('"stop"') !== -1) {
              this.currentTask = '';
              this.finishExecution();
            }
            this.sendJson(client, response);
            return;
          }

          this.sendError(client, 'Unsupported request type: ' + reqType);
        } catch (e) {
          let message = String(e);
          if (this.isCancellationRequested()) {
            onLog('>> [Cloud Request] cancelled during in-flight request.');
            this.sendTerminate(client, 'Task cancelled by user');
            return;
          }
          onLog('[ERROR] Cloud request handling failed: ' + message);
          this.sendError(client, 'Failed');
        }
      });
    });
  }
}
