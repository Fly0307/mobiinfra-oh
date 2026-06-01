import { promptAction, router } from '@kit.ArkUI';
import { AppHeader } from '../../components/AppHeader';

interface GalleryInsightItem {
  title: string;
  source: string;
  time: string;
  category: string;
  summary: string;
  image: Resource;
  color: string;
}

@Entry
@Component
struct GalleryPage {
  @State analyzing: boolean = false;
  @State progress: number = 0;
  @State selectedFilter: number = 0;
  @State lastRunText: string = '尚未开始';

  private insights: GalleryInsightItem[] = [
    {
      title: '外卖订单截图',
      source: 'Screenshots',
      time: '今天 09:12',
      category: '餐饮',
      summary: '识别到一笔早餐外卖订单，可归入近期饮食和消费记录。',
      image: $r('app.media.rec_food'),
      color: '#39BFA3'
    },
    {
      title: '周末出行图片',
      source: 'Camera',
      time: '昨天 18:30',
      category: '出行',
      summary: '图片包含路线和地点信息，适合沉淀到周末出行记忆。',
      image: $r('app.media.rec_travel'),
      color: '#4B8BFF'
    },
    {
      title: '运动打卡截图',
      source: 'Screenshots',
      time: '周六 21:05',
      category: '健康',
      summary: '识别到运动时长和消耗信息，可用于生活画像更新。',
      image: $r('app.media.rec_sport'),
      color: '#765BFF'
    }
  ];

  private visibleCount(): string {
    if (this.selectedFilter === 0) {
      return '3 张';
    }
    if (this.selectedFilter === 1) {
      return '2 张';
    }
    return '1 张';
  }

  private startAnalyze(scope: string): void {
    if (this.analyzing) {
      promptAction.showToast({ message: '图库分析正在进行', duration: 1200 });
      return;
    }
    this.analyzing = true;
    this.progress = 36;
    this.lastRunText = scope + '分析中';
    promptAction.showToast({ message: '已创建图库分析任务', duration: 1200 });
  }

  private finishMockAnalyze(): void {
    this.analyzing = false;
    this.progress = 100;
    this.lastRunText = '刚刚';
    promptAction.showToast({ message: '图库分析结果已刷新', duration: 1200 });
  }

  @Builder StatCell(label: string, value: string, color: string) {
    Column() {
      Text(label).fontSize(12).fontColor('#737987').maxLines(1)
      Text(value).fontSize(21).fontWeight(FontWeight.Bold).fontColor(color).margin({ top: 5 }).maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  private runAction(actionId: number): void {
    if (actionId === 0) {
      this.startAnalyze('最近图片');
      return;
    }
    if (actionId === 1) {
      this.startAnalyze('手动选择');
      return;
    }
    if (this.analyzing) {
      this.finishMockAnalyze();
    } else {
      promptAction.showToast({ message: '缓存清理入口待接入', duration: 1200 });
    }
  }

  @Builder ActionButton(title: string, subtitle: string, color: string, actionId: number) {
    Row() {
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(1)
        Text(subtitle).fontSize(11).fontColor('#7C8494').margin({ top: 4 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('>').fontSize(18).fontColor(Color.White).width(30).height(30).textAlign(TextAlign.Center).backgroundColor(color).borderRadius(15)
    }
    .width('100%')
    .height(62)
    .padding({ left: 16, right: 14 })
    .backgroundColor('#F8FAFE')
    .borderRadius(15)
    .margin({ top: 10 })
    .onClick(() => { this.runAction(actionId); })
  }

  @Builder FilterChip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.selectedFilter === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.selectedFilter === index ? Color.White : '#596071')
      .height(36)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.selectedFilter === index ? '#5B68FF' : '#F1F4FA')
      .borderRadius(18)
      .margin({ right: 8 })
      .onClick(() => { this.selectedFilter = index; })
  }

  @Builder InsightRow(item: GalleryInsightItem) {
    Row() {
      Image(item.image).width(62).height(62).objectFit(ImageFit.Cover).borderRadius(12)
      Column() {
        Row() {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.category).fontSize(11).fontColor(item.color).padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor('#F4F7FF').borderRadius(9)
        }.width('100%')
        Text(item.summary).fontSize(12).fontColor('#6F7584').margin({ top: 6 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.source + ' · ' + item.time).fontSize(11).fontColor('#9AA2B1').margin({ top: 5 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Button('返回')
            .height(36)
            .fontSize(13)
            .backgroundColor('#EEF4FF')
            .fontColor('#4F68FF')
            .borderRadius(12)
            .onClick(() => { router.back(); })
        }
        .width('86%')
        .margin({ top: 12 })

        AppHeader({ title: '图库采集', subtitle: '相册、截图与文档图片分析' })

        Column() {
          Row() {
            this.StatCell('已分析', this.visibleCount(), '#5B68FF')
            Divider().vertical(true).height(42).color('#E7E9F0')
            this.StatCell('最近分析', this.lastRunText, '#151A28')
            Divider().vertical(true).height(42).color('#E7E9F0')
            this.StatCell('缓存状态', '可用', '#39BFA3')
          }.width('100%')
          if (this.analyzing) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(6)
              .color('#5B68FF')
              .backgroundColor('#E8EDF8')
              .margin({ top: 16 })
            Text('正在读取图片、OCR 预筛和模型分类').fontSize(12).fontColor('#6F7584').margin({ top: 8 }).width('100%')
          }
        }
        .width('86%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 12 })

        Column() {
          Text('分析操作').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#11182F').width('100%')
          this.ActionButton('自动分析最近图片', '扫描最近相册和截图，适合日常增量采集', '#5B68FF', 0)
          this.ActionButton('手动选择图片', '选择明确需要入库的图片，跳过关键词预筛', '#39BFA3', 1)
          this.ActionButton(this.analyzing ? '完成本次模拟分析' : '清理图库缓存', this.analyzing ? '写入示例分析结果并刷新状态' : '删除缩略图、OCR 和模型分析缓存', '#FF8A3D', 2)
        }
        .width('86%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 18 })

        Column() {
          Row() {
            Text('图库结果').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1)
            Text('查看全部').fontSize(13).fontColor('#7F8592')
          }.width('100%')
          Scroll() {
            Row() {
              this.FilterChip('全部', 0)
              this.FilterChip('截图', 1)
              this.FilterChip('照片', 2)
              this.FilterChip('文档', 3)
            }
          }
          .width('100%')
          .height(42)
          .scrollable(ScrollDirection.Horizontal)
          .margin({ top: 12 })
          ForEach(this.insights, (item: GalleryInsightItem) => {
            this.InsightRow(item)
            Divider().color('#EEF0F5')
          }, (item: GalleryInsightItem) => item.title)
        }
        .width('86%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 18 })

        Blank().height(100)
      }.width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8FF')
  }
}
