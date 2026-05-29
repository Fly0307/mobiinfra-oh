import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { DataManagerFacade } from '../../datamanager/DataManagerFacade';
import {
  CollectionEventViewModel,
  CollectionGroupViewModel,
  JsonMap
} from '../../datamanager/DataManagerTypes';

@Entry
@Component
struct CollectionGroupDetailPage {
  @State title: string = '采集详情';
  @State events: CollectionEventViewModel[] = [];
  @State expandedEventId: string = '';
  private detailTabIndex: number = 1;
  private groupId: string = '';

  aboutToAppear(): void {
    this.readParams();
    this.loadGroup();
  }

  private readParams(): void {
    let params = router.getParams() as JsonMap;
    if (!params) {
      return;
    }
    let rawTabIndex = Number(params['tabIndex']);
    if (!isNaN(rawTabIndex)) {
      this.detailTabIndex = rawTabIndex;
    }
    let rawGroupId = params['groupId'];
    this.groupId = rawGroupId === null || rawGroupId === undefined ? '' : String(rawGroupId);
  }

  private loadGroup(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    let facade = new DataManagerFacade(ctx.filesDir);
    facade.ensureReady();
    let group = facade.loadCollectionGroupViewModel(this.detailTabIndex, this.groupId);
    if (group !== null) {
      this.applyGroup(group);
      return;
    }
    this.title = '采集详情';
    this.events = [];
  }

  private applyGroup(group: CollectionGroupViewModel): void {
    this.title = group.title;
    this.events = group.events;
  }

  private isExpanded(eventId: string): boolean {
    return this.expandedEventId === eventId;
  }

  private toggleExpanded(eventId: string): void {
    this.expandedEventId = this.expandedEventId === eventId ? '' : eventId;
  }

  private eventText(event: CollectionEventViewModel): string {
    return event.fullText.length > 0 ? event.fullText : event.summary;
  }

  private canExpand(event: CollectionEventViewModel): boolean {
    return this.eventText(event).length > 72;
  }

  private collapsedPrefix(event: CollectionEventViewModel): string {
    let text = this.eventText(event);
    if (!this.canExpand(event)) {
      return text;
    }
    return text.substring(0, 72);
  }

  @Builder EventCard(event: CollectionEventViewModel) {
    Column() {
      if (this.isExpanded(event.id)) {
        Text(this.eventText(event))
          .fontSize(15)
          .fontColor('#151A28')
          .fontWeight(FontWeight.Medium)
          .lineHeight(22)
          .width('100%')
        if (this.canExpand(event)) {
          Text('收起')
            .fontSize(14)
            .fontColor('#8066FF')
            .fontWeight(FontWeight.Medium)
            .margin({ top: 6 })
            .onClick(() => {
              this.toggleExpanded(event.id);
            })
        }
      } else if (this.canExpand(event)) {
        Text() {
          Span(this.collapsedPrefix(event))
          Span('...展开')
            .fontColor('#8066FF')
            .fontWeight(FontWeight.Medium)
        }
          .fontSize(15)
          .fontColor('#151A28')
          .fontWeight(FontWeight.Medium)
          .lineHeight(22)
          .width('100%')
          .onClick(() => {
            this.toggleExpanded(event.id);
          })
      } else {
        Text(this.eventText(event))
          .fontSize(15)
          .fontColor('#151A28')
          .fontWeight(FontWeight.Medium)
          .lineHeight(22)
          .width('100%')
      }
      Text(event.time)
        .fontSize(12)
        .fontColor('#7C8494')
        .margin({ top: 8 })
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  build() {
    Column() {
      Row() {
        Text('返回')
          .fontSize(14)
          .fontColor('#8066FF')
          .height(36)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#F0ECFF')
          .borderRadius(18)
          .onClick(() => {
            router.back();
          })
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .layoutWeight(1)
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('86%')
      .margin({ top: 18, bottom: 14 })

      if (this.events.length === 0) {
        Column() {
          Text('暂无已整理记录')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
          Text('返回采集页后重新同步或重分组')
            .fontSize(12)
            .fontColor('#7C8494')
            .margin({ top: 8 })
        }
        .width('86%')
        .height(140)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
      } else {
        List({ space: 12 }) {
          ForEach(this.events, (event: CollectionEventViewModel) => {
            ListItem() {
              this.EventCard(event)
            }
            .width('100%')
          }, (event: CollectionEventViewModel) => event.id)
        }
        .width('86%')
        .layoutWeight(1)
        .alignListItem(ListItemAlign.Center)
        .padding({ bottom: 40 })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#F4F8FF')
  }
}

