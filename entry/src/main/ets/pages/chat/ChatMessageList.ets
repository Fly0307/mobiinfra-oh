import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  CHAT_MESSAGE_KIND_CONTEXT_NOTICE,
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage,
  chatMessageCopyContent,
  chatMessageImagePath,
  chatMessageThinkingCollapsed,
  chatMessageThinkingContent,
  chatMessageRenderKey
} from './ChatSessionTypes';
import { MarkdownView, MarkdownViewVariant } from '../../components/MarkdownView';
import { AppLogger } from '../../utils/AppLogger';
import { markdownTitleText } from '../../utils/markdown/MarkdownParser';

@Component
export struct ChatMessageList {
  @Prop messages: ChatMessage[] = [];
  @Prop thinking: boolean = false;
  @Prop @Watch('onAutoScrollKeyChanged') autoScrollKey: string = '';
  @Prop modeLabel: string = '';
  @Prop modeMark: string = '';
  onToggleTaskTrace: (id: string) => void = () => {};
  onToggleThinking: (id: string) => void = () => {};
  onPreviewDebugImage: (path: string) => void = () => {};
  onScrollContent: (yOffset: number) => void = () => {};
  private messageScroller: Scroller = new Scroller();
  private lastAutoScrollKey: string = '';

  aboutToAppear(): void {
    this.scheduleScrollToLatest(true);
  }

  private onAutoScrollKeyChanged(): void {
    this.scheduleScrollToLatest(false);
  }

  private scheduleScrollToLatest(force: boolean): void {
    if (!force && this.autoScrollKey === this.lastAutoScrollKey) {
      return;
    }
    this.lastAutoScrollKey = this.autoScrollKey;
    // 消息气泡中有 Markdown/图片等异步布局，延迟两次滚动确保切换会话时落到底部。
    setTimeout(() => {
      this.messageScroller.scrollEdge(Edge.Bottom);
    }, 0);
    setTimeout(() => {
      this.messageScroller.scrollEdge(Edge.Bottom);
    }, 80);
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
    if (message.role === 'user') {
      return '我';
    }
    if (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
      return '压';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT || message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '任';
    }
    return this.modeMark.length > 0 ? this.modeMark : '助';
  }

  private avatarColor(message: ChatMessage): string {
    if (message.role === 'user') {
      return '#111827';
    }
    if (message.kind === CHAT_MESSAGE_KIND_CONTEXT_NOTICE) {
      return '#F59E0B';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
      return '#059669';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '#7C3AED';
    }
    return '#5968FF';
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

  private async copyMessageContent(message: ChatMessage): Promise<void> {
    let content = chatMessageCopyContent(message).trim();
    if (content.length === 0) {
      promptAction.showToast({ message: '暂无可复制内容', duration: 1200 });
      return;
    }
    try {
      let pb = pasteboard.getSystemPasteboard();
      await pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content));
      promptAction.showToast({ message: '已复制消息', duration: 1200 });
    } catch (e) {
      AppLogger.warnCause('ChatMessageList', 'copy message content failed', e as Error);
      promptAction.showToast({ message: '复制失败', duration: 1200 });
    }
  }

  private formatMessageTime(time: number): string {
    if (time <= 0) {
      return '';
    }
    return new Date(time).toLocaleString();
  }

  @Builder Avatar(message: ChatMessage) {
    Text(this.avatarText(message))
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(34)
      .height(34)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.avatarColor(message))
      .borderRadius(13)
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
        Blank()
          .layoutWeight(1)
        if (this.hasVisibleContent(message)) {
          Text('复制')
            .fontSize(10)
            .fontColor(this.isUserMessage(message) ? '#DBEAFE' : '#5968FF')
            .height(22)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.isUserMessage(message) ? '#273449' : '#EEF2FF')
            .borderRadius(11)
            .onClick(async () => {
              await this.copyMessageContent(message);
            })
        }
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
        .width(34)
        .margin({ left: 10 })
      } else {
        Column() {
          this.Avatar(message)
        }
        .width(34)
        .margin({ right: 10 })
        .onClick(() => {
          if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
            this.onToggleTaskTrace(message.id);
          }
        })
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

  build() {
    Scroll(this.messageScroller) {
      Column() {
        ForEach(this.messages, (message: ChatMessage) => {
          this.MessageRow(message)
        }, (message: ChatMessage) => chatMessageRenderKey(message))

        if (this.thinking) {
          Row() {
            Text(this.modeMark.length > 0 ? this.modeMark : '助')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(34)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor('#5968FF')
              .borderRadius(13)
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
    .onScroll((_xOffset: number, yOffset: number) => {
      this.onScrollContent(yOffset);
    })
    .layoutWeight(1)
    .width('100%')
  }
}
