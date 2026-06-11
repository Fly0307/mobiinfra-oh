import { AppHeader } from '../../components/AppHeader';
import { promptAction, router } from '@kit.ArkUI';
import {
  CollectionGroupViewModel,
  CollectionViewModel
} from '../../datamanager/DataManagerTypes';
import { createEmptyCollectionViewModels } from '../../datamanager/DataManagerFacade';
import { dataManagerInfo } from '../../datamanager/DataManagerLog';
import { workflowSceneConfigs, WorkflowSceneConfig } from '../../utils/WorkflowSceneConfig';
import {
  normalizeWechatAutoSummaryDays,
  normalizeWechatAutoSummaryHistorySwipeRatio,
  normalizeWechatAutoSummaryMaxContacts,
  normalizeWechatAutoSummaryMaxHistorySwipes,
  normalizeWechatAutoSummaryMode,
  normalizeWechatAutoSummaryStableSwipes,
  normalizeWechatAutoSummarySwipeSpeed,
  normalizeWechatAutoSummaryWait,
  validateWechatAutoSummaryRequest,
  WechatAutoSummaryRequest,
  WECHAT_AUTO_SUMMARY_MODE_RECENT,
  WECHAT_AUTO_SUMMARY_MODE_TARGET
} from '../../utils/wechat/WechatAutoSummaryTypes';

const COLLECTION_GROUPS_PER_PAGE: number = 5;
const COLLECTION_SECTION_GAP: number = 18;

// 数据采集页：按 workflow 场景切换展示对应任务采集到的已整理数据。
// collectionModule 由 Index.ets 通过 @Link 传入，保证底部 tab 与页面内状态共享。
@Component
export struct CollectionPage {
  @Link collectionModule: number;
  @Prop viewModels: CollectionViewModel[] = createEmptyCollectionViewModels();
  @Prop refreshing: boolean = false;
  @Prop wechatAutoSummaryEnabled: boolean = false;
  @Prop wechatAutoSummaryDefaultDays: string = '7';
  @Prop wechatAutoSummaryDefaultMaxContacts: string = '10';
  @Prop wechatAutoSummarySwipeSpeed: string = '2500';
  @Prop wechatAutoSummaryHistorySwipeRatio: string = '0.65';
  @Prop wechatAutoSummaryStableSwipes: string = '3';
  @Prop wechatAutoSummaryMaxHistorySwipes: string = '80';
  @Prop wechatAutoSummaryWait: string = '1.0';
  @Prop wechatAutoSummaryRunning: boolean = false;
  @Prop wechatAutoSummaryStatus: string = '';
  @State private groupPageIndex: number = 0;
  @State private wechatMode: string = WECHAT_AUTO_SUMMARY_MODE_RECENT;
  @State private wechatDaysInput: string = '';
  @State private wechatMaxContactsInput: string = '';
  @State private wechatTargetContactInput: string = '';
  onRefresh: () => void = () => {};
  onOpenDataCollectionSettings: () => void = () => {};
  onRunWechatAutoSummary: (request: WechatAutoSummaryRequest) => Promise<void> =
    async (request: WechatAutoSummaryRequest) => {};

  private currentView(): CollectionViewModel {
    if (this.viewModels.length > this.collectionModule) {
      return this.viewModels[this.collectionModule];
    }
    return createEmptyCollectionViewModels()[this.collectionModule];
  }

  private getCollectionTitle(): string {
    return this.currentView().title;
  }

  private getCollectionCount(): string {
    return this.currentView().countLabel;
  }

  private getCollectionSyncTime(): string {
    return this.currentView().lastUpdatedLabel;
  }

  private groupCount(): number {
    return this.currentView().groups.length;
  }

  private groupPageCount(): number {
    return Math.max(1, Math.ceil(this.groupCount() / COLLECTION_GROUPS_PER_PAGE));
  }

  private currentGroupPageIndex(): number {
    let maxPageIndex = this.groupPageCount() - 1;
    if (this.groupPageIndex < 0) {
      return 0;
    }
    if (this.groupPageIndex > maxPageIndex) {
      return maxPageIndex;
    }
    return this.groupPageIndex;
  }

  private currentPageGroups(): CollectionGroupViewModel[] {
    let start = this.currentGroupPageIndex() * COLLECTION_GROUPS_PER_PAGE;
    return this.currentView().groups.slice(start, start + COLLECTION_GROUPS_PER_PAGE);
  }

