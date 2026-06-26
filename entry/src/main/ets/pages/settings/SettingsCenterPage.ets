import { router } from '@kit.ArkUI';
import { AppHeader } from '../../components/AppHeader';
import { DEFAULT_ENDPOINT_CONFIG } from '../../config/DefaultEndpointConfig';
import { DEFAULT_MODELSCOPE_MNN_REPO } from '../../config/ModelDownloadConfig';
import {
  CHAT_CONTEXT_COMPRESSION_THRESHOLD_PERCENT_DEFAULT,
  CHAT_CONTEXT_RECENT_ROUNDS_DEFAULT,
  normalizeChatContextCompressionThresholdPercent,
  normalizeChatContextRecentRounds
} from '../chat/ChatContextBudget';
import {
  DEFAULT_GALLERY_AMAP_WEB_KEY,
  DEFAULT_GALLERY_API_BASE_URL,
  DEFAULT_GALLERY_API_KEY,
  DEFAULT_GALLERY_EMBEDDING_API_KEY,
  DEFAULT_GALLERY_EMBEDDING_BASE_URL,
  DEFAULT_GALLERY_EMBEDDING_CONCURRENCY,
  DEFAULT_GALLERY_EMBEDDING_MODE,
  DEFAULT_GALLERY_EMBEDDING_MODEL,
  DEFAULT_GALLERY_IMAGE_SCALE,
  DEFAULT_GALLERY_MODEL,
  DEFAULT_GALLERY_MODEL_CONCURRENCY,
  DEFAULT_GALLERY_OCR_CONCURRENCY,
  DEFAULT_GALLERY_PARALLEL_FIELD_REQUESTS,
  DEFAULT_GALLERY_SKIP_OCR,
  DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER,
  registerGallerySettingsDefaults
} from '../../utils/gallery/GallerySettingsDefaults';
import { showToastSafely } from '../../utils/PromptSafe';
import {
  DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
  DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED,
  DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES,
  DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES,
  DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED,
  DEFAULT_WECHAT_AUTO_SUMMARY_WAIT,
  normalizeWechatAutoSummaryDays,
  normalizeWechatAutoSummaryHistorySwipeRatio,
  normalizeWechatAutoSummaryMaxContacts,
  normalizeWechatAutoSummaryMaxHistorySwipes,
  normalizeWechatAutoSummaryStableSwipes,
  normalizeWechatAutoSummarySwipeSpeed,
  normalizeWechatAutoSummaryWait
} from '../../utils/wechat/WechatAutoSummaryTypes';
import {
  isSettingsSectionSelected,
  normalizeSettingsSectionId,
  SETTINGS_SECTION_ITEMS,
  SETTINGS_SECTION_NONE,
  SettingsSectionItem,
  SettingsSectionId,
  settingsSectionSubtitle,
  settingsSectionTitle
} from './SettingsCenterTypes';

registerGallerySettingsDefaults();

interface DownloadedModelItem {
  id: string;
  label: string;
  path: string;
  repo: string;
  sizeText: string;
  statusText: string;
  ready: boolean;
}

