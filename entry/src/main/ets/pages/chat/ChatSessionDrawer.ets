import {
  CHAT_MODE_CLOUD_AGENT,
  CHAT_MODE_LOCAL_INFERENCE,
  chatModeLabel
} from './ChatPageTypes';
import { ChatSessionSummary } from './ChatSessionTypes';

@Component
export struct ChatSessionDrawer {
  @Prop sessions: ChatSessionSummary[] = [];
  @Prop activeSessionId: string = '';
  @Prop restoringLocalSession: boolean = false;
  onClose: () => void = () => {};
  onCreateSession: (mode: string) => void = () => {};
  onSelectSession: (id: string) => Promise<void> = async () => {};
  onDeleteSession: (id: string) => Promise<void> = async () => {};

  private sessionCount(mode: string): number {
    let count = 0;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].mode === mode) {
        count++;
      }
    }
    return count;
  }

  private formatSessionTime(time: number): string {
    if (time <= 0) {
      return '未知时间';
    }
    return new Date(time).toLocaleString();
  }

  @Builder NewSessionButton(mode: string) {
    Text('+ ' + chatModeLabel(mode))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#111827')
      .height(36)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#F4F6FA')
      .borderRadius(18)
      .border({ width: 1, color: '#E7EAF0' })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onCreateSession(mode);
      })
  }

  @Builder SessionItem(session: ChatSessionSummary) {
    Row() {
      Column() {
        Row() {
          Text(session.mode === CHAT_MODE_LOCAL_INFERENCE ? '本' : '云')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .backgroundColor(session.mode === CHAT_MODE_LOCAL_INFERENCE ? '#111827' : '#5968FF')
            .borderRadius(9)
          Text(session.title)
            .fontSize(15)
            .fontWeight(this.activeSessionId === session.id ? FontWeight.Bold : FontWeight.Medium)
            .fontColor('#111827')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(session.lastMessagePreview)
          .fontSize(12)
          .fontColor('#6B7280')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })

        Text(String(session.messageCount) + ' 条消息 · ' + this.formatSessionTime(session.updatedAt))
          .fontSize(11)
          .fontColor('#9CA3AF')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .onClick(async () => {
        await this.onSelectSession(session.id);
      })

      Text('删')
        .fontSize(12)
        .fontColor('#EF4444')
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .backgroundColor('#FFF1F2')
        .borderRadius(17)
        .margin({ left: 10 })
        .onClick(async () => {
          await this.onDeleteSession(session.id);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.activeSessionId === session.id ? '#EEF2FF' : Color.White)
    .borderRadius(16)
    .border({ width: 1, color: this.activeSessionId === session.id ? '#C7D2FE' : '#EDF0F5' })
    .margin({ bottom: 10 })
  }

  @Builder SessionSection(mode: string) {
    Column() {
      Row() {
        Text(chatModeLabel(mode))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#374151')
        Text(String(this.sessionCount(mode)))
          .fontSize(11)
          .fontColor('#6B7280')
          .height(22)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#F3F4F6')
          .borderRadius(11)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 10 })

      ForEach(this.sessions, (session: ChatSessionSummary) => {
        if (session.mode === mode) {
          this.SessionItem(session)
        }
      }, (session: ChatSessionSummary) => session.id)

      if (this.sessionCount(mode) === 0) {
        Text('暂无' + chatModeLabel(mode) + '会话')
          .fontSize(12)
          .fontColor('#9CA3AF')
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 16 })
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('历史会话')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text(this.restoringLocalSession ? '正在恢复本地上下文' : '选择会话后由上层恢复上下文')
            .fontSize(12)
            .fontColor(this.restoringLocalSession ? '#5968FF' : '#6B7280')
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('×')
          .fontSize(24)
          .fontColor('#4B5563')
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor('#F4F6FA')
          .borderRadius(20)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap }) {
        this.NewSessionButton(CHAT_MODE_CLOUD_AGENT)
        this.NewSessionButton(CHAT_MODE_LOCAL_INFERENCE)
      }
      .width('100%')
      .margin({ top: 18 })

      Scroll() {
        Column() {
          this.SessionSection(CHAT_MODE_CLOUD_AGENT)
          this.SessionSection(CHAT_MODE_LOCAL_INFERENCE)
          Blank()
            .height(28)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 4 })
    }
    .width(320)
    .height('100%')
    .padding({ left: 18, right: 18, top: 26, bottom: 20 })
    .backgroundColor('#FFFFFF')
    .shadow({ radius: 20, color: '#26000000', offsetX: 5, offsetY: 0 })
  }
}
