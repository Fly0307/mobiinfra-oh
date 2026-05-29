import { promptAction, router } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { JSON as ArkJSON, util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import mnnllm from 'libentry.so';
import { AppHeader } from '../components/AppHeader';
import { CollectionPage } from './collection/CollectionPage';
import { HomePage } from './home/HomePage';
import { TaskPage } from './task/TaskPage';
import { AgentRouterServer } from '../utils/AgentRouterServer';
import { CloudModelClient, CloudModelConfig } from '../utils/CloudModelClient';
import { AgentExecutionController } from '../utils/AgentExecutionController';
import { WorkflowRunner } from '../utils/WorkflowRunner';
import { WorkflowStorage } from '../utils/WorkflowStorage';
import { WorkflowTask, WorkflowRunResult } from '../utils/WorkflowTypes';

// 首页总入口：负责把“数据归家”业务 UI、本地端侧推理、云端 Planner/Decider、
// 模型下载/调试工具和 PC 侧 HDC Agent 控制入口串起来。各业务 tab 的展示 UI
// 下沉到 home/collection/task，避免 Index.ets 继续膨胀。
interface ServerFile {
  name: string;
  size: number;
}

interface RunCmdRequest {
  cmd: string;
}

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

const DEFAULT_WIRELESS_IP = '192.168.137.195:33117';
const DEFAULT_MODEL_SERVER_URL = 'http://166.111.53.96:9123';
const DEFAULT_HDC_SERVER_URL = 'http://192.168.137.1:9124';
const DEFAULT_CLOUD_BASE_URL = 'http://166.111.53.96:7003';
const DEFAULT_CLOUD_API_KEY = 'mobiagent-key';
const LEGACY_WIRELESS_IPS: string[] = [
  '101.5.155.98:35729',
  '192.168.137.172:35963',
  '192.168.137.55:35963',
  '192.168.137.55:33117'
];

PersistentStorage.persistProp('wirelessIp', DEFAULT_WIRELESS_IP);
PersistentStorage.persistProp('serverIp', DEFAULT_MODEL_SERVER_URL);
PersistentStorage.persistProp('hdcServerIp', DEFAULT_HDC_SERVER_URL);
PersistentStorage.persistProp('cloudPlannerBaseUrl', DEFAULT_CLOUD_BASE_URL);
PersistentStorage.persistProp('cloudDeciderBaseUrl', DEFAULT_CLOUD_BASE_URL);
PersistentStorage.persistProp('cloudApiKey', DEFAULT_CLOUD_API_KEY);
PersistentStorage.persistProp('cloudDeciderModel', '');

@Entry
@Component
struct Index {
  @State output: string = '请先检查服务器连接';
  @State chatHistory: string = '';
  @State userInput: string = '';
  @State downloading: boolean = false;
  @State modelLoaded: boolean = false;
  @State connected: boolean = false;
  @State autoConfirm: boolean = true;
  @State debugImagePath: string = '';
  @State selectedModelVariant: string = '';
  @State customOppReady: boolean = false;
  @State threadNumInput: string = '4';
  @State backendTypeInput: string = 'cpu';
  @State mllmBackendTypeInput: string = 'cpu';
  @State currentTab: number = 0;
  @State collectionModule: number = 1;
  @State taskScene: number = 0;
  @State assistantSettingsOpen: boolean = false;
  @StorageLink('serverIp') serverIp: string = DEFAULT_MODEL_SERVER_URL;
  @StorageLink('hdcServerIp') hdcServerIp: string = DEFAULT_HDC_SERVER_URL;
  @StorageLink('wirelessIp') wirelessIp: string = DEFAULT_WIRELESS_IP;
  @StorageLink('cloudPlannerBaseUrl') cloudPlannerBaseUrl: string = DEFAULT_CLOUD_BASE_URL;
  @StorageLink('cloudDeciderBaseUrl') cloudDeciderBaseUrl: string = DEFAULT_CLOUD_BASE_URL;
  @StorageLink('cloudApiKey') cloudApiKey: string = DEFAULT_CLOUD_API_KEY;
  @StorageLink('cloudDeciderModel') cloudDeciderModel: string = '';
  @State isThinking: boolean = false;
  @State cloudOutput: string = '请先配置 Planner 和 Decider 云端服务';
  @State cloudUserInput: string = '';
  @State cloudDebugImagePath: string = '';
  @State cloudAutoConfirm: boolean = true;
  @State cloudThinking: boolean = false;

  private filesDir: string = '';
  private modelDir: string = '';
  private serverFiles: ServerFile[] = [];
  private totalBytesAll: number = 0;
  
  // PC 控制服务端单例。AgentRouterServer 在本地模型和云端模型之间切换同一个 9126 入口。
  private agentRouter: AgentRouterServer = new AgentRouterServer();
  private cloudClient: CloudModelClient = new CloudModelClient();

  // 云端 Agent 日志会同步写入 AppStorage，便于日志页/浮窗读取最近状态。
  private appendCloudLog(message: string): void {
    let stamp = new Date().toLocaleTimeString();
    let line = `[${stamp}] ${message}`;
    let nextLogs = this.cloudOutput.length > 0 ? this.cloudOutput + '\n' + line : line;
    if (nextLogs.length > 60000) {
      nextLogs = nextLogs.substring(nextLogs.length - 60000);
    }
    this.cloudOutput = nextLogs;
    AppStorage.setOrCreate('cloudAgentLogs', this.cloudOutput);
  }

  private resetCloudLog(message: string): void {
    let stamp = new Date().toLocaleTimeString();
    this.cloudOutput = `[${stamp}] ${message}`;
    AppStorage.setOrCreate('cloudAgentLogs', this.cloudOutput);
  }

  aboutToAppear() {
    // 页面启动时先修正旧版本持久化默认值，再初始化模型目录、日志捕获、自定义算子和 Agent 路由。
    this.migrateDefaultEndpointValues();
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    this.syncModelDir();
    try {
      mnnllm.initLogFile(this.filesDir + '/mnn_runtime.log');
    } catch (e) {
      let err = e as Error;
      console.error('initLogFile failed: ' + err.message);
    }
    this.prepareCustomOpp();
    this.agentRouter.configureLocal(mnnllm as Record<string, Function>, (msg: string) => {
      this.output = msg;
      let match = msg.match(/<img>(.*?)<hw>/);
      if (match && match[1]) {
        this.debugImagePath = 'file://' + match[1];
      }
    }, async (response: string) => {
      if (this.autoConfirm) { return true; }
      return new Promise<boolean>((resolve) => {
        promptAction.showDialog({
          title: '大模型返回确认',
          message: '模型推理结果：\n' + response + '\n\n是否同意执行？',
          buttons: [
            { text: '拒绝', color: '#ff0000' },
            { text: '同意', color: '#00cc00' }
          ]
        }).then((data: promptAction.ShowDialogSuccessResponse) => { resolve(data.index === 1); }).catch(() => { resolve(false); });
      });
    });
    this.agentRouter.configureCloud(this.cloudClient, () => this.getCloudConfig(), (msg: string) => {
      this.appendCloudLog(msg);
      let match = msg.match(/agent_snapshot_.*?\.jpg/);
      if (match && match[0]) {
        this.cloudDebugImagePath = 'file://' + this.filesDir + '/' + match[0];
      }
    }, async (response: string) => {
      if (this.cloudAutoConfirm) {
        this.appendCloudLog('自动同意已开启，模型动作已放行给 PC 执行。');
        return true;
      }
      this.appendCloudLog('等待用户确认模型动作。PC 会停在 Sending step request，直到点击同意。');
      return new Promise<boolean>((resolve) => {
        promptAction.showDialog({
          title: '云端模型返回确认',
          message: '模型推理结果:\n' + response + '\n\n是否同意执行？',
          buttons: [
            { text: '拒绝', color: '#ff0000' },
            { text: '同意', color: '#00cc00' }
          ]
        }).then((data: promptAction.ShowDialogSuccessResponse) => {
          let approved = data.index === 1;
          this.appendCloudLog(approved ? '用户已同意，动作返回 PC。' : '用户已拒绝，任务终止。');
          resolve(approved);
        }).catch(() => {
          this.appendCloudLog('确认弹窗关闭或失败，动作按拒绝处理。');
          resolve(false);
        });
      });
    });
    // 浮窗终止按钮只发取消信号；真正的模型上下文清理由当前路由的 LlmServer 完成。
    AgentExecutionController.registerLocalCancelHandler(async () => {
      if (this.agentRouter.getRouteMode() !== 'local') {
        return;
      }
      await this.agentRouter.requestTaskCancellation();
      this.output = '用户已通过悬浮窗终止本地 Agent 任务。';
    });
    AgentExecutionController.registerCloudCancelHandler(async () => {
      if (this.agentRouter.getRouteMode() !== 'cloud') {
        return;
      }
      await this.agentRouter.requestTaskCancellation();
      this.appendCloudLog('用户已通过悬浮窗终止云端 Agent 任务。');
    });
  }

  private migrateDefaultEndpointValues(): void {
    // 兼容历史版本写入 PersistentStorage 的默认地址，避免用户升级后仍连到废弃端口。
    if (this.hdcServerIp === 'http://166.111.53.96:9124') {
      this.hdcServerIp = DEFAULT_HDC_SERVER_URL;
    }
    if (this.wirelessIp.trim().length === 0 || LEGACY_WIRELESS_IPS.includes(this.wirelessIp)) {
      this.wirelessIp = DEFAULT_WIRELESS_IP;
    }
    if (this.cloudPlannerBaseUrl === 'http://166.111.53.96:8001') {
      this.cloudPlannerBaseUrl = DEFAULT_CLOUD_BASE_URL;
    }
    if (this.cloudDeciderBaseUrl === 'http://166.111.53.96:8000') {
      this.cloudDeciderBaseUrl = DEFAULT_CLOUD_BASE_URL;
    }
    if (this.cloudApiKey.trim().length === 0) {
      this.cloudApiKey = DEFAULT_CLOUD_API_KEY;
    }
    if (this.cloudDeciderModel === 'decider' || this.cloudDeciderModel === 'decider_model') {
      this.cloudDeciderModel = '';
    }
  }

  private prepareCustomOpp(): boolean {
    let ctx = getContext(this) as common.UIAbilityContext;
    try {
      let res = mnnllm.prepareCustomOpp(ctx.resourceManager, this.filesDir + '/custom_opp');
      this.customOppReady = (res === 'ok');
      if (!this.customOppReady) {
        this.output = '自定义算子准备失败: ' + res;
      }
      return this.customOppReady;
    } catch (e) {
      let err = e as Error;
      this.customOppReady = false;
      this.output = '自定义算子准备异常: ' + err.message;
      return false;
    }
  }

  private getCurrentModelFolderName(): string {
    return this.selectedModelVariant.length > 0 ? this.selectedModelVariant : 'model';
  }

  private syncModelDir(): void {
    this.modelDir = `${this.filesDir}/${this.getCurrentModelFolderName()}`;
  }

  private switchModelVariant(variant: string): void {
    let nextVariant = '';
    if (variant === 'modelv2' || variant === 'modelv3' || variant === 'modelv4' || variant === 'model_omc') {
      nextVariant = variant;
    }
    if (this.selectedModelVariant === nextVariant) {
      return;
    }
    this.selectedModelVariant = nextVariant;
    this.syncModelDir();
    this.modelLoaded = false;
    this.output = `模型路径已切换至: ${this.getCurrentModelFolderName()}`;
  }

  formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes}B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)}KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)}MB`;
    return `${(bytes / 1073741824).toFixed(2)}GB`;
  }

  clearScreenshots() {
    try {
      let files = fs.listFileSync(this.filesDir);
      let count = 0;
      for (let f of files) {
        if (f.startsWith('agent_') || f.toLowerCase().endsWith('.jpg') || f.toLowerCase().endsWith('.jpeg')) {
          try {
            fs.unlinkSync(`${this.filesDir}/${f}`);
            count++;
          } catch (e) {
            this.appendCloudLog(`删除截图失败：${f}，${String(e)}`);
          }
        }
      }
      this.output = `清理成功，删除了 ${count} 张缓存截图。`;
      this.debugImagePath = '';
      this.cloudDebugImagePath = '';
      this.appendCloudLog(`已删除 App 中保存的截图：${count} 张`);
    } catch(e) {
      this.output = `清理截图失败: ${e}`;
    }
  }

  listScreenshots() {
    try {
      let files = fs.listFileSync(this.filesDir);
      let screenshots = files.filter(f => f.toLowerCase().endsWith('.jpg') || f.toLowerCase().endsWith('.jpeg') || f.startsWith('agent_'));
      if (screenshots.length > 0) {
        this.output = `====== 沙箱内截图文件列表 ======\n${screenshots.join('\n')}`;
      } else {
        this.output = '沙箱内当前没有截图文件。';
      }
    } catch (e) {
      this.output = `列出截图失败: ${e}`;
    }
  }

  deleteModelFiles() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = '模型目录不存在，无需删除。';
        return;
      }
      let deletedCount = this.deletePathRecursively(this.modelDir);
      this.modelLoaded = false;
      this.output = `模型删除成功\n已删除 ${this.getCurrentModelFolderName()} 目录及其内容（共 ${deletedCount} 项）。`;
    } catch (e) {
      this.output = `模型删除失败: ${e}`;
    }
  }

  deleteModelConfigJson() {
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型文件夹不存在: ${this.modelDir}`;
        return;
      }
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}\n无需删除。`;
        return;
      }
      fs.unlinkSync(cfgPath);
      this.modelLoaded = false;
      this.output = `已删除 ${this.getCurrentModelFolderName()}/config.json。\n其他模型文件保留，可重新下载补齐 config.json。`;
    } catch (e) {
      this.output = `删除 config.json 失败: ${e}`;
    }
  }

  private deletePathRecursively(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let deleted = 0;
      for (let name of children) {
        deleted += this.deletePathRecursively(`${path}/${name}`);
      }
      fs.rmdirSync(path);
      return deleted + 1;
    } catch {
      fs.unlinkSync(path);
      return 1;
    }
  }

  private calcPathSize(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let sum = 0;
      for (let name of children) {
        let childPath = `${path}/${name}`;
        sum += this.calcPathSize(childPath);
      }
      return sum;
    } catch {
      try {
        return fs.statSync(path).size;
      } catch {
        return 0;
      }
    }
  }

  private buildFileTree(path: string, depth: number, out: string[]): void {
    let indent = '';
    for (let i = 0; i < depth; i++) {
      indent += '  ';
    }
    try {
      let children = fs.listFileSync(path);
      let dirSize = this.calcPathSize(path);
      let baseName = path.substring(path.lastIndexOf('/') + 1);
      out.push(`${indent}[D] ${baseName}/ (${this.formatSize(dirSize)})`);
      children.sort();
      for (let name of children) {
        this.buildFileTree(`${path}/${name}`, depth + 1, out);
      }
    } catch {
      let fileSize = 0;
      try { fileSize = fs.statSync(path).size; } catch {}
      let baseName = path.substring(path.lastIndexOf('/') + 1);
      out.push(`${indent}[F] ${baseName} (${this.formatSize(fileSize)})`);
    }
  }

  listModelFilesTree() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型目录不存在: ${this.modelDir}`;
        return;
      }
      let lines: string[] = [];
      this.buildFileTree(this.modelDir, 0, lines);
      this.output = `====== ${this.getCurrentModelFolderName()} 文件树 ======\n` +
        `根目录: ${this.modelDir}\n` +
        lines.join('\n');
    } catch (e) {
      this.output = `查看模型文件树失败: ${e}`;
    }
  }

  private deleteChunkVisionOmUnder(path: string): number {
    let deleted = 0;
    let children: string[] = [];
    try {
      children = fs.listFileSync(path);
    } catch {
      return 0;
    }
    for (let name of children) {
      let childPath = `${path}/${name}`;
      if (name.startsWith('chunk_')) {
        let visionPath = `${childPath}/vision.om`;
        try {
          if (fs.accessSync(visionPath)) {
            fs.unlinkSync(visionPath);
            deleted++;
          }
        } catch {}
      }
      deleted += this.deleteChunkVisionOmUnder(childPath);
    }
    return deleted;
  }

  deleteChunkVisionOmFiles() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型目录不存在: ${this.modelDir}`;
        return;
      }
      let count = this.deleteChunkVisionOmUnder(this.modelDir);
      this.output = `已在 ${this.getCurrentModelFolderName()} 下删除 ${count} 个 chunk_*/vision.om`;
    } catch (e) {
      this.output = `删除 chunk_*/vision.om 失败: ${e}`;
    }
  }

  deleteDebugOutputs() {
    let variants = ['model', 'modelv2', 'modelv3', 'modelv4', 'model_omc'];
    let totalDeleted = 0;
    let results: string[] = [];
    for (let variant of variants) {
      let debugDir = `${this.filesDir}/${variant}/debug_outputs`;
      try {
        if (!fs.accessSync(debugDir)) {
          continue;
        }
        let files = fs.listFileSync(debugDir);
        let count = 0;
        for (let f of files) {
          try {
            fs.unlinkSync(`${debugDir}/${f}`);
            count++;
          } catch {}
        }
        try {
          fs.rmdirSync(debugDir);
        } catch {}
        totalDeleted += count;
        results.push(`${variant}/debug_outputs: ${count} files`);
      } catch {
        // directory doesn't exist, skip
      }
    }
    if (totalDeleted === 0) {
      this.output = '所有 model 目录下均无 debug_outputs';
    } else {
      this.output = `已删除 ${totalDeleted} 个调试输出文件\n${results.join('\n')}`;
    }
  }

  showConfigJson() {
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}\n请先下载模型`;
        return;
      }
      let file = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      this.output = `====== ${this.getCurrentModelFolderName()}/config.json ======\n${content}`;
    } catch (e) {
      this.output = `读取 config.json 失败: ${e}`;
    }
  }

  updateConfigThreadNum() {
    let num = parseInt(this.threadNumInput);
    if (isNaN(num) || num <= 0) {
      this.output = '请输入有效的线程数（正整数）';
      return;
    }
    
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}`;
        return;
      }
      
      // 读取文件。
      let fileRead = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(fileRead.fd, buf);
      fs.closeSync(fileRead);
      
      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      
      // 修改 JSON。
      let configObj = ArkJSON.parse(content) as JsonMap;
      configObj['thread_num'] = num;
      if (configObj['mllm']) {
        let mllmObj = configObj['mllm'] as JsonMap;
        mllmObj['thread_num'] = num;
      }
      
      // 写入文件。
      let newStr = ArkJSON.stringify(configObj, null, 4);
      let byteStr = util.TextEncoder.create('utf-8').encodeInto(newStr);
      let fileWrite = fs.openSync(cfgPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(fileWrite.fd, byteStr.buffer);
      fs.closeSync(fileWrite);
      
      this.output = `更新线程数成功: ${num}\n====== 新配置 ======\n${newStr}`;
    } catch (e) {
      this.output = `更新 config.json 失败: ${e}`;
    }
  }

  updateConfigBackendType(target: string) {
    let value = (target === 'mllm') ? this.mllmBackendTypeInput.trim() : this.backendTypeInput.trim();
    if (value.length === 0) {
      this.output = '请输入有效的 backend_type';
      return;
    }

    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}`;
        return;
      }

      let fileRead = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(fileRead.fd, buf);
      fs.closeSync(fileRead);

      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      let configObj = ArkJSON.parse(content) as JsonMap;

      if (target === 'mllm') {
        if (configObj['mllm']) {
          let mllmObj = configObj['mllm'] as JsonMap;
          mllmObj['backend_type'] = value;
        } else {
          this.output = 'config.json 中不存在 mllm 字段';
          return;
        }
      } else {
        configObj['backend_type'] = value;
      }

      let newStr = ArkJSON.stringify(configObj, null, 4);
      let byteStr = util.TextEncoder.create('utf-8').encodeInto(newStr);
      let fileWrite = fs.openSync(cfgPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(fileWrite.fd, byteStr.buffer);
      fs.closeSync(fileWrite);

      let label = (target === 'mllm') ? 'mllm.backend_type' : 'backend_type';
      this.output = `更新 ${label} 成功: ${value}\n====== 新配置 ======\n${newStr}`;
    } catch (e) {
      this.output = `更新 config.json 失败: ${e}`;
    }
  }

  async testAndConnectHdc() {
    if (this.wirelessIp.trim().length === 0) {
      this.output = '请先填写当前手机的无线 HDC 地址，例如 192.168.x.x:端口';
      return;
    }
    this.output = `正在请求远程服务执行 HDC 连接测试: ${this.wirelessIp}...`;
    let httpReq = http.createHttp();
    try {
      // 构造 Python 脚本，在远端执行 HDC 连接测试。
      let pyScript = `import os; targets = os.popen('hdc list targets').read().split(); ` + 
                     `[os.system('hdc kill ' + t) for t in targets if t and t != '${this.wirelessIp}' and '[Empty]' not in t]; ` +
                     `os.system('hdc tconn ${this.wirelessIp}')`;

      let runCmdPayload: RunCmdRequest = {
        cmd: `python -c "${pyScript}"`
      };
      let runCmdHeader: Record<string, string> = {
        'Content-Type': 'application/json'
      };
      let runCmdOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: runCmdHeader,
        extraData: ArkJSON.stringify(runCmdPayload),
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING,
      };
      let resp = await httpReq.request(`${this.hdcServerIp}/api/run_cmd`, runCmdOptions);
      if (resp.responseCode === 200) {
        this.output = `远程连接测试请求成功!\n${resp.result}`;
      } else {
        this.output = `请求失败: HTTP ${resp.responseCode}`;
      }
    } catch(err) {
      let e = err as BusinessError;
      this.output = `HDC 请求出错: ${e.message}\n请确认远端服务 ${this.hdcServerIp}/api/run_cmd 已运行。`;
    } finally {
      httpReq.destroy();
    }
  }

  // ========== Step 1: Check connection, list files ==========
  async checkServer() {
    this.output = `正在连接 ${this.serverIp} ...`;
    // 每个 httpRequest 对应一个 HTTP 请求任务，不复用。
    let httpReq = http.createHttp();
    try {
      let listOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING,
      };
      let resp = await httpReq.request(`${this.serverIp}/api/files`, listOptions);
      if (resp.responseCode !== 200) {
        this.output = `连接失败: HTTP ${resp.responseCode}`;
        return;
      }
      let files: ServerFile[] = ArkJSON.parse(resp.result as string) as ServerFile[];
      this.serverFiles = files.filter((f: ServerFile) => f.name !== 'serve_model.py');
      this.totalBytesAll = 0;

      let listing = '服务器连接成功\n\n文件列表:\n';
      listing += '----------------------------------------\n';
      for (let f of this.serverFiles) {
        this.totalBytesAll += f.size;
        let pad = ' '.repeat(Math.max(1, 28 - f.name.length));
        listing += `  ${f.name}${pad}${this.formatSize(f.size)}\n`;
      }
      listing += '----------------------------------------\n';
      listing += `共 ${this.serverFiles.length} 个文件，总大小: ${this.formatSize(this.totalBytesAll)}\n\n`;
      listing += '点击“下载全部”开始下载';
      this.output = listing;
      this.connected = true;
    } catch (err) {
      let e = err as BusinessError;
      this.output = `连接失败: code=${e.code} ${e.message}\n\n请检查:\n1. 服务器 python serve_model.py 是否运行\n2. 防火墙是否开放端口\n3. 手机网络是否可达服务器`;
      this.connected = false;
    } finally {
      httpReq.destroy();
    }
  }

  // ========== Step 2: Stream-download one file ==========
  private downloadOneFile(file: ServerFile, index: number, fileCount: number,
    completedBytes: number): Promise<number> {
    const url = `${this.serverIp}/${file.name}`;
    const savePath = `${this.modelDir}/${file.name}`;

    // Skip if exists with correct size
    try {
      let st = fs.statSync(savePath);
      if (st.size === file.size) {
        this.output = `[${index + 1}/${fileCount}] ${file.name}\n` +
          `已存在 (${this.formatSize(st.size)})，跳过\n` +
          `总进度: ${this.formatSize(completedBytes + file.size)} / ${this.formatSize(this.totalBytesAll)}`;
        return Promise.resolve(file.size);
      }
    } catch {
      // not exists
    }

    this.output = `[${index + 1}/${fileCount}] 连接: ${file.name}`;
    let self = this;
    let idx = index;
    let completed = completedBytes;

    return new Promise<number>((resolve) => {
      // 每个 httpRequest 对应一个 HTTP 请求任务，不复用。
      let httpReq = http.createHttp();
      let fileHandle: fs.File;
      let failed = false;
      let resolved = false;

      try {
        fileHandle = fs.openSync(savePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY |
        fs.OpenMode.TRUNC);
      } catch {
        self.output = `[${idx + 1}/${fileCount}] 创建文件失败: ${file.name}`;
        httpReq.destroy();
        resolve(-1);
        return;
      }

      // Helper: cleanup and resolve
      let finish = (size: number): void => {
        if (resolved) return;
        resolved = true;
        httpReq.off('dataReceive');
        httpReq.off('dataReceiveProgress');
        httpReq.off('dataEnd');
        try { fs.closeSync(fileHandle); } catch {}
        httpReq.destroy();
        resolve(size);
      };

      // Subscribe: stream data -> write to file
      httpReq.on('dataReceive', (data: ArrayBuffer) => {
        if (!failed) {
          try {
            fs.writeSync(fileHandle.fd, data);
          } catch {
            failed = true;
          }
        }
      });

      // Subscribe: download progress
      httpReq.on('dataReceiveProgress', (data: http.DataReceiveProgressInfo) => {
        if (failed) return;
        let filePct = data.totalSize > 0 ? Math.floor(data.receiveSize * 100 / data.totalSize)
          : 0;
        let overallRecv = completed + data.receiveSize;
        let overallPct = self.totalBytesAll > 0
          ? Math.floor(overallRecv * 100 / self.totalBytesAll) : 0;
        self.output =
          `[${idx + 1}/${fileCount}] ${file.name}\n` +
            `文件: ${self.formatSize(data.receiveSize)} / ${self.formatSize(data.totalSize)} ${filePct}%\n` +
            `总量: ${self.formatSize(overallRecv)} / ${self.formatSize(self.totalBytesAll)} ${overallPct}%`;
      });

      // Subscribe: data receive complete
      httpReq.on('dataEnd', () => {
        if (failed) {
          self.output = `[${idx + 1}/${fileCount}] ${file.name} 写入失败`;
          finish(-1);
        } else {
          let fileSize = 0;
          try {
            fs.closeSync(fileHandle);
            fileSize = fs.statSync(savePath).size;
          } catch {}
          self.output = `[${idx + 1}/${fileCount}] ${file.name} 完成 (${self.formatSize(fileSize)})`;
          if (resolved) return;
          resolved = true;
          httpReq.off('dataReceive');
          httpReq.off('dataReceiveProgress');
          httpReq.off('dataEnd');
          httpReq.destroy();
          resolve(fileSize);
        }
      });

      // Issue stream request
      let streamOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 60000,
        readTimeout: 7200000, // 2 hours for large files
      };
      httpReq.requestInStream(url, streamOptions).then((code: number) => {
        if (code !== 200) {
          failed = true;
          self.output = `[${idx + 1}/${fileCount}] ${file.name} HTTP ${code}`;
          finish(-1);
        }
        // if 200, wait for dataEnd
      }).catch((err: BusinessError) => {
        failed = true;
        self.output = `[${idx + 1}/${fileCount}] ${file.name} 错误: code=${err.code} ${err.message}`;
        finish(-1);
      });
    });
  }

  // ========== Step 3: Download all files ==========
  async downloadAll() {
    if (this.serverFiles.length === 0) {
      this.output = '请先检查服务器连接';
      return;
    }
    this.downloading = true;
    try { fs.mkdirSync(this.modelDir); } catch {}

    let completedBytes = 0;
    let failed: string[] = [];

    for (let i = 0; i < this.serverFiles.length; i++) {
      let size = await this.downloadOneFile(this.serverFiles[i], i, this.serverFiles.length,
        completedBytes);
      if (size < 0) {
        failed.push(this.serverFiles[i].name);
      } else {
        completedBytes += size;
      }
    }

    if (failed.length === 0) {
      this.output = `全部下载完成!\n模型总大小: ${this.formatSize(completedBytes)}\n\n点击“加载大模型”开始使用`;
    } else {
      this.output = `${failed.length} 个失败: ${failed.join(', ')}\n已下载: ${this.formatSize(completedBytes)}\n再次点击可继续，已有文件会跳过。`;
    }
    this.downloading = false;
  }

  private getCloudConfig(): CloudModelConfig {
    let config: CloudModelConfig = {
      plannerBaseUrl: this.cloudPlannerBaseUrl,
      deciderBaseUrl: this.cloudDeciderBaseUrl,
      apiKey: this.cloudApiKey,
      deciderModel: this.cloudDeciderModel
    };
    return config;
  }

  private isCloudConfigReady(): boolean {
    return this.cloudPlannerBaseUrl.trim().length > 0 &&
      this.cloudDeciderBaseUrl.trim().length > 0 &&
      this.cloudApiKey.trim().length > 0;
  }

  async testCloudPlanner() {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return;
    }
    this.cloudThinking = true;
    this.appendCloudLog(`测试 Planner：${this.cloudPlannerBaseUrl}`);
    try {
      let response = await this.cloudClient.chatPlanner('请只回复 ok', this.getCloudConfig());
      this.appendCloudLog(`Planner 测试返回：\n${response}`);
    } catch (err) {
      let e = err as Error;
      this.appendCloudLog('Planner 连接失败：' + e.message);
    } finally {
      this.cloudThinking = false;
    }
  }

  async runCloudPlannerOnce() {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return;
    }
    if (this.cloudUserInput.trim().length === 0 || this.cloudThinking) {
      return;
    }
    this.cloudThinking = true;
    this.appendCloudLog(`手动调用 Planner，任务：${this.cloudUserInput}`);
    try {
      let response = await this.cloudClient.chatPlanner(this.cloudUserInput, this.getCloudConfig());
      this.appendCloudLog(`Planner 手动返回：\n${response}`);
    } catch (err) {
      let e = err as Error;
      this.appendCloudLog('云端 Planner 推理失败：' + e.message);
    } finally {
      this.cloudThinking = false;
    }
  }

  startCloudBackend() {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return;
    }
    this.appendCloudLog('准备切换到云端 Agent 路由，复用 9126...');
    // 云端模式仍复用 PC 侧同一套 TCP 协议；区别是 App 通过 AgentRouterServer 转发到云端模型。
    this.agentRouter.useCloud();
    this.agentRouter.start(9126, this.filesDir);
  }

  private async ensureLocalModelLoaded(): Promise<boolean> {
    // 本地 Agent 启动前自动加载模型，减少用户遗漏“加载大模型”按钮导致的失败。
    if (this.modelLoaded) {
      return true;
    }

    let cfg = this.modelDir + '/config.json';
    if (!this.prepareCustomOpp()) {
      return false;
    }

    this.output = '未检测到已加载模型，正在自动加载大模型...';
    try {
      this.output = await mnnllm.loadModel(cfg);
      this.modelLoaded = this.output === 'ok';
      if (!this.modelLoaded) {
        this.output = `自动加载模型失败: ${this.output}`;
      }
      return this.modelLoaded;
    } catch (err) {
      let e = err as Error;
      this.output = '自动加载模型失败: ' + e.message;
      return false;
    }
  }

  private startLocalBackend(): void {
    // 本地模式下 9126 请求会进入 libentry.so/MNN，本函数只负责切换路由并启动监听。
    this.agentRouter.useLocal();
    this.agentRouter.start(9126, this.filesDir);
  }

  private async ensureLocalAgentReady(): Promise<boolean> {
    if (!await this.ensureLocalModelLoaded()) {
      return false;
    }

    this.agentRouter.useLocal();
    if (!this.agentRouter.running()) {
      this.output = '未检测到本地 PC 控制后端，正在自动启动...';
      this.startLocalBackend();
    }
    return true;
  }

  private ensureCloudAgentBackend(): boolean {
    // 云端任务下发前确保路由已切换到 cloud 且 9126 正在监听。
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return false;
    }

    this.agentRouter.useCloud();
    if (!this.agentRouter.running()) {
      this.appendCloudLog('未检测到云端 PC 控制后端，正在自动启动...');
      this.startCloudBackend();
    }
    return true;
  }

  private async runWorkflowTask(task: WorkflowTask): Promise<void> {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('Workflow 无法启动：请先填写 Planner / Decider 的服务地址和 API Key。');
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, '失败', '云端模型配置不完整');
      return;
    }
    if (this.hdcServerIp.trim().length === 0) {
      this.appendCloudLog('Workflow 无法启动：请先配置 HDC Server。');
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, '失败', 'HDC Server 未配置');
      return;
    }

    this.currentTab = 3;
    this.resetCloudLog('准备执行 Workflow：' + task.title);
    this.appendCloudLog('Workflow 编排将在 App 沙箱内执行；PC 端仅负责 HDC 截图和动作桥接。');
    this.appendCloudLog('HDC Server=' + this.hdcServerIp);
    let runner = new WorkflowRunner(this.filesDir, this.cloudClient, () => this.getCloudConfig(),
      this.hdcServerIp, (msg: string) => { this.appendCloudLog(msg); });
    try {
      let result: WorkflowRunResult = await runner.runTask(task);
      let message = result.message;
      if (result.dailyLogPath.length > 0) {
        message += '，daily-log 已生成';
      }
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, result.status, message);
      this.appendCloudLog('Workflow 运行摘要：' + result.runDir);
    } catch (err) {
      let e = err as Error;
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, 'failed', e.message);
      this.appendCloudLog('Workflow 执行异常：' + e.message);
      AgentExecutionController.finishExecution('Workflow failed');
    }
  }

  @Builder AssistantPage() {
    Scroll() {
      Column() {
        AppHeader({ title: '本地推理', subtitle: this.assistantSettingsOpen ? '模型与网络设置' : '端侧模型控制台' })
        if (this.assistantSettingsOpen) {
          this.NetworkSettingsPage()
        } else {
        Scroll() {
          Text(this.output).fontSize(13).fontFamily('monospace').fontColor('#333333').width('100%').padding(16)
        }.constraintSize({ minHeight: 110, maxHeight: 190 }).width('92%').backgroundColor('#EEF4FF').borderRadius(18).margin({ top: 16 }).border({ width: 1, color: '#D9E5FF' })

        if (this.debugImagePath !== '') {
          Row() {
            Text('Debug 截图预览').fontSize(14).fontColor('#555555').layoutWeight(1)
            Image(this.debugImagePath).width(100).height(150).objectFit(ImageFit.Contain).backgroundColor(Color.Black).borderRadius(12).onClick(() => { this.debugImagePath = ''; })
          }.width('92%').padding(14).backgroundColor(Color.White).borderRadius(18).margin({ top: 14 })
        }

        Scroll() {
          Text(this.chatHistory.length > 0 ? this.chatHistory : '模型对话内容会显示在这里。')
            .fontSize(15)
            .fontColor(this.chatHistory.length > 0 ? '#232936' : '#9AA0AA')
            .width('100%')
            .padding(18)
            .lineHeight(22)
        }.constraintSize({ minHeight: 190, maxHeight: 320 }).width('92%').backgroundColor(Color.White).borderRadius(20).margin({ top: 16 }).shadow({ radius: 16, color: '#12000000', offsetX: 0, offsetY: 8 })

        Row() {
          TextInput({ placeholder: '输入消息或 Agent 任务...', text: this.userInput })
            .onChange((val: string) => { this.userInput = val; })
            .layoutWeight(1)
            .height(48)
            .backgroundColor('#F2F5FC')
            .borderRadius(24)
            .padding({ left: 18, right: 18 })
          Button('发送')
            .height(48)
            .width(86)
            .backgroundColor(this.isThinking ? '#A9B7E9' : '#5B68FF')
            .borderRadius(24)
            .margin({ left: 10 })
            .onClick(async () => {
              if (!this.modelLoaded || this.userInput.length === 0 || this.isThinking) return;
              let msg = this.userInput;
              this.userInput = '';
              this.chatHistory += `\nUser: ${msg}\nAssistant: 思考中...`;
              this.isThinking = true;
              try {
                let reply = await mnnllm.chat(msg);
                this.chatHistory = this.chatHistory.replace('Assistant: 思考中...', `Assistant: ${reply}\n`);
              } catch(err) {
                let e = err as Error;
                this.chatHistory = this.chatHistory.replace('Assistant: 思考中...', `Assistant: [错误] ${e.message}\n`);
              } finally {
                this.isThinking = false;
              }
            })
        }.width('92%').margin({ top: 16 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Button('加载大模型')
            .onClick(async () => {
              this.output = '加载中，请稍候...';
              await this.ensureLocalModelLoaded();
            })
            .enabled(!this.downloading)
            .height(42)
            .width('30%')
            .backgroundColor(this.modelLoaded ? '#E2E6EF' : '#38BE8B')
            .fontColor(this.modelLoaded ? '#8B93A2' : '#FFFFFF')
            .borderRadius(12)
          Button('单轮推理')
            .onClick(async () => {
              if (!this.modelLoaded) { this.output = '请先加载模型'; return; }
              this.output = '推理中...';
              try { this.output = await mnnllm.generate('你好'); } catch(err) { let e = err as Error; this.output = '推理错误: ' + e.message; }
            })
            .height(42)
            .width('30%')
            .backgroundColor('#4B8BFF')
            .borderRadius(12)
          Button('重置会话')
            .onClick(() => { this.output = mnnllm.reset(); this.chatHistory = ''; })
            .height(42)
            .width('30%')
            .backgroundColor('#FF7043')
            .borderRadius(12)
        }.width('92%').margin({ top: 16 })

        Button('开始智能体执行（输入框为任务）')
          .width('92%')
          .height(52)
          .backgroundColor('#765BFF')
          .borderRadius(16)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 16 })
          .onClick(async () => {
            if (this.userInput.length === 0) { this.output = '请在上方文本框输入任务目标，例如：去淘宝买手机'; return; }
            if (!await this.ensureLocalAgentReady()) { return; }
            this.agentRouter.submitLocalTask(this.userInput);
            AgentExecutionController.beginExecution('等待 PC 控制本地任务...');
            this.output = `====== 等待 PC 截图 ======\n当前任务已设定为: ${this.userInput}\nPC 脚本检测到任务后将自动开始。`;
          })

        Row() {
          Button('启动 PC 控制后端 (HDC)')
            .height(48)
            .backgroundColor('#607D8B')
            .borderRadius(14)
            .layoutWeight(1)
            .onClick(async () => {
              if (!await this.ensureLocalModelLoaded()) { return; }
              this.startLocalBackend();
            })
          Row() {
            Checkbox({ name: 'autoConfirm', group: 'settings' })
              .select(this.autoConfirm)
              .selectedColor('#5B68FF')
              .onChange((value: boolean) => { this.autoConfirm = value; })
            Text('自动同意').fontSize(14).fontColor('#333333')
          }.height(48).padding({ left: 12, right: 12 }).backgroundColor(Color.White).borderRadius(14).margin({ left: 10 })
        }.width('92%').margin({ top: 14 })

        Button('网络设置')
          .width('92%')
          .height(46)
          .backgroundColor(Color.White)
          .fontColor('#4F68FF')
          .borderRadius(14)
          .margin({ top: 14 })
          .border({ width: 1, color: '#DDE5FF' })
          .onClick(() => { this.assistantSettingsOpen = true; })
        Blank().height(110)
        }
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }

  @Builder NetworkSettingsPage() {
    Column() {
      Row() {
        Text('<')
          .fontSize(18)
          .fontColor('#4F68FF')
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor('#EEF3FF')
          .borderRadius(17)
        Column() {
          Text('网络与设置')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
          Text('配置模型下载、运行参数和调试入口')
            .fontSize(13)
            .fontColor('#7B8290')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
        .layoutWeight(1)
      }
      .width('92%')
      .margin({ top: 16 })
      .onClick(() => { this.assistantSettingsOpen = false; })

      Scroll() {
        Text(this.output)
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor('#333333')
          .width('100%')
          .padding(16)
      }
      .constraintSize({ minHeight: 100, maxHeight: 170 })
      .width('92%')
      .backgroundColor('#EEF4FF')
      .borderRadius(18)
      .margin({ top: 14 })
      .border({ width: 1, color: '#D9E5FF' })

      Column() {
        Text('服务地址')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#11182F')
          .width('100%')
          .margin({ bottom: 12 })
        Text('模型下载服务')
          .fontSize(13)
          .fontColor('#6F7684')
          .width('100%')
        TextInput({ placeholder: 'http://服务器IP:端口，例如 http://166.111.53.96:9123', text: this.serverIp })
          .height(42)
          .width('100%')
          .fontSize(13)
          .backgroundColor('#F2F5FC')
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6, bottom: 12 })
          .onChange((val: string) => {
            this.serverIp = val;
            this.connected = false;
          })
        Text('HDC Server')
          .fontSize(13)
          .fontColor('#6F7684')
          .width('100%')
        TextInput({ placeholder: 'http://服务器IP:端口，例如 http://166.111.53.96:9124', text: this.hdcServerIp })
          .height(42)
          .width('100%')
          .fontSize(13)
          .backgroundColor('#F2F5FC')
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6, bottom: 12 })
          .onChange((val: string) => { this.hdcServerIp = val; })
        Text('无线 HDC 目标')
          .fontSize(13)
          .fontColor('#6F7684')
          .width('100%')
        Row() {
          TextInput({ placeholder: '手机无线调试地址，例如 192.168.137.195:33117', text: this.wirelessIp })
            .height(42)
            .layoutWeight(1)
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((val: string) => { this.wirelessIp = val; })
          Button('连接测试')
            .height(42)
            .width(92)
            .fontSize(13)
            .backgroundColor('#765BFF')
            .borderRadius(12)
            .margin({ left: 10 })
            .onClick(() => { this.testAndConnectHdc(); })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('92%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ top: 16 })

      Column() {
        Text('模型文件')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#11182F')
          .width('100%')
          .margin({ bottom: 12 })
        Row() {
          Button('检查连接')
            .onClick(() => { this.checkServer(); })
            .enabled(!this.downloading)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#38BE8B')
            .borderRadius(12)
          Button('下载全部')
            .onClick(() => { this.downloadAll(); })
            .enabled(!this.downloading && this.connected)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#FF7043')
            .borderRadius(12)
            .margin({ left: 10 })
          Button('删除模型')
            .onClick(() => { this.deleteModelFiles(); })
            .enabled(!this.downloading)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#F44336')
            .borderRadius(12)
            .margin({ left: 10 })
        }.width('100%')
      }
      .width('92%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ top: 16 })

      Column() {
        Text('运行参数')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#11182F')
          .width('100%')
          .margin({ bottom: 12 })
        Row() {
          Text('线程数')
            .fontSize(14)
            .fontColor('#666666')
            .width(58)
          TextInput({ text: this.threadNumInput })
            .type(InputType.Number)
            .width(76)
            .height(40)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .onChange((val: string) => { this.threadNumInput = val; })
          Button('修改 Config')
            .onClick(() => { this.updateConfigThreadNum(); })
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#4B8BFF')
            .borderRadius(12)
            .margin({ left: 10 })
          Button('查看 Config')
            .onClick(() => { this.showConfigJson(); })
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#607D8B')
            .borderRadius(12)
            .margin({ left: 10 })
        }.width('100%')
      }
      .width('92%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ top: 14 })

      Row() {
        Button('Op Precision Test')
          .height(42)
          .layoutWeight(1)
          .backgroundColor('#FF9800')
          .borderRadius(12)
          .onClick(() => { router.pushUrl({ url: 'pages/OpTest' }) })
        Button('Runtime Logs')
          .height(42)
          .layoutWeight(1)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { router.pushUrl({ url: 'pages/LogView' }) })
      }
      .width('92%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ top: 14 })

      Button('返回助手')
        .width('92%')
        .height(46)
        .fontColor('#4F68FF')
        .backgroundColor('#EEF3FF')
        .borderRadius(14)
        .margin({ top: 14 })
        .onClick(() => { this.assistantSettingsOpen = false; })
      Blank().height(110)
    }.width('100%')
  }

  @Builder CloudAssistantPage() {
    Scroll() {
      Column() {
        AppHeader({ title: '云助手', subtitle: 'vLLM 云端推理控制台' })

        Scroll() {
          Text(this.cloudOutput)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor('#333333')
            .width('100%')
            .padding(16)
        }
        .constraintSize({ minHeight: 110, maxHeight: 190 })
        .width('92%')
        .backgroundColor('#EEF4FF')
        .borderRadius(18)
        .margin({ top: 16 })
        .border({ width: 1, color: '#D9E5FF' })

        if (this.cloudDebugImagePath !== '') {
          Row() {
            Text('Debug 截图预览')
              .fontSize(14)
              .fontColor('#555555')
              .layoutWeight(1)
            Image(this.cloudDebugImagePath)
              .width(100)
              .height(150)
              .objectFit(ImageFit.Contain)
              .backgroundColor(Color.Black)
              .borderRadius(12)
              .onClick(() => { this.cloudDebugImagePath = ''; })
          }
          .width('92%')
          .padding(14)
          .backgroundColor(Color.White)
          .borderRadius(18)
          .margin({ top: 14 })
        }

        Column() {
          Text('云端模型')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .width('100%')
            .margin({ bottom: 12 })
          Text('Planner 服务')
            .fontSize(13)
            .fontColor('#6F7684')
            .width('100%')
          TextInput({ placeholder: 'http://服务器IP:端口，例如 http://166.111.53.96:7003', text: this.cloudPlannerBaseUrl })
            .height(42)
            .width('100%')
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6, bottom: 10 })
            .onChange((val: string) => { this.cloudPlannerBaseUrl = val; })
          Text('Decider 服务')
            .fontSize(13)
            .fontColor('#6F7684')
            .width('100%')
          TextInput({ placeholder: 'http://服务器IP:端口，例如 http://166.111.53.96:7003', text: this.cloudDeciderBaseUrl })
            .height(42)
            .width('100%')
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6, bottom: 10 })
            .onChange((val: string) => { this.cloudDeciderBaseUrl = val; })
          TextInput({ placeholder: 'API Key', text: this.cloudApiKey })
            .height(42)
            .width('100%')
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((val: string) => { this.cloudApiKey = val; })
          Text('Decider Model')
            .fontSize(13)
            .fontColor('#6F7684')
            .width('100%')
            .margin({ top: 10 })
          TextInput({ placeholder: '留空则不传 model', text: this.cloudDeciderModel })
            .height(42)
            .width('100%')
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((val: string) => { this.cloudDeciderModel = val; })
        }
        .width('92%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .margin({ top: 16 })

        Column() {
          Text('HDC 控制')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .width('100%')
            .margin({ bottom: 12 })
          TextInput({ placeholder: 'HDC Server，例如 http://192.168.137.1:9124', text: this.hdcServerIp })
            .height(42)
            .width('100%')
            .fontSize(13)
            .backgroundColor('#F2F5FC')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ bottom: 10 })
            .onChange((val: string) => { this.hdcServerIp = val; })
          Row() {
            TextInput({ placeholder: '无线 HDC 地址，例如 192.168.137.195:33117', text: this.wirelessIp })
              .height(42)
              .layoutWeight(1)
              .fontSize(13)
              .backgroundColor('#F2F5FC')
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((val: string) => { this.wirelessIp = val; })
            Button('连接测试')
              .height(42)
              .width(92)
              .fontSize(13)
              .backgroundColor('#765BFF')
              .borderRadius(12)
              .margin({ left: 10 })
              .onClick(async () => {
                this.appendCloudLog(`请求 HDC 连接测试：server=${this.hdcServerIp}, target=${this.wirelessIp}`);
                await this.testAndConnectHdc();
                this.appendCloudLog(this.output);
              })
          }.width('100%')
        }
        .width('92%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .margin({ top: 14 })

        Row() {
          TextInput({ placeholder: '输入云端 Agent 任务...', text: this.cloudUserInput })
            .onChange((val: string) => { this.cloudUserInput = val; })
            .layoutWeight(1)
            .height(48)
            .backgroundColor('#F2F5FC')
            .borderRadius(24)
            .padding({ left: 18, right: 18 })
          Button('Planner')
            .height(48)
            .width(92)
            .fontSize(13)
            .backgroundColor(this.cloudThinking ? '#A9B7E9' : '#5B68FF')
            .borderRadius(24)
            .margin({ left: 10 })
            .onClick(() => { this.runCloudPlannerOnce(); })
        }.width('92%').margin({ top: 16 })

        Button('开始云端智能体执行（输入框为任务）')
          .width('92%')
          .height(52)
          .backgroundColor('#765BFF')
          .borderRadius(16)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 16 })
          .onClick(() => {
            if (this.cloudUserInput.trim().length === 0) {
              this.appendCloudLog('请先输入云端 Agent 任务。');
              return;
            }
            if (!this.ensureCloudAgentBackend()) {
              return;
            }
            this.agentRouter.submitCloudTask(this.cloudUserInput);
            AgentExecutionController.beginExecution('等待 PC 控制云端任务...');
            this.resetCloudLog(`任务已下发：${this.cloudUserInput}`);
            this.appendCloudLog('等待 PC 侧 harmony_agent.py 轮询 9126。若没有后续 [Cloud Poll]，说明 PC 没连到 App 后端。');
            this.appendCloudLog(`Planner=${this.cloudPlannerBaseUrl}, Decider=${this.cloudDeciderBaseUrl}`);
          })

        Row() {
          Button('启动云端 PC 控制后端')
            .height(48)
            .layoutWeight(1)
            .backgroundColor('#607D8B')
            .borderRadius(14)
            .onClick(() => { this.startCloudBackend(); })
          Row() {
            Checkbox({ name: 'cloudAutoConfirm', group: 'cloudSettings' })
              .select(this.cloudAutoConfirm)
              .selectedColor('#5B68FF')
              .onChange((value: boolean) => { this.cloudAutoConfirm = value; })
            Text('自动同意')
              .fontSize(14)
              .fontColor('#333333')
          }
          .height(48)
          .padding({ left: 12, right: 12 })
          .backgroundColor(Color.White)
          .borderRadius(14)
          .margin({ left: 10 })
        }.width('92%').margin({ top: 14 })

        Row() {
          Button('测试 Planner')
            .height(42)
            .layoutWeight(1)
            .fontSize(11)
            .backgroundColor('#38BE8B')
            .borderRadius(12)
            .onClick(() => { this.testCloudPlanner(); })
          Button('Runtime Logs')
            .height(42)
            .layoutWeight(1)
            .fontSize(11)
            .backgroundColor('#607D8B')
            .borderRadius(12)
            .margin({ left: 10 })
            .onClick(() => { router.pushUrl({ url: 'pages/LogView' }) })
          Button('删除截图')
            .height(42)
            .layoutWeight(1)
            .fontSize(11)
            .backgroundColor('#FF6B4A')
            .borderRadius(12)
            .margin({ left: 10 })
            .onClick(() => { this.clearScreenshots(); })
        }
        .width('92%')
        .margin({ top: 14 })

        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }

  @Builder TabItem(icon: string, label: string, index: number) {
    Column() {
      Text(icon)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentTab === index ? Color.White : '#747B87')
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.currentTab === index ? '#4F68FF' : '#00FFFFFF')
        .borderRadius(16)
      Text(label)
        .fontSize(13)
        .fontColor(this.currentTab === index ? '#4F68FF' : '#747B87')
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Regular)
        .margin({ top: 2 })
        .maxLines(1)
    }.width(72).height(58).justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() { HomePage() }.tabBar(this.TabItem('H', '首页', 0))
      TabContent() { CollectionPage({ collectionModule: $collectionModule }) }.tabBar(this.TabItem('C', '采集', 1))
      TabContent() { this.AssistantPage() }.tabBar(this.TabItem('A', '助手', 2))
      TabContent() { this.CloudAssistantPage() }.tabBar(this.TabItem('V', '云端', 3))
      TabContent() { TaskPage({ taskScene: $taskScene, onRunWorkflow: async (task: WorkflowTask) => { await this.runWorkflowTask(task); }, onOpenCloudLog: () => { this.currentTab = 3; } }) }.tabBar(this.TabItem('T', '任务', 4))
    }
    .onChange((index: number) => { this.currentTab = index; })
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8FF')
  }
}
