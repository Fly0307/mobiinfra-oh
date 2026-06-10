import { AppHeader } from '../../components/AppHeader';
import {
  HomeDomainViewModel,
  HomeProfileViewModel,
  HomeRecommendationViewModel
} from '../../datamanager/DataManagerTypes';
import { createEmptyHomeProfileViewModel } from '../../datamanager/DataManagerFacade';
import { AvatarDomainSnapshot, AvatarGenerationMode, AvatarVersionViewModel } from '../../datamanager/avatar/AvatarTypes';
import { GalleryPhotoPicker } from '../../utils/gallery/GalleryPhotoPicker';
import { promptAction } from '@kit.ArkUI';
import { showToastSafely } from '../../utils/PromptSafe';

// “数据归家”首页展示层：只做静态画像、推荐和进度概览，不承载推理/Agent 逻辑。
@Component
export struct HomePage {
  @Prop profile: HomeProfileViewModel = createEmptyHomeProfileViewModel();
  @Prop avatarVersions: AvatarVersionViewModel[] = [];
  onExecuteAgentTask: (taskDescription: string) => Promise<void> = async (taskDescription: string) => {};
  onGenerateAvatar: (mode: AvatarGenerationMode, sourceImage: string) => Promise<void> =
    async (mode: AvatarGenerationMode, sourceImage: string) => {};
  @State recommendationBatchIndex: number = 0;
  @State selectedRecommendationId: string = '';
  @State agentTaskDraft: string = '';
  @State agentTaskSubmitting: boolean = false;
  @State avatarGenerationOpen: boolean = false;
  @State avatarGenerating: boolean = false;
  @State avatarHistoryOpen: boolean = false;
  @State selectedAvatarVersionId: string = '';
  @State selectedAvatarPhotoUri: string = '';

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

  private avatarStatusLabel(): string {
    if (this.avatarGenerating || this.profile.avatarStatus === 'generating') {
      return '正在生成数字分身';
    }
    if (this.profile.avatarStatus === 'stale') {
      return '可更新数字分身';
    }
    if (this.profile.avatarStatus === 'current') {
      return '你的数字分身已更新';
    }
    if (this.profile.avatarStatus === 'failed') {
      return '上次生成失败，可重试';
    }
    return this.profile.empty ? '等待导入数据生成数字分身' : '可生成数字分身';
  }

  private avatarActionLabel(): string {
    if (this.avatarGenerating || this.profile.avatarStatus === 'generating') {
      return '生成中';
    }
    if (this.profile.avatarStatus === 'stale') {
      return '可更新数字分身';
    }
    if (this.profile.avatarActionLabel.length > 0) {
      return this.profile.avatarActionLabel;
    }
    return this.profile.avatarUri.length > 0 ? '更新数字分身' : '生成数字分身';
  }

  private avatarUpdatedLabel(): string {
    if (this.profile.avatarUpdatedLabel.length > 0) {
      return this.profile.avatarUpdatedLabel;
    }
    return this.profile.updatedLabel;
  }

  private async submitAvatarGeneration(): Promise<void> {
    if (this.avatarGenerating) {
      return;
    }
    this.avatarGenerating = true;
    try {
      await this.onGenerateAvatar('text_to_image', '');
      this.avatarGenerationOpen = false;
    } catch (e) {
      let err = e as Error;
      console.error('submitAvatarGeneration failed: ' + err.message);
    } finally {
      this.avatarGenerating = false;
    }
  }

  private async selectAvatarReferencePhoto(): Promise<void> {
    if (this.avatarGenerating) {
      return;
    }
    try {
      let picker = new GalleryPhotoPicker();
      let uris = await picker.selectImageUris(1);
      if (uris.length === 0) {
        showToastSafely('未选择照片', 1200);
        return;
      }
      this.selectedAvatarPhotoUri = uris[0];
    } catch (e) {
      let err = e as Error;
      showToastSafely('选择照片失败：' + err.message, 1800);
    }
  }

