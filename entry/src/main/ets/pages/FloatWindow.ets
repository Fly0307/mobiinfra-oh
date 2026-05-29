import { AgentExecutionController } from '../utils/AgentExecutionController';

// 后台浮窗页面：展示 AppStorage.floatText 中的实时模型输出/Agent 状态，
// 并提供“终止”入口通知 AgentExecutionController 请求取消当前任务。
@Entry
@Component
struct FloatWindow {
  @StorageLink('floatText') @Watch('onTextChange') floatText: string = 'AI Agent 运行中...'
  private scroller: Scroller = new Scroller()

  onTextChange(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 50)
  }

  build() {
    Row() {
      Column() {
        Scroll(this.scroller) {
          Text(this.floatText)
            .width('100%')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F8FAFC')
            .padding({ left: 4, right: 2, top: 2, bottom: 2 })
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .height('100%')
        .scrollable(ScrollDirection.Vertical)
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor('#66111827')
      .borderRadius(8)

      Text('终止')
        .width(34)
        .height('100%')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E2E8F0')
        .textAlign(TextAlign.Center)
        .backgroundColor('#7A1E293B')
        .borderRadius(8)
        .padding({ left: 2, right: 2 })
        .onClick(() => {
          AgentExecutionController.requestCancellation();
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#8010202F')
    .borderRadius(10)
  }
}