  private setGroupPage(index: number): void {
    let maxPageIndex = this.groupPageCount() - 1;
    let nextIndex = Math.max(0, Math.min(index, maxPageIndex));
    this.groupPageIndex = nextIndex;
  }

  private shouldShowGroupPagination(): boolean {
    return this.groupCount() > COLLECTION_GROUPS_PER_PAGE;
  }

  private wechatInputOrDefault(input: string, fallback: string): string {
    let text = input.trim();
    if (text.length > 0) {
      return text;
    }
    return fallback;
  }

  private wechatDaysText(): string {
    return this.wechatInputOrDefault(this.wechatDaysInput, this.wechatAutoSummaryDefaultDays);
  }

  private wechatMaxContactsText(): string {
    return this.wechatInputOrDefault(this.wechatMaxContactsInput, this.wechatAutoSummaryDefaultMaxContacts);
  }

  private buildWechatRequest(): WechatAutoSummaryRequest {
    let mode = normalizeWechatAutoSummaryMode(this.wechatMode);
    let targetContact = mode === WECHAT_AUTO_SUMMARY_MODE_TARGET ? this.wechatTargetContactInput.trim() : '';
    return {
      mode: mode,
      days: normalizeWechatAutoSummaryDays(this.wechatDaysText()),
      max_contacts: normalizeWechatAutoSummaryMaxContacts(this.wechatMaxContactsText()),
      target_contact: targetContact,
      swipe_speed: normalizeWechatAutoSummarySwipeSpeed(this.wechatAutoSummarySwipeSpeed),
      history_swipe_ratio: normalizeWechatAutoSummaryHistorySwipeRatio(this.wechatAutoSummaryHistorySwipeRatio),
      stable_swipes: normalizeWechatAutoSummaryStableSwipes(this.wechatAutoSummaryStableSwipes),
      max_history_swipes: normalizeWechatAutoSummaryMaxHistorySwipes(this.wechatAutoSummaryMaxHistorySwipes),
      wait: normalizeWechatAutoSummaryWait(this.wechatAutoSummaryWait)
    };
  }

  private showWechatToast(message: string): void {
    promptAction.showToast({ message: message, duration: 1600 });
  }

