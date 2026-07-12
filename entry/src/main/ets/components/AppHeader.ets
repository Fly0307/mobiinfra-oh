// 跨页面头部组件：保持 ClawMate 各 tab 的品牌区和隐私状态样式一致。
@Component
export struct AppHeader {
  title: string = '';
  subtitle: string = '';
  icon: Resource = $r('app.media.header_companion');

  build() {
    Row() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Image(this.icon)
            .width(36)
            .height(36)
            .objectFit(ImageFit.Contain)
        }
        .width(40)
        .height(40)

        Column() {
          Text(this.title)
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172033')
            .lineHeight(32)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(14)
              .fontColor('#717684')
              .lineHeight(18)
              .margin({ top: 3 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .height(this.subtitle.length > 0 ? 52 : 40)
        .margin({ left: 9 })
      }
      .height(52)
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)

      Row() {
        Text('盾').fontSize(12).fontColor('#8066FF').width(24).height(24).textAlign(TextAlign.Center).borderRadius(12).backgroundColor('#F0ECFF')
        Text('隐私守护中').fontSize(13).fontColor('#6B6F7C').margin({ left: 5, right: 5 }).maxLines(1)
        Text('>').fontSize(16).fontColor('#8B909A')
      }
      .width(118)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 22, right: 18, top: 24, bottom: 10 })
  }
}