  private async submitAvatarPhotoGeneration(): Promise<void> {
    if (this.avatarGenerating) {
      return;
    }
    if (this.selectedAvatarPhotoUri.length === 0) {
      showToastSafely('请先选择参考照片', 1200);
      return;
    }
    this.avatarGenerating = true;
    try {
      await this.onGenerateAvatar('image_to_image', this.selectedAvatarPhotoUri);
      this.avatarGenerationOpen = false;
    } catch (e) {
      let err = e as Error;
      console.error('submitAvatarPhotoGeneration failed: ' + err.message);
    } finally {
      this.avatarGenerating = false;
    }
  }

  private selectedAvatarVersionItems(): AvatarVersionViewModel[] {
    if (this.selectedAvatarVersionId.length === 0) {
      return [];
    }
    return this.avatarVersions.filter((item: AvatarVersionViewModel): boolean => {
      return item.versionId === this.selectedAvatarVersionId;
    }).slice(0, 1);
  }

  private avatarModeLabel(mode: AvatarGenerationMode): string {
    return mode === 'image_to_image' ? '照片参考生成' : '画像生成';
  }

  private avatarParamsLabel(item: AvatarVersionViewModel): string {
    return item.generationParams.size + ' / ' + item.generationParams.response_format + ' / ' +
      item.generationParams.output_format;
  }

  private avatarConsentLabel(item: AvatarVersionViewModel): string {
    return item.consentSnapshot.photo_used ? '已使用授权照片' : '未使用照片';
  }

  private avatarDemographicLabel(item: AvatarVersionViewModel): string {
    let genderText = item.profileSnapshot.gender;
    let ageText = item.profileSnapshot.age;
    let gender = genderText !== undefined && genderText.length > 0 ? genderText : '未设置';
    let age = ageText !== undefined && ageText.length > 0 ? ageText : '未设置';
    return '性别：' + gender + ' · 年龄：' + age;
  }

  @Builder AvatarImage() {
    if (this.profile.avatarUri.length > 0) {
      Image(this.profile.avatarUri)
        .width('92%')
        .height(270)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E8F1FF')
        .borderRadius(20)
        .clip(true)
        .margin({ top: 8 })
        .onClick(() => {
          this.avatarGenerationOpen = true;
        })
    } else {
      Image($r('app.media.digital_avatar'))
        .width('92%')
        .height(270)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E8F1FF')
        .borderRadius(20)
        .clip(true)
        .margin({ top: 8 })
        .onClick(() => {
          this.avatarGenerationOpen = true;
        })
    }
  }

