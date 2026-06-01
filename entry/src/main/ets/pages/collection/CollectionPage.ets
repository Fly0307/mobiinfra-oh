import { AppHeader } from '../../components/AppHeader';
import { promptAction, router } from '@kit.ArkUI';

@Component
export struct CollectionPage {
  @Link collectionModule: number;

  private getCollectionTitle(): string {
    if (this.collectionModule === 0) {
      return '最近聊天';
    }
    if (this.collectionModule === 2) {
      return '最近通知';
    }
    if (this.collectionModule === 3) {
      return '娱乐记录';
    }
    return '最近订单';
  }

  private getCollectionCount(): string {
    if (this.collectionModule === 0) {
      return '12 条';
    }
    if (this.collectionModule === 2) {
      return '36 条';
    }
    if (this.collectionModule === 3) {
      return '8 条';
    }
    return '24 条';
  }

  private getCollectionSyncTime(): string {
    if (this.collectionModule === 0) {
      return '3 分钟前';
    }
    if (this.collectionModule === 2) {
      return '刚刚';
    }
    if (this.collectionModule === 3) {
      return '昨天 22:10';
    }
    return '10 分钟前';
  }

  @Builder CollectTab(label: string, icon: string, index: number) {
    Row() {
      Text(icon).fontSize(11).fontColor(this.collectionModule === index ? Color.White : '#596071').fontWeight(FontWeight.Bold)
      Text(label).fontSize(14).fontWeight(this.collectionModule === index ? FontWeight.Bold : FontWeight.Regular).fontColor(this.collectionModule === index ? Color.White : '#596071').margin({ left: 5 }).maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height(48)
    .backgroundColor(this.collectionModule === index ? '#8066FF' : '#00FFFFFF')
    .borderRadius(24)
    .onClick(() => {
      this.collectionModule = index;
    })
  }

  @Builder OrderRow(image: Resource, title: string, source: string, time: string, price: string) {
    Row() {
      Image(image).width(58).height(58).objectFit(ImageFit.Cover).borderRadius(11)
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(source).fontSize(12).fontColor('#7C8494').margin({ top: 5 }).maxLines(1)
        Text(time).fontSize(12).fontColor('#7C8494').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12, right: 8 })
      Column() {
        Text(price).fontSize(13).fontColor('#161B28').maxLines(1)
        Text('已完成').fontSize(12).fontColor('#35C487').margin({ top: 6 }).maxLines(1)
      }.alignItems(HorizontalAlign.End)
      Text('>').fontSize(18).fontColor('#9AA0AA').margin({ left: 7 })
    }.width('100%').padding({ top: 10, bottom: 10 })
  }

  @Builder CollectionRows() {
    if (this.collectionModule === 0) {
      this.OrderRow($r('app.media.rec_food'), '和妈妈的晚餐计划', '微信聊天', '今天 08:12', '12 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '周末出游讨论', '家庭群', '昨天 21:45', '8 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_sport'), '运动打卡提醒', '好友聊天', '昨天 19:30', '5 条')
    } else if (this.collectionModule === 2) {
      this.OrderRow($r('app.media.rec_travel'), '航班价格提醒', '系统通知', '今天 09:05', '已收录')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '外卖配送更新', '生活服务', '今天 08:40', '已收录')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_sport'), '健康步数摘要', '运动健康', '昨天 22:00', '已收录')
    } else if (this.collectionModule === 3) {
      this.OrderRow($r('app.media.rec_sport'), '晚间瑜伽课程', '视频记录', '昨天 20:30', '42 分钟')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '露营路线收藏', '短视频收藏', '周六 10:12', '3 条')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '轻食探店视频', '兴趣推荐', '周五 18:20', '6 条')
    } else {
      this.OrderRow($r('app.media.rec_sport'), '无线耳机 Pro 2', '京东商城', '05-20 10:23', '¥ 1299.00')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_food'), '馥芮白咖啡 12瓶装', '天猫超市', '05-19 16:45', '¥ 59.90')
      Divider().color('#EEF0F5')
      this.OrderRow($r('app.media.rec_travel'), '纯棉基础T恤', '优衣库官方旗舰店', '05-18 09:12', '¥ 99.00')
    }
  }

  @Builder PreferenceLine(color: string, name: string, value: string, widthValue: string) {
    Row() {
      Row().width(7).height(7).backgroundColor(color).borderRadius(4)
      Text(name).fontSize(12).fontColor('#4C5260').width(66).margin({ left: 6 }).maxLines(1)
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(4).backgroundColor('#F0F1F6').borderRadius(3)
        Row().width(widthValue).height(4).backgroundColor(color).borderRadius(3)
      }.layoutWeight(1).height(5)
      Text(value).fontSize(12).fontColor('#7A808C').width(36).textAlign(TextAlign.End)
    }.width('100%').margin({ bottom: 12 })
  }

  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '数据采集', subtitle: '按模块查看已采集内容' })

        Row() {
          this.CollectTab('聊天', 'C', 0)
          this.CollectTab('购物', 'B', 1)
          this.CollectTab('通知', 'N', 2)
          this.CollectTab('娱乐', 'V', 3)
        }
        .width('86%')
        .height(56)
        .padding({ left: 4, right: 4 })
        .backgroundColor('#EFFFFFFF')
        .borderRadius(28)
        .margin({ top: 24 })
        .shadow({ radius: 12, color: '#0C000000', offsetX: 0, offsetY: 6 })

        Row() {
          Column() {
            Text('今日新增').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionCount()).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#8066FF').margin({ top: 3 }).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Divider().vertical(true).height(44).color('#E7E9F0')
          Column() {
            Text('最近同步').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionSyncTime()).fontSize(16).fontColor('#151A28').margin({ top: 5 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding({ left: 18, right: 10 })
          Text('同步')
            .fontSize(12)
            .fontColor('#8066FF')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor('#F0ECFF')
            .borderRadius(22)
            .onClick(() => {
              promptAction.showToast({ message: '已刷新采集数据', duration: 1200 });
            })
        }
        .width('86%')
        .height(82)
        .padding({ left: 22, right: 16 })
        .backgroundColor('#F8FAFE')
        .borderRadius(16)
        .margin({ top: 22 })

        Column() {
          Row() {
            Text(this.getCollectionTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1)
            Text('查看全部 >').fontSize(13).fontColor('#7F8592')
          }.width('100%').margin({ bottom: 8 })
          this.CollectionRows()
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: 22 })

        Column() {
          Row() {
            Text('消费偏好').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1)
            Text('近30天').fontSize(13).fontColor('#7F8592')
          }.width('100%')
          Row() {
            Stack() {
              Progress({ value: 72, total: 100, type: ProgressType.Ring }).width(112).height(112).color('#8066FF').backgroundColor('#EDF0F8')
              Column() {
                Text('主要品类').fontSize(12).fontColor('#4C5260')
                Text('分布').fontSize(12).fontColor('#4C5260').margin({ top: 3 })
              }
            }.width(120).height(132)
            Column() {
              this.PreferenceLine('#8066FF', '数码家电', '42%', '78%')
              this.PreferenceLine('#5B8DFF', '食品饮料', '28%', '60%')
              this.PreferenceLine('#FFB14B', '服饰鞋包', '18%', '42%')
              this.PreferenceLine('#42C995', '美妆个护', '12%', '28%')
            }.layoutWeight(1).margin({ left: 12 })
          }.width('100%').margin({ top: 16 })
          Row() {
            Text('AI').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#8066FF')
            Text('你在数码和食品品类的消费较多').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#6D62F5').layoutWeight(1).margin({ left: 10 })
            Text('>').fontSize(18).fontColor('#9AA0AA')
          }.width('100%').height(46).padding({ left: 16, right: 12 }).backgroundColor('#F2EEFF').borderRadius(12)
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: 22 })

        Column() {
          Text('+  新增采集源').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('连接更多平台，采集更多数据').fontSize(12).fontColor('#E8E2FF').margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .width('86%')
        .height(72)
        .backgroundColor('#725CFF')
        .borderRadius(18)
        .margin({ top: 22 })
        .onClick(() => { promptAction.showToast({ message: '新增采集源功能即将接入', duration: 1500 }); })

        Column() {
          Text('图库分析').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('采集相册、截图和文档图片，进行 OCR 与分类整理').fontSize(12).fontColor('#E9F7FF').margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .width('86%')
        .height(72)
        .backgroundColor('#4B8BFF')
        .borderRadius(18)
        .margin({ top: 12 })
        .onClick(() => { router.pushUrl({ url: 'pages/gallery/GalleryPage' }); })
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }
}
