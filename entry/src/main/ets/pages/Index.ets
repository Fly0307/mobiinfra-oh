import entry from 'libentry.so';

// @Entry
// @Component
// struct Index {
//   @State status: string = '未加载模型'
//   @State output: string = ''
//   @State userInput: string = ''
//   @State loading: boolean = false
//   private modelPath: string = ''
//
//   aboutToAppear() {
//     // 获取应用沙箱 files 目录
//     let filesDir = getContext(this).filesDir
//     this.modelPath = filesDir + '/model/config.json'
//     this.output = '沙箱路径: ' + filesDir
//   }
//
//   build() {
//     Column() {
//       Text(this.status)
//         .fontSize(16)
//         .fontColor(this.status.startsWith('error') ? Color.Red : Color.Green)
//         .margin(10)
//
//       Button('拷贝模型到沙箱')
//         .onClick(() => {
//           let filesDir = getContext(this).filesDir
//           let res = entry.copyModel('/data/local/tmp/MNN/model', filesDir + '/model')
//           this.output = '拷贝结果: ' + res + '\n路径: ' + filesDir + '/model'
//         })
//         .margin(10)
//
//       Button('加载模型')
//         .onClick(() => {
//           this.status = '加载中...'
//           this.loading = true
//           let res = entry.loadModel(this.modelPath)
//           this.status = res === 'ok' ? '模型已加载' : res
//           this.loading = false
//         })
//         .margin(10)
//         .enabled(!this.loading)
//
//       TextInput({ placeholder: '输入问题...', text: this.userInput })
//         .onChange((value: string) => { this.userInput = value })
//         .margin(10)
//         .width('90%')
//
//       Row() {
//         Button('单轮推理')
//           .onClick(() => {
//             if (!this.userInput) return
//             this.output = '推理中...'
//             this.output = entry.generate(this.userInput)
//           })
//           .margin(5)
//
//         Button('对话')
//           .onClick(() => {
//             if (!this.userInput) return
//             this.output = '思考中...'
//             let reply = entry.chat(this.userInput)
//             this.output = '> ' + this.userInput + '\n\n' + reply
//             this.userInput = ''
//           })
//           .margin(5)
//
//         Button('重置')
//           .onClick(() => {
//             entry.reset()
//             this.output = '对话已重置'
//           })
//           .margin(5)
//       }
//
//       Scroll() {
//         Text(this.output)
//           .fontSize(14)
//           .margin(10)
//           .width('90%')
//       }
//       .height('50%')
//       .width('100%')
//     }
//     .width('100%')
//     .height('100%')
//     .padding(10)
//   }
// }