  @Builder AvatarHistoryEntry(item: AvatarVersionViewModel) {
    Row() {
      if (item.imageUri.length > 0) {
        Image(item.imageUri)
          .width(64)
          .height(82)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
      } else {
        Column() {
          Text('无图').fontSize(12).fontColor('#8B93A4')
        }
        .justifyContent(FlexAlign.Center)
        .width(64)
        .height(82)
        .backgroundColor('#EEF2F7')
        .borderRadius(12)
      }
      Column() {
        Text(item.createdAt.length > 0 ? item.createdAt : '未知时间')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.avatarModeLabel(item.mode) + ' · ' + item.provider)
          .fontSize(12)
          .fontColor('#6F7684')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.model)
          .fontSize(12)
          .fontColor('#8A92A3')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.avatarParamsLabel(item))
          .fontSize(12)
          .fontColor('#8A92A3')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text('>').fontSize(18).fontColor('#A4ABBA')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F8FBFF')
    .borderRadius(14)
    .margin({ top: 10 })
    .onClick(() => {
      this.selectedAvatarVersionId = item.versionId;
    })
  }

  @Builder AvatarEvidenceDomain(item: AvatarDomainSnapshot) {
    Column() {
      Row() {
        Text(item.display_name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .layoutWeight(1)
        Text(item.event_count + ' 条')
          .fontSize(12)
          .fontColor('#8A92A3')
      }
      .width('100%')
      Text(item.short_summary.length > 0 ? item.short_summary : '暂无摘要')
        .fontSize(13)
        .fontColor('#4E5668')
        .width('100%')
        .margin({ top: 6 })
      ForEach(item.claims.slice(0, 3), (claim: string) => {
        Text('· ' + claim)
          .fontSize(12)
          .fontColor('#6F7684')
          .width('100%')
          .margin({ top: 4 })
      }, (claim: string) => claim)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F8FBFF')
    .borderRadius(12)
    .margin({ top: 8 })
  }

  @Builder AvatarVersionDetailOverlay(item: AvatarVersionViewModel) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.selectedAvatarVersionId = '';
        })
      Column() {
        Row() {
          Text('生成依据')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .layoutWeight(1)
          Text('返回')
            .fontSize(13)
            .fontColor('#7C8494')
            .onClick(() => {
              this.selectedAvatarVersionId = '';
            })
        }.width('100%')
        Scroll() {
          Column() {
            if (item.imageUri.length > 0) {
              Image(item.imageUri)
                .width('100%')
                .height(220)
                .objectFit(ImageFit.Contain)
                .borderRadius(14)
                .backgroundColor('#F5F7FB')
                .margin({ top: 14 })
            }
            Text(item.createdAt + ' · ' + this.avatarModeLabel(item.mode))
              .fontSize(13)
              .fontColor('#6F7684')
              .width('100%')
              .margin({ top: 14 })
            Text(item.provider + ' / ' + item.model)
              .fontSize(13)
              .fontColor('#4E5668')
              .width('100%')
              .margin({ top: 6 })
            Text(this.avatarParamsLabel(item) + ' · ' + this.avatarConsentLabel(item))
              .fontSize(13)
              .fontColor('#4E5668')
              .width('100%')
              .margin({ top: 6 })
            Text(this.avatarDemographicLabel(item))
              .fontSize(13)
              .fontColor('#4E5668')
              .width('100%')
              .margin({ top: 6 })
            Text('画像摘要')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
              .width('100%')
              .margin({ top: 18 })
            ForEach(item.profileSnapshot.domains, (domain: AvatarDomainSnapshot) => {
              this.AvatarEvidenceDomain(domain)
            }, (domain: AvatarDomainSnapshot) => domain.domain + '-' + domain.short_summary)
            Text('Prompt')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
              .width('100%')
              .margin({ top: 18 })
            Text(item.promptSnapshot)
              .fontSize(12)
              .fontColor('#4E5668')
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('#F8FBFF')
              .borderRadius(12)
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .width('100%')
        .height(560)
        .scrollBar(BarState.Off)
      }
      .alignItems(HorizontalAlign.Start)
      .width('90%')
      .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 22, color: '#26000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(102)
  }

  @Builder AvatarHistoryOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.avatarHistoryOpen = false;
          this.selectedAvatarVersionId = '';
        })
      Column() {
        Row() {
          Text('历史记录')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .layoutWeight(1)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7C8494')
            .onClick(() => {
              this.avatarHistoryOpen = false;
              this.selectedAvatarVersionId = '';
            })
        }.width('100%')
        if (this.avatarVersions.length === 0) {
          Text('暂无历史数字分身')
            .fontSize(14)
            .fontColor('#7C8494')
            .width('100%')
            .margin({ top: 20 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.avatarVersions, (item: AvatarVersionViewModel) => {
                this.AvatarHistoryEntry(item)
              }, (item: AvatarVersionViewModel) => item.versionId)
            }
            .width('100%')
          }
          .width('100%')
          .height(430)
          .scrollBar(BarState.Off)
          .margin({ top: 8 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('90%')
      .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 22, color: '#26000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(101)
  }

  @Builder AvatarGenerationOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.avatarGenerationOpen = false;
        })
      Column() {
        Row() {
          Text('数字分身')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .layoutWeight(1)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7C8494')
            .onClick(() => {
              this.avatarGenerationOpen = false;
            })
        }.width('100%')

        Text(this.avatarStatusLabel())
          .fontSize(14)
          .fontColor('#4E5668')
          .width('100%')
          .margin({ top: 12 })

        Row() {
          Column() {
            Text('画像生成')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
            Text('使用当前吃穿住行画像生成首页数字分身')
              .fontSize(12)
              .fontColor('#6F7684')
              .margin({ top: 4 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('已选择')
            .fontSize(12)
            .fontColor('#8066FF')
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor('#F1EEFF')
            .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#F8FBFF')
        .borderRadius(14)
        .margin({ top: 18 })

        Row() {
          Column() {
            Text('照片参考')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
            Text(this.selectedAvatarPhotoUri.length > 0 ? '已选择照片，可结合画像生成' : '选择一张个人照片作为形象参考')
              .fontSize(12)
              .fontColor('#6F7684')
              .margin({ top: 4 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text(this.selectedAvatarPhotoUri.length > 0 ? '重选' : '选择')
            .fontSize(12)
            .fontColor('#8066FF')
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor('#F1EEFF')
            .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#F5F7FB')
        .borderRadius(14)
        .margin({ top: 10 })
        .onClick(() => {
          this.selectAvatarReferencePhoto();
        })

        if (this.selectedAvatarPhotoUri.length > 0) {
          Column() {
            Image(this.selectedAvatarPhotoUri)
              .width('100%')
              .height(160)
              .objectFit(ImageFit.Contain)
              .borderRadius(12)
              .backgroundColor('#F5F7FB')
            Button(this.avatarGenerating ? '生成中...' : '使用照片生成')
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .backgroundColor(this.avatarGenerating ? '#A9B7E9' : '#8066FF')
              .borderRadius(14)
              .margin({ top: 10 })
              .enabled(!this.avatarGenerating)
              .onClick(() => {
                this.submitAvatarPhotoGeneration();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }

        Row() {
          Column() {
            Text('历史记录 / 生成依据')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
            Text(this.avatarVersions.length > 0 ? '查看缩略图、模型参数和画像证据' : '生成后可查看每次的画像证据')
              .fontSize(12)
              .fontColor('#6F7684')
              .margin({ top: 4 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text(this.avatarVersions.length + ' 条')
            .fontSize(12)
            .fontColor('#8066FF')
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor('#F1EEFF')
            .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#F8FBFF')
        .borderRadius(14)
        .margin({ top: 10 })
        .onClick(() => {
          this.avatarHistoryOpen = true;
        })

        Button(this.avatarGenerating ? '生成中...' : this.avatarActionLabel())
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(this.avatarGenerating ? '#A9B7E9' : '#8066FF')
          .borderRadius(15)
          .margin({ top: 18 })
          .enabled(!this.avatarGenerating)
          .onClick(() => {
            this.submitAvatarGeneration();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('88%')
      .padding({ left: 18, right: 18, top: 20, bottom: 20 })
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 22, color: '#26000000', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
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

  @Builder RecommendCard(item: HomeRecommendationViewModel) {
    // 推荐卡片横滑列表，统一图片、标签、标题和元信息的布局。
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.RecommendationImage(item)
        Text(item.tag)
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
          .fontColor('#151A28')
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
      this.selectedRecommendationId = item.id;
      this.agentTaskDraft = item.agentTask;
    })
  }

  @Builder EmptyRecommendationCard() {
    Row() {
      Text('暂无待办事项')
        .fontSize(14)
        .fontColor('#7C8494')
    }
    .width('92%')
    .margin({ top: 2 })
  }

  private recommendationPageCount(): number {
    return Math.max(1, Math.ceil(this.profile.recommendations.length / 4));
  }

  private recommendationPageItems(): HomeRecommendationViewModel[] {
    if (this.profile.recommendations.length === 0) {
      return [];
    }
    let page = this.recommendationBatchIndex % this.recommendationPageCount();
    let start = page * 4;
    return this.profile.recommendations.slice(start, start + 4);
  }

  private nextRecommendationBatch(): void {
    if (this.profile.recommendations.length <= 4) {
      return;
    }
    this.recommendationBatchIndex = (this.recommendationBatchIndex + 1) % this.recommendationPageCount();
  }

  private selectedRecommendationItems(): HomeRecommendationViewModel[] {
    if (this.selectedRecommendationId.length === 0) {
      return [];
    }
    return this.profile.recommendations.filter((item: HomeRecommendationViewModel): boolean => item.id === this.selectedRecommendationId).slice(0, 1);
  }

  private async executeAgentTask(): Promise<void> {
    let task = this.agentTaskDraft.trim();
    if (task.length === 0) {
      showToastSafely('请输入要执行的任务', 1200);
      return;
    }
    if (this.agentTaskSubmitting) {
      return;
    }
    this.agentTaskSubmitting = true;
    try {
      await this.onExecuteAgentTask(task);
      this.selectedRecommendationId = '';
    } catch (e) {
      let err = e as Error;
      showToastSafely('任务下发失败：' + err.message, 1800);
    } finally {
      this.agentTaskSubmitting = false;
    }
  }

  @Builder RecommendationDetailImage(item: HomeRecommendationViewModel) {
    if (item.thumbnailUri.length > 0) {
      Scroll() {
        Row() {
          Image(item.thumbnailUri)
            .width(128)
            .height(260)
            .objectFit(ImageFit.Contain)
            .borderRadius(12)
        }
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height(270)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .margin({ top: 14 })
    } else {
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
    }
  }

  @Builder RecommendationDetailOverlay(item: HomeRecommendationViewModel) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.selectedRecommendationId = '';
        })
      Column() {
        Row() {
          Text(item.tag)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(item.color)
            .borderRadius(8)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7C8494')
            .margin({ left: 12 })
            .onClick(() => {
              this.selectedRecommendationId = '';
            })
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        Text(item.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#151A28')
          .width('100%')
          .margin({ top: 14 })
        this.RecommendationDetailImage(item)
        Text(item.desc.length > 0 ? item.desc : '暂无描述')
          .fontSize(14)
          .fontColor('#4E5668')
          .width('100%')
          .margin({ top: 14 })
        if (item.agentTask.length > 0) {
          Column() {
            Text('执行任务')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#151A28')
              .width('100%')
            TextArea({ placeholder: '调整要交给 GUI Agent 的任务', text: this.agentTaskDraft })
              .width('100%')
              .height(92)
              .fontSize(14)
              .fontColor('#222B3A')
              .backgroundColor('#F5F7FB')
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
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
          this.AvatarImage()

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
            Text(this.avatarStatusLabel()).fontSize(16).fontColor('#1B2030').margin({ left: 8 }).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.avatarUpdatedLabel() + ' >').fontSize(13).fontColor('#7B8190').margin({ left: 8 }).width(88).textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('82%')
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor(Color.White)
          .borderRadius(21)
          .margin({ top: 12, bottom: 16 })
          .onClick(() => {
            this.avatarGenerationOpen = true;
          })
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
            Text('换一批')
              .fontSize(14)
              .fontColor(this.profile.recommendations.length > 4 ? '#8066FF' : '#C0C5D0')
              .onClick(() => {
                this.nextRecommendationBatch();
              })
          }.width('92%').margin({ top: 24, bottom: 14 })

          if (this.profile.recommendations.length === 0) {
            this.EmptyRecommendationCard()
          } else {
            Grid() {
              ForEach(this.recommendationPageItems(), (item: HomeRecommendationViewModel) => {
                GridItem() {
                  this.RecommendCard(item)
                }
              }, (item: HomeRecommendationViewModel) => item.id + '-' + item.title)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(12)
            .rowsGap(12)
            .width('92%')
            .height(368)
          }

          Blank().height(88)
        }.width('100%')
      }.width('100%').height('100%').backgroundColor('#F4F8FF')

      ForEach(this.selectedRecommendationItems(), (item: HomeRecommendationViewModel) => {
        this.RecommendationDetailOverlay(item)
      }, (item: HomeRecommendationViewModel) => item.id)
      if (this.avatarGenerationOpen) {
        this.AvatarGenerationOverlay()
      }
      if (this.avatarHistoryOpen) {
        this.AvatarHistoryOverlay()
      }
      ForEach(this.selectedAvatarVersionItems(), (item: AvatarVersionViewModel) => {
        this.AvatarVersionDetailOverlay(item)
      }, (item: AvatarVersionViewModel) => item.versionId)
    }
    .width('100%')
    .height('100%')
  }
}
