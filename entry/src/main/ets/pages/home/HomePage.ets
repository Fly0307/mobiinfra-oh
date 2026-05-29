import { AppHeader } from '../../components/AppHeader';
import {
  HomeDomainViewModel,
  HomeProfileViewModel,
  HomeRecommendationViewModel
} from '../../datamanager/DataManagerTypes';
import { createEmptyHomeProfileViewModel } from '../../datamanager/DataManagerFacade';

@Component
export struct HomePage {
  @Prop profile: HomeProfileViewModel = createEmptyHomeProfileViewModel();

  @Builder FeaturePill(icon: string, title: string, desc: string) {
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

  @Builder LifestyleItem(icon: string, title: string, desc: string, color: string) {
    Column() {
      Text(icon).fontSize(13).fontColor(color).fontWeight(FontWeight.Bold).height(18).textAlign(TextAlign.Center).maxLines(1)
      Column() {
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#151A28').maxLines(1)
        Text(desc).fontSize(11).fontColor('#818795').margin({ top: 2 }).maxLines(1)
      }.alignItems(HorizontalAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
  }

  private recommendationImage(domain: string): Resource {
    if (domain === 'eat') {
      return $r('app.media.rec_food');
    }
    if (domain === 'travel' || domain === 'live') {
      return $r('app.media.rec_travel');
    }
    return $r('app.media.rec_sport');
  }

  @Builder RecommendCard(image: Resource, tag: string, title: string, desc: string, meta: string, color: string) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(image).width('100%').height(116).objectFit(ImageFit.Cover)
        Text(tag)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(color)
          .borderRadius(8)
          .margin({ left: 10, top: 10 })
      }.width('100%').height(116)
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(desc)
          .fontSize(12)
          .fontColor('#787F8E')
          .width('100%')
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(meta).fontSize(12).fontColor('#7C8494').layoutWeight(1).maxLines(1)
          Text('>').fontSize(18).fontColor(Color.White).textAlign(TextAlign.Center).width(30).height(30).backgroundColor(color).borderRadius(15)
        }.width('100%').margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 14 })
    }
    .alignItems(HorizontalAlign.Start)
    .width(158)
    .height(234)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .clip(true)
    .shadow({ radius: 18, color: '#16000000', offsetX: 0, offsetY: 8 })
  }

  build() {
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
            this.LifestyleItem(item.icon, item.title, item.desc, item.color)
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
          Text('换一批').fontSize(14).fontColor('#858B98')
        }.width('92%').margin({ top: 24, bottom: 14 })

        Scroll() {
          Row() {
            ForEach(this.profile.recommendations, (item: HomeRecommendationViewModel) => {
              this.RecommendCard(this.recommendationImage(item.domain), item.tag, item.title, item.desc, item.meta, item.color)
              Blank().width(14)
            }, (item: HomeRecommendationViewModel) => item.id)
          }
          .padding({ left: 18, right: 18, bottom: 6 })
        }
        .width('100%')
        .height(250)
        .scrollable(ScrollDirection.Horizontal)

        Blank().height(88)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }
}