@Component
export struct SettingsCenterPage {
  @Link autoConfirm: boolean;
  @Link cloudAutoConfirm: boolean;
  @Link threadNumInput: string;
  @Link backendTypeInput: string;
  @Link mllmBackendTypeInput: string;
  @Link selectedSectionId: number;
  @Link output: string;
  @Link cloudOutput: string;
  @Link modelDownloadProgressVisible: boolean;
  @Link modelDownloadProgressPercent: number;
  @Link modelDownloadProgressText: string;
  @Link modelDownloadProgressTitle: string;
  @Prop downloading: boolean = false;
  @Prop connected: boolean = false;
  @Prop modelScopeDownloading: boolean = false;
  @Prop modelScopePauseRequested: boolean = false;
  @Prop hdcAutoStatus: string = '';
  @Prop hdcAutoConnected: boolean = false;
  @Prop hdcAutoConnecting: boolean = false;
  @Prop hdcManualPairing: boolean = false;
  @Prop selectedModelVariant: string = '';
  @Prop downloadedModels: DownloadedModelItem[] = [];
  @Prop selectedModelId: string = '';
  @StorageLink('modelScopeMnnRepo') modelScopeMnnRepo: string = DEFAULT_MODELSCOPE_MNN_REPO;
  @StorageLink('serverIp') serverIp: string = DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl;
  @StorageLink('hdcServerIp') hdcServerIp: string = DEFAULT_ENDPOINT_CONFIG.hdcServerUrl;
  @StorageLink('manualHdcServerIp') manualHdcServerIp: string = '';
  @StorageLink('wirelessIp') wirelessIp: string = DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget;
  @StorageLink('cloudPlannerBaseUrl') cloudPlannerBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl;
  @StorageLink('cloudDeciderBaseUrl') cloudDeciderBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl;
  @StorageLink('cloudApiKey') cloudApiKey: string = DEFAULT_ENDPOINT_CONFIG.cloudApiKey;
  @StorageLink('cloudDeciderModel') cloudDeciderModel: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderModel;
  @StorageLink('voiceTtsBaseUrl') voiceTtsBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl;
  @StorageLink('voiceTtsApiKey') voiceTtsApiKey: string = '';
  @StorageLink('voiceTtsModel') voiceTtsModel: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsModel;
  @StorageLink('voiceTtsVoice') voiceTtsVoice: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsVoice;
  @StorageLink('chatContextCompressionThresholdPercent') chatContextCompressionThresholdPercent: string =
    String(CHAT_CONTEXT_COMPRESSION_THRESHOLD_PERCENT_DEFAULT);
  @StorageLink('chatContextRecentRounds') chatContextRecentRounds: string =
    String(CHAT_CONTEXT_RECENT_ROUNDS_DEFAULT);
  @StorageLink('avatarImageBaseUrl') avatarImageBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl;
  @StorageLink('avatarImageApiKey') avatarImageApiKey: string = '';
  @StorageLink('avatarTextToImageModel') avatarTextToImageModel: string = DEFAULT_ENDPOINT_CONFIG.avatarImageModel;
  @StorageLink('avatarImageToImageModel') avatarImageToImageModel: string = DEFAULT_ENDPOINT_CONFIG.avatarImageModel;
  @StorageLink('avatarImageSize') avatarImageSize: string = DEFAULT_ENDPOINT_CONFIG.avatarImageSize;
  @StorageLink('galleryApiBaseUrl') galleryApiBaseUrl: string = DEFAULT_GALLERY_API_BASE_URL;
  @StorageLink('galleryApiKey') galleryApiKey: string = DEFAULT_GALLERY_API_KEY;
  @StorageLink('galleryModel') galleryModel: string = DEFAULT_GALLERY_MODEL;
  @StorageLink('gallerySkipOcr') gallerySkipOcr: string = DEFAULT_GALLERY_SKIP_OCR;
  @StorageLink('galleryUseOcrKeywordFilter') galleryUseOcrKeywordFilter: string = DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER;
  @StorageLink('galleryParallelFieldRequests') galleryParallelFieldRequests: string = DEFAULT_GALLERY_PARALLEL_FIELD_REQUESTS;
  @StorageLink('galleryOcrConcurrency') galleryOcrConcurrency: string = DEFAULT_GALLERY_OCR_CONCURRENCY;
  @StorageLink('galleryModelConcurrency') galleryModelConcurrency: string = DEFAULT_GALLERY_MODEL_CONCURRENCY;
  @StorageLink('galleryEmbeddingConcurrency') galleryEmbeddingConcurrency: string = DEFAULT_GALLERY_EMBEDDING_CONCURRENCY;
  @StorageLink('galleryEmbeddingMode') galleryEmbeddingMode: string = DEFAULT_GALLERY_EMBEDDING_MODE;
  @StorageLink('galleryEmbeddingBaseUrl') galleryEmbeddingBaseUrl: string = DEFAULT_GALLERY_EMBEDDING_BASE_URL;
  @StorageLink('galleryEmbeddingApiKey') galleryEmbeddingApiKey: string = DEFAULT_GALLERY_EMBEDDING_API_KEY;
  @StorageLink('galleryEmbeddingModel') galleryEmbeddingModel: string = DEFAULT_GALLERY_EMBEDDING_MODEL;
  @StorageLink('galleryImageScale') galleryImageScale: string = DEFAULT_GALLERY_IMAGE_SCALE;
  @StorageLink('galleryAmapWebKey') galleryAmapWebKey: string = DEFAULT_GALLERY_AMAP_WEB_KEY;
  @StorageLink('wechatAutoSummaryEnabled') wechatAutoSummaryEnabled: string = DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED;
  @StorageLink('wechatAutoSummaryDefaultDays') wechatAutoSummaryDefaultDays: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_DAYS;
  @StorageLink('wechatAutoSummaryDefaultMaxContacts') wechatAutoSummaryDefaultMaxContacts: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS;
  @StorageLink('wechatAutoSummarySwipeSpeed') wechatAutoSummarySwipeSpeed: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED;
  @StorageLink('wechatAutoSummaryHistorySwipeRatio') wechatAutoSummaryHistorySwipeRatio: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO;
  @StorageLink('wechatAutoSummaryStableSwipes') wechatAutoSummaryStableSwipes: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES;
  @StorageLink('wechatAutoSummaryMaxHistorySwipes') wechatAutoSummaryMaxHistorySwipes: string =
    DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES;
  @StorageLink('wechatAutoSummaryWait') wechatAutoSummaryWait: string = DEFAULT_WECHAT_AUTO_SUMMARY_WAIT;
  @State private wechatAutoSummaryAdvancedOpen: boolean = false;
  onCheckServer: () => void = () => {};
  onDownloadAll: () => void = () => {};
  onDeleteModelFiles: () => void = () => {};
  onDownloadModelScopeModel: () => Promise<void> = async () => {};
  onPauseModelScopeDownload: () => void = () => {};
  onUpdateConfigThreadNum: () => void = () => {};
  onShowConfigJson: () => void = () => {};
  onDiscoverHdc: () => Promise<void> = async () => {};
  onSetHdcManualPairing: () => void = () => {};
  onMarkHdcManualEditing: () => void = () => {};
  onTestAndConnectHdc: () => Promise<void> = async () => {};
  onTestCloudPlanner: () => Promise<void> = async () => {};
  onStartCloudBackend: () => Promise<void> = async () => {};
  onClearScreenshots: () => void = () => {};
  onDeleteDebugOutputs: () => void = () => {};
  onSwitchModelVariant: (variant: string) => void = (variant: string) => {};
  onSwitchDownloadedModel: (modelId: string) => void = (modelId: string) => {};
  onRefreshDownloadedModels: () => void = () => {};
  onListScreenshots: () => void = () => {};
  onDeleteModelConfigJson: () => void = () => {};
  onListModelFilesTree: () => void = () => {};
  onDeleteChunkVisionOmFiles: () => void = () => {};
  onUpdateConfigBackendType: (target: string) => void = (target: string) => {};

