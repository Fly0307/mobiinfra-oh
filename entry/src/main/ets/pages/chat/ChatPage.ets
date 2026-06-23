import { inputMethod } from '@kit.IMEKit';
import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatComposerBarHeight,
  chatComposerTextAreaHeight,
  chatDeepThinkingToggleVisible,
  chatModeLabel,
  chatModePlaceholder,
  chatTimeGreeting
} from './ChatPageTypes';
import {
  chatAttachmentComposerExtraHeight,
  chatAttachmentPreviewHeight,
  chatCanSendMessage,
  hasChatImageAttachment
} from './ChatAttachmentPolicy';
import {
  ChatMessage,
  ChatSessionSummary,
  chatMessagesAutoScrollKey,
  chatMessagesStreamFollowKey
} from './ChatSessionTypes';
import { ChatMessageList } from './ChatMessageList';
import { ChatSessionDrawer } from './ChatSessionDrawer';
import { DigitalAvatarView } from './DigitalAvatarView';
import { digitalAvatarContainerHeight } from './DigitalAvatarTypes';

@Component
export struct ChatPage {
  @Link chatMode: string;
  @Link cloudUserInput: string;
  @Link userInput: string;
  @Link chatDeepThinkingEnabled: boolean;
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
  @Prop avatarMessageForegroundUri: string = '';
  @Prop pendingImageAttachmentUri: string = '';
  @Prop sessionDrawerOpen: boolean = false;
  @Prop restoringLocalSession: boolean = false;
  onSwitchMode: (mode: string) => Promise<void> = async () => {};
  onOpenSessionDrawer: () => void = () => {};
  onCloseSessionDrawer: () => void = () => {};
  onCreateSession: (mode: string) => void = () => {};
  onSelectSession: (id: string) => Promise<void> = async () => {};
  onDeleteSession: (id: string) => Promise<void> = async () => {};
  onToggleTaskTrace: (id: string) => void = () => {};
  onToggleThinking: (id: string) => void = () => {};
  onRunCloudPlanner: () => Promise<void> = async () => {};
  onCancelCloudChat: () => void = () => {};
  onSubmitCloudTask: () => Promise<void> = async () => {};
  onSendLocalMessage: () => Promise<void> = async () => {};
  onSubmitLocalTask: () => Promise<void> = async () => {};
  onPickImageAttachment: () => Promise<void> = async () => {};
  onClearImageAttachment: () => void = () => {};
  onClearCloudDebugImage: () => void = () => {};
  onClearLocalDebugImage: () => void = () => {};
  onOpenRuntimeLogs: () => void = () => {};

  private isCloudMode(): boolean {
    return this.chatMode !== CHAT_MODE_LOCAL_INFERENCE;
  }

  private activeInput(): string {
    return this.isCloudMode() ? this.cloudUserInput : this.userInput;
  }

  private composerBarHeight(): number {
    return chatComposerBarHeight(this.activeInput());
  }

  private composerTextAreaHeight(): number {
    return chatComposerTextAreaHeight(this.activeInput());
  }

  private attachmentComposerExtraHeight(): number {
    return chatAttachmentComposerExtraHeight(this.composerTextAreaHeight(), this.pendingImageAttachmentUri);
  }

  private attachmentPreviewHeight(): number {
    return chatAttachmentPreviewHeight(this.composerTextAreaHeight());
  }

  private bottomOverlayInset(): number {
    return this.composerBarHeight() + this.attachmentComposerExtraHeight() + 64;
  }