  @Builder WechatModeButton(label: string, mode: string) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(13)
      .fontColor(this.wechatMode === mode ? Color.White : '#4F68FF')
      .backgroundColor(this.wechatMode === mode ? '#4F68FF' : '#EEF3FF')
      .borderRadius(10)
      .onClick(() => {
        if (this.wechatAutoSummaryRunning) {
          return;
        }
        this.wechatMode = mode;
      })
  }

  @Builder WechatInput(label: string, value: string, placeholder: string, onValueChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor('#6F7684')
        .width('100%')
        .maxLines(1)
      TextInput({ placeholder: placeholder, text: value })
        .height(42)
        .width('100%')
        .fontSize(13)
        .fontColor('#161B28')
        .backgroundColor('#F2F5FC')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .enabled(!this.wechatAutoSummaryRunning)
        .margin({ top: 6 })
        .onChange((input: string) => { onValueChange(input); })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder WechatAutoSummaryCard() {
    if (this.wechatAutoSummaryEnabled) {
      Column() {
        Text('微信消息自动汇总')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .maxLines(1)
        Text('调用 PC 侧采集服务读取微信会话，保存原始产物并写入 daily-log。')
          .fontSize(12)
          .fontColor('#6F7684')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })

        Row() {
          this.WechatModeButton('最近联系人', WECHAT_AUTO_SUMMARY_MODE_RECENT)
          Blank().width(10)
          this.WechatModeButton('指定联系人', WECHAT_AUTO_SUMMARY_MODE_TARGET)
        }
        .width('100%')
        .margin({ top: 14 })

        this.WechatInput('时间范围（天）', this.wechatDaysText(), this.wechatAutoSummaryDefaultDays,
          (value: string) => { this.wechatDaysInput = value; })
        this.WechatInput('最近联系人数量', this.wechatMaxContactsText(), this.wechatAutoSummaryDefaultMaxContacts,
          (value: string) => { this.wechatMaxContactsInput = value; })
        if (this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_TARGET) {
          this.WechatInput('指定联系人', this.wechatTargetContactInput, '请输入微信联系人名称',
            (value: string) => { this.wechatTargetContactInput = value; })
        }

        Button(this.wechatAutoSummaryRunning ? '采集中' : '开始采集')
          .height(44)
          .width('100%')
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(this.wechatAutoSummaryRunning ? '#A9B0C2' : '#4F68FF')
          .borderRadius(12)
          .enabled(!this.wechatAutoSummaryRunning)
          .margin({ top: 16 })
          .onClick(async () => {
            // 点击时即时归一化并校验，避免设置页默认值和卡片输入不一致。
            let request = this.buildWechatRequest();
            let error = validateWechatAutoSummaryRequest(request);
            if (error.length > 0) {
              this.showWechatToast(error);
              return;
            }
            await this.onRunWechatAutoSummary(request);
          })

        if (this.wechatAutoSummaryStatus.length > 0) {
          Text(this.wechatAutoSummaryStatus)
            .fontSize(12)
            .fontColor(this.wechatAutoSummaryStatus.startsWith('采集失败') ? '#B42318' : '#52606D')
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 10 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('86%')
      .padding(18)
      .backgroundColor('#F9FBFF')
      .borderRadius(16)
      .margin({ top: COLLECTION_SECTION_GAP })
    }
  }

  @Builder CollectTab(scene: WorkflowSceneConfig) {
    // 顶部分段控制器，切换后所有统计卡片和列表内容通过 collectionModule 派生。
    Text(scene.label)
      .fontSize(13)
      .fontWeight(this.collectionModule === scene.sceneId ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.collectionModule === scene.sceneId ? Color.White : '#6D7481')
      .height(38)
      .padding({ left: 16, right: 16 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.collectionModule === scene.sceneId ? scene.color : Color.White)
      .borderRadius(10)
      .margin({ left: scene.sceneId === 0 ? 0 : 10 })
      .onClick(() => {
        this.collectionModule = scene.sceneId;
        this.groupPageIndex = 0;
      })
  }

  @Builder GroupThumbnail(group: CollectionGroupViewModel) {
    if (group.thumbnailUri.length > 0) {
      Image(group.thumbnailUri)
        .width(58)
        .height(58)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#EEF2F7')
        .borderRadius(11)
    } else {
      Column() {
        Text('暂无图片')
          .fontSize(10)
          .fontColor('#8A92A3')
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
      .width(58)
      .height(58)
      .backgroundColor('#EEF2F7')
      .borderRadius(11)
    }
  }

  @Builder GroupRow(group: CollectionGroupViewModel) {
    Row() {
      this.GroupThumbnail(group)
      Column() {
        Text(group.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(group.source).fontSize(12).fontColor('#7C8494').margin({ top: 5 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(group.time).fontSize(12).fontColor('#7C8494').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12, right: 8 })
      Column() {
        Text(group.meta).fontSize(13).fontColor('#161B28').maxLines(1)
        Text('详情').fontSize(12).fontColor('#8066FF').margin({ top: 6 }).maxLines(1)
      }.alignItems(HorizontalAlign.End)
    }.width('100%').padding({ top: 10, bottom: 10 }).onClick(() => {
      router.pushUrl({
        url: 'pages/collection/CollectionGroupDetailPage',
        params: {
          tabIndex: this.collectionModule,
          groupId: group.id
        }
      });
    })
  }

  @Builder CollectionRows() {
    if (this.groupCount() === 0) {
      Column() {
        Text('暂无已整理记录').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#151A28')
        Text('生成日志后，点击同步即可开始整理').fontSize(12).fontColor('#7C8494').margin({ top: 6 })
      }.width('100%').height(92).justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.currentPageGroups(), (group: CollectionGroupViewModel) => {
          ListItem() {
            Column() {
              this.GroupRow(group)
              Divider().color('#EEF0F5')
            }
            .width('100%')
          }
          .width('100%')
        }, (group: CollectionGroupViewModel) => group.id)
      }
      .width('100%')
      .alignListItem(ListItemAlign.Start)
      .scrollBar(BarState.Off)
    }
  }

  @Builder GroupPagination() {
    if (this.shouldShowGroupPagination()) {
      Row() {
        Button('上一页')
          .fontSize(12)
          .fontColor(this.currentGroupPageIndex() > 0 ? '#8066FF' : '#A7ADBA')
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.currentGroupPageIndex() > 0 ? '#F0ECFF' : '#EEF0F5')
          .enabled(this.currentGroupPageIndex() > 0)
          .onClick(() => {
            this.setGroupPage(this.currentGroupPageIndex() - 1);
          })
        Text(`${this.currentGroupPageIndex() + 1}/${this.groupPageCount()}`)
          .fontSize(13)
          .fontColor('#6D7481')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .maxLines(1)
        Button('下一页')
          .fontSize(12)
          .fontColor(this.currentGroupPageIndex() < this.groupPageCount() - 1 ? '#8066FF' : '#A7ADBA')
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.currentGroupPageIndex() < this.groupPageCount() - 1 ? '#F0ECFF' : '#EEF0F5')
          .enabled(this.currentGroupPageIndex() < this.groupPageCount() - 1)
          .onClick(() => {
            this.setGroupPage(this.currentGroupPageIndex() + 1);
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
  }

  @Builder GroupRangeLabel() {
    Text(`共${this.groupCount()}组`)
      .fontSize(13)
      .fontColor('#7F8592')
      .maxLines(1)
  }

  @Builder PreferenceLine(color: string, name: string, value: string, widthValue: string) {
    // 消费偏好条形图的最小复用单元。
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

        Scroll() {
          Row() {
            ForEach(workflowSceneConfigs(), (scene: WorkflowSceneConfig) => {
              this.CollectTab(scene)
            }, (scene: WorkflowSceneConfig) => scene.tabId)
          }.padding({ left: 24, right: 24 })
        }
        .width('100%')
        .height(42)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .margin({ top: COLLECTION_SECTION_GAP, bottom: 0 })

        Row() {
          Column() {
            Text('已整理').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionCount()).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#8066FF').margin({ top: 3 }).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Divider().vertical(true).height(44).color('#E7E9F0')
          Column() {
            Text('最近同步').fontSize(12).fontColor('#737987').maxLines(1)
            Text(this.getCollectionSyncTime()).fontSize(16).fontColor('#151A28').margin({ top: 5 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding({ left: 18, right: 10 })
          Text(this.refreshing ? '整理中' : '同步')
            .fontSize(12)
            .fontColor('#8066FF')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor('#F0ECFF')
            .borderRadius(22)
            .onClick(() => {
              dataManagerInfo(`Collection sync tapped: refreshing=${this.refreshing}, tab=${this.collectionModule}`);
              if (this.refreshing) {
                return;
              }
              this.onRefresh();
            })
        }
        .width('86%')
        .height(82)
        .padding({ left: 22, right: 16 })
        .backgroundColor('#F8FAFE')
        .borderRadius(16)
        .margin({ top: COLLECTION_SECTION_GAP })

        Column() {
          Row() {
            Text(this.getCollectionTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            this.GroupRangeLabel()
          }.width('100%').margin({ bottom: 8 })
          this.CollectionRows()
          this.GroupPagination()
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: COLLECTION_SECTION_GAP })

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
            Text('你在数码和食品品类的消费较多').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#6D62F5').layoutWeight(1).margin({ left: 10 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('详情').fontSize(12).fontColor('#9AA0AA')
          }.width('100%').height(46).padding({ left: 16, right: 12 }).backgroundColor('#F2EEFF').borderRadius(12)
        }.width('86%').padding(20).backgroundColor('#F9FBFF').borderRadius(16).margin({ top: COLLECTION_SECTION_GAP })

        this.WechatAutoSummaryCard()

        Column() {
          Text('+  新增采集源').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('连接更多平台，采集更多数据').fontSize(12).fontColor('#E8E2FF').margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .width('86%')
        .height(72)
        .backgroundColor('#725CFF')
        .borderRadius(18)
        .margin({ top: COLLECTION_SECTION_GAP })
        .onClick(() => { this.onOpenDataCollectionSettings(); })

        Column() {
          Text('图库分析').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('采集相册、截图和文档图片，进行 OCR 与分类整理').fontSize(12).fontColor('#E9F7FF').margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .width('86%')
        .height(72)
        .backgroundColor('#4B8BFF')
        .borderRadius(18)
        .margin({ top: COLLECTION_SECTION_GAP })
        .onClick(() => { router.pushUrl({ url: 'pages/gallery/GalleryPage' }); })
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }
}