  private hdcInputEditable(): boolean {
    return this.hdcManualPairing || !this.hdcAutoConnected;
  }

  private hdcInputBackgroundColor(): string {
    return this.hdcInputEditable() ? '#F2F5FC' : '#E6EAF2';
  }

  private hdcInputTextColor(): string {
    return this.hdcInputEditable() ? '#11182F' : '#7A8494';
  }

  private hdcStatusColor(): string {
    if (this.hdcAutoConnected) {
      return '#2D9B73';
    }
    if (this.hdcAutoConnecting) {
      return '#4F68FF';
    }
    return '#D26B31';
  }

  private openSection(id: SettingsSectionId): void {
    this.selectedSectionId = normalizeSettingsSectionId(id);
  }

  private closeSection(): void {
    this.selectedSectionId = SETTINGS_SECTION_NONE;
  }

  private sectionInitial(id: SettingsSectionId): string {
    if (id === SettingsSectionId.PersonalPrivacy) {
      return 'P';
    }
    if (id === SettingsSectionId.DataCollection) {
      return 'D';
    }
    if (id === SettingsSectionId.ModelAgents) {
      return 'M';
    }
    if (id === SettingsSectionId.TaskAutomation) {
      return 'T';
    }
    return 'S';
  }

  private activeSectionTitle(): string {
    if (this.selectedSectionId === SettingsSectionId.PersonalPrivacy) {
      return settingsSectionTitle(SettingsSectionId.PersonalPrivacy);
    }
    if (this.selectedSectionId === SettingsSectionId.DataCollection) {
      return settingsSectionTitle(SettingsSectionId.DataCollection);
    }
    if (this.selectedSectionId === SettingsSectionId.ModelAgents) {
      return settingsSectionTitle(SettingsSectionId.ModelAgents);
    }
    if (this.selectedSectionId === SettingsSectionId.TaskAutomation) {
      return settingsSectionTitle(SettingsSectionId.TaskAutomation);
    }
    if (this.selectedSectionId === SettingsSectionId.StorageAbout) {
      return settingsSectionTitle(SettingsSectionId.StorageAbout);
    }
    return '';
  }

