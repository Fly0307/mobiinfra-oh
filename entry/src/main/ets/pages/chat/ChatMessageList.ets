import {
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  ChatMessage,
  chatMessageRenderKey
} from './ChatSessionTypes';

@Component
export struct ChatMessageList {
  @Prop messages: ChatMessage[] = [];
  @Prop thinking: boolean = false;
  @Prop debugImagePath: string = '';
  @Prop modeLabel: string = '';
  @Prop modeMark: string = '';
  onToggleTaskTrace: (id: string) => void = () => {};
  onPreviewDebugImage: (path: string) => void = () => {};

  private isUserMessage(message: ChatMessage): boolean {
    return message.role === 'user';
  }

  private roleLabel(message: ChatMessage): string {
    if (message.role === 'user') {
      return '你';
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
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT || message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '任';
    }
    return this.modeMark.length > 0 ? this.modeMark : '助';
  }

  private avatarColor(message: ChatMessage): string {
    if (message.role === 'user') {
      return '#111827';
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
    if (message.kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
      return '#ECFDF5';
    }
    if (message.kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
      return '#F5F3FF';
    }
    return '#F8FAFD';
  }

  private textColor(message: ChatMessage): string {
    return this.isUserMessage(message) ? '#FFFFFF' : '#1F2937';
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
      }
      .width('100%')

      Text(message.content)
        .fontSize(15)
        .fontColor(this.textColor(message))
        .lineHeight(22)
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.bubbleColor(message))
    .borderRadius(17)
    .border({
      width: this.isUserMessage(message) ? 0 : 1,
      color: message.kind === CHAT_MESSAGE_KIND_TASK_RESULT ? '#A7F3D0' : '#E8ECF3'
    })
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
          Text(message.content.length > 0 ? message.content : '任务执行过程')
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

  @Builder DebugImagePreview() {
    if (this.debugImagePath.length > 0) {
      Row() {
        Text('调试截图')
          .fontSize(12)
          .fontColor('#6B7280')
        Image(this.debugImagePath)
          .width(86)
          .height(120)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.Black)
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => {
            this.onPreviewDebugImage(this.debugImagePath);
          })
      }
      .width('100%')
      .padding({ left: 44, right: 44, top: 12 })
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Scroll() {
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

        this.DebugImagePreview()

        Blank()
          .height(150)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }
}
