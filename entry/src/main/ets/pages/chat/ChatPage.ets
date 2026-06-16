import { inputMethod } from '@kit.IMEKit';
import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatModeLabel,
  chatModePlaceholder
} from './ChatPageTypes';
import { ChatMessage, ChatSessionSummary } from './ChatSessionTypes';
import { ChatMessageList } from './ChatMessageList';
import { ChatSessionDrawer } from './ChatSessionDrawer';

@Component
export struct ChatPage {
  @Link chatMode: string;
  @Link cloudUserInput: string;
  @Link userInput: string;
  @State previewImagePath: string = '';
  @Prop cloudOutput: string = '';
  @Prop cloudDebugImagePath: string = '';
  @Prop cloudThinking: boolean = false;
  @Prop localOutput: string = '';
  @Prop localDebugImagePath: string = '';
  @Prop chatHistory: string = '';
  @Prop localThinking: boolean = false;
  @Prop modelLoaded: boolean = false;
  @Prop sessions: ChatSessionSummary[] = [];
  @Prop activeSessionId: string = '';
  @Prop messages: ChatMessage[] = [];
  // 数字分身透明前景图入口：前景图来自数据层 PNG 缓存，未传入时回退到原有 H 徽标。
  @Prop avatarForegroundUri: string = '';
  @Prop sessionDrawerOpen: boolean = false;
  @Prop restoringLocalSession: boolean = false;
  onSwitchMode: (mode: string) => Promise<void> = async () => {};
  onOpenSessionDrawer: () => void = () => {};
  onCloseSessionDrawer: () => void = () => {};
  onCreateSession: (mode: string) => void = () => {};
  onSelectSession: (id: string) => Promise<void> = async () => {};
  onDeleteSession: (id: string) => Promise<void> = async () => {};
  onToggleTaskTrace: (id: string) => void = () => {};
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

  private hasConversationContent(): boolean {
    return this.messages.length > 0 || this.isBusy();
  }

  private openDebugImagePreview(path: string): void {
    if (path.length > 0) {
      this.previewImagePath = path;
    }
  }

  private closeDebugImagePreview(): void {
    this.previewImagePath = '';
  }

  private activeConversationText(): string {
    if (this.isCloudMode()) {
      return this.cloudThinking ? '云端智能体正在处理...' : '';
    }
    if (!this.modelLoaded) {
      return '本地模型未加载';
    }
    return this.localThinking ? '本地模型正在生成...' : '';
  }

  private compactModeLabel(mode: string): string {
    if (mode === CHAT_MODE_LOCAL_INFERENCE) {
      return '本地';
    }
    return '云端';
  }