  @Builder SectionTitle(id: SettingsSectionId) {
    Column() {
      Text(settingsSectionTitle(id))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#11182F')
        .width('100%')
      Text(settingsSectionSubtitle(id))
        .fontSize(12)
        .fontColor('#7B8290')
        .width('100%')
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 14 })
  }

  @Builder FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor('#6F7684')
      .width('100%')
      .margin({ top: 8, bottom: 6 })
  }

  @Builder SettingInput(label: string, value: string, placeholder: string, onValueChange: (value: string) => void) {
    this.FieldLabel(label)
    TextInput({ placeholder: placeholder, text: value })
      .height(42)
      .width('100%')
      .fontSize(13)
      .backgroundColor('#F2F5FC')
      .borderRadius(12)
      .padding({ left: 12, right: 12 })
      .onChange((val: string) => { onValueChange(val); })
  }

  @Builder DownloadedModelList() {
    this.FieldLabel('已下载模型')
    Row() {
      Text(this.downloadedModels.length > 0 ? '点击可加载模型切换后续本地加载路径' : '未扫描到模型目录')
        .fontSize(12)
        .fontColor('#7B8290')
        .layoutWeight(1)
        .maxLines(2)
      Button('刷新')
        .height(32)
        .width(72)
        .fontSize(12)
        .backgroundColor('#607D8B')
        .borderRadius(10)
        .onClick(() => { this.onRefreshDownloadedModels(); })
    }
    .width('100%')
    .margin({ bottom: 8 })

    if (this.downloadedModels.length > 0) {
      Column() {
        ForEach(this.downloadedModels, (item: DownloadedModelItem) => {
          Row() {
            Column() {
              Text(item.label)
                .fontSize(13)
                .fontWeight(this.selectedModelId === item.id ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.selectedModelId === item.id ? '#4F68FF' : '#11182F')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(item.statusText + ' · ' + item.sizeText)
                .fontSize(11)
                .fontColor(item.ready ? '#2D9B73' : '#D26B31')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button(this.selectedModelId === item.id ? (item.statusText === '下载完成' ? '已完成' : '当前') :
              (item.ready ? '切换' : '未完成'))
              .height(32)
              .width(72)
              .fontSize(12)
              .backgroundColor(this.selectedModelId === item.id || !item.ready ? '#A9B0BE' : '#4F68FF')
              .borderRadius(10)
              .enabled(this.selectedModelId !== item.id && item.ready)
              .onClick(() => { this.onSwitchDownloadedModel(item.id); })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor(this.selectedModelId === item.id ? '#EEF4FF' : '#F7F9FC')
          .borderRadius(12)
          .border({ width: 1, color: this.selectedModelId === item.id ? '#BFD3FF' : '#E6EAF2' })
          .margin({ bottom: 8 })
        }, (item: DownloadedModelItem) => item.id + ':' + item.statusText + ':' + item.sizeText + ':' + String(item.ready))
      }
      .width('100%')
    }
  }

  @Builder WechatAutoSummaryInput(label: string, value: string, placeholder: string,
    onValueChange: (value: string) => void, onNormalize: () => void) {
    this.FieldLabel(label)
    TextInput({ placeholder: placeholder, text: value })
      .height(42)
      .width('100%')
      .fontSize(13)
      .backgroundColor('#F2F5FC')
      .borderRadius(12)
      .padding({ left: 12, right: 12 })
      .onChange((input: string) => {
        // 编辑期间保留原文，避免小数和临时空值被立即改写。
        onValueChange(input);
      })
      .onBlur(() => {
        // 失焦后由调用点读取当前字段再归一化，避免使用上一轮渲染入参。
        onNormalize();
      })
  }

  @Builder VariantButton(label: string, variant: string) {
    Button(label)
      .height(36)
      .width('31%')
      .fontSize(11)
      .fontColor(this.selectedModelVariant === variant ? Color.White : '#4F68FF')
      .backgroundColor(this.selectedModelVariant === variant ? '#4F68FF' : '#EEF3FF')
      .borderRadius(10)
      .margin({ right: 6, bottom: 8 })
      .onClick(() => { this.onSwitchModelVariant(variant); })
  }

  @Builder SettingToggle(label: string, desc: string, selected: boolean, onValueChange: (value: boolean) => void) {
    Row() {
      Checkbox({ name: label, group: 'settingsCenter' })
        .select(selected)
        .selectedColor('#5B68FF')
        .onChange((value: boolean) => { onValueChange(value); })
      Column() {
        Text(label)
          .fontSize(14)
          .fontColor('#11182F')
          .width('100%')
        Text(desc)
          .fontSize(12)
          .fontColor('#7B8290')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder OutputPanel(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontColor('#6F7684')
        .width('100%')
      Scroll() {
        Text(content.length > 0 ? content : '暂无输出')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor('#333333')
          .width('100%')
          .padding(12)
      }
      .constraintSize({ minHeight: 72, maxHeight: 130 })
      .width('100%')
      .backgroundColor('#EEF4FF')
      .borderRadius(12)
      .margin({ top: 6 })
      .border({ width: 1, color: '#D9E5FF' })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: 10 })
  }

  private isWechatAutoSummaryEnabled(): boolean {
    return this.wechatAutoSummaryEnabled === 'true';
  }

  private setWechatAutoSummaryEnabled(value: boolean): void {
    this.wechatAutoSummaryEnabled = value ? 'true' : 'false';
  }

  @Builder WechatAutoSummarySettings() {
    Column() {
      this.SettingToggle('微信消息自动汇总', '开启后采集任务会按默认参数汇总最近微信会话',
        this.isWechatAutoSummaryEnabled(), (value: boolean) => { this.setWechatAutoSummaryEnabled(value); })
      if (this.isWechatAutoSummaryEnabled()) {
        this.WechatAutoSummaryInput('默认时间范围（天）', this.wechatAutoSummaryDefaultDays,
          DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
          (value: string) => { this.wechatAutoSummaryDefaultDays = value; },
          () => {
            this.wechatAutoSummaryDefaultDays = String(
              normalizeWechatAutoSummaryDays(this.wechatAutoSummaryDefaultDays));
          })
        this.WechatAutoSummaryInput('默认最近联系人数量', this.wechatAutoSummaryDefaultMaxContacts,
          DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
          (value: string) => { this.wechatAutoSummaryDefaultMaxContacts = value; },
          () => {
            this.wechatAutoSummaryDefaultMaxContacts = String(
              normalizeWechatAutoSummaryMaxContacts(this.wechatAutoSummaryDefaultMaxContacts));
          })
        Text('将保存微信原始消息 JSON/Markdown，并生成联系人级 daily-log。')
          .fontSize(12)
          .fontColor('#D26B31')
          .width('100%')
          .margin({ top: 8, bottom: 8 })

        Row() {
          Text('高级参数')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .layoutWeight(1)
          Text(this.wechatAutoSummaryAdvancedOpen ? '收起' : '展开')
            .fontSize(12)
            .fontColor('#5B68FF')
        }
        .width('100%')
        .padding({ top: 12, bottom: 8 })
        .onClick(() => { this.wechatAutoSummaryAdvancedOpen = !this.wechatAutoSummaryAdvancedOpen; })

        if (this.wechatAutoSummaryAdvancedOpen) {
          this.WechatAutoSummaryInput('滑动速度', this.wechatAutoSummarySwipeSpeed,
            DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED,
            (value: string) => { this.wechatAutoSummarySwipeSpeed = value; },
            () => {
              this.wechatAutoSummarySwipeSpeed = String(
                normalizeWechatAutoSummarySwipeSpeed(this.wechatAutoSummarySwipeSpeed));
            })
          this.WechatAutoSummaryInput('历史滑动距离比例', this.wechatAutoSummaryHistorySwipeRatio,
            DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO,
            (value: string) => { this.wechatAutoSummaryHistorySwipeRatio = value; },
            () => {
              this.wechatAutoSummaryHistorySwipeRatio = String(
                normalizeWechatAutoSummaryHistorySwipeRatio(this.wechatAutoSummaryHistorySwipeRatio));
            })
          this.WechatAutoSummaryInput('稳定停止次数', this.wechatAutoSummaryStableSwipes,
            DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES,
            (value: string) => { this.wechatAutoSummaryStableSwipes = value; },
            () => {
              this.wechatAutoSummaryStableSwipes = String(
                normalizeWechatAutoSummaryStableSwipes(this.wechatAutoSummaryStableSwipes));
            })
          this.WechatAutoSummaryInput('最大历史滑动次数', this.wechatAutoSummaryMaxHistorySwipes,
            DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES,
            (value: string) => { this.wechatAutoSummaryMaxHistorySwipes = value; },
            () => {
              this.wechatAutoSummaryMaxHistorySwipes = String(
                normalizeWechatAutoSummaryMaxHistorySwipes(this.wechatAutoSummaryMaxHistorySwipes));
            })
          this.WechatAutoSummaryInput('导航等待秒数', this.wechatAutoSummaryWait,
            DEFAULT_WECHAT_AUTO_SUMMARY_WAIT,
            (value: string) => { this.wechatAutoSummaryWait = value; },
            () => {
              this.wechatAutoSummaryWait = String(normalizeWechatAutoSummaryWait(this.wechatAutoSummaryWait));
            })
        }
      }
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder ModelDownloadProgressPanel() {
    if (this.modelDownloadProgressVisible) {
      Column() {
        Row() {
          Text(this.modelDownloadProgressTitle.length > 0 ? this.modelDownloadProgressTitle : '模型下载进度')
            .fontSize(12)
            .fontColor('#6F7684')
            .layoutWeight(1)
          Text(Math.max(0, Math.min(100, this.modelDownloadProgressPercent)).toString() + '%')
            .fontSize(12)
            .fontColor('#4B8BFF')
        }
        .width('100%')

        Progress({ value: Math.max(0, Math.min(100, this.modelDownloadProgressPercent)), total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color('#4B8BFF')
          .backgroundColor('#DCE8FF')
          .borderRadius(6)
          .margin({ top: 8 })

        Row() {
          Blank()
          Text(this.modelDownloadProgressText.length > 0 ? this.modelDownloadProgressText : '等待下载')
            .fontSize(11)
            .fontColor('#7B8290')
            .textAlign(TextAlign.End)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 5 })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F4F8FF')
      .borderRadius(12)
      .border({ width: 1, color: '#D9E5FF' })
      .margin({ top: 10 })
    }
  }

  @Builder SettingsListItem(item: SettingsSectionItem) {
    Row() {
      Text(this.sectionInitial(item.id))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .backgroundColor('#4F68FF')
        .borderRadius(14)
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#11182F')
          .width('100%')
        Text(item.subtitle)
          .fontSize(12)
          .fontColor('#7B8290')
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 10 })
      Text('›')
        .fontSize(28)
        .fontColor('#8A93A3')
    }
    .width('92%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ top: 12 })
    .onClick(() => { this.openSection(item.id); })
  }

  @Builder SettingsSectionList() {
    Column() {
      AppHeader({ title: '设置中心', subtitle: '服务、采集、模型、任务与存储' })
      ForEach(SETTINGS_SECTION_ITEMS, (item: SettingsSectionItem) => {
        this.SettingsListItem(item)
      }, (item: SettingsSectionItem) => String(item.id))
    }
    .width('100%')
    .padding({ bottom: 110 })
  }

  @Builder SettingsDetailHeader() {
    Row() {
      Button('‹')
        .width(42)
        .height(42)
        .fontSize(28)
        .fontColor('#11182F')
        .backgroundColor(Color.White)
        .borderRadius(14)
        .onClick(() => { this.closeSection(); })
      Column() {
        Text('设置中心')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#11182F')
          .width('100%')
        Text(this.activeSectionTitle())
          .fontSize(12)
          .fontColor('#7B8290')
          .width('100%')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('92%')
    .margin({ top: 18, bottom: 2 })
  }

  @Builder SelectedSectionContent() {
    Column() {
      if (this.selectedSectionId === SettingsSectionId.PersonalPrivacy) {
        this.PrivacySection()
      } else if (this.selectedSectionId === SettingsSectionId.DataCollection) {
        this.DataCollectionSection()
      } else if (this.selectedSectionId === SettingsSectionId.ModelAgents) {
        this.ModelAgentsSection()
      } else if (this.selectedSectionId === SettingsSectionId.TaskAutomation) {
        this.TaskAutomationSection()
      } else if (this.selectedSectionId === SettingsSectionId.StorageAbout) {
        this.StorageAboutSection()
      }
    }
    .width('100%')
  }

  @Builder PrivacySection() {
    Column() {
      this.SectionTitle(SettingsSectionId.PersonalPrivacy)
      this.SettingToggle('本地 Agent 自动同意', '关闭后每次端侧模型动作都会弹窗确认', this.autoConfirm,
        (value: boolean) => { this.autoConfirm = value; })
      this.SettingToggle('云端 Agent 自动同意', '关闭后云端模型动作需要手动确认后发给 PC', this.cloudAutoConfirm,
        (value: boolean) => { this.cloudAutoConfirm = value; })
      this.SettingInput('数字分身图片服务', this.avatarImageBaseUrl, '默认 ' + DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl,
        (value: string) => { this.avatarImageBaseUrl = value; })
      this.SettingInput('数字分身图片 API Key', this.avatarImageApiKey, '图片服务密钥',
        (value: string) => { this.avatarImageApiKey = value; })
      this.SettingInput('文生图模型', this.avatarTextToImageModel, DEFAULT_ENDPOINT_CONFIG.avatarImageModel,
        (value: string) => { this.avatarTextToImageModel = value; })
      this.SettingInput('图生图模型', this.avatarImageToImageModel, DEFAULT_ENDPOINT_CONFIG.avatarImageModel,
        (value: string) => { this.avatarImageToImageModel = value; })
      this.SettingInput('图片尺寸', this.avatarImageSize, '默认 ' + DEFAULT_ENDPOINT_CONFIG.avatarImageSize,
        (value: string) => { this.avatarImageSize = value; })
    }
    .width('92%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ top: 16 })
  }

  @Builder DataCollectionSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.DataCollection)
      this.WechatAutoSummarySettings()
      this.SettingInput('图库 API Base URL', this.galleryApiBaseUrl, DEFAULT_GALLERY_API_BASE_URL,
        (value: string) => { this.galleryApiBaseUrl = value; })
      this.SettingInput('图库 API Key', this.galleryApiKey, '图库分析服务密钥',
        (value: string) => { this.galleryApiKey = value; })
      this.SettingInput('图库大模型', this.galleryModel, DEFAULT_GALLERY_MODEL,
        (value: string) => { this.galleryModel = value; })
      this.SettingToggle('跳过本地 OCR', '模拟器不支持 CoreVision OCR 时开启', this.gallerySkipOcr === 'true',
        (value: boolean) => { this.gallerySkipOcr = value ? 'true' : 'false'; })
      this.SettingToggle('OCR 关键词预筛', '自动分析时先用 OCR 关键词过滤图片', this.galleryUseOcrKeywordFilter === 'true',
        (value: boolean) => { this.galleryUseOcrKeywordFilter = value ? 'true' : 'false'; })
      this.SettingToggle('字段级并发请求', '同一张图并发请求各分析字段，降低整包 JSON 解析失败概率', this.galleryParallelFieldRequests === 'true',
        (value: boolean) => { this.galleryParallelFieldRequests = value ? 'true' : 'false'; })
      this.SettingInput('OCR 并发请求数', this.galleryOcrConcurrency, DEFAULT_GALLERY_OCR_CONCURRENCY,
        (value: string) => { this.galleryOcrConcurrency = value; })
      this.SettingInput('大模型并发请求数', this.galleryModelConcurrency, DEFAULT_GALLERY_MODEL_CONCURRENCY,
        (value: string) => { this.galleryModelConcurrency = value; })
      this.SettingInput('Embedding 并发请求数', this.galleryEmbeddingConcurrency, DEFAULT_GALLERY_EMBEDDING_CONCURRENCY,
        (value: string) => { this.galleryEmbeddingConcurrency = value; })
      this.SettingToggle('使用云端 Embedding API', '关闭时使用华为端侧 Embedding', this.galleryEmbeddingMode === 'remote',
        (value: boolean) => { this.galleryEmbeddingMode = value ? 'remote' : 'huawei_local'; })
      this.SettingInput('Embedding Base URL', this.galleryEmbeddingBaseUrl, DEFAULT_GALLERY_EMBEDDING_BASE_URL,
        (value: string) => { this.galleryEmbeddingBaseUrl = value; })
      this.SettingInput('Embedding API Key', this.galleryEmbeddingApiKey, 'Embedding 服务密钥',
        (value: string) => { this.galleryEmbeddingApiKey = value; })
      this.SettingInput('Embedding 模型', this.galleryEmbeddingModel, DEFAULT_GALLERY_EMBEDDING_MODEL,
        (value: string) => { this.galleryEmbeddingModel = value; })
      this.SettingInput('图片分析缩放比例', this.galleryImageScale, DEFAULT_GALLERY_IMAGE_SCALE,
        (value: string) => { this.galleryImageScale = value; })
      this.SettingInput('高德 Web 服务 Key', this.galleryAmapWebKey, '用于拍摄位置逆地理编码',
        (value: string) => { this.galleryAmapWebKey = value; })
    }
    .width('92%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ top: 16 })
  }

  @Builder ModelAgentsSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.ModelAgents)
      this.SettingInput('Planner 服务', this.cloudPlannerBaseUrl, '默认 ' + DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl,
        (value: string) => { this.cloudPlannerBaseUrl = value; })
      this.SettingInput('Decider 服务', this.cloudDeciderBaseUrl, '默认 ' + DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl,
        (value: string) => { this.cloudDeciderBaseUrl = value; })
      this.SettingInput('云端 API Key', this.cloudApiKey, 'Planner / Decider 服务密钥',
        (value: string) => { this.cloudApiKey = value; })
      this.SettingInput('Decider Model', this.cloudDeciderModel, '留空则不传 model',
        (value: string) => { this.cloudDeciderModel = value; })
      this.SettingInput('语音合成服务', this.voiceTtsBaseUrl, '默认 ' + DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl,
        (value: string) => { this.voiceTtsBaseUrl = value; })
      this.SettingInput('语音合成 API Key', this.voiceTtsApiKey, 'MiMO TTS 服务密钥',
        (value: string) => { this.voiceTtsApiKey = value; })
      this.SettingInput('语音合成模型', this.voiceTtsModel, DEFAULT_ENDPOINT_CONFIG.voiceTtsModel,
        (value: string) => { this.voiceTtsModel = value; })
      this.SettingInput('语音合成音色', this.voiceTtsVoice, DEFAULT_ENDPOINT_CONFIG.voiceTtsVoice,
        (value: string) => { this.voiceTtsVoice = value; })
      this.WechatAutoSummaryInput('上下文压缩阈值(%)', this.chatContextCompressionThresholdPercent, '默认 85，范围 50-95',
        (value: string) => { this.chatContextCompressionThresholdPercent = value; },
        () => {
          this.chatContextCompressionThresholdPercent =
            String(normalizeChatContextCompressionThresholdPercent(this.chatContextCompressionThresholdPercent));
        })
      this.WechatAutoSummaryInput('压缩保留轮数', this.chatContextRecentRounds, '默认 8，范围 2-20',
        (value: string) => { this.chatContextRecentRounds = value; },
        () => {
          this.chatContextRecentRounds = String(normalizeChatContextRecentRounds(this.chatContextRecentRounds));
        })
      this.SettingInput('模型下载服务', this.serverIp, '默认 ' + DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl,
        (value: string) => { this.serverIp = value; })

      this.DownloadedModelList()

      this.FieldLabel('旧模型目录快捷切换')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.VariantButton('默认', '')
        this.VariantButton('modelv2', 'modelv2')
        this.VariantButton('modelv3', 'modelv3')
        this.VariantButton('modelv4', 'modelv4')
        this.VariantButton('model_omc', 'model_omc')
      }
      .width('100%')

      this.SettingInput('backend_type', this.backendTypeInput, 'cpu / hiai / nnrt',
        (value: string) => { this.backendTypeInput = value; })
      this.SettingInput('mllm.backend_type', this.mllmBackendTypeInput, 'cpu / hiai / nnrt',
        (value: string) => { this.mllmBackendTypeInput = value; })
      Row() {
        Button('更新 base')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .onClick(() => { this.onUpdateConfigBackendType('base'); })
        Button('更新 mllm')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onUpdateConfigBackendType('mllm'); })
      }
      .width('100%')
      .margin({ top: 10 })

      this.FieldLabel('HDC Server')
      TextInput({ placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.hdcServerUrl, text: this.hdcServerIp })
        .height(42)
        .width('100%')
        .fontSize(13)
        .fontColor(this.hdcInputTextColor())
        .backgroundColor(this.hdcInputBackgroundColor())
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .enabled(this.hdcInputEditable())
        .onChange((value: string) => {
          this.hdcServerIp = value;
          this.manualHdcServerIp = value;
          this.onMarkHdcManualEditing();
        })
      Text(this.hdcAutoStatus)
        .fontSize(12)
        .fontColor(this.hdcStatusColor())
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 8 })
      Row() {
        Button(this.hdcAutoConnecting ? '自动连接中' : '自动连接')
          .height(38)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4F68FF')
          .borderRadius(12)
          .enabled(!this.hdcAutoConnecting)
          .onClick(async () => { await this.onDiscoverHdc(); })
        Button('手动配对')
          .height(38)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor(this.hdcManualPairing ? '#765BFF' : '#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onSetHdcManualPairing(); })
      }
      .width('100%')

      this.FieldLabel('无线 HDC 目标')
      Row() {
        TextInput({ placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget, text: this.wirelessIp })
          .height(42)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(this.hdcInputTextColor())
          .backgroundColor(this.hdcInputBackgroundColor())
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .enabled(this.hdcInputEditable())
          .onChange((value: string) => {
            this.wirelessIp = value;
            this.onMarkHdcManualEditing();
          })
        Button('连接测试')
          .height(42)
          .width(92)
          .fontSize(13)
          .backgroundColor('#765BFF')
          .borderRadius(12)
          .margin({ left: 10 })
          .enabled(this.hdcInputEditable())
          .onClick(async () => { await this.onTestAndConnectHdc(); })
      }
      .width('100%')

      Row() {
        Button('测试 Planner')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#38BE8B')
          .borderRadius(12)
          .onClick(async () => { await this.onTestCloudPlanner(); })
        Button('检查模型')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .margin({ left: 10 })
          .enabled(!this.downloading)
          .onClick(() => { this.onCheckServer(); })
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        Button('下载全部')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FF7043')
          .borderRadius(12)
          .enabled(!this.downloading && this.connected)
          .onClick(() => { this.onDownloadAll(); })
        Button('删除模型')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F44336')
          .borderRadius(12)
          .margin({ left: 10 })
          .enabled(!this.downloading)
          .onClick(() => { this.onDeleteModelFiles(); })
      }
      .width('100%')
      .margin({ top: 10 })

      this.FieldLabel('ModelScope 仓库')
      TextInput({ placeholder: 'modelscope仓库("用户名/模型名")', text: this.modelScopeMnnRepo })
        .height(42)
        .width('100%')
        .fontSize(12)
        .backgroundColor('#F2F5FC')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => { this.modelScopeMnnRepo = value; })

      Row() {
        Button('从 ModelScope 下载')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .enabled(!this.downloading)
          .onClick(async () => {
            showToastSafely('开始 ModelScope 下载');
            await this.onDownloadModelScopeModel();
          })
        Button(this.modelScopePauseRequested ? '暂停中' : '暂停下载')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor(this.modelScopePauseRequested ? '#A9B0BE' : '#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .enabled(this.modelScopeDownloading && !this.modelScopePauseRequested)
          .onClick(() => { this.onPauseModelScopeDownload(); })
      }
      .width('100%')
      .margin({ top: 10 })

      this.ModelDownloadProgressPanel()

      Row() {
        Text('线程数')
          .fontSize(14)
          .fontColor('#666666')
          .width(58)
        TextInput({ text: this.threadNumInput })
          .type(InputType.Number)
          .width(76)
          .height(40)
          .backgroundColor('#F2F5FC')
          .borderRadius(12)
          .onChange((value: string) => { this.threadNumInput = value; })
        Button('修改 Config')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onUpdateConfigThreadNum(); })
        Button('查看 Config')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onShowConfigJson(); })
      }
      .width('100%')
      .margin({ top: 14 })

      this.OutputPanel('本地输出', this.output)
      this.OutputPanel('云端输出', this.cloudOutput)
    }
    .width('92%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ top: 16 })
  }

  @Builder TaskAutomationSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.TaskAutomation)
      Row() {
        Button('Workflow 文件')
          .height(42)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#4F68FF')
          .borderRadius(12)
          .onClick(() => { router.pushUrl({ url: 'pages/task/WorkflowFileViewer' }); })
        Button('Runtime Logs')
          .height(42)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { router.pushUrl({ url: 'pages/LogView' }); })
      }
      .width('100%')
      Button('启动云端 PC 控制后端')
        .width('100%')
        .height(44)
        .fontSize(13)
        .backgroundColor('#765BFF')
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(async () => { await this.onStartCloudBackend(); })
    }
    .width('92%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ top: 16 })
  }

  @Builder StorageAboutSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.StorageAbout)
      Row() {
        Button('清理截图')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FF6B4A')
          .borderRadius(12)
          .onClick(() => { this.onClearScreenshots(); })
        Button('清理调试输出')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F44336')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onDeleteDebugOutputs(); })
      }
      .width('100%')
      .margin({ bottom: 10 })
      Row() {
        Button('Op Precision Test')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FF9800')
          .borderRadius(12)
          .onClick(() => { router.pushUrl({ url: 'pages/OpTest' }); })
        Button('LLM Op Profile')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#455A64')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { router.pushUrl({ url: 'pages/ProfileTest' }); })
      }
      .width('100%')
      .margin({ bottom: 10 })
      Row() {
        Button('Runtime Logs')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .onClick(() => { router.pushUrl({ url: 'pages/LogView' }); })
      }
      .width('100%')
      .margin({ bottom: 10 })
      Row() {
        Button('列出截图')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#38BE8B')
          .borderRadius(12)
          .onClick(() => { this.onListScreenshots(); })
        Button('删除 Config')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F44336')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onDeleteModelConfigJson(); })
      }
      .width('100%')
      .margin({ bottom: 10 })
      Row() {
        Button('模型文件树')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#4B8BFF')
          .borderRadius(12)
          .onClick(() => { this.onListModelFilesTree(); })
        Button('删除 vision.om')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FF7043')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.onDeleteChunkVisionOmFiles(); })
      }
      .width('100%')
      Text('MobiInfer LLM Chat')
        .fontSize(13)
        .fontColor('#7B8290')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 16 })
    }
    .width('92%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ top: 16, bottom: 110 })
  }

  build() {
    Column() {
      if (isSettingsSectionSelected(this.selectedSectionId)) {
        this.SettingsDetailHeader()
        Scroll() {
          this.SelectedSectionContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Scroll() {
          this.SettingsSectionList()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8FF')
  }
}
