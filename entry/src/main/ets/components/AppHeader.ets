// 跨页面头部组件：保持“数据归家”各 tab 的品牌区和隐私状态样式一致。
@Component
export struct AppHeader {
  title: string = '';
  subtitle: string = '';

  build() {
    Row() {
      Row() {
        Stack() {
          Text('H')
            .fontSize(21)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(50)
        .height(50)
        .backgroundColor('#5968FF')
        .borderRadius(15)
        .shadow({ radius: 12, color: '#365968FF', offsetX: 0, offsetY: 5 })

        Column() {
          Text(this.title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(14)
              .fontColor('#717684')
              .margin({ top: 3 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .layoutWeight(1)

      Row() {
        Text('盾').fontSize(12).fontColor('#8066FF').width(24).height(24).textAlign(TextAlign.Center).borderRadius(12).backgroundColor('#F0ECFF')
        Text('隐私守护中').fontSize(13).fontColor('#6B6F7C').margin({ left: 5, right: 5 }).maxLines(1)
        Text('>').fontSize(16).fontColor('#8B909A')
      }
      .width(118)
    }
    .width('100%')
    .padding({ left: 22, right: 18, top: 24, bottom: 10 })
  }
}
