@Entry
@Component
struct FloatWindow {
  build() {
    Row() {
      Column() {
        Text('AI Agent 运行中...')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000') // Semi-transparent black
    .borderRadius(10)
  }
}
