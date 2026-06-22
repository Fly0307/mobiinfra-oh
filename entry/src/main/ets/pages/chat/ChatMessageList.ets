import {
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage,
  chatMessageImagePath,
  chatMessageRenderKey,
  chatMessageThinkingCollapsed,
  chatMessageThinkingContent
} from './ChatSessionTypes';
import { DigitalAvatarView } from './DigitalAvatarView';
import {
  chatAvatarRenderModel,
  digitalAvatarContainerWidth,
  DigitalAvatarVisualState,
  TEXT_AVATAR_SIZE,
  useDigitalAvatarForMessage
} from './DigitalAvatarTypes';
import { MarkdownView, MarkdownViewVariant } from '../../components/MarkdownView';
import { markdownTitleText } from '../../utils/markdown/MarkdownParser';
import { AppLogger } from '../../utils/AppLogger';

const STREAM_FOLLOW_STEP: number = 96;
const STREAM_FOLLOW_DELAY_MS: number = 40;
const STREAM_FOLLOW_ANIMATION_MS: number = 120;
const STRUCTURAL_SCROLL_SETTLE_MS: number = 80;
const BACK_TO_BOTTOM_BUTTON_GAP: number = 12;

@Component
export struct ChatMessageList {
  @Prop messages: ChatMessage[] = [];
  @Prop thinking: boolean = false;
  @Prop @Watch('onAutoScrollKeyChanged') autoScrollKey: string = '';
  @Prop @Watch('onStreamFollowKeyChanged') streamFollowKey: string = '';
  @Prop modeLabel: string = '';
  @Prop modeMark: string = '';
  @Prop avatarForegroundUri: string = '';
  @Prop bottomOverlayInset: number = 122;
  @State autoFollowEnabled: boolean = true;
  @State backToBottomVisible: boolean = false;
  onToggleTaskTrace: (id: string) => void = () => {};
  onToggleThinking: (id: string) => void = () => {};
  onPreviewDebugImage: (path: string) => void = () => {};
  onScrollContent: (yOffset: number) => void = () => {};
  private messageScroller: Scroller = new Scroller();
  private lastAutoScrollKey: string = '';
  private lastStreamFollowKey: string = '';
  private structuralScrollTimerId: number = -1;
  private structuralSettleTimerId: number = -1;
  private streamFollowTimerId: number = -1;

  aboutToAppear(): void {
    this.scheduleScrollToLatest(true);
  }

  aboutToDisappear(): void {
    this.clearScrollTimers();
  }

  private onAutoScrollKeyChanged(): void {
    this.scheduleScrollToLatest(false);
  }

  private onStreamFollowKeyChanged(): void {
    if (this.streamFollowKey === this.lastStreamFollowKey) {
      return;
    }
    this.lastStreamFollowKey = this.streamFollowKey;
    if (!this.autoFollowEnabled) {
      this.markPendingBottomContent('stream-follow-deferred');
      return;
    }
    this.scheduleStreamFollow();
  }

  private clearStructuralScrollTimers(): void {
    if (this.structuralScrollTimerId !== -1) {
      clearTimeout(this.structuralScrollTimerId);
      this.structuralScrollTimerId = -1;
    }
    if (this.structuralSettleTimerId !== -1) {
      clearTimeout(this.structuralSettleTimerId);
      this.structuralSettleTimerId = -1;
    }
  }

  private clearStreamFollowTimer(): void {
    if (this.streamFollowTimerId !== -1) {
      clearTimeout(this.streamFollowTimerId);
      this.streamFollowTimerId = -1;
    }
  }

  private clearScrollTimers(): void {
    this.clearStructuralScrollTimers();
    this.clearStreamFollowTimer();
  }

  private sessionPart(scrollKey: string): string {
    let delimiterIndex = scrollKey.indexOf(':');
    if (delimiterIndex < 0) {
      return scrollKey;
    }
    return scrollKey.substring(0, delimiterIndex);
  }