  private welcomeGreeting(): string {
    return chatTimeGreeting(new Date().getHours());
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

  private primaryButtonText(): string {
    if (this.isCloudMode() && this.cloudThinking) {
      return '停止';
    }
    return this.isBusy() ? '...' : '发送';
  }

  private toggleDeepThinking(): void {
    // Think 开关只影响下一次默认云端模型聊天请求；处理中保持当前请求参数不变。
    if (this.isBusy()) {
      return;
    }
    this.chatDeepThinkingEnabled = !this.chatDeepThinkingEnabled;
  }

  private hasConversationContent(): boolean {
    return this.messages.length > 0 || this.isBusy();
  }

  private hasPendingImageAttachment(): boolean {
    return hasChatImageAttachment(this.pendingImageAttachmentUri);
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

  @Builder WelcomeActionIcon(kind: string) {
    // 欢迎态功能卡使用 ASCII 命名资源，避免在 ArkTS 中直接引用中文资源名。
    Stack({ alignContent: Alignment.Center }) {
      if (kind === 'image') {
        Image($r('app.media.chat_card_image'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      } else if (kind === 'flow') {
        Image($r('app.media.chat_card_flow'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      } else {
        Image($r('app.media.chat_card_search'))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      }
    }
    .width(38)
    .height(38)
    .backgroundColor('#F2F5FF')
    .borderRadius(14)
  }

  @Builder WelcomeActionCard(kind: string, title: string, desc: string, task: string) {
    Row() {
      this.WelcomeActionIcon(kind)
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(desc)
          .fontSize(11)
          .fontColor('#7B8392')
          .width('100%')
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .height(58)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 3 })
    .margin({ bottom: 8 })
    .onClick(() => {
      this.setActiveInput(task);
    })
  }

  @Builder WelcomeAvatarHero() {
    Row() {
      DigitalAvatarView({
        avatarForegroundUri: this.avatarForegroundUri,
        fallbackText: 'H',
        fallbackColor: '#5968FF',
        visualState: 'idle',
        avatarSize: 'hero',
        debugSource: 'welcome-hero mode=' + this.chatMode
      })
      .margin({ left: 8 })
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .height(this.avatarForegroundUri.length > 0 ? digitalAvatarContainerHeight('hero', true) + 8 : 118)
    .alignItems(VerticalAlign.Bottom)
    .margin({ top: 0 })
  }

  @Builder EmptyWelcome() {
    Scroll() {
      Column() {
        this.WelcomeAvatarHero()

        Text(this.welcomeGreeting())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .width('100%')
          .margin({ top: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('我可以帮你整理信息、执行任务')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#6F7787')
          .width('100%')
          .margin({ top: 8 })
          .maxLines(2)
          .lineHeight(22)

        Column() {
          this.WelcomeActionCard('image', '整理今天截图里的关键信息', '从图片和聊天里提取重点', '整理今天截图里的关键信息')
          this.WelcomeActionCard('flow', '规划一个自动化 workflow', '拆解步骤并生成执行计划', '规划一个收集微信聊天记录的 workflow')
          this.WelcomeActionCard('search', '淘宝搜索耳机比价', '帮你比较价格和参数', '淘宝搜索耳机比价')
        }
        .width('100%')
        .margin({ top: 14 })

        Blank()
          .height(this.bottomOverlayInset())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
        autoScrollKey: chatMessagesAutoScrollKey(this.activeSessionId, this.messages, this.isBusy()),
        streamFollowKey: chatMessagesStreamFollowKey(this.activeSessionId, this.messages, this.isBusy()),
        modeLabel: chatModeLabel(this.chatMode),
        modeMark: this.isCloudMode() ? '云' : '本',
        avatarForegroundUri: this.avatarForegroundUri,
        avatarMessageForegroundUri: this.avatarMessageForegroundUri,
        bottomOverlayInset: this.bottomOverlayInset(),
        onToggleTaskTrace: (id: string) => { this.onToggleTaskTrace(id); },
        onToggleThinking: (id: string) => { this.onToggleThinking(id); },
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
            .height(this.bottomOverlayInset())
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  private async runPrimaryAction(): Promise<void> {
    if (this.isBusy()) {
      if (this.isCloudMode()) {
        this.onCancelCloudChat();
      }
      return;
    }
    if (!chatCanSendMessage(this.activeInput(), this.pendingImageAttachmentUri)) {
      return;
    }
    if (!this.isBusy()) {
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

  @Builder PendingImageAttachmentPreview() {
    if (this.hasPendingImageAttachment()) {
      Row() {
        Image(this.pendingImageAttachmentUri)
          .width(this.attachmentPreviewHeight() * 0.9)
          .height(this.attachmentPreviewHeight())
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .backgroundColor('#F3F4F6')
        Column() {
          Text('图片附件')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .maxLines(1)
          Text('将随下一条消息发送')
            .fontSize(10)
            .fontColor('#7B8392')
            .margin({ top: 2 })
            .maxLines(1)
        }
        .layoutWeight(1)
        .margin({ left: 10 })
        .alignItems(HorizontalAlign.Start)
        Text('×')
          .fontSize(18)
          .fontColor('#6B7280')
          .width(this.attachmentPreviewHeight() * 0.72)
          .height(this.attachmentPreviewHeight() * 0.72)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F3F4F6')
          .borderRadius(this.attachmentPreviewHeight() * 0.36)
          .onClick(() => {
            this.onClearImageAttachment();
          })
      }
      .width('100%')
      .height(this.attachmentPreviewHeight())
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8 })
      .margin({ left: 22, right: 22, bottom: Math.round(this.composerTextAreaHeight() * 0.18) })
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 10, color: '#12000000', offsetX: 0, offsetY: 3 })
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
      .backgroundColor(this.hasConversationContent() ? Color.White : '#F4F8FF')

      Column() {
        this.PendingImageAttachmentPreview()

        Row() {
          if (chatDeepThinkingToggleVisible(this.chatMode)) {
            Text(this.chatDeepThinkingEnabled ? '深度思考 开' : '深度思考 关')
              .fontSize(12)
              .fontColor(this.chatDeepThinkingEnabled ? '#FFFFFF' : '#222222')
              .height(34)
              .padding({ left: 13, right: 13 })
              .backgroundColor(this.chatDeepThinkingEnabled ? '#111827' : Color.White)
              .borderRadius(17)
              .border({ width: 1, color: this.chatDeepThinkingEnabled ? '#111827' : '#E2E5EA' })
              .opacity(this.isBusy() ? 0.6 : 1)
              .onClick(() => { this.toggleDeepThinking(); })
          }
          Text('下发任务')
            .fontSize(12)
            .fontColor('#222222')
            .height(34)
            .padding({ left: 13, right: 13 })
            .backgroundColor(Color.White)
            .borderRadius(17)
            .border({ width: 1, color: '#E2E5EA' })
            .margin({ left: chatDeepThinkingToggleVisible(this.chatMode) ? 10 : 0 })
            .onClick(async () => { await this.runTaskAction(); })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 8 })

        Row() {
          Text('+')
            .fontSize(30)
            .fontColor('#111827')
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .backgroundColor(Color.White)
            .borderRadius(20)
            .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 2 })
            .onClick(async () => { await this.onPickImageAttachment(); })
          TextArea({ placeholder: chatModePlaceholder(this.chatMode), text: this.activeInput() })
            .layoutWeight(1)
            .height(this.composerTextAreaHeight())
            .fontSize(15)
            .lineHeight(20)
            .fontColor('#4B5563')
            .backgroundColor('#00FFFFFF')
            .padding({ left: 14, right: 12, top: 8, bottom: 8 })
            .margin({ left: 8 })
            .onChange((value: string) => { this.setActiveInput(value); })
          Button(this.primaryButtonText())
            .width(68)
            .height(40)
            .fontSize(14)
            .backgroundColor(this.isBusy() ? '#AEB7C8' : '#111827')
            .borderRadius(20)
            .onClick(async () => { await this.runPrimaryAction(); })
        }
        .width('100%')
        .height(this.composerBarHeight())
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12 })
        .backgroundColor(Color.White)
        .borderRadius(26)
        .shadow({ radius: 14, color: '#20000000', offsetX: 0, offsetY: 5 })
        .margin({ left: 20, right: 20, bottom: 22 })
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
