import { AppHeader } from '../../components/AppHeader';
import {
  CollectionImageViewModel,
  HomeDomainViewModel,
  HomeProfileViewModel,
  HomeRecommendationViewModel
} from '../../datamanager/DataManagerTypes';
import { createEmptyHomeProfileViewModel } from '../../datamanager/DataManagerFacade';
import { promptAction } from '@kit.ArkUI';

// “数据归家”首页展示层：只做静态画像、推荐和进度概览，不承载推理/Agent 逻辑。
@Component
export struct HomePage {
  @Prop profile: HomeProfileViewModel = createEmptyHomeProfileViewModel();
  onSetRecommendationCompleted: (id: string, completed: boolean) => void = (id: string, completed: boolean) => {};
  onExecuteAgentTask: (taskDescription: string) => Promise<void> = async (taskDescription: string) => {};
  @State recommendationPageIndex: number = 0;
  @State selectedRecommendationId: string = '';
  @State selectedRecommendationCompletedOverrideId: string = '';
  @State selectedRecommendationCompletedOverrideValue: boolean = false;
  @State agentTaskDraft: string = '';
  @State agentTaskSubmitting: boolean = false;
  @State showAllRecommendations: boolean = false;

  @Builder FeaturePill(icon: string, title: string, desc: string) {
    // 顶部四个能力点胶囊，作为数字分身价值点的轻量入口。
    Row() {
      Text(icon)
        .fontSize(13)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor('#6A67FF')
        .borderRadius(14)
      Column() {
        Text(title).fontSize(14).fontColor('#172033').fontWeight(FontWeight.Medium).maxLines(1)
        Text(desc).fontSize(11).fontColor('#6F7684').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 8 })
    }
    .width('48%')
    .height(54)
    .padding({ left: 10, right: 8 })
    .backgroundColor('#F8FBFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E8EEFA' })
  }

  private profileDetailMessage(item: HomeDomainViewModel): string {
    let lines: string[] = [item.fullDesc.length > 0 ? item.fullDesc : '暂无数据'];
    let claims = item.claims || [];
    if (claims.length > 0) {
      lines.push('');
      lines.push('画像依据');
      claims.forEach((claim: string) => {
        lines.push('- ' + claim);
      });
    }
    return lines.join('\n');
  }

  private showProfileDetail(item: HomeDomainViewModel): void {
    promptAction.showDialog({
      title: item.title + '画像',
      message: this.profileDetailMessage(item),
      buttons: [
        { text: '知道了', color: item.color }
      ]
    }).catch(() => {});
  }

  @Builder LifestyleItem(item: HomeDomainViewModel) {
    // 吃/穿/住/行画像摘要，当前为前端静态展示，后续可替换为真实画像数据。
    Column() {
      Text(item.icon).fontSize(13).fontColor(item.color).fontWeight(FontWeight.Bold).height(18).textAlign(TextAlign.Center).maxLines(1)
      Column() {
        Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(1)
        Text(item.desc).fontSize(11).fontColor('#818795').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
    .onClick(() => {
      this.showProfileDetail(item);
    })
  }

  @Builder RecommendationImage(item: HomeRecommendationViewModel) {
    if (item.thumbnailUri.length > 0) {
      Image(item.thumbnailUri)
        .width('100%')
        .height(82)
        .objectFit(ImageFit.Cover)
    } else {
      Column() {
        Text('暂无图片')
          .fontSize(12)
          .fontColor('#8B93A4')
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(82)
      .backgroundColor('#EEF2F7')
    }
  }

  private recommendationDisplayTag(item: HomeRecommendationViewModel): string {
    if (this.recommendationCompleted(item)) {
      return '已完成';
    }
    return item.tag;
  }

  private recommendationCardTitleColor(item: HomeRecommendationViewModel): string {
    return this.showAllRecommendations && this.recommendationCompleted(item) ? '#A0A7B5' : '#151A28';
  }

  private recommendationCompleted(item: HomeRecommendationViewModel): boolean {
    if (this.selectedRecommendationCompletedOverrideId === item.id) {
      return this.selectedRecommendationCompletedOverrideValue;
    }
    return item.completed;
  }

  private openRecommendationDetail(item: HomeRecommendationViewModel): void {
    this.selectedRecommendationId = item.id;
    this.selectedRecommendationCompletedOverrideId = item.id;
    this.selectedRecommendationCompletedOverrideValue = item.completed;
    this.agentTaskDraft = item.agentTask;
  }

  private closeRecommendationDetail(): void {
    this.selectedRecommendationId = '';
    this.selectedRecommendationCompletedOverrideId = '';
  }

  @Builder RecommendCard(item: HomeRecommendationViewModel) {
    // 推荐卡片横滑列表，统一图片、标签、标题和元信息的布局。
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.RecommendationImage(item)
        Text(this.recommendationDisplayTag(item))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(item.color)
          .borderRadius(8)
          .margin({ left: 8, top: 8 })
      }.width('100%').height(82)
      Column() {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.recommendationCardTitleColor(item))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.desc)
          .fontSize(11)
          .fontColor('#787F8E')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          if (item.meta.length > 0) {
            Text(item.meta).fontSize(11).fontColor('#7C8494').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Blank().layoutWeight(1)
          }
          Text('>').fontSize(16).fontColor(Color.White).textAlign(TextAlign.Center).width(28).height(28).backgroundColor(item.color).borderRadius(14)
        }.width('100%').margin({ top: 10 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height(178)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .clip(true)
    .shadow({ radius: 18, color: '#16000000', offsetX: 0, offsetY: 8 })
    .onClick(() => {
      this.openRecommendationDetail(item);
    })
  }

  @Builder EmptyRecommendationCard() {
    Row() {
      Text(this.showAllRecommendations ? '暂无待办事项' : '暂无未完成待办')
        .fontSize(14)
        .fontColor('#7C8494')
    }
    .width('92%')
    .margin({ top: 2 })
  }

  private recommendationPageCount(): number {
    return Math.max(1, Math.ceil(this.visibleRecommendations().length / 4));
  }

  private currentRecommendationPageIndex(): number {
    let maxPageIndex = this.recommendationPageCount() - 1;
    if (this.recommendationPageIndex < 0) {
      return 0;
    }
    if (this.recommendationPageIndex > maxPageIndex) {
      return maxPageIndex;
    }
    return this.recommendationPageIndex;
  }

  private visibleRecommendations(): HomeRecommendationViewModel[] {
    if (this.showAllRecommendations) {
      let pending = this.profile.recommendations.filter((item: HomeRecommendationViewModel): boolean => !item.completed);
      let completed = this.profile.recommendations.filter((item: HomeRecommendationViewModel): boolean => item.completed);
      return pending.concat(completed);
    }
    return this.profile.recommendations.filter((item: HomeRecommendationViewModel): boolean => !item.completed);
  }

  private recommendationPageItems(): HomeRecommendationViewModel[] {
    let items = this.visibleRecommendations();
    if (items.length === 0) {
      return [];
    }
    let page = this.currentRecommendationPageIndex();
    let start = page * 4;
    return items.slice(start, start + 4);
  }

  private setRecommendationPage(index: number): void {
    let maxPageIndex = this.recommendationPageCount() - 1;
    let nextIndex = Math.max(0, Math.min(index, maxPageIndex));
    this.recommendationPageIndex = nextIndex;
  }

  private shouldShowRecommendationPagination(): boolean {
    return this.visibleRecommendations().length > 0;
  }

  private selectedRecommendationItems(): HomeRecommendationViewModel[] {
    if (this.selectedRecommendationId.length === 0) {
      return [];
    }
    return this.profile.recommendations.filter((item: HomeRecommendationViewModel): boolean => item.id === this.selectedRecommendationId).slice(0, 1);
  }

  private setRecommendationFilter(showAll: boolean): void {
    this.showAllRecommendations = showAll;
    this.recommendationPageIndex = 0;
    if (!showAll) {
      this.closeRecommendationDetail();
    }
  }

  private setRecommendationCompleted(item: HomeRecommendationViewModel, completed: boolean): void {
    this.selectedRecommendationCompletedOverrideId = item.id;
    this.selectedRecommendationCompletedOverrideValue = completed;
    this.onSetRecommendationCompleted(item.id, completed);
  }

  private async executeAgentTask(): Promise<void> {
    let task = this.agentTaskDraft.trim();
    if (task.length === 0) {
      promptAction.showToast({ message: '请输入要执行的任务', duration: 1200 });
      return;
    }
    if (this.agentTaskSubmitting) {
      return;
    }
    this.agentTaskSubmitting = true;
    try {
      await this.onExecuteAgentTask(task);
      this.closeRecommendationDetail();
    } catch (e) {
      let err = e as Error;
      promptAction.showToast({ message: '任务下发失败：' + err.message, duration: 1800 });
    } finally {
      this.agentTaskSubmitting = false;
    }
  }

  @Builder RecommendationFilterButton(label: string, showAll: boolean) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.showAllRecommendations === showAll ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.showAllRecommendations === showAll ? Color.White : '#6D7481')
      .height(30)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.showAllRecommendations === showAll ? '#8066FF' : '#F1F3F8')
      .borderRadius(15)
      .onClick(() => {
        this.setRecommendationFilter(showAll);
      })
  }

  @Builder RecommendationPagination() {
    if (this.shouldShowRecommendationPagination()) {
      Row() {
        Button('上一页')
          .fontSize(12)
          .fontColor(this.currentRecommendationPageIndex() > 0 ? '#8066FF' : '#A7ADBA')
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.currentRecommendationPageIndex() > 0 ? '#F0ECFF' : '#EEF0F5')
          .enabled(this.currentRecommendationPageIndex() > 0)
          .onClick(() => {
            this.setRecommendationPage(this.currentRecommendationPageIndex() - 1);
          })
        Text(`${this.currentRecommendationPageIndex() + 1}/${this.recommendationPageCount()}`)
          .fontSize(13)
          .fontColor('#6D7481')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .maxLines(1)
        Button('下一页')
          .fontSize(12)
          .fontColor(this.currentRecommendationPageIndex() < this.recommendationPageCount() - 1 ? '#8066FF' : '#A7ADBA')
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.currentRecommendationPageIndex() < this.recommendationPageCount() - 1 ? '#F0ECFF' : '#EEF0F5')
          .enabled(this.currentRecommendationPageIndex() < this.recommendationPageCount() - 1)
          .onClick(() => {
            this.setRecommendationPage(this.currentRecommendationPageIndex() + 1);
          })
      }
      .width('92%')
      .margin({ top: 12 })
    }
  }

  @Builder RecommendationDetailImage(image: CollectionImageViewModel) {
    if (image.available && image.uri.length > 0) {
      Column() {
        Image(image.uri)
          .width(128)
          .height(260)
          .objectFit(ImageFit.Contain)
          .borderRadius(12)
      }
      .width(128)
      .height(260)
      .margin({ right: 10 })
    } else {
      Column() {
        Text('图片暂不可显示')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#596273')
          .maxLines(1)
        Text('图片引用暂不可显示')
          .fontSize(12)
          .fontColor('#8A92A3')
          .margin({ top: 5 })
          .maxLines(1)
        Text(image.ref)
          .fontSize(10)
          .fontColor('#A0A7B5')
          .margin({ top: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width(220)
      .height(240)
      .padding(12)
      .backgroundColor('#F7F9FC')
      .borderRadius(12)
      .margin({ right: 10 })
    }
  }

  @Builder RecommendationDetailImages(item: HomeRecommendationViewModel) {
    if (item.imageRefs.length === 0) {
      Column() {
        Text('暂无图片')
          .fontSize(13)
          .fontColor('#7C8494')
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(86)
      .backgroundColor('#F7F9FC')
      .borderRadius(12)
      .margin({ top: 14 })
    } else {
      Scroll() {
        Row() {
          ForEach(item.imageRefs, (image: CollectionImageViewModel, index: number) => {
            this.RecommendationDetailImage(image)
          }, (image: CollectionImageViewModel, index: number) => item.id + '_image_' + index.toString())
        }
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height(270)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .margin({ top: 14 })
    }
  }

  @Builder RecommendationCompletedCheckbox(item: HomeRecommendationViewModel) {
    Row() {
      Blank().layoutWeight(1)
      Row() {
        Checkbox({ name: 'homeRecommendationCompleted-' + item.id })
          .select(this.recommendationCompleted(item))
          .selectedColor(item.color)
          .margin({ right: 6 })
          .onChange((checked: boolean) => {
            this.setRecommendationCompleted(item, checked);
          })
        Text('已完成')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.recommendationCompleted(item) ? item.color : '#6D7481')
          .maxLines(1)
          .padding({ top: 6, bottom: 6 })
          .onClick(() => {
            this.setRecommendationCompleted(item, !this.recommendationCompleted(item));
          })
      }
      .alignItems(VerticalAlign.Center)
      .height(32)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder RecommendationDetailOverlay(item: HomeRecommendationViewModel) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeRecommendationDetail();
        })
      Column() {
        Row() {
          Text(this.recommendationDisplayTag(item))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(item.color)
            .borderRadius(8)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7C8494')
            .layoutWeight(1)
            .textAlign(TextAlign.End)
            .onClick(() => {
              this.closeRecommendationDetail();
            })
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        Text(item.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .margin({ top: 14 })
        this.RecommendationDetailImages(item)
        Text(item.desc.length > 0 ? item.desc : '暂无描述')
          .fontSize(14)
          .fontColor('#4E5668')
          .width('100%')
          .margin({ top: 14 })
        this.RecommendationCompletedCheckbox(item)
        if (item.agentTask.length > 0) {
          Column() {
            Text('执行任务')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
              .width('100%')
            TextArea({ placeholder: '调整要交给 GUI Agent 的任务', text: this.agentTaskDraft })
              .width('100%')
              .height(56)
              .fontSize(14)
              .lineHeight(20)
              .fontColor('#222B3A')
              .backgroundColor('#F5F7FB')
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ top: 10 })
              .onChange((value: string) => {
                this.agentTaskDraft = value;
              })
            Button(this.agentTaskSubmitting ? '下发中' : '执行')
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .backgroundColor(this.agentTaskSubmitting ? '#A9B7E9' : item.color)
              .borderRadius(14)
              .margin({ top: 12 })
              .enabled(!this.agentTaskSubmitting)
              .onClick(() => {
                this.executeAgentTask();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 18 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('88%')
      .padding({ left: 18, right: 18, top: 18, bottom: 20 })
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 22, color: '#26000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          AppHeader({ title: '数据归家' })

        Column() {
          Image($r('app.media.digital_avatar'))
            .width('74%')
            .height(245)
            .objectFit(ImageFit.Contain)
            .margin({ top: 6 })

          Row() {
            this.FeaturePill('I', '理解你', '更懂你的偏好')
            Blank().layoutWeight(1)
            this.FeaturePill('P', '守护你', '隐私安全可靠')
          }.width('92%').margin({ top: 8 })

          Row() {
            this.FeaturePill('L', '陪伴你', '服务你的生活')
            Blank().layoutWeight(1)
            this.FeaturePill('G', '成就你', '助力你的成长')
          }.width('92%').margin({ top: 8 })

          Row() {
            Row().width(8).height(8).backgroundColor('#7669FF').borderRadius(4)
            Text(this.profile.empty ? '等待导入数据生成数字分身' : '你的数字分身已更新').fontSize(16).fontColor('#1B2030').margin({ left: 8 }).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.profile.updatedLabel + ' >').fontSize(13).fontColor('#7B8190').margin({ left: 8 }).width(88).textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('82%')
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor(Color.White)
          .borderRadius(21)
          .margin({ top: 12, bottom: 16 })
        }
        .width('100%')
        .backgroundColor('#EDF5FF')

        Row() {
          Text('画像完整度').fontSize(15).fontColor('#272C38').width(82)
          Progress({ value: this.profile.completeness, total: 100, type: ProgressType.Linear })
            .layoutWeight(1)
            .height(6)
            .color('#8066FF')
            .backgroundColor('#E6E8F3')
            .margin({ left: 12, right: 14 })
          Text(this.profile.completeness + '%').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#9D6BFF').width(78).textAlign(TextAlign.End).maxLines(1)
          Text('>').fontSize(20).fontColor('#7A808C').margin({ left: 8 })
        }
        .width('92%')
        .height(70)
        .padding({ left: 18, right: 18 })
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 16 })

        Row() {
          ForEach(this.profile.domains.slice(0, 4), (item: HomeDomainViewModel, index: number) => {
            this.LifestyleItem(item)
            if (index < 3) {
              Divider().vertical(true).height(34).color('#E5E7EF')
            }
          }, (item: HomeDomainViewModel) => item.domain + '-' + item.desc + '-' + item.eventCount)
        }
        .width('92%')
        .height(82)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .padding({ left: 12, right: 12 })
        .margin({ top: 14 })

          Row() {
            Text('为你推荐').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1)
            this.RecommendationFilterButton('未完成', false)
            Blank().width(8)
            this.RecommendationFilterButton('全部', true)
          }.width('92%').margin({ top: 24 })

          if (this.visibleRecommendations().length === 0) {
            this.EmptyRecommendationCard()
          } else {
            Grid() {
              ForEach(this.recommendationPageItems(), (item: HomeRecommendationViewModel) => {
                GridItem() {
                  this.RecommendCard(item)
                }
              }, (item: HomeRecommendationViewModel) => item.id + '-' + item.title + '-' + String(item.completed))
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(12)
            .rowsGap(12)
            .width('92%')
            .height(368)
            .margin({ top: 14 })
            this.RecommendationPagination()
          }

          Blank().height(88)
        }.width('100%')
      }.width('100%').height('100%').backgroundColor('#F4F8FF')

      ForEach(this.selectedRecommendationItems(), (item: HomeRecommendationViewModel) => {
        this.RecommendationDetailOverlay(item)
      }, (item: HomeRecommendationViewModel) => item.id)
    }
    .width('100%')
    .height('100%')
  }
}