  private isSessionScopeChanged(previousKey: string, nextKey: string): boolean {
    if (previousKey.length === 0 || nextKey.length === 0) {
      return false;
    }
    return this.sessionPart(previousKey) !== this.sessionPart(nextKey);
  }

  private logScroll(message: string): void {
    AppLogger.info('Chat.Scroll', message + ' autoFollow=' + String(this.autoFollowEnabled) +
      ', showBackButton=' + String(this.backToBottomVisible) +
      ', autoKeyLength=' + String(this.autoScrollKey.length) +
      ', streamKeyLength=' + String(this.streamFollowKey.length));
  }

  private logScrollDebug(message: string): void {
    AppLogger.debug('Chat.Scroll', message + ' autoFollow=' + String(this.autoFollowEnabled) +
      ', showBackButton=' + String(this.backToBottomVisible) +
      ', autoKeyLength=' + String(this.autoScrollKey.length) +
      ', streamKeyLength=' + String(this.streamFollowKey.length));
  }

  private markPendingBottomContent(reason: string): void {
    this.backToBottomVisible = true;
    this.logScroll(reason);
  }

  private scheduleScrollToLatest(force: boolean): void {
    if (!force && this.autoScrollKey === this.lastAutoScrollKey) {
      return;
    }
    let previousKey = this.lastAutoScrollKey;
    this.lastAutoScrollKey = this.autoScrollKey;
    if (force || this.isSessionScopeChanged(previousKey, this.autoScrollKey)) {
      this.autoFollowEnabled = true;
      this.backToBottomVisible = false;
    }
    if (!this.autoFollowEnabled) {
      this.markPendingBottomContent('structural-scroll-deferred');
      return;
    }
    this.clearStructuralScrollTimers();
    this.logScroll(force ? 'structural-scroll-initial' : 'structural-scroll');
    // 消息气泡中有 Markdown/图片等异步布局，保留一次延迟兜底，但先取消旧任务避免流式更新堆积。
    this.structuralScrollTimerId = setTimeout(() => {
      this.structuralScrollTimerId = -1;
      this.scrollToBottomEdge('structural-scroll');
    }, 0);
    this.structuralSettleTimerId = setTimeout(() => {
      this.structuralSettleTimerId = -1;
      this.scrollToBottomEdge('structural-scroll-settle');
    }, STRUCTURAL_SCROLL_SETTLE_MS);
  }

  private scheduleStreamFollow(): void {
    this.clearStreamFollowTimer();
    this.streamFollowTimerId = setTimeout(() => {
      this.streamFollowTimerId = -1;
      this.followStreamingContent();
    }, STREAM_FOLLOW_DELAY_MS);
  }

  private scrollToBottomEdge(reason: string): void {
    if (!this.autoFollowEnabled) {
      this.markPendingBottomContent(reason + '-blocked');
      return;
    }
    try {
      this.messageScroller.scrollEdge(Edge.Bottom);
      this.backToBottomVisible = false;
      this.logScroll(reason + '-edge');
    } catch (e) {
      AppLogger.warnCause('Chat.Scroll', reason + ' failed', e as Error);
    }
  }

  private followStreamingContent(): void {
    if (!this.autoFollowEnabled) {
      this.markPendingBottomContent('stream-follow-skipped');
      return;
    }
    try {
      let offset = this.messageScroller.currentOffset();
      this.messageScroller.scrollTo({
        xOffset: offset.xOffset,
        yOffset: Math.max(0, offset.yOffset + STREAM_FOLLOW_STEP),
        animation: {
          duration: STREAM_FOLLOW_ANIMATION_MS,
          curve: Curve.Smooth,
          canOverScroll: false
        },
        canOverScroll: false
      });
      this.logScrollDebug('stream-follow');
    } catch (e) {
      AppLogger.warnCause('Chat.Scroll', 'stream-follow failed', e as Error);
    }
  }