// import mnnllm from 'libentry.so';
// import request from '@ohos.request';
// import fs from '@ohos.file.fs';
// import common from '@ohos.app.ability.common';
//
// const MODEL_ID: string = 'doulujiyao/mnn_mobi_gptq_new_sym_e2e_2B_w8a8_half_rl_n64_s512_visual';
//
// const MODEL_FILES: string[] = [
//   'config.json',
//   'llm_config.json',
//   'export_args.json',
//   'tokenizer.mtok',
//   'llm.mnn',
//   'llm.mnn.json',
//   'llm.mnn.weight',
//   'embeddings_bf16.bin',
//   'visual.mnn',
//   'visual.mnn.json',
//   'visual.mnn.weight'
// ];
//
// @Entry
// @Component
// struct Index {
//   @State output: string = '准备就绪';
//   @State chatHistory: string = '';
//   @State userInput: string = '';
//   @State downloading: boolean = false;
//   @State modelLoaded: boolean = false;
//
//   private filesDir: string = '';
//   private modelDir: string = '';
//
//   aboutToAppear() {
//     let ctx = getContext(this) as common.UIAbilityContext;
//     this.filesDir = ctx.filesDir;
//     this.modelDir = this.filesDir + '/model';
//   }
//
//   private getDownloadUrl(filename: string): string {
//     return `https://modelscope.cn/models/${MODEL_ID}/resolve/master/${filename}`;
//   }
//
//   private downloadOneFile(filename: string, index: number, fileCount: number): Promise<boolean> {
//     const url = this.getDownloadUrl(filename);
//     const savePath = `${this.modelDir}/${filename}`;
//
//     // Skip if already downloaded
//     try {
//       let st = fs.statSync(savePath);
//       if (st.size > 0) {
//         this.output = `[${index + 1}/${fileCount}] ${filename} 已存在(${(st.size /
//           1048576).toFixed(1)}MB)，跳过`;
//         return Promise.resolve(true);
//       }
//     } catch (e) {
//       // file doesn't exist, proceed
//     }
//
//     this.output = `[${index + 1}/${fileCount}] 开始下载: ${filename}`;
//
//     let ctx = getContext(this) as common.UIAbilityContext;
//     let self = this;
//
//     return new Promise<boolean>((resolve) => {
//       request.downloadFile(ctx, {
//         url: url,
//         filePath: savePath,
//         enableMetered: true,
//         enableRoaming: true,
//       }).then((task: request.DownloadTask) => {
//         task.on('progress', (receivedSize: number, totalSize: number) => {
//           let pct = totalSize > 0 ? Math.floor(receivedSize * 100 / totalSize) : 0;
//           let recvMB = (receivedSize / 1048576).toFixed(1);
//           let totMB = (totalSize / 1048576).toFixed(1);
//           self.output = `[${index + 1}/${fileCount}] ${filename}\n${recvMB}MB / ${totMB}MB  ${pct}%`;
//         });
//         task.on('complete', () => {
//           self.output = `[${index + 1}/${fileCount}] ${filename} done`;
//           resolve(true);
//         });
//         task.on('fail', (err: number) => {
//           self.output = `[${index + 1}/${fileCount}] ${filename} 失败(err=${err})`;
//           resolve(false);
//         });
//       }).catch((err: Error) => {
//         self.output = `创建下载任务失败: ${filename}\n${err.message}`;
//         resolve(false);
//       });
//     });
//   }
//
//   async downloadModel() {
//     this.downloading = true;
//     this.output = '准备下载...';
//
//     // Create model directory
//     try {
//       fs.mkdirSync(this.modelDir);
//     } catch (e) {
//       // already exists
//     }
//
//     let failed: string[] = [];
//     for (let i = 0; i < MODEL_FILES.length; i++) {
//       let ok = await this.downloadOneFile(MODEL_FILES[i], i, MODEL_FILES.length);
//       if (!ok) {
//         failed.push(MODEL_FILES[i]);
//       }
//     }
//
//     if (failed.length === 0) {
//       this.output = '全部下载完成! 可以加载模型了';
//     } else {
//       this.output = `完成，${failed.length}个失败: ${failed.join(', ')}\n可重新点击下载(已有文件会跳过)`;
//     }
//     this.downloading = false;
//   }
//
//   build() {
//     Column() {
//       Text('MNN LLM').fontSize(20).fontWeight(FontWeight.Bold).margin(10)
//
//       Scroll() {
//         Text(this.output)
//           .fontSize(13)
//           .fontFamily('monospace')
//           .width('100%')
//           .padding(10)
//       }
//       .height('30%')
//       .width('95%')
//       .backgroundColor('#f5f5f5')
//       .borderRadius(8)
//       .margin(5)
//
//       // Download & Load
//       Row() {
//         Button('下载模型')
//           .onClick(() => { this.downloadModel(); })
//           .enabled(!this.downloading)
//           .margin(5)
//         Button('加载模型')
//           .onClick(() => {
//             let configPath = this.modelDir + '/config.json';
//             this.output = '加载中...';
//             this.output = mnnllm.loadModel(configPath);
//             if (this.output.indexOf('success') >= 0) {
//               this.modelLoaded = true;
//             }
//           })
//           .enabled(!this.downloading)
//           .margin(5)
//       }.margin(5)
//
//       // Chat area
//       Scroll() {
//         Text(this.chatHistory)
//           .fontSize(14)
//           .width('100%')
//           .padding(10)
//       }
//       .height('30%')
//       .width('95%')
//       .backgroundColor('#fafafa')
//       .borderRadius(8)
//       .margin(5)
//
//       Row() {
//         TextInput({ placeholder: '输入消息...', text: this.userInput })
//           .onChange((val: string) => { this.userInput = val; })
//           .layoutWeight(1)
//           .margin(5)
//         Button('发送')
//           .onClick(() => {
//             if (!this.modelLoaded || this.userInput.length === 0) return;
//             let msg = this.userInput;
//             this.userInput = '';
//             this.chatHistory += `\nUser: ${msg}\n`;
//             let reply = mnnllm.chat(msg);
//             this.chatHistory += `Assistant: ${reply}\n`;
//           })
//           .margin(5)
//       }.width('95%')
//
//       Row() {
//         Button('单轮推理')
//           .onClick(() => {
//             if (!this.modelLoaded) return;
//             this.output = mnnllm.generate('你好');
//           })
//           .margin(5)
//         Button('重置')
//           .onClick(() => {
//             this.output = mnnllm.reset();
//             this.chatHistory = '';
//           })
//           .margin(5)
//       }.margin(5)
//
//     }
//     .width('100%')
//     .height('100%')
//     .padding(10)
//   }
// }

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import mnnllm from 'libentry.so';
import { LlmServer } from '../utils/LlmServer';
import { promptAction } from '@kit.ArkUI';

