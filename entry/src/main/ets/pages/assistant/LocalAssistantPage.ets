import { router } from '@kit.ArkUI';
import mnnllm from 'libentry.so';
import { AppHeader } from '../../components/AppHeader';
import { DEFAULT_ENDPOINT_CONFIG } from '../../config/DefaultEndpointConfig';
import { DEFAULT_MODELSCOPE_MNN_REPO } from '../../config/ModelDownloadConfig';

@Component
export struct LocalAssistantPage {
  @Link output: string;
  @Link assistantSettingsOpen: boolean;
  @Link debugImagePath: string;
  @Link chatHistory: string;
  @Link userInput: string;
  @Link isThinking: boolean;
  @Link modelLoaded: boolean;
  @Link downloading: boolean;
  @Link autoConfirm: boolean;
  @Link serverIp: string;
  @Link modelScopeMnnRepo: string;
  @Link connected: boolean;
  @Link hdcServerIp: string;
  @Link manualHdcServerIp: string;
  @Link wirelessIp: string;
  @Link hdcAutoStatus: string;
  @Link hdcAutoConnecting: boolean;
  @Link hdcManualPairing: boolean;
  @Link threadNumInput: string;

  onEnsureLocalModelLoaded: () => Promise<boolean> = async () => false;
  onStartLocalBackend: () => Promise<void> = async () => {};
  onStartLocalAgentTask: (task: string) => Promise<void> = async (task: string) => {};
  onCheckServer: () => void = () => {};
  onDownloadAll: () => void = () => {};
  onDeleteModelFiles: () => void = () => {};
  onDownloadModelScopeModel: () => void = () => {};
  onUpdateConfigThreadNum: () => void = () => {};
  onShowConfigJson: () => void = () => {};
  onDiscoverHdcServer: (preferManual: boolean, showToast: boolean) => Promise<void> = async (
    preferManual: boolean, showToast: boolean) => {};
  onSetHdcManualPairing: () => void = () => {};
  onMarkHdcManualEditing: () => void = () => {};
  onTestAndConnectHdc: () => void = () => {};
  hdcInputTextColor: () => string = () => '#333333';
  hdcInputBackgroundColor: () => string = () => '#F2F5FC';
  hdcInputEditable: () => boolean = () => true;
  hdcStatusColor: () => string = () => '#6F7684';

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
        TextInput({ placeholder: 'http://服务器IP:端口，默认 ' + DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl, text: this.serverIp })
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
        TextInput({ placeholder: 'http://服务器IP:端口，默认 ' + DEFAULT_ENDPOINT_CONFIG.hdcServerUrl, text: this.hdcServerIp })
          .height(42)
          .width('100%')
          .fontSize(13)
          .fontColor(this.hdcInputTextColor())
          .backgroundColor(this.hdcInputBackgroundColor())
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6, bottom: 8 })
          .enabled(this.hdcInputEditable())
          .onChange((val: string) => {
            this.hdcServerIp = val;
            this.manualHdcServerIp = val;
            this.onMarkHdcManualEditing();
          })
        Text(this.hdcAutoStatus)
          .fontSize(12)
          .fontColor(this.hdcStatusColor())
          .width('100%')
          .maxLines(2)
          .margin({ bottom: 8 })
        Row() {
          Button(this.hdcAutoConnecting ? '自动连接中' : '自动连接')
            .height(38)
            .layoutWeight(1)
            .fontSize(12)
            .backgroundColor('#4F68FF')
            .borderRadius(12)
            .enabled(!this.hdcAutoConnecting)
            .onClick(async () => {
              this.hdcManualPairing = false;
              await this.onDiscoverHdcServer(false, true);
            })
          Button('手动配对')
            .height(38)
            .layoutWeight(1)
            .fontSize(12)
            .backgroundColor(this.hdcManualPairing ? '#765BFF' : '#607D8B')
            .borderRadius(12)
            .margin({ left: 10 })
            .onClick(() => { this.onSetHdcManualPairing(); })
        }
        .width('100%')
        .margin({ bottom: 12 })
        Text('无线 HDC 目标')
          .fontSize(13)
          .fontColor('#6F7684')
          .width('100%')
        Row() {
          TextInput({ placeholder: '手机无线调试地址，默认 ' + DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget, text: this.wirelessIp })
            .height(42)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(this.hdcInputTextColor())
            .backgroundColor(this.hdcInputBackgroundColor())
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .enabled(this.hdcInputEditable())
            .onChange((val: string) => {
              this.wirelessIp = val;
              this.onMarkHdcManualEditing();
            })
          Button('连接测试')
            .height(42)
            .width(92)
            .fontSize(13)
            .backgroundColor('#765BFF')
            .borderRadius(12)
            .margin({ left: 10 })
            .enabled(this.hdcInputEditable())
            .onClick(() => { this.onTestAndConnectHdc(); })
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
        Text('ModelScope 仓库')
          .fontSize(13)
          .fontColor('#6F7684')
          .width('100%')
        TextInput({ placeholder: DEFAULT_MODELSCOPE_MNN_REPO, text: this.modelScopeMnnRepo })
          .height(42)
          .width('100%')
          .fontSize(12)
          .backgroundColor('#F2F5FC')
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .margin({ top: 6, bottom: 12 })
          .onChange((val: string) => { this.modelScopeMnnRepo = val; })
        Row() {
          Button('检查连接')
            .onClick(() => { this.onCheckServer(); })
            .enabled(!this.downloading)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#38BE8B')
            .borderRadius(12)
          Button('下载全部')
            .onClick(() => { this.onDownloadAll(); })
            .enabled(!this.downloading && this.connected)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#FF7043')
            .borderRadius(12)
            .margin({ left: 10 })
          Button('删除模型')
            .onClick(() => { this.onDeleteModelFiles(); })
            .enabled(!this.downloading)
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#F44336')
            .borderRadius(12)
            .margin({ left: 10 })
        }.width('100%')
        Button('从 ModelScope 下载')
          .onClick(() => { this.onDownloadModelScopeModel(); })
          .enabled(!this.downloading)
          .height(40)
          .width('100%')
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .margin({ top: 10 })
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
            .onClick(() => { this.onUpdateConfigThreadNum(); })
            .height(40)
            .layoutWeight(1)
            .backgroundColor('#4B8BFF')
            .borderRadius(12)
            .margin({ left: 10 })
          Button('查看 Config')
            .onClick(() => { this.onShowConfigJson(); })
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

  build() {
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
                await this.onEnsureLocalModelLoaded();
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
            .onClick(async () => { await this.onStartLocalAgentTask(this.userInput); })

          Row() {
            Button('启动 PC 控制后端 (HDC)')
              .height(48)
              .backgroundColor('#607D8B')
              .borderRadius(14)
              .layoutWeight(1)
              .onClick(async () => {
                if (!await this.onEnsureLocalModelLoaded()) { return; }
                await this.onStartLocalBackend();
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
}