  private isUserScrollSource(scrollSource: ScrollSource): boolean {
    return scrollSource === ScrollSource.DRAG || scrollSource === ScrollSource.OTHER_USER_INPUT ||
      scrollSource === ScrollSource.SCROLL_BAR || scrollSource === ScrollSource.FLING ||
      scrollSource === ScrollSource.SCROLL_BAR_FLING;
  }

  private onScrollWillMove(_xOffset: number, yOffset: number, _scrollState: ScrollState, scrollSource: ScrollSource): void {
    this.onScrollContent(yOffset);
    if (this.autoFollowEnabled && this.isUserScrollSource(scrollSource) && yOffset > 0) {
      this.autoFollowEnabled = false;
      this.backToBottomVisible = true;
      this.clearScrollTimers();
      this.logScroll('auto-follow-paused');
    }
  }

  private onReachBottom(): void {
    if (!this.autoFollowEnabled || this.backToBottomVisible) {
      this.autoFollowEnabled = true;
      this.backToBottomVisible = false;
      this.logScroll('reach-end');
    }
  }

  private handleBackToBottom(): void {
    this.autoFollowEnabled = true;
    this.backToBottomVisible = false;
    this.clearScrollTimers();
    this.scrollToBottomEdge('back-to-bottom');
  }

  private backToBottomButtonBottomOffset(): number {
    return this.bottomOverlayInset + BACK_TO_BOTTOM_BUTTON_GAP;
  }

  private isUserMessage(message: ChatMessage): boolean {
    return message.role === 'user';
  }

  private roleLabel(message: ChatMessage): string {
    if (message.role === 'user') {
      return '你';
    }
    if (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
      return '上下文';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
      return '任务结果';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '任务过程';
    }
    if (message.role === 'system') {
      return '系统';
    }
    return this.modeLabel.length > 0 ? this.modeLabel : '助手';
  }

  private avatarText(message: ChatMessage): string {
    return chatAvatarRenderModel(message, this.modeMark, 'idle').fallbackText;
  }

  private avatarColor(message: ChatMessage): string {
    return chatAvatarRenderModel(message, this.modeMark, 'idle').fallbackColor;
  }

  private shouldUseDigitalAvatar(message: ChatMessage): boolean {
    return useDigitalAvatarForMessage(message);
  }

  private avatarColumnWidth(message: ChatMessage): number {
    if (this.shouldUseDigitalAvatar(message) && this.avatarForegroundUri.length > 0) {
      return digitalAvatarContainerWidth('message', true);
    }
    return TEXT_AVATAR_SIZE;
  }

  private thinkingAvatarColumnWidth(): number {
    if (this.avatarForegroundUri.length > 0) {
      return digitalAvatarContainerWidth('message', true);
    }
    return TEXT_AVATAR_SIZE;
  }

  private avatarDebugSource(message: ChatMessage): string {
    return 'message id=' + message.id + ', role=' + message.role + ', kind=' + message.kind;
  }

  private thinkingAvatarDebugSource(): string {
    return 'thinking-row modeMark=' + (this.modeMark.length > 0 ? this.modeMark : '助');
  }

  private bubbleColor(message: ChatMessage): string {
    if (this.isUserMessage(message)) {
      return '#111827';
    }
    if (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
      return '#FFFBEB';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
      return '#ECFDF5';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '#F5F3FF';
    }
    return '#F8FAFD';
  }

  private markdownVariant(message: ChatMessage): MarkdownViewVariant {
    return this.isUserMessage(message) ? 'chat_user' : 'chat_assistant';
  }

  private traceTitle(message: ChatMessage): string {
    let title = markdownTitleText(message.content);
    if (title.length > 0) {
      return title;
    }
    return message.content.length > 0 ? message.content : '任务执行过程';
  }

  private toolCallCount(message: ChatMessage): number {
    if (message.role !== 'assistant' || message.kind === CHAT_MESSAGE_KIND_TASK_RESULT ||
      message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return 0;
    }
    return message.trace.length;
  }

  private hasVisibleContent(message: ChatMessage): boolean {
    return message.content.trim().length > 0;
  }

