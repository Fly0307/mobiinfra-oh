import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatModeLabel,
  chatModePlaceholder
} from './ChatPageTypes';

@Component
export struct ChatPage {
  @Link chatMode: string;
  @Link cloudUserInput: string;
  @Link userInput: string;
  @Prop cloudOutput: string = '';
  @Prop cloudDebugImagePath: string = '';
  @Prop cloudThinking: boolean = false;
  @Prop localOutput: string = '';
  @Prop localDebugImagePath: string = '';
  @Prop chatHistory: string = '';
  @Prop localThinking: boolean = false;
  @Prop modelLoaded: boolean = false;
  onRunCloudPlanner: () => Promise<void> = async () => {};
  onSubmitCloudTask: () => Promise<void> = async () => {};
  onSendLocalMessage: () => Promise<void> = async () => {};
  onSubmitLocalTask: () => Promise<void> = async () => {};
  onClearCloudDebugImage: () => void = () => {};
  onClearLocalDebugImage: () => void = () => {};
  onOpenRuntimeLogs: () => void = () => {};

  private isCloudMode(): boolean {
    return this.chatMode !== CHAT_MODE_LOCAL_INFERENCE;
  }

  private activeInput(): string {
    return this.isCloudMode() ? this.cloudUserInput : this.userInput;
  }

  private setActiveInput(value: string): void {
    if (this.isCloudMode()) {
      this.cloudUserInput = value;
      return;
    }
    this.userInput = value;
  }

  private isBusy(): boolean {
    return this.isCloudMode() ? this.cloudThinking : this.localThinking;
  }

  private statusText(): string {
    if (this.isCloudMode()) {
      return this.cloudOutput.length > 0 ? this.cloudOutput : '云端智能体准备就绪';
    }
    if (!this.modelLoaded) {
      return '本地模型未加载';
    }
    return this.chatHistory.length > 0 ? this.chatHistory : this.localOutput;
  }

  @Builder ModeChip(mode: string) {
    Text(chatModeLabel(mode))
      .fontSize(13)
      .fontWeight(this.chatMode === mode ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.chatMode === mode ? Color.White : '#5D6472')
      .height(34)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.chatMode === mode ? '#111827' : '#F4F6FA')
      .borderRadius(17)
      .onClick(() => {
        this.chatMode = mode;
      })
  }

  @Builder PromptChip(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor('#232936')
      .height(42)
      .padding({ left: 16, right: 16 })
      .backgroundColor(Color.White)
      .borderRadius(21)
      .border({ width: 1, color: '#E7EAF0' })
      .margin({ right: 10, bottom: 10 })
      .onClick(() => {
        this.setActiveInput(text);
      })
  }

  @Builder DebugImagePreview() {
    if (this.isCloudMode() && this.cloudDebugImagePath.length > 0) {
      Image(this.cloudDebugImagePath)
        .width(86)
        .height(120)
        .objectFit(ImageFit.Contain)
        .backgroundColor(Color.Black)
        .borderRadius(12)
        .onClick(() => { this.onClearCloudDebugImage(); })
    } else if (!this.isCloudMode() && this.localDebugImagePath.length > 0) {
      Image(this.localDebugImagePath)
        .width(86)
        .height(120)
        .objectFit(ImageFit.Contain)
        .backgroundColor(Color.Black)
        .borderRadius(12)
        .onClick(() => { this.onClearLocalDebugImage(); })
    }
  }

  @Builder StatusPanel() {
    Row() {
      Scroll() {
        Text(this.statusText())
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor('#4B5563')
          .width('100%')
          .padding(12)
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: 76, maxHeight: 132 })
      .backgroundColor('#F8FAFD')
      .borderRadius(14)
      this.DebugImagePreview()
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .border({ width: 1, color: '#EDF0F5' })
  }

  private async runPrimaryAction(): Promise<void> {
    if (this.isCloudMode()) {
      await this.onRunCloudPlanner();
      return;
    }
    await this.onSendLocalMessage();
  }

  private async runTaskAction(): Promise<void> {
    if (this.isCloudMode()) {
      await this.onSubmitCloudTask();
      return;
    }
    await this.onSubmitLocalTask();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text('☰')
            .fontSize(28)
            .fontColor('#111827')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
          Row() {
            Text('MobiAgent')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
              .maxLines(1)
            Text(chatModeLabel(this.chatMode))
              .fontSize(12)
              .fontColor('#6B7280')
              .margin({ left: 8, top: 4 })
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          Text('日志')
            .fontSize(14)
            .fontColor('#111827')
            .width(52)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.onOpenRuntimeLogs(); })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 22 })

        Column() {
          Row() {
            this.ModeChip(CHAT_MODE_CLOUD_AGENT)
            this.ModeChip(CHAT_MODE_LOCAL_INFERENCE)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 24 })

          Row() {
            Text('H')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(54)
              .height(54)
              .textAlign(TextAlign.Center)
              .backgroundColor('#5968FF')
              .borderRadius(18)
            Text('我是 MobiAgent')
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor('#D8D5EA')
              .margin({ left: 18 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 120 })

          Text('随时为你答疑、规划，也可以下发自动化任务')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#9AA3B2')
            .width('100%')
            .margin({ top: 22 })
            .maxLines(2)

          Flex({ wrap: FlexWrap.Wrap }) {
            this.PromptChip('整理今天截图里的关键信息')
            this.PromptChip('规划一个收集微信聊天记录的 workflow')
            this.PromptChip('打开淘宝搜索耳机并比较价格')
          }
          .width('100%')
          .margin({ top: 28 })

          Column() {
            this.StatusPanel()
          }
          .width('100%')
          .margin({ top: 18 })

          Blank()
        }
        .width('100%')
        .padding({ left: 28, right: 28 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)

      Column() {
        Row() {
          Text('深度思考')
            .fontSize(13)
            .fontColor('#222222')
            .height(38)
            .padding({ left: 14, right: 14 })
            .backgroundColor(Color.White)
            .borderRadius(19)
            .border({ width: 1, color: '#E2E5EA' })
            .onClick(async () => { await this.runPrimaryAction(); })
          Text('下发任务')
            .fontSize(13)
            .fontColor('#222222')
            .height(38)
            .padding({ left: 14, right: 14 })
            .backgroundColor(Color.White)
            .borderRadius(19)
            .border({ width: 1, color: '#E2E5EA' })
            .margin({ left: 10 })
            .onClick(async () => { await this.runTaskAction(); })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 12 })

        Row() {
          Text('语')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .borderRadius(22)
            .border({ width: 2, color: '#111827' })
          TextInput({ placeholder: chatModePlaceholder(this.chatMode), text: this.activeInput() })
            .layoutWeight(1)
            .height(52)
            .fontSize(16)
            .backgroundColor('#00FFFFFF')
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.setActiveInput(value); })
          Button(this.isBusy() ? '...' : '发送')
            .width(72)
            .height(44)
            .fontSize(14)
            .backgroundColor(this.isBusy() ? '#AEB7C8' : '#111827')
            .borderRadius(22)
            .onClick(async () => { await this.runPrimaryAction(); })
        }
        .width('100%')
        .height(68)
        .padding({ left: 14, right: 14 })
        .backgroundColor(Color.White)
        .borderRadius(28)
        .shadow({ radius: 18, color: '#22000000', offsetX: 0, offsetY: 6 })
        .margin({ left: 20, right: 20, bottom: 28 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