  @Builder ModeTopTab(mode: string) {
    Text(this.compactModeLabel(mode))
      .fontSize(12)
      .fontWeight(this.chatMode === mode ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.chatMode === mode ? Color.White : '#5D6472')
      .width(46)
      .height(28)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.chatMode === mode ? '#111827' : '#F4F6FA')
      .borderRadius(14)
      .onClick(async () => {
        await this.onSwitchMode(mode);
      })
  }

  @Builder ModeTopTabs() {
    Row() {
      this.ModeTopTab(CHAT_MODE_CLOUD_AGENT)
      Blank()
        .width(4)
      this.ModeTopTab(CHAT_MODE_LOCAL_INFERENCE)
    }
    .height(32)
    .padding({ left: 2, right: 2 })
    .backgroundColor('#F4F6FA')
    .borderRadius(16)
  }

  @Builder PromptChip(text: string) {
    Row() {
      Text(text)
        .fontSize(14)
        .fontColor('#232936')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(42)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
    .borderRadius(22)
    .border({ width: 1, color: '#E7EAF0' })
    .margin({ bottom: 8 })
    .onClick(() => {
      this.setActiveInput(text);
    })
  }

  @Builder WelcomeAvatarHero() {
    if (this.avatarForegroundUri.length > 0) {
      Row() {
        Image(this.avatarForegroundUri)
          .width(177)
          .height(221)
          .objectFit(ImageFit.Contain)
          .margin({ left: 6 })
        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .height(176)
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 0 })
    } else {
      Text('H')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(54)
        .height(54)
        .textAlign(TextAlign.Center)
        .backgroundColor('#5968FF')
        .borderRadius(18)
    }
  }

  @Builder EmptyWelcome() {
    Scroll() {
      Column() {
        if (this.avatarForegroundUri.length > 0) {
          this.WelcomeAvatarHero()
          Text('我是 MobiAgent')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D8D5EA')
            .width('100%')
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Row() {
            this.WelcomeAvatarHero()
            Text('我是 MobiAgent')
              .fontSize(25)
              .fontWeight(FontWeight.Bold)
              .fontColor('#D8D5EA')
              .margin({ left: 18 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 46 })
        }

        Text('随时为你答疑、规划，也可以下发自动化任务')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#9AA3B2')
          .width('100%')
          .margin({ top: 8 })
          .maxLines(2)
          .lineHeight(22)

        Column() {
          this.PromptChip('整理今天截图里的关键信息')
          this.PromptChip('规划一个收集微信聊天记录的 workflow')
          this.PromptChip('淘宝搜索耳机比价')
        }
        .width('100%')
        .margin({ top: 14 })

        Blank()
          .height(this.avatarForegroundUri.length > 0 ? 152 : 176)
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder ConversationPanel() {
    if (this.messages.length > 0) {
      ChatMessageList({
        messages: this.messages,
        thinking: this.isBusy(),
        modeLabel: chatModeLabel(this.chatMode),
        modeMark: this.isCloudMode() ? '云' : '本',
        onToggleTaskTrace: (id: string) => { this.onToggleTaskTrace(id); },
        onPreviewDebugImage: (path: string) => { this.openDebugImagePreview(path); },
        onScrollContent: (_yOffset: number) => {}
      })
    } else {
      Scroll() {
        Column() {
          Row() {
            Text(this.isCloudMode() ? '云' : '本')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(42)
              .height(42)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.isCloudMode() ? '#5968FF' : '#111827')
              .borderRadius(16)
            Column() {
              Text(chatModeLabel(this.chatMode))
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#111827')
              Text(this.activeConversationText())
                .fontSize(15)
                .fontColor('#1F2937')
                .lineHeight(22)
                .width('100%')
                .margin({ top: 8 })
            }
            .layoutWeight(1)
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .backgroundColor('#F8FAFD')
            .borderRadius(18)
            .border({ width: 1, color: '#E8ECF3' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 28 })

          if (this.isBusy()) {
            Text('处理中...')
              .fontSize(13)
              .fontColor('#6B7280')
              .margin({ left: 56, top: 12 })
          }

          Blank()
            .height(150)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  private async runPrimaryAction(): Promise<void> {
    if (this.activeInput().trim().length > 0 && !this.isBusy()) {
      this.dismissChatInput();
    }
    if (this.isCloudMode()) {
      await this.onRunCloudPlanner();
      return;
    }
    await this.onSendLocalMessage();
  }

  private async runTaskAction(): Promise<void> {
    if (this.activeInput().trim().length > 0 && !this.isBusy()) {
      this.dismissChatInput();
    }
    if (this.isCloudMode()) {
      await this.onSubmitCloudTask();
      return;
    }
    await this.onSubmitLocalTask();
  }

  private dismissChatInput(): void {
    try {
      inputMethod.getController().stopInputSession().catch(() => {});
    } catch (e) {
    }

    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
  }

  @Builder ImagePreviewOverlay() {
    if (this.previewImagePath.length > 0) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          Row() {
            Blank()
              .layoutWeight(1)
            Text('关闭')
              .fontSize(14)
              .fontColor(Color.White)
              .height(36)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#33000000')
              .borderRadius(18)
              .onClick(() => {
                this.closeDebugImagePreview();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 28 })

          Image(this.previewImagePath)
            .width('92%')
            .height('78%')
            .objectFit(ImageFit.Contain)
            .borderRadius(18)
            .margin({ top: 24 })
            .backgroundColor(Color.Black)

          Text('调试截图')
            .fontSize(13)
            .fontColor('#E5E7EB')
            .margin({ top: 12 })
            .maxLines(1)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#D9000000')
      .zIndex(90)
    }
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
            .onClick(() => {
              this.onOpenSessionDrawer();
            })
          Row() {
            Text('MobiAgent')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
              .maxLines(1)
              .layoutWeight(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              this.ModeTopTabs()
            }
            .margin({ left: 6 })
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
          if (this.hasConversationContent()) {
            this.ConversationPanel()
          } else {
            this.EmptyWelcome()
          }
        }
        .width('100%')
        .padding({ left: 28, right: 28 })
        .layoutWeight(1)
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
          // Text('语')
          //   .fontSize(18)
          //   .fontWeight(FontWeight.Bold)
          //   .fontColor('#111827')
          //   .width(44)
          //   .height(44)
          //   .textAlign(TextAlign.Center)
          //   .borderRadius(22)
          //   .border({ width: 2, color: '#111827' })
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

      if (this.sessionDrawerOpen) {
        Row() {
          ChatSessionDrawer({
            sessions: this.sessions,
            activeSessionId: this.activeSessionId,
            restoringLocalSession: this.restoringLocalSession,
            onClose: () => { this.onCloseSessionDrawer(); },
            onCreateSession: (mode: string) => { this.onCreateSession(mode); },
            onSelectSession: async (id: string) => { await this.onSelectSession(id); },
            onDeleteSession: async (id: string) => { await this.onDeleteSession(id); }
          })
          Blank()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => {
              this.onCloseSessionDrawer();
            })
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Top)
      }

      this.ImagePreviewOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
