import { promptAction } from '@kit.ArkUI';
import { AppHeader } from '../../components/AppHeader';

@Component
export struct TaskPage {
  @Link taskScene: number;

  @Builder TaskCard(icon: string, iconColor: string, title: string, status: string, nextRun: string, source: string, enabled: boolean) {
    Column() {
      Row() {
        Text(icon).fontSize(17).fontColor(iconColor).fontWeight(FontWeight.Bold).width(58).height(58).textAlign(TextAlign.Center).backgroundColor(enabled ? '#F1F5FF' : '#F4F5F8').borderRadius(16)
        Column() {
          Row() {
            Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row().width(7).height(7).backgroundColor(enabled ? '#39BFA3' : '#A8AFBC').borderRadius(4).margin({ left: 8, right: 5 })
            Text(status).fontSize(12).fontColor(enabled ? '#66707E' : '#8E95A3').maxLines(1)
          }.width('100%')
          Text('下次运行：' + nextRun).fontSize(12).fontColor('#7B8290').margin({ top: 8 }).maxLines(1)
          Text('来源模块：' + source).fontSize(12).fontColor('#7B8290').margin({ top: 4 }).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14, right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: enabled }).selectedColor('#6B5CFF').width(44).height(26)
      }.width('100%')
    }
    .width('86%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .shadow({ radius: 12, color: '#10000000', offsetX: 0, offsetY: 6 })
    .margin({ bottom: 18 })
    .onClick(() => { promptAction.showToast({ message: title + ' 详情暂未接入', duration: 1500 }); })
  }

  @Builder TaskSceneTab(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.taskScene === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.taskScene === index ? Color.White : '#6D7481')
      .height(42)
      .padding({ left: 18, right: 18 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.taskScene === index ? '#765BFF' : Color.White)
      .borderRadius(21)
      .onClick(() => {
        this.taskScene = index;
      })
  }

  @Builder TaskSceneList() {
    if (this.taskScene === 0) {
      this.TaskCard('Buy', '#4B8BFF', '晚间购物订单同步', '运行中', '今天 20:30', '电商订单', true)
      this.TaskCard('Cart', '#8066FF', '优惠价格监控', '运行中', '每天 12:00', '商品收藏', true)
    } else if (this.taskScene === 1) {
      this.TaskCard('Food', '#39BFA3', '午餐外卖偏好整理', '运行中', '今天 11:20', '外卖订单', true)
      this.TaskCard('Shop', '#FF9347', '晚餐配送提醒', '运行中', '今天 18:10', '生活服务', true)
    } else if (this.taskScene === 2) {
      this.TaskCard('Play', '#8066FF', '周末娱乐记录整理', '已暂停', '周六 10:00', '视频 & 音乐', false)
      this.TaskCard('Movie', '#4B8BFF', '观影清单同步', '运行中', '周五 21:30', '影音收藏', true)
    } else {
      this.TaskCard('Chat', '#4B8BFF', '家庭群消息摘要', '运行中', '明天 07:30', '聊天记录', true)
      this.TaskCard('Bell', '#FF9347', '晨间通知摘要', '运行中', '明天 07:30', '系统通知', true)
    }
  }

  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '定时任务', subtitle: '自定义采集 workflow' })
        Column() {
          Row() {
            Column() {
              Row() {
                Text('新建任务').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#11182F')
                Text('AI 编排').fontSize(11).fontColor('#765BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F0ECFF').borderRadius(10).margin({ left: 10 })
              }
              Text('选择场景，自动采集并整理你的生活数据').fontSize(12).fontColor('#6F7584').margin({ top: 7 }).maxLines(1)
              Row() {
                Text('购物').fontSize(11).fontColor('#6B5CFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F8F5FF').borderRadius(10)
                Text('外卖').fontSize(11).fontColor('#39BFA3').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFFBF7').borderRadius(10).margin({ left: 8 })
                Text('聊天').fontSize(11).fontColor('#4B8BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFF5FF').borderRadius(10).margin({ left: 8 })
              }.margin({ top: 12 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Column() {
              Text('+').fontSize(28).fontColor(Color.White).fontWeight(FontWeight.Regular)
              Text('创建').fontSize(11).fontColor('#F2EEFF').margin({ top: 1 })
            }
            .justifyContent(FlexAlign.Center)
            .width(58)
            .height(58)
            .backgroundColor('#765BFF')
            .borderRadius(20)
          }.width('100%')
        }
        .width('86%')
        .height(136)
        .padding(22)
        .backgroundColor('#F3EEFF')
        .borderRadius(20)
        .margin({ top: 24 })
        .onClick(() => { promptAction.showToast({ message: '新建任务流程后续接入', duration: 1500 }); })

        Scroll() {
          Row() {
            this.TaskSceneTab('购物', 0)
            Blank().width(10)
            this.TaskSceneTab('外卖', 1)
            Blank().width(10)
            this.TaskSceneTab('娱乐', 2)
            Blank().width(10)
            this.TaskSceneTab('聊天', 3)
          }.padding({ left: 24, right: 24 })
        }
        .width('100%')
        .height(46)
        .scrollable(ScrollDirection.Horizontal)
        .margin({ top: 22, bottom: 18 })

        this.TaskSceneList()
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }
}