  private formatMessageTime(time: number): string {
    if (time <= 0) {
      return '';
    }
    return new Date(time).toLocaleString();
  }

  @Builder Avatar(message: ChatMessage) {
    this.AvatarWithState(message, 'idle');
  }

  @Builder AvatarWithState(message: ChatMessage, visualState: DigitalAvatarVisualState) {
    if (this.shouldUseDigitalAvatar(message)) {
      DigitalAvatarView({
        avatarForegroundUri: this.avatarForegroundUri,
        fallbackText: this.avatarText(message),
        fallbackColor: this.avatarColor(message),
        visualState: visualState,
        avatarSize: 'message',
        debugSource: this.avatarDebugSource(message)
      })
    } else {
      Text(this.avatarText(message))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(TEXT_AVATAR_SIZE)
        .height(TEXT_AVATAR_SIZE)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.avatarColor(message))
        .borderRadius(13)
    }
  }

  @Builder ThinkingAvatar() {
    DigitalAvatarView({
      avatarForegroundUri: this.avatarForegroundUri,
      fallbackText: this.modeMark.length > 0 ? this.modeMark : '助',
      fallbackColor: '#5968FF',
      visualState: 'thinking',
      avatarSize: 'message',
      debugSource: this.thinkingAvatarDebugSource()
    })
  }

  @Builder ChatBubble(message: ChatMessage) {
    Column() {
      Row() {
        Text(this.roleLabel(message))
          .fontSize(11)
          .fontColor(this.isUserMessage(message) ? '#E5E7EB' : '#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.formatMessageTime(message.createdAt))
          .fontSize(10)
          .fontColor(this.isUserMessage(message) ? '#D1D5DB' : '#9CA3AF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })
      }
      .width('100%')

      this.ToolCallSummary(message)

      this.ThinkingModule(message)

      if (this.hasVisibleContent(message)) {
        MarkdownView({ text: message.content, variant: this.markdownVariant(message) })
          .width('100%')
          .margin({ top: 6 })
      }

      this.MessageImagePreview(message)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.bubbleColor(message))
    .borderRadius(17)
    .border({
      width: this.isUserMessage(message) ? 0 : 1,
      color: message.kind === CHAT_MESSAGE_KIND_TASK_RESULT ? '#A7F3D0' :
        (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE ? '#FDE68A' : '#E8ECF3')
    })
  }

  @Builder ToolCallSummary(message: ChatMessage) {
    if (this.toolCallCount(message) > 0) {
      Text('已执行 ' + String(this.toolCallCount(message)) + ' 次工具调用')
        .fontSize(12)
        .fontColor('#9CA3AF')
        .lineHeight(18)
        .width('100%')
        .margin({ top: 6 })
    }
  }

  @Builder ThinkingModule(message: ChatMessage) {
    if (message.role === 'assistant' && chatMessageThinkingContent(message).length > 0) {
      Column() {
        Row() {
          Text(chatMessageThinkingCollapsed(message) ? '▶' : '▼')
            .fontSize(11)
            .fontColor('#6B7280')
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
          Column() {
            Text('Think 思考过程')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#4B5563')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(chatMessageThinkingCollapsed(message) ? '已折叠，点击查看' : '点击收起')
              .fontSize(10)
              .fontColor('#8B95A5')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!chatMessageThinkingCollapsed(message)) {
          Text(chatMessageThinkingContent(message))
            .fontSize(12)
            .fontColor('#4B5563')
            .lineHeight(18)
            .width('100%')
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .margin({ top: 8 })
      .backgroundColor('#F3F4F6')
      .borderRadius(12)
      .border({ width: 1, color: '#E5E7EB' })
      .onClick(() => {
        this.onToggleThinking(message.id);
      })
    }
  }

  @Builder MessageImagePreview(message: ChatMessage) {
    if (chatMessageImagePath(message).length > 0) {
      Image(chatMessageImagePath(message))
        .width(96)
        .height(132)
        .objectFit(ImageFit.Contain)
        .backgroundColor(Color.Black)
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.onPreviewDebugImage(chatMessageImagePath(message));
        })
    }
  }

  @Builder TraceBubble(message: ChatMessage) {
    Column() {
      Row() {
        Text(message.collapsed ? '▶' : '▼')
          .fontSize(12)
          .fontColor('#7C3AED')
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
        Column() {
          Text(this.traceTitle(message))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4C1D95')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(String(message.trace.length) + ' 步操作')
            .fontSize(11)
            .fontColor('#7C3AED')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!message.collapsed) {
        Column() {
          if (message.trace.length === 0) {
            Text('暂无步骤')
              .fontSize(12)
              .fontColor('#8B5CF6')
              .width('100%')
          } else {
            ForEach(message.trace, (line: string, index?: number) => {
              Row() {
                Text(String((index === undefined ? 0 : index) + 1))
                  .fontSize(10)
                  .fontColor('#8B5CF6')
                  .width(28)
                Text(line)
                  .fontSize(12)
                  .fontColor('#4B5563')
                  .lineHeight(18)
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ top: 8 })
            }, (line: string, index?: number) => String(index === undefined ? 0 : index) + line)
          }
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.bubbleColor(message))
    .borderRadius(17)
    .border({ width: 1, color: '#DDD6FE' })
    .onClick(() => {
      this.onToggleTaskTrace(message.id);
    })
  }

  @Builder MessageRow(message: ChatMessage) {
    Row() {
      if (this.isUserMessage(message)) {
        Blank()
          .layoutWeight(1)
        Column() {
          this.ChatBubble(message)
        }
        .width('78%')
        Column() {
          this.Avatar(message)
        }
        .width(TEXT_AVATAR_SIZE)
        .margin({ left: 10 })
      } else {
        if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
          Column() {
            this.Avatar(message)
          }
          .width(this.avatarColumnWidth(message))
          .margin({ right: 10 })
          .onClick(() => {
            this.onToggleTaskTrace(message.id);
          })
        } else {
          Column() {
            this.Avatar(message)
          }
          .width(this.avatarColumnWidth(message))
          .margin({ right: 10 })
        }
        Column() {
          if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
            this.TraceBubble(message)
          } else {
            this.ChatBubble(message)
          }
        }
        .width('78%')
        Blank()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 14 })
  }

  @Builder BackToBottomButton() {
    Text('↓ 回到底部')
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .height(34)
      .padding({ left: 14, right: 14 })
      .backgroundColor('#111827')
      .borderRadius(17)
      .shadow({ radius: 10, color: '#24000000', offsetX: 0, offsetY: 3 })
      .margin({ right: 4, bottom: this.backToBottomButtonBottomOffset() })
      .onClick(() => {
        this.handleBackToBottom();
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll(this.messageScroller) {
        Column() {
          ForEach(this.messages, (message: ChatMessage) => {
            this.MessageRow(message)
          }, (message: ChatMessage) => chatMessageRenderKey(message))

          if (this.thinking) {
            Row() {
              Column() {
                this.ThinkingAvatar()
              }
              .width(this.thinkingAvatarColumnWidth())
                .margin({ right: 10 })
              Text('处理中...')
                .fontSize(13)
                .fontColor('#6B7280')
                .height(36)
                .padding({ left: 14, right: 14 })
                .backgroundColor('#F8FAFD')
                .borderRadius(18)
                .border({ width: 1, color: '#E8ECF3' })
              Blank()
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 14 })
          }

          Blank()
            .height(150)
        }
        .width('100%')
      }
      .onWillScroll((xOffset: number, yOffset: number, scrollState: ScrollState, scrollSource: ScrollSource) => {
        this.onScrollWillMove(xOffset, yOffset, scrollState, scrollSource);
      })
      .onReachEnd(() => {
        this.onReachBottom();
      })
      .height('100%')
      .width('100%')
      if (this.backToBottomVisible) {
        this.BackToBottomButton()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }
}