const SERVER: string = 'http://166.111.53.96:9123';

interface ServerFile {
  name: string;
  size: number;
}

@Entry
@Component
struct Index {
  @State output: string = '请先检查服务器连接';
  @State chatHistory: string = '';
  @State userInput: string = '';
  @State downloading: boolean = false;
  @State modelLoaded: boolean = false;
  @State connected: boolean = false;

  private filesDir: string = '';
  private modelDir: string = '';
  private serverFiles: ServerFile[] = [];
  private totalBytesAll: number = 0;
  
  // 我们将 PC 控制的服务端作为单例保存
  private llmServer: LlmServer = new LlmServer();

  aboutToAppear() {
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    this.modelDir = this.filesDir + '/model';
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
        if (f.startsWith('agent_step_') || f.startsWith('agent_cur_screen')) {
          fs.unlinkSync(`${this.filesDir}/${f}`);
          count++;
        }
      }
      this.output = `清理成功！删除了 ${count} 张缓存截图。`;
    } catch(e) {
      this.output = `清理截图失败: ${e}`;
    }
  }

  // ========== Step 1: Check connection, list files ==========
  async checkServer() {
    this.output = `正在连接 ${SERVER} ...`;
    // 每一个httpRequest对应一个HTTP请求任务，不可复用
    let httpReq = http.createHttp();
    try {
      let resp = await httpReq.request(`${SERVER}/api/files`, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING,
      });
      if (resp.responseCode !== 200) {
        this.output = `连接失败: HTTP ${resp.responseCode}`;
        return;
      }
      let files: ServerFile[] = JSON.parse(resp.result as string);
      this.serverFiles = files.filter((f: ServerFile) => f.name !== 'serve_model.py');
      this.totalBytesAll = 0;

      let listing = '服务器连接成功!\n\n文件列表:\n';
      listing += '────────────────────────────────────────\n';
      for (let f of this.serverFiles) {
        this.totalBytesAll += f.size;
        let pad = ' '.repeat(Math.max(1, 28 - f.name.length));
        listing += `  ${f.name}${pad}${this.formatSize(f.size)}\n`;
      }
      listing += '────────────────────────────────────────\n';
      listing += `共 ${this.serverFiles.length} 个文件, 总大小:
  ${this.formatSize(this.totalBytesAll)}\n\n`;
      listing += '点击"下载全部"开始下载';
      this.output = listing;
      this.connected = true;
    } catch (err) {
      let e = err as BusinessError;
      this.output = `连接失败: code=${e.code} ${e.message}\n\n请检查:\n1. 服务器 python3
  serve_model.py 是否运行\n2. 防火墙是否开放端口\n3. 手机网络是否可达服务器`;
      this.connected = false;
    } finally {
      httpReq.destroy();
    }
  }

  // ========== Step 2: Stream-download one file ==========
  private downloadOneFile(file: ServerFile, index: number, fileCount: number,
    completedBytes: number): Promise<number> {
    const url = `${SERVER}/${file.name}`;
    const savePath = `${this.modelDir}/${file.name}`;

    // Skip if exists with correct size
    try {
      let st = fs.statSync(savePath);
      if (st.size === file.size) {
        this.output = `[${index + 1}/${fileCount}] ${file.name}
  已存在(${this.formatSize(st.size)})，跳过\n` +
          `总进度: ${this.formatSize(completedBytes + file.size)} /
  ${this.formatSize(this.totalBytesAll)}`;
        return Promise.resolve(file.size);
      }
    } catch (e) {
      // not exists
    }

    this.output = `[${index + 1}/${fileCount}] 连接: ${file.name}`;
    let self = this;
    let idx = index;
    let completed = completedBytes;

    return new Promise<number>((resolve) => {
      // 每一个httpRequest对应一个HTTP请求任务，不可复用
      let httpReq = http.createHttp();
      let fileHandle: fs.File;
      let failed = false;
      let resolved = false;

      try {
        fileHandle = fs.openSync(savePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY |
        fs.OpenMode.TRUNC);
      } catch (e) {
        self.output = `[${idx + 1}/${fileCount}] 创建文件失败: ${file.name}`;
        httpReq.destroy();
        resolve(-1);
        return;
      }

      // Helper: cleanup and resolve
      let finish = (size: number) => {
        if (resolved) return;
        resolved = true;
        httpReq.off('dataReceive');
        httpReq.off('dataReceiveProgress');
        httpReq.off('dataEnd');
        try { fs.closeSync(fileHandle); } catch (e) {}
        httpReq.destroy();
        resolve(size);
      };

      // Subscribe: stream data -> write to file
      httpReq.on('dataReceive', (data: ArrayBuffer) => {
        if (!failed) {
          try {
            fs.writeSync(fileHandle.fd, data);
          } catch (e) {
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
            `文件: ${self.formatSize(data.receiveSize)} / ${self.formatSize(data.totalSize)}
  ${filePct}%\n` +
            `总量: ${self.formatSize(overallRecv)} / ${self.formatSize(self.totalBytesAll)}
  ${overallPct}%`;
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
          } catch (e) {}
          self.output = `[${idx + 1}/${fileCount}] ${file.name} 完成
  (${self.formatSize(fileSize)})`;
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
      httpReq.requestInStream(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 60000,
        readTimeout: 7200000, // 2 hours for large files
      }).then((code: number) => {
        if (code !== 200) {
          failed = true;
          self.output = `[${idx + 1}/${fileCount}] ${file.name} HTTP ${code}`;
          finish(-1);
        }
        // if 200, wait for dataEnd
      }).catch((err: BusinessError) => {
        failed = true;
        self.output = `[${idx + 1}/${fileCount}] ${file.name} 错误: code=${err.code}
  ${err.message}`;
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
    try { fs.mkdirSync(this.modelDir); } catch (e) {}

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
      this.output = `全部下载完成!\n模型总大小:
  ${this.formatSize(completedBytes)}\n\n点击"加载模型"开始使用`;
    } else {
      this.output = `${failed.length}个失败: ${failed.join(', ')}\n已下载:
  ${this.formatSize(completedBytes)}\n再次点击可继续(已有文件跳过)`;
    }
    this.downloading = false;
  }

  // ========== UI ==========
  build() {
    Column() {
      Text('MNN LLM Chat').fontSize(20).fontWeight(FontWeight.Bold).margin(10)

      Scroll() {
        Text(this.output).fontSize(13).fontFamily('monospace').width('100%').padding(10)
      }
      .height('30%').width('95%').backgroundColor('#f5f5f5').borderRadius(8).margin(5)

      Row() {
        Button('检查连接')
          .onClick(() => { this.checkServer(); })
          .enabled(!this.downloading).margin(5)
        Button('下载全部')
          .onClick(() => { this.downloadAll(); })
          .enabled(!this.downloading && this.connected).margin(5)
        Button('加载模型')
          .onClick(async () => {
            let cfg = this.modelDir + '/config.json';
            this.output = '加载中，请稍候...';
            try {
              // 变为异步调用，界面不再卡死
              this.output = await mnnllm.loadModel(cfg);
              // 修复 Bug：C++ 侧返回的是 "ok"，不是 "success"
              if (this.output === 'ok') {
                this.modelLoaded = true;
              }
            } catch(err) {
              this.output = '加载失败: ' + err;
            }
          })
          .enabled(!this.downloading).margin(5)
      }.margin(5)

      Scroll() {
        Text(this.chatHistory).fontSize(14).width('100%').padding(10)
      }
      .height('25%').width('95%').backgroundColor('#fafafa').borderRadius(8).margin(5)

      Row() {
        TextInput({ placeholder: '输入消息...', text: this.userInput })
          .onChange((val: string) => { this.userInput = val; })
          .layoutWeight(1).margin(5)
        Button('发送')
          .onClick(async () => {
            if (!this.modelLoaded || this.userInput.length === 0) return;
            let msg = this.userInput;
            this.userInput = '';
            this.chatHistory += `\nUser: ${msg}\nAssistant:思考中...`;

            try {
              // 异步请求对话
              let reply = await mnnllm.chat(msg);
              // 清除掉 "思考中..." 替换为真实回复
              this.chatHistory = this.chatHistory.replace('Assistant:思考中...', `Assistant: ${reply}\n`);
            } catch(err) {
              this.chatHistory = this.chatHistory.replace('Assistant:思考中...', `Assistant: [错误] ${err}\n`);
            }
          }).margin(5)
      }.width('95%')

      Row() {
        Button('单轮推理')
          .onClick(async () => {
            if (!this.modelLoaded) { this.output = '请先加载模型'; return; }
            this.output = '推理中...';
            try {
              this.output = await mnnllm.generate('你好');
            } catch(err) {
              this.output = '推理错误: ' + err;
            }
          }).margin(5)
        Button('重置')
          .onClick(() => {
            this.output = mnnllm.reset();
            this.chatHistory = '';
          }).margin(5)
      }.margin(5)

      Row() {
        Button('开始智能体执行 (输入框为任务)')
          .onClick(async () => {
            if (!this.modelLoaded) {
              this.output = "请先加载模型后再运行智能体！";
              return;
            }
            if (this.userInput.length === 0) {
              this.output = "请在上方文本框输入任务目标，比如: '去淘宝买手机'";
              return;
            }
            
            // 仅仅在这里设定 Task，后续的事情由 PC python 轮询接管
            this.llmServer.currentTask = this.userInput;
            this.output = `====== 等待 PC 截图 ======\n当前任务已设定为: ${this.userInput}\nPC 脚本检测到任务后将自动开始。`;

          }).margin(5).backgroundColor(Color.Orange)
      }.margin(5)

      Row() {
        Button('启动 PC 控制后端(HDC)')
          .onClick(() => {
            if (!this.modelLoaded) {
              this.output = "请先加载模型！";
              return;
            }
            this.llmServer.start(9126, this.filesDir, mnnllm as Record<string, Function>, (msg: string) => {
              this.output = msg;
              }, async (response: string) => {
                 return new Promise<boolean>((resolve) => {
                     promptAction.showDialog({
                         title: '大模型返回确认',
                         message: '模型推理结果：\n' + response + '\n\n是否同意执行？',
                         buttons: [
                             { text: '拒绝', color: '#ff0000' },
                             { text: '同意', color: '#00cc00' }
                         ]
                     }).then((data) => {
                         resolve(data.index === 1);
                     }).catch(() => {
                         resolve(false);
                     });
                  });
                }); // close llmServer.start
          }).margin(5).backgroundColor(Color.Gray)
      }.margin(5)
    }.width('100%').height('100%').padding(10)
  }
}