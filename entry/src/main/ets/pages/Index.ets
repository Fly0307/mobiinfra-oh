import entry from 'libentry.so';
import { router } from '@kit.ArkUI';


import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { JSON as ArkJSON, util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import mnnllm from 'libentry.so';
import { LlmServer } from '../utils/LlmServer';
import { promptAction } from '@kit.ArkUI';

interface ServerFile {
  name: string;
  size: number;
}

interface RunCmdRequest {
  cmd: string;
}

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

PersistentStorage.persistProp('wirelessIp', '101.5.155.98:35729');
PersistentStorage.persistProp('serverIp', 'http://166.111.53.96:9123');
PersistentStorage.persistProp('hdcServerIp', 'http://166.111.53.96:9124');

@Entry
@Component
struct Index {
  @State output: string = '请先检查服务器连接';
  @State chatHistory: string = '';
  @State userInput: string = '';
  @State downloading: boolean = false;
  @State modelLoaded: boolean = false;
  @State connected: boolean = false;
  @State autoConfirm: boolean = false;
  @State debugImagePath: string = '';
  @State selectedModelVariant: string = '';
  @State customOppReady: boolean = false;
  @State threadNumInput: string = '4';
  @State backendTypeInput: string = 'cpu';
  @State mllmBackendTypeInput: string = 'cpu';
  @State currentTab: number = 0;
  @State collectionModule: number = 1;
  @State taskScene: number = 0;
  @StorageLink('serverIp') serverIp: string = 'http://166.111.53.96:9123';
  @StorageLink('hdcServerIp') hdcServerIp: string = 'http://166.111.53.96:9124';
  @StorageLink('wirelessIp') wirelessIp: string = '101.5.155.98:35729';
  @State isThinking: boolean = false;
  @State buttonScale: number = 1.0;

  private filesDir: string = '';
  private modelDir: string = '';
  private serverFiles: ServerFile[] = [];
  private totalBytesAll: number = 0;
  
  // PC 控制服务端单例。
  private llmServer: LlmServer = new LlmServer();

  aboutToAppear() {
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
          try { fs.unlinkSync(`${this.filesDir}/${f}`); } catch {}
          count++;
        }
      }
      this.output = `清理成功，删除了 ${count} 张缓存截图。`;
      this.debugImagePath = '';
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
        this.output = '模型文件夹不存在，无需删除。';
        return;
      }
      let files = fs.listFileSync(this.modelDir);
      let count = 0;
      for (let f of files) {
        fs.unlinkSync(`${this.modelDir}/${f}`);
        count++;
      }
      this.modelLoaded = false;
      this.output = `成功删除了 ${count} 个模型文件，\n现在可以重新下载了。`;
    } catch (e) {
      this.output = `删除模型文件失败: ${e}`;
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
  // ========== Digital Home UI ==========
  @Builder AppHeader(title: string, subtitle: string = '') {
    Row() {
      Row() {
        Stack() {
          Text('H')
            .fontSize(21)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(50)
        .height(50)
        .backgroundColor('#5968FF')
        .borderRadius(15)
        .shadow({ radius: 12, color: '#365968FF', offsetX: 0, offsetY: 5 })

        Column() {
          Text(title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (subtitle.length > 0) {
            Text(subtitle)
              .fontSize(14)
              .fontColor('#717684')
              .margin({ top: 3 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .layoutWeight(1)

      Row() {
        Text('盾').fontSize(12).fontColor('#8066FF').width(24).height(24).textAlign(TextAlign.Center).borderRadius(12).backgroundColor('#F0ECFF')
        Text('隐私守护中').fontSize(13).fontColor('#6B6F7C').margin({ left: 5, right: 5 }).maxLines(1)
        Text('>').fontSize(16).fontColor('#8B909A')
      }
      .width(118)
    }
    .width('100%')
    .padding({ left: 22, right: 18, top: 24, bottom: 10 })
  }

  @Builder FeaturePill(icon: string, title: string, desc: string) {
    Row() {
      Text(icon)
        .fontSize(13)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor('#6A67FF')
        .borderRadius(14)
      Column() {
        Text(title).fontSize(14).fontColor('#172033').fontWeight(FontWeight.Medium).maxLines(1)
        Text(desc).fontSize(11).fontColor('#6F7684').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 8 })
    }
    .width('48%')
    .height(54)
    .padding({ left: 10, right: 8 })
    .backgroundColor('#F8FBFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E8EEFA' })
  }

  @Builder LifestyleItem(icon: string, title: string, desc: string, color: string) {
    Column() {
      Text(icon).fontSize(13).fontColor(color).fontWeight(FontWeight.Bold).height(18).textAlign(TextAlign.Center).maxLines(1)
      Column() {
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(1)
        Text(desc).fontSize(11).fontColor('#818795').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
  }

  @Builder RecommendCard(image: Resource, tag: string, title: string, desc: string, meta: string, color: string) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(image).width('100%').height(116).objectFit(ImageFit.Cover)
        Text(tag)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(color)
          .borderRadius(8)
          .margin({ left: 10, top: 10 })
      }.width('100%').height(116)
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(desc)
          .fontSize(12)
          .fontColor('#787F8E')
          .width('100%')
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(meta).fontSize(12).fontColor('#7C8494').layoutWeight(1).maxLines(1)
          Text('>').fontSize(18).fontColor(Color.White).textAlign(TextAlign.Center).width(30).height(30).backgroundColor(color).borderRadius(15)
        }.width('100%').margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 14 })
    }
    .alignItems(HorizontalAlign.Start)
    .width(158)
    .height(234)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .clip(true)
    .shadow({ radius: 18, color: '#16000000', offsetX: 0, offsetY: 8 })
  }

  @Builder HomePage() {
    Scroll() {
      Column() {
        this.AppHeader('数据归家')

        Column() {
          Image($r('app.media.digital_avatar'))
            .width('74%')
            .height(245)
            .objectFit(ImageFit.Contain)
            .margin({ top: 6 })

          Row() {
            this.FeaturePill('I', '理解你', '更懂你的偏好')
            Blank().layoutWeight(1)
            this.FeaturePill('P', '守护你', '隐私安全可靠')
          }.width('92%').margin({ top: 8 })

          Row() {
            this.FeaturePill('L', '陪伴你', '服务你的生活')
            Blank().layoutWeight(1)
            this.FeaturePill('G', '成就你', '助力你的成长')
          }.width('92%').margin({ top: 8 })

          Row() {
            Row().width(8).height(8).backgroundColor('#7669FF').borderRadius(4)
            Text('你的数字分身已更新').fontSize(16).fontColor('#1B2030').margin({ left: 8 }).layoutWeight(1).maxLines(1)
            Text('今天 08:30 >').fontSize(13).fontColor('#7B8190').margin({ left: 10 }).maxLines(1)
          }
          .width('82%')
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor(Color.White)
          .borderRadius(21)
          .margin({ top: 12, bottom: 16 })
        }
        .width('100%')
        .backgroundColor('#EDF5FF')

        Row() {
          Text('画像完整度').fontSize(15).fontColor('#272C38').width(82)
          Progress({ value: 86, total: 100, type: ProgressType.Linear })
            .layoutWeight(1)
            .height(6)
            .color('#8066FF')
            .backgroundColor('#E6E8F3')
            .margin({ left: 12, right: 14 })
          Text('86%').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#9D6BFF').width(62).textAlign(TextAlign.End)
          Text('>').fontSize(20).fontColor('#7A808C').margin({ left: 8 })
        }
        .width('92%')
        .height(70)
        .padding({ left: 18, right: 18 })
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 16 })

        Row() {
          this.LifestyleItem('Eat', '吃', '清淡轻食', '#39C2A2')
          Divider().vertical(true).height(34).color('#E5E7EF')
          this.LifestyleItem('Wear', '穿', '简约舒适', '#7669FF')
          Divider().vertical(true).height(34).color('#E5E7EF')
          this.LifestyleItem('Live', '住', '整洁有序', '#FF963D')
          Divider().vertical(true).height(34).color('#E5E7EF')
          this.LifestyleItem('Go', '行', '地铁通勤', '#4B9BFF')
        }
        .width('92%')
        .height(82)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .padding({ left: 12, right: 12 })
        .margin({ top: 14 })

        Row() {
          Text('为你推荐').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1)
          Text('换一批').fontSize(14).fontColor('#858B98')
        }.width('92%').margin({ top: 24, bottom: 14 })

        Scroll() {
          Row() {
            this.RecommendCard($r('app.media.rec_food'), '美食推荐', '健康轻食餐厅', '连续推荐 3 家优质餐厅', '1.2km', '#39C2A2')
            Blank().width(14)
            this.RecommendCard($r('app.media.rec_sport'), '健康提醒', '晚间运动提醒', '建议 20:30 开始运动', '20:30', '#8066FF')
            Blank().width(14)
            this.RecommendCard($r('app.media.rec_travel'), '出行建议', '周末出行建议', '2 条适合你的周末路线', '约 120km', '#4B9BFF')
          }
          .padding({ left: 18, right: 18, bottom: 6 })
        }
        .width('100%')
        .height(250)
        .scrollable(ScrollDirection.Horizontal)

        Blank().height(88)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }

  private getCollectionTitle(): string {
    if (this.collectionModule === 0) {
      return '最近聊天';
    }
    if (this.collectionModule === 2) {
      return '最近通知';
    }
    if (this.collectionModule === 3) {
      return '娱乐记录';
    }
    return '最近订单';
  }

  private getCollectionCount(): string {
    if (this.collectionModule === 0) {
      return '12 条';
    }
    if (this.collectionModule === 2) {
      return '36 条';
    }
    if (this.collectionModule === 3) {
      return '8 条';
    }
    return '24 条';
  }

  private getCollectionSyncTime(): string {
    if (this.collectionModule === 0) {
      return '3 分钟前';
    }
    if (this.collectionModule === 2) {
      return '刚刚';
    }
    if (this.collectionModule === 3) {
      return '昨天 22:10';
    }
    return '10 分钟前';
  }

  @Builder CollectTab(label: string, icon: string, index: number) {
    Row() {
      Text(icon).fontSize(11).fontColor(this.collectionModule === index ? Color.White : '#596071').fontWeight(FontWeight.Bold)
      Text(label).fontSize(14).fontWeight(this.collectionModule === index ? FontWeight.Bold : FontWeight.Regular).fontColor(this.collectionModule === index ? Color.White : '#596071').margin({ left: 5 }).maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height(48)
    .backgroundColor(this.collectionModule === index ? '#8066FF' : '#00FFFFFF')
    .borderRadius(24)
    .onClick(() => {
      this.collectionModule = index;
    })
  }

  @Builder OrderRow(image: Resource, title: string, source: string, time: string, price: string) {
    Row() {
      Image(image).width(58).height(58).objectFit(ImageFit.Cover).borderRadius(11)
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(source).fontSize(12).fontColor('#7C8494').margin({ top: 5 }).maxLines(1)
        Text(time).fontSize(12).fontColor('#7C8494').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12, right: 8 })
      Column() {
        Text(price).fontSize(13).fontColor('#161B28').maxLines(1)
        Text('已完成').fontSize(12).fontColor('#35C487').margin({ top: 6 }).maxLines(1)
      }.alignItems(HorizontalAlign.End)
      Text('>').fontSize(18).fontColor('#9AA0AA').margin({ left: 7 })
    }.width('100%').padding({ top: 10, bottom: 10 })
  }

  @Builder CollectionRows() {
    if (this.collectionModule === 0) {
      this.OrderRow($r('app.media.rec_food'), '和妈妈的晚餐计划', '微信聊天', '今天 08:12', '12 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '周末出游讨论', '家庭群', '昨天 21:45', '8 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_sport'), '运动打卡提醒', '好友聊天', '昨天 19:30', '5 条')
    } else if (this.collectionModule === 2) {
      this.OrderRow($r('app.media.rec_travel'), '航班价格提醒', '系统通知', '今天 09:05', '已收录')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '外卖配送更新', '生活服务', '今天 08:40', '已收录')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_sport'), '健康步数摘要', '运动健康', '昨天 22:00', '已收录')
    } else if (this.collectionModule === 3) {
      this.OrderRow($r('app.media.rec_sport'), '晚间瑜伽课程', '视频记录', '昨天 20:30', '42 分钟')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '露营路线收藏', '短视频收藏', '周六 10:12', '3 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '轻食探店视频', '兴趣推荐', '周五 18:20', '6 条')
    } else {
      this.OrderRow($r('app.media.rec_sport'), '无线耳机 Pro 2', '京东商城', '05-20 10:23', '¥ 1299.00')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '馥芮白咖啡 12瓶装', '天猫超市', '05-19 16:45', '¥ 59.90')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '纯棉基础T恤', '优衣库官方旗舰店', '05-18 09:12', '¥ 99.00')
    }
  }

  @Builder PreferenceLine(color: string, name: string, value: string, widthValue: string) {
    Row() {
      Row().width(7).height(7).backgroundColor(color).borderRadius(4)
      Text(name).fontSize(12).fontColor('#4C5260').width(66).margin({ left: 6 }).maxLines(1)
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(4).backgroundColor('#F0F1F6').borderRadius(3)
        Row().width(widthValue).height(4).backgroundColor(color).borderRadius(3)
      }.layoutWeight(1).height(5)
      Text(value).fontSize(12).fontColor('#7A808C').width(36).textAlign(TextAlign.End)
    }.width('100%').margin({ bottom: 12 })
  }

  @Builder CollectionPage() {
    Scroll() {
      Column() {
        this.AppHeader('数据采集', '按模块查看已采集内容')

        Row() {
          this.CollectTab('聊天', 'C', 0)
          this.CollectTab('购物', 'B', 1)
          this.CollectTab('通知', 'N', 2)
          this.CollectTab('娱乐', 'V', 3)
        }
        .width('86%')
        .height(56)
        .padding({ left: 4, right: 4 })
        .backgroundColor('#EFFFFFFF')
        .borderRadius(28)
        .margin({ top: 24 })
        .shadow({ radius: 12, color: '#0C000000', offsetX: 0, offsetY: 6 })

        Row() {
          Column() {
            Text('今日新增').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionCount()).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#8066FF').margin({ top: 3 }).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Divider().vertical(true).height(44).color('#E7E9F0')
          Column() {
            Text('最近同步').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionSyncTime()).fontSize(16).fontColor('#151A28').margin({ top: 5 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding({ left: 18, right: 10 })
          Text('同步')
            .fontSize(12)
            .fontColor('#8066FF')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor('#F0ECFF')
            .borderRadius(22)
            .onClick(() => {
              promptAction.showToast({ message: '已刷新采集数据', duration: 1200 });
            })
        }
        .width('86%')
        .height(82)
        .padding({ left: 22, right: 16 })
        .backgroundColor('#F8FAFE')
        .borderRadius(16)
        .margin({ top: 22 })

        Column() {
          Row() {
            Text(this.getCollectionTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1)
            Text('查看全部 >').fontSize(13).fontColor('#7F8592')
          }.width('100%').margin({ bottom: 8 })
          this.CollectionRows()
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: 22 })

        Column() {
          Row() {
            Text('消费偏好').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1)
            Text('近30天').fontSize(13).fontColor('#7F8592')
          }.width('100%')
          Row() {
            Stack() {
              Progress({ value: 72, total: 100, type: ProgressType.Ring }).width(112).height(112).color('#8066FF').backgroundColor('#EDF0F8')
              Column() {
                Text('主要品类').fontSize(12).fontColor('#4C5260')
                Text('分布').fontSize(12).fontColor('#4C5260').margin({ top: 3 })
              }
            }.width(120).height(132)
            Column() {
              this.PreferenceLine('#8066FF', '数码家电', '42%', '78%')
              this.PreferenceLine('#5B8DFF', '食品饮料', '28%', '60%')
              this.PreferenceLine('#FFB14B', '服饰鞋包', '18%', '42%')
              this.PreferenceLine('#42C995', '美妆个护', '12%', '28%')
            }.layoutWeight(1).margin({ left: 12 })
          }.width('100%').margin({ top: 16 })
          Row() {
            Text('AI').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#8066FF')
            Text('你在数码和食品品类的消费较多').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#6D62F5').layoutWeight(1).margin({ left: 10 })
            Text('>').fontSize(18).fontColor('#9AA0AA')
          }.width('100%').height(46).padding({ left: 16, right: 12 }).backgroundColor('#F2EEFF').borderRadius(12)
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: 22 })

        Column() {
          Text('+  新增采集源').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('连接更多平台，采集更多数据').fontSize(12).fontColor('#E8E2FF').margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .width('86%')
        .height(72)
        .backgroundColor('#725CFF')
        .borderRadius(18)
        .margin({ top: 22 })
        .onClick(() => { promptAction.showToast({ message: '新增采集源功能即将接入', duration: 1500 }); })
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }

  @Builder TaskCard(icon: string, iconColor: string, title: string, status: string, nextRun: string, source: string, enabled: boolean) {
    Column() {
      Row() {
        Text(icon).fontSize(17).fontColor(iconColor).fontWeight(FontWeight.Bold).width(58).height(58).textAlign(TextAlign.Center).backgroundColor(enabled ? '#F1F5FF' : '#F4F5F8').borderRadius(16)
        Column() {
          Row() {
            Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row().width(7).height(7).backgroundColor(enabled ? '#39BFA3' : '#A8AFBC').borderRadius(4).margin({ left: 8, right: 5 })
            Text(status).fontSize(12).fontColor(enabled ? '#66707E' : '#8E95A3').maxLines(1)
          }.width('100%')
          Text('下次运行：' + nextRun).fontSize(12).fontColor('#7B8290').margin({ top: 8 }).maxLines(1)
          Text('来源模块：' + source).fontSize(12).fontColor('#7B8290').margin({ top: 4 }).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14, right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: enabled }).selectedColor('#6B5CFF').width(44).height(26)
      }.width('100%')
    }
    .width('86%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .shadow({ radius: 12, color: '#10000000', offsetX: 0, offsetY: 6 })
    .margin({ bottom: 18 })
    .onClick(() => { promptAction.showToast({ message: title + ' 详情暂未接入', duration: 1500 }); })
  }

  @Builder TaskSceneTab(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.taskScene === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.taskScene === index ? Color.White : '#6D7481')
      .height(42)
      .padding({ left: 18, right: 18 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.taskScene === index ? '#765BFF' : Color.White)
      .borderRadius(21)
      .onClick(() => {
        this.taskScene = index;
      })
  }

  @Builder TaskSceneList() {
    if (this.taskScene === 0) {
      this.TaskCard('Buy', '#4B8BFF', '晚间购物订单同步', '运行中', '今天 20:30', '电商订单', true)
      this.TaskCard('Cart', '#8066FF', '优惠价格监控', '运行中', '每天 12:00', '商品收藏', true)
    } else if (this.taskScene === 1) {
      this.TaskCard('Food', '#39BFA3', '午餐外卖偏好整理', '运行中', '今天 11:20', '外卖订单', true)
      this.TaskCard('Shop', '#FF9347', '晚餐配送提醒', '运行中', '今天 18:10', '生活服务', true)
    } else if (this.taskScene === 2) {
      this.TaskCard('Play', '#8066FF', '周末娱乐记录整理', '已暂停', '周六 10:00', '视频 & 音乐', false)
      this.TaskCard('Movie', '#4B8BFF', '观影清单同步', '运行中', '周五 21:30', '影音收藏', true)
    } else {
      this.TaskCard('Chat', '#4B8BFF', '家庭群消息摘要', '运行中', '明天 07:30', '聊天记录', true)
      this.TaskCard('Bell', '#FF9347', '晨间通知摘要', '运行中', '明天 07:30', '系统通知', true)
    }
  }

  @Builder TaskPage() {
    Scroll() {
      Column() {
        this.AppHeader('定时任务', '自定义采集 workflow')
        Column() {
          Row() {
            Column() {
              Row() {
                Text('新建任务').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#11182F')
                Text('AI 编排').fontSize(11).fontColor('#765BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F0ECFF').borderRadius(10).margin({ left: 10 })
              }
              Text('选择场景，自动采集并整理你的生活数据').fontSize(12).fontColor('#6F7584').margin({ top: 7 }).maxLines(1)
              Row() {
                Text('购物').fontSize(11).fontColor('#6B5CFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F8F5FF').borderRadius(10)
                Text('外卖').fontSize(11).fontColor('#39BFA3').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFFBF7').borderRadius(10).margin({ left: 8 })
                Text('聊天').fontSize(11).fontColor('#4B8BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFF5FF').borderRadius(10).margin({ left: 8 })
              }.margin({ top: 12 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Column() {
              Text('+').fontSize(28).fontColor(Color.White).fontWeight(FontWeight.Regular)
              Text('创建').fontSize(11).fontColor('#F2EEFF').margin({ top: 1 })
            }
            .justifyContent(FlexAlign.Center)
            .width(58)
            .height(58)
            .backgroundColor('#765BFF')
            .borderRadius(20)
          }.width('100%')
        }
        .width('86%')
        .height(136)
        .padding(22)
        .backgroundColor('#F3EEFF')
        .borderRadius(20)
        .margin({ top: 24 })
        .onClick(() => { promptAction.showToast({ message: '新建任务流程后续接入', duration: 1500 }); })

        Scroll() {
          Row() {
            this.TaskSceneTab('购物', 0)
            Blank().width(10)
            this.TaskSceneTab('外卖', 1)
            Blank().width(10)
            this.TaskSceneTab('娱乐', 2)
            Blank().width(10)
            this.TaskSceneTab('聊天', 3)
          }.padding({ left: 24, right: 24 })
        }
        .width('100%')
        .height(46)
        .scrollable(ScrollDirection.Horizontal)
        .margin({ top: 22, bottom: 18 })

        this.TaskSceneList()
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }

  @Builder AssistantPage() {
    Scroll() {
      Column() {
        this.AppHeader('本地推理', '端侧模型控制台')
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
              let cfg = this.modelDir + '/config.json';
              if (!this.prepareCustomOpp()) { return; }
              this.output = '加载中，请稍候...';
              try {
                this.output = await mnnllm.loadModel(cfg);
                if (this.output === 'ok') { this.modelLoaded = true; }
              } catch(err) { let e = err as Error; this.output = '加载失败: ' + e.message; }
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
            if (!this.modelLoaded) { this.output = '请先加载模型后再运行智能体'; return; }
            if (this.userInput.length === 0) { this.output = '请在上方文本框输入任务目标，例如：去淘宝买手机'; return; }
            this.llmServer.currentTask = this.userInput;
            this.output = `====== 等待 PC 截图 ======\n当前任务已设定为: ${this.userInput}\nPC 脚本检测到任务后将自动开始。`;
          })

        Row() {
          Button('启动 PC 控制后端 (HDC)')
            .height(48)
            .backgroundColor('#607D8B')
            .borderRadius(14)
            .layoutWeight(1)
            .onClick(() => {
              if (!this.modelLoaded) { this.output = '请先加载模型'; return; }
              this.llmServer.start(9126, this.filesDir, mnnllm as Record<string, Function>, (msg: string) => {
                this.output = msg;
                let match = msg.match(/<img>(.*?)<hw>/);
                if (match && match[1]) { this.debugImagePath = 'file://' + match[1]; }
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
            })
          Row() {
            Checkbox({ name: 'autoConfirm', group: 'settings' })
              .select(this.autoConfirm)
              .selectedColor('#5B68FF')
              .onChange((value: boolean) => { this.autoConfirm = value; })
            Text('自动同意').fontSize(14).fontColor('#333333')
          }.height(48).padding({ left: 12, right: 12 }).backgroundColor(Color.White).borderRadius(14).margin({ left: 10 })
        }.width('92%').margin({ top: 14 })

        Column() {
          Text('模型与网络设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#11182F').width('100%').margin({ bottom: 14 })
          Row() {
            Button('检查连接').onClick(() => { this.checkServer(); }).enabled(!this.downloading).height(40).layoutWeight(1).backgroundColor('#38BE8B').borderRadius(12)
            Button('下载全部').onClick(() => { this.downloadAll(); }).enabled(!this.downloading && this.connected).height(40).layoutWeight(1).backgroundColor('#FF7043').borderRadius(12).margin({ left: 10 })
            Button('删除模型').onClick(() => { this.deleteModelFiles(); }).enabled(!this.downloading).height(40).layoutWeight(1).backgroundColor('#F44336').borderRadius(12).margin({ left: 10 })
          }.width('100%').margin({ bottom: 12 })
          Row() {
            Text('线程数').fontSize(14).fontColor('#666666').width(58)
            TextInput({ text: this.threadNumInput }).type(InputType.Number).width(76).height(40).backgroundColor('#F2F5FC').borderRadius(12).onChange((val: string) => { this.threadNumInput = val; })
            Button('修改 Config').onClick(() => { this.updateConfigThreadNum(); }).height(40).layoutWeight(1).backgroundColor('#4B8BFF').borderRadius(12).margin({ left: 10 })
            Button('查看 Config').onClick(() => { this.showConfigJson(); }).height(40).layoutWeight(1).backgroundColor('#607D8B').borderRadius(12).margin({ left: 10 })
          }.width('100%')
          Row() {
            Button('Op Precision Test').height(42).layoutWeight(1).backgroundColor('#FF9800').borderRadius(12).onClick(() => { router.pushUrl({ url: 'pages/OpTest' }) })
            Button('Runtime Logs').height(42).layoutWeight(1).backgroundColor('#607D8B').borderRadius(12).margin({ left: 10 }).onClick(() => { router.pushUrl({ url: 'pages/LogView' }) })
          }.width('100%').margin({ top: 12 })
        }.width('92%').padding(20).backgroundColor(Color.White).borderRadius(20).margin({ top: 18 })
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
      TabContent() { this.HomePage() }.tabBar(this.TabItem('H', '首页', 0))
      TabContent() { this.CollectionPage() }.tabBar(this.TabItem('C', '采集', 1))
      TabContent() { this.AssistantPage() }.tabBar(this.TabItem('A', '助手', 2))
      TabContent() { this.TaskPage() }.tabBar(this.TabItem('T', '任务', 3))
    }
    .onChange((index: number) => { this.currentTab = index; })
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8FF')
  }
}
