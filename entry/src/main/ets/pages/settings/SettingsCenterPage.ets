import { promptAction, router } from '@kit.ArkUI';
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
  MIMO_CHINESE_VOICE_PRESETS,
  VOICE_TTS_ROLE_PRESETS,
  VoiceTtsRolePreset,
  VoiceTtsRoleSelection,
  VoiceTtsVoicePreset,
  voiceTtsSelectionFromRolePreset
} from '../../utils/voice/VoiceTtsPresets';
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
  DownloadedModelItem,
  isSettingsSectionSelected,
  normalizeSettingsSectionId,
  restoreMaskedSensitiveSettingDefault,
  SETTINGS_SECTION_ITEMS,
  SETTINGS_SECTION_NONE,
  SettingsActionKind,
  SettingsConfirmConfig,
  SettingsSectionItem,
  SettingsSectionId,
  settingsSectionSubtitle,
  settingsSectionTitle
} from './SettingsCenterTypes';
import {
  SETTINGS_BUTTON_HEIGHT,
  SETTINGS_CONTROL_RADIUS,
  SETTINGS_FIELD_HEIGHT,
  SETTINGS_INPUT_BACKGROUND_COLOR,
  SETTINGS_MUTED_TEXT_COLOR,
  SETTINGS_PAGE_BACKGROUND_COLOR,
  SETTINGS_PAGE_HORIZONTAL_PADDING,
  SETTINGS_SECONDARY_TEXT_COLOR,
  settingsActionColor
} from './SettingsCenterTheme';
import {
  SensitiveSettingInput,
  SettingInput,
  SettingsActionButton,
  SettingsActionRow,
  SettingsGroupCard,
  SettingsOutputPanel,
  SettingToggle as SettingToggleControl
} from './SettingsCenterControls';

registerGallerySettingsDefaults();

const LEGACY_MIMO_TTS_BASE_URL = 'https://api.xiaomimimo.com';
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
  @StorageLink('cloudPlannerModel') cloudPlannerModel: string = DEFAULT_ENDPOINT_CONFIG.cloudPlannerModel;
  @StorageLink('cloudDeciderBaseUrl') cloudDeciderBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl;
  @StorageLink('cloudApiKey') cloudApiKey: string = DEFAULT_ENDPOINT_CONFIG.cloudApiKey;
  @StorageLink('cloudDeciderModel') cloudDeciderModel: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderModel;
  @StorageLink('voiceTtsBaseUrl') voiceTtsBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl;
  @StorageLink('voiceTtsApiKey') voiceTtsApiKey: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsApiKey;
  @StorageLink('voiceTtsModel') voiceTtsModel: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsModel;
  @StorageLink('voiceTtsVoice') voiceTtsVoice: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsVoice;
  @StorageLink('voiceTtsStylePrompt') voiceTtsStylePrompt: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsStylePrompt;
  @StorageLink('voiceTtsRolePreset') voiceTtsRolePreset: string = DEFAULT_ENDPOINT_CONFIG.voiceTtsRolePreset;
  @StorageLink('voiceTtsStreamingEnabled') voiceTtsStreamingEnabled: boolean =
    DEFAULT_ENDPOINT_CONFIG.voiceTtsStreamingEnabled;
  @StorageLink('chatContextCompressionThresholdPercent') chatContextCompressionThresholdPercent: string =
    String(CHAT_CONTEXT_COMPRESSION_THRESHOLD_PERCENT_DEFAULT);
  @StorageLink('chatContextRecentRounds') chatContextRecentRounds: string =
    String(CHAT_CONTEXT_RECENT_ROUNDS_DEFAULT);
  @StorageLink('avatarImageBaseUrl') avatarImageBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl;
  @StorageLink('avatarImageApiKey') avatarImageApiKey: string = DEFAULT_ENDPOINT_CONFIG.avatarImageApiKey;
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
  private detailScroller: Scroller = new Scroller();
  @State private voiceTtsStylePromptEditorRevision: number = 0;
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

  aboutToAppear(): void {
    this.restoreMaskedDefaultSecrets();
    this.upgradeLegacyVoiceTtsBaseUrl();
  }

  private restoreMaskedDefaultSecrets(): void {
    this.cloudApiKey = restoreMaskedSensitiveSettingDefault(this.cloudApiKey, DEFAULT_ENDPOINT_CONFIG.cloudApiKey);
    this.avatarImageApiKey = restoreMaskedSensitiveSettingDefault(this.avatarImageApiKey,
      DEFAULT_ENDPOINT_CONFIG.avatarImageApiKey);
    this.voiceTtsApiKey = restoreMaskedSensitiveSettingDefault(this.voiceTtsApiKey,
      DEFAULT_ENDPOINT_CONFIG.voiceTtsApiKey);
    this.galleryApiKey = restoreMaskedSensitiveSettingDefault(this.galleryApiKey, DEFAULT_GALLERY_API_KEY);
    this.galleryEmbeddingApiKey =
      restoreMaskedSensitiveSettingDefault(this.galleryEmbeddingApiKey, DEFAULT_GALLERY_EMBEDDING_API_KEY);
  }

  private upgradeLegacyVoiceTtsBaseUrl(): void {
    // 只迁移旧默认值；用户手动配置的其他 OpenAI-compatible 地址保持不变。
    if (this.voiceTtsBaseUrl.trim() === LEGACY_MIMO_TTS_BASE_URL) {
      this.voiceTtsBaseUrl = DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl;
    }
  }

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
      return settingsActionColor(SettingsActionKind.Primary);
    }
    return '#D26B31';
  }

  private resetDetailScroll(): void {
    try {
      this.detailScroller.scrollEdge(Edge.Top);
    } catch (e) {}
  }

  private openSection(id: SettingsSectionId): void {
    this.selectedSectionId = normalizeSettingsSectionId(id);
    this.resetDetailScroll();
    setTimeout(() => {
      this.resetDetailScroll();
    }, 0);
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

  private confirmDanger(config: SettingsConfirmConfig, action: () => void): void {
    promptAction.showDialog({
      title: config.title,
      message: config.message,
      buttons: [
        { text: '取消', color: settingsActionColor(SettingsActionKind.Secondary) },
        { text: config.confirmText, color: settingsActionColor(SettingsActionKind.Danger) }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        action();
      }
    }).catch(() => {});
  }

  private confirmDeleteModelFiles(): void {
    this.confirmDanger({
      title: '删除模型',
      message: '确认执行该操作？将删除本地模型文件，后续需要重新下载或重新选择模型。',
      confirmText: '删除'
    }, () => { this.onDeleteModelFiles(); });
  }

  private confirmClearScreenshots(): void {
    this.confirmDanger({
      title: '清理截图',
      message: '确认执行该操作？将清理当前保存的截图调试产物。',
      confirmText: '清理'
    }, () => { this.onClearScreenshots(); });
  }

  private confirmDeleteDebugOutputs(): void {
    this.confirmDanger({
      title: '清理调试输出',
      message: '确认执行该操作？将删除调试输出文件，操作不可撤回。',
      confirmText: '清理'
    }, () => { this.onDeleteDebugOutputs(); });
  }

  private confirmDeleteModelConfigJson(): void {
    this.confirmDanger({
      title: '删除 Config',
      message: '确认执行该操作？将删除模型 Config 文件，后续需要重新生成或下载。',
      confirmText: '删除'
    }, () => { this.onDeleteModelConfigJson(); });
  }

  private confirmDeleteChunkVisionOmFiles(): void {
    this.confirmDanger({
      title: '删除 vision.om',
      message: '确认执行该操作？将删除 vision.om 相关文件，操作不可撤回。',
      confirmText: '删除'
    }, () => { this.onDeleteChunkVisionOmFiles(); });
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
      .fontColor(SETTINGS_MUTED_TEXT_COLOR)
      .width('100%')
      .margin({ top: 8, bottom: 6 })
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
    SettingInput({
      label: label,
      value: value,
      placeholder: placeholder,
      onValueChange: (input: string) => {
        // 编辑期间保留原文，避免小数和临时空值被立即改写。
        onValueChange(input);
      },
      onInputBlur: () => {
        // 失焦后由调用点读取当前字段再归一化，避免使用上一轮渲染入参。
        onNormalize();
      }
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
    SettingToggleControl({
      label: label,
      desc: desc,
      selected: selected,
      onValueChange: onValueChange
    })
  }

  @Builder VoiceTtsStylePromptTextArea() {
    TextArea({ placeholder: '留空则不发送 user 风格消息', text: this.voiceTtsStylePrompt })
      .height(96)
      .width('100%')
      .maxLines(5)
      .fontSize(13)
      .lineHeight(20)
      .fontColor(SETTINGS_MUTED_TEXT_COLOR)
      .backgroundColor(SETTINGS_INPUT_BACKGROUND_COLOR)
      .borderRadius(SETTINGS_CONTROL_RADIUS)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onChange((val: string) => {
        this.voiceTtsStylePrompt = val;
      })
  }

  @Builder VoiceTtsStylePromptInput() {
    this.FieldLabel('语音风格提示')
    if (this.voiceTtsStylePromptEditorRevision % 2 === 0) {
      this.VoiceTtsStylePromptTextArea()
    } else {
      // 角色预设切换会改变外部状态；输入组件自身有编辑态，切换分支可确保文本重建同步。
      this.VoiceTtsStylePromptTextArea()
    }
  }

  @Builder VoiceTtsRolePresetButton(preset: VoiceTtsRolePreset) {
    Button(preset.label)
      .height(36)
      .width('48%')
      .fontSize(12)
      .fontColor(this.voiceTtsRolePreset === preset.id ? Color.White : settingsActionColor(SettingsActionKind.Primary))
      .backgroundColor(this.voiceTtsRolePreset === preset.id ? settingsActionColor(SettingsActionKind.Primary) :
        '#EEF3FF')
      .borderRadius(10)
      .margin({ right: 6, bottom: 8 })
      .onClick(() => {
        let selection: VoiceTtsRoleSelection = voiceTtsSelectionFromRolePreset(preset);
        this.voiceTtsRolePreset = selection.rolePreset;
        this.voiceTtsVoice = selection.voice;
        this.voiceTtsStylePrompt = selection.stylePrompt;
        this.voiceTtsStylePromptEditorRevision++;
      })
  }

  @Builder VoiceTtsVoicePresetButton(voice: VoiceTtsVoicePreset) {
    Button(voice)
      .height(34)
      .width('31%')
      .fontSize(11)
      .fontColor(this.voiceTtsVoice === voice ? Color.White : settingsActionColor(SettingsActionKind.Primary))
      .backgroundColor(this.voiceTtsVoice === voice ? settingsActionColor(SettingsActionKind.Primary) : '#EEF3FF')
      .borderRadius(10)
      .margin({ right: 6, bottom: 8 })
      .onClick(() => { this.voiceTtsVoice = voice; })
  }

  @Builder VoiceTtsPresetSettings() {
    this.SettingToggle('流式语音合成', '开启后首批 PCM 到达即播放，失败时回退 WAV 合成',
      this.voiceTtsStreamingEnabled, (value: boolean) => { this.voiceTtsStreamingEnabled = value; })
    this.FieldLabel('助手朗读角色')
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(VOICE_TTS_ROLE_PRESETS, (preset: VoiceTtsRolePreset) => {
        this.VoiceTtsRolePresetButton(preset)
      }, (preset: VoiceTtsRolePreset) => preset.id)
    }
    .width('100%')
    this.FieldLabel('语音合成音色')
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(MIMO_CHINESE_VOICE_PRESETS, (voice: VoiceTtsVoicePreset) => {
        this.VoiceTtsVoicePresetButton(voice)
      }, (voice: VoiceTtsVoicePreset) => voice)
    }
    .width('100%')
    this.VoiceTtsStylePromptInput()
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
      SettingsGroupCard({
        title: 'Agent 确认策略',
        subtitle: '控制本地与云端 Agent 动作是否需要人工确认',
        contentBuilder: () => { this.AgentConfirmPolicyGroup() }
      })
      SettingsGroupCard({
        title: '数字分身图片服务',
        subtitle: '配置头像生成服务地址、密钥、模型与图片尺寸',
        contentBuilder: () => { this.AvatarImageServiceGroup() }
      })
    }
    .width(SETTINGS_PAGE_HORIZONTAL_PADDING)
    .margin({ top: 16, bottom: 110 })
  }

  @Builder AgentConfirmPolicyGroup() {
    this.SettingToggle('本地 Agent 自动同意', '关闭后每次端侧模型动作都会弹窗确认', this.autoConfirm,
      (value: boolean) => { this.autoConfirm = value; })
    this.SettingToggle('云端 Agent 自动同意', '关闭后云端模型动作需要手动确认后发给 PC', this.cloudAutoConfirm,
      (value: boolean) => { this.cloudAutoConfirm = value; })
  }

  @Builder AvatarImageServiceGroup() {
    SettingInput({
      label: '数字分身图片服务',
      value: this.avatarImageBaseUrl,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl,
      onValueChange: (value: string) => { this.avatarImageBaseUrl = value; }
    })
    SensitiveSettingInput({
      label: '数字分身图片 API Key',
      value: this.avatarImageApiKey,
      placeholder: '图片服务密钥',
      onValueChange: (value: string) => { this.avatarImageApiKey = value; }
    })
    SettingInput({
      label: '文生图模型',
      value: this.avatarTextToImageModel,
      placeholder: DEFAULT_ENDPOINT_CONFIG.avatarImageModel,
      onValueChange: (value: string) => { this.avatarTextToImageModel = value; }
    })
    SettingInput({
      label: '图生图模型',
      value: this.avatarImageToImageModel,
      placeholder: DEFAULT_ENDPOINT_CONFIG.avatarImageModel,
      onValueChange: (value: string) => { this.avatarImageToImageModel = value; }
    })
    SettingInput({
      label: '图片尺寸',
      value: this.avatarImageSize,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.avatarImageSize,
      onValueChange: (value: string) => { this.avatarImageSize = value; }
    })
  }

  @Builder DataCollectionSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.DataCollection)
      SettingsGroupCard({
        title: '微信汇总',
        subtitle: '默认采集范围和高级滑动参数',
        contentBuilder: () => { this.WechatAutoSummarySettings() }
      })
      SettingsGroupCard({
        title: '图库分析',
        subtitle: '图库大模型服务与字段级请求策略',
        contentBuilder: () => { this.GalleryAnalysisGroup() }
      })
      SettingsGroupCard({
        title: 'OCR',
        subtitle: '本地 OCR 回退、关键词预筛和并发控制',
        contentBuilder: () => { this.OcrSettingsGroup() }
      })
      SettingsGroupCard({
        title: 'Embedding',
        subtitle: '图片检索向量服务和端云模式',
        contentBuilder: () => { this.EmbeddingSettingsGroup() }
      })
      SettingsGroupCard({
        title: '地图服务',
        subtitle: '图片位置解析和分析缩放参数',
        contentBuilder: () => { this.MapSettingsGroup() }
      })
    }
    .width(SETTINGS_PAGE_HORIZONTAL_PADDING)
    .margin({ top: 16, bottom: 110 })
  }

  @Builder GalleryAnalysisGroup() {
    SettingInput({
      label: '图库 API Base URL',
      value: this.galleryApiBaseUrl,
      placeholder: DEFAULT_GALLERY_API_BASE_URL,
      onValueChange: (value: string) => { this.galleryApiBaseUrl = value; }
    })
    SensitiveSettingInput({
      label: '图库 API Key',
      value: this.galleryApiKey,
      placeholder: '图库分析服务密钥',
      onValueChange: (value: string) => { this.galleryApiKey = value; }
    })
    SettingInput({
      label: '图库大模型',
      value: this.galleryModel,
      placeholder: DEFAULT_GALLERY_MODEL,
      onValueChange: (value: string) => { this.galleryModel = value; }
    })
    this.SettingToggle('字段级并发请求', '同一张图并发请求各分析字段，降低整包 JSON 解析失败概率',
      this.galleryParallelFieldRequests === 'true',
      (value: boolean) => { this.galleryParallelFieldRequests = value ? 'true' : 'false'; })
    SettingInput({
      label: '大模型并发请求数',
      value: this.galleryModelConcurrency,
      placeholder: DEFAULT_GALLERY_MODEL_CONCURRENCY,
      onValueChange: (value: string) => { this.galleryModelConcurrency = value; }
    })
  }

  @Builder OcrSettingsGroup() {
    this.SettingToggle('跳过本地 OCR', '模拟器不支持 CoreVision OCR 时开启', this.gallerySkipOcr === 'true',
      (value: boolean) => { this.gallerySkipOcr = value ? 'true' : 'false'; })
    this.SettingToggle('OCR 关键词预筛', '自动分析时先用 OCR 关键词过滤图片',
      this.galleryUseOcrKeywordFilter === 'true',
      (value: boolean) => { this.galleryUseOcrKeywordFilter = value ? 'true' : 'false'; })
    SettingInput({
      label: 'OCR 并发请求数',
      value: this.galleryOcrConcurrency,
      placeholder: DEFAULT_GALLERY_OCR_CONCURRENCY,
      onValueChange: (value: string) => { this.galleryOcrConcurrency = value; }
    })
  }

  @Builder EmbeddingSettingsGroup() {
    SettingInput({
      label: 'Embedding 并发请求数',
      value: this.galleryEmbeddingConcurrency,
      placeholder: DEFAULT_GALLERY_EMBEDDING_CONCURRENCY,
      onValueChange: (value: string) => { this.galleryEmbeddingConcurrency = value; }
    })
    this.SettingToggle('使用云端 Embedding API', '关闭时使用华为端侧 Embedding',
      this.galleryEmbeddingMode === 'remote',
      (value: boolean) => { this.galleryEmbeddingMode = value ? 'remote' : 'huawei_local'; })
    SettingInput({
      label: 'Embedding Base URL',
      value: this.galleryEmbeddingBaseUrl,
      placeholder: DEFAULT_GALLERY_EMBEDDING_BASE_URL,
      onValueChange: (value: string) => { this.galleryEmbeddingBaseUrl = value; }
    })
    SensitiveSettingInput({
      label: 'Embedding API Key',
      value: this.galleryEmbeddingApiKey,
      placeholder: 'Embedding 服务密钥',
      onValueChange: (value: string) => { this.galleryEmbeddingApiKey = value; }
    })
    SettingInput({
      label: 'Embedding 模型',
      value: this.galleryEmbeddingModel,
      placeholder: DEFAULT_GALLERY_EMBEDDING_MODEL,
      onValueChange: (value: string) => { this.galleryEmbeddingModel = value; }
    })
  }

  @Builder MapSettingsGroup() {
    SettingInput({
      label: '图片分析缩放比例',
      value: this.galleryImageScale,
      placeholder: DEFAULT_GALLERY_IMAGE_SCALE,
      onValueChange: (value: string) => { this.galleryImageScale = value; }
    })
    SettingInput({
      label: '高德 Web 服务 Key',
      value: this.galleryAmapWebKey,
      placeholder: '用于拍摄位置逆地理编码',
      onValueChange: (value: string) => { this.galleryAmapWebKey = value; }
    })
  }

  @Builder ModelAgentsSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.ModelAgents)
      SettingsGroupCard({
        title: '云端 Planner/Decider',
        subtitle: '云端智能体服务、模型和连通性测试',
        contentBuilder: () => { this.CloudPlannerDeciderGroup() }
      })
      SettingsGroupCard({
        title: '语音合成服务',
        subtitle: '配置助手朗读的 TTS 服务、模型、音色与流式播放',
        contentBuilder: () => { this.VoiceTtsServiceGroup() }
      })
      SettingsGroupCard({
        title: '上下文压缩',
        subtitle: '聊天上下文压缩阈值和保留轮数',
        contentBuilder: () => { this.ContextCompressionGroup() }
      })
      SettingsGroupCard({
        title: '本地模型',
        subtitle: '已下载模型、旧目录快捷切换和后端类型',
        contentBuilder: () => { this.LocalModelGroup() }
      })
      SettingsGroupCard({
        title: 'HDC 连接',
        subtitle: '自动发现、手动配对和无线调试目标',
        contentBuilder: () => { this.HdcConnectionGroup() }
      })
      SettingsGroupCard({
        title: '模型下载',
        subtitle: '模型文件服务、ModelScope 仓库和下载进度',
        contentBuilder: () => { this.ModelDownloadGroup() }
      })
      SettingsGroupCard({
        title: 'Config 与输出',
        subtitle: '模型配置修改、查看和运行输出',
        contentBuilder: () => { this.ConfigOutputGroup() }
      })
    }
    .width(SETTINGS_PAGE_HORIZONTAL_PADDING)
    .margin({ top: 16, bottom: 110 })
  }

  @Builder CloudPlannerDeciderGroup() {
    SettingInput({
      label: 'Planner 服务',
      value: this.cloudPlannerBaseUrl,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl,
      onValueChange: (value: string) => { this.cloudPlannerBaseUrl = value; }
    })
    SettingInput({
      label: 'Planner Model',
      value: this.cloudPlannerModel,
      placeholder: DEFAULT_ENDPOINT_CONFIG.cloudPlannerModel.length > 0 ?
        DEFAULT_ENDPOINT_CONFIG.cloudPlannerModel : '留空则不传 model',
      onValueChange: (value: string) => { this.cloudPlannerModel = value; }
    })
    SettingInput({
      label: 'Decider 服务',
      value: this.cloudDeciderBaseUrl,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl,
      onValueChange: (value: string) => { this.cloudDeciderBaseUrl = value; }
    })
    SensitiveSettingInput({
      label: '云端 API Key',
      value: this.cloudApiKey,
      placeholder: 'Planner / Decider 服务密钥',
      onValueChange: (value: string) => { this.cloudApiKey = value; }
    })
    SettingInput({
      label: 'Decider Model',
      value: this.cloudDeciderModel,
      placeholder: '留空则不传 model',
      onValueChange: (value: string) => { this.cloudDeciderModel = value; }
    })
    SettingsActionRow({ contentBuilder: () => { this.CloudPlannerActionRow() } })
    SettingsOutputPanel({ title: 'Planner 测试结果', content: this.cloudOutput })
  }

  @Builder CloudPlannerActionRow() {
    SettingsActionButton({
      label: '测试 Planner',
      kind: SettingsActionKind.Success,
      onActionClick: async () => { await this.onTestCloudPlanner(); }
    })
  }

  @Builder VoiceTtsServiceGroup() {
    SettingInput({
      label: '语音合成服务',
      value: this.voiceTtsBaseUrl,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl,
      onValueChange: (value: string) => { this.voiceTtsBaseUrl = value; }
    })
    SensitiveSettingInput({
      label: '语音合成 API Key',
      value: this.voiceTtsApiKey,
      placeholder: 'MiMO TTS 服务密钥，格式 tp-xxxxx',
      onValueChange: (value: string) => { this.voiceTtsApiKey = value; }
    })
    SettingInput({
      label: '语音合成模型',
      value: this.voiceTtsModel,
      placeholder: DEFAULT_ENDPOINT_CONFIG.voiceTtsModel,
      onValueChange: (value: string) => { this.voiceTtsModel = value; }
    })
    this.VoiceTtsPresetSettings()
  }

  @Builder ContextCompressionGroup() {
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
  }

  @Builder LocalModelGroup() {
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
    SettingInput({
      label: 'backend_type',
      value: this.backendTypeInput,
      placeholder: 'cpu / hiai / nnrt',
      onValueChange: (value: string) => { this.backendTypeInput = value; }
    })
    SettingInput({
      label: 'mllm.backend_type',
      value: this.mllmBackendTypeInput,
      placeholder: 'cpu / hiai / nnrt',
      onValueChange: (value: string) => { this.mllmBackendTypeInput = value; }
    })
    SettingsActionRow({ contentBuilder: () => { this.BackendTypeActionRow() } })
  }

  @Builder BackendTypeActionRow() {
    SettingsActionButton({
      label: '更新 base',
      kind: SettingsActionKind.Primary,
      onActionClick: () => { this.onUpdateConfigBackendType('base'); }
    })
    SettingsActionButton({
      label: '更新 mllm',
      kind: SettingsActionKind.Secondary,
      onActionClick: () => { this.onUpdateConfigBackendType('mllm'); }
    })
  }

  @Builder HdcConnectionGroup() {
    SettingInput({
      label: 'HDC Server',
      value: this.hdcServerIp,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.hdcServerUrl,
      inputEnabled: this.hdcInputEditable(),
      onValueChange: (value: string) => {
        this.hdcServerIp = value;
        this.manualHdcServerIp = value;
        this.onMarkHdcManualEditing();
      }
    })
    Text(this.hdcAutoStatus)
      .fontSize(12)
      .fontColor(this.hdcStatusColor())
      .width('100%')
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .margin({ top: 8, bottom: 8 })
    SettingsActionRow({ contentBuilder: () => { this.HdcPairActionRow() } })
    this.FieldLabel('无线 HDC 目标')
    Row() {
      TextInput({ placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget, text: this.wirelessIp })
        .height(SETTINGS_FIELD_HEIGHT)
        .layoutWeight(1)
        .fontSize(13)
        .fontColor(this.hdcInputTextColor())
        .backgroundColor(this.hdcInputBackgroundColor())
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .padding({ left: 12, right: 12 })
        .enabled(this.hdcInputEditable())
        .onChange((value: string) => {
          this.wirelessIp = value;
          this.onMarkHdcManualEditing();
        })
      Button('连接测试')
        .height(SETTINGS_FIELD_HEIGHT)
        .width(92)
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(settingsActionColor(SettingsActionKind.Special))
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .margin({ left: 10 })
        .enabled(this.hdcInputEditable())
        .onClick(async () => { await this.onTestAndConnectHdc(); })
    }
    .width('100%')
  }

  @Builder HdcPairActionRow() {
    SettingsActionButton({
      label: this.hdcAutoConnecting ? '自动连接中' : '自动连接',
      kind: SettingsActionKind.Primary,
      actionEnabled: !this.hdcAutoConnecting,
      onActionClick: async () => { await this.onDiscoverHdc(); }
    })
    SettingsActionButton({
      label: '手动配对',
      kind: this.hdcManualPairing ? SettingsActionKind.Special : SettingsActionKind.Secondary,
      onActionClick: () => { this.onSetHdcManualPairing(); }
    })
  }

  @Builder ModelDownloadGroup() {
    SettingInput({
      label: '模型下载服务',
      value: this.serverIp,
      placeholder: '默认 ' + DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl,
      onValueChange: (value: string) => { this.serverIp = value; }
    })
    SettingsActionRow({ contentBuilder: () => { this.ModelServerActionRow() } })
    SettingInput({
      label: 'ModelScope 仓库',
      value: this.modelScopeMnnRepo,
      placeholder: 'modelscope仓库("用户名/模型名")',
      onValueChange: (value: string) => { this.modelScopeMnnRepo = value; }
    })
    SettingsActionRow({ contentBuilder: () => { this.ModelScopeActionRow() } })
    this.ModelDownloadProgressPanel()
  }

  @Builder ModelServerActionRow() {
    SettingsActionButton({
      label: '检查模型',
      kind: SettingsActionKind.Primary,
      actionEnabled: !this.downloading,
      onActionClick: () => { this.onCheckServer(); }
    })
    SettingsActionButton({
      label: '下载全部',
      kind: SettingsActionKind.Warning,
      actionEnabled: !this.downloading && this.connected,
      onActionClick: () => { this.onDownloadAll(); }
    })
    SettingsActionButton({
      label: '删除模型',
      kind: SettingsActionKind.Danger,
      actionEnabled: !this.downloading,
      onActionClick: () => { this.confirmDeleteModelFiles(); }
    })
  }

  @Builder ModelScopeActionRow() {
    SettingsActionButton({
      label: '从 ModelScope 下载',
      kind: SettingsActionKind.Primary,
      actionEnabled: !this.downloading,
      onActionClick: async () => {
        showToastSafely('开始 ModelScope 下载');
        await this.onDownloadModelScopeModel();
      }
    })
    SettingsActionButton({
      label: this.modelScopePauseRequested ? '暂停中' : '暂停下载',
      kind: SettingsActionKind.Secondary,
      actionEnabled: this.modelScopeDownloading && !this.modelScopePauseRequested,
      onActionClick: () => { this.onPauseModelScopeDownload(); }
    })
  }

  @Builder ConfigOutputGroup() {
    Row() {
      Text('线程数')
        .fontSize(14)
        .fontColor(SETTINGS_MUTED_TEXT_COLOR)
        .width(58)
      TextInput({ text: this.threadNumInput })
        .type(InputType.Number)
        .width(76)
        .height(SETTINGS_BUTTON_HEIGHT)
        .fontSize(13)
        .backgroundColor(SETTINGS_INPUT_BACKGROUND_COLOR)
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .padding({ left: 10, right: 10 })
        .onChange((value: string) => { this.threadNumInput = value; })
      Button('修改 Config')
        .height(SETTINGS_BUTTON_HEIGHT)
        .layoutWeight(1)
        .fontSize(12)
        .fontColor(Color.White)
        .backgroundColor(settingsActionColor(SettingsActionKind.Primary))
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .margin({ left: 10 })
        .onClick(() => { this.onUpdateConfigThreadNum(); })
      Button('查看 Config')
        .height(SETTINGS_BUTTON_HEIGHT)
        .layoutWeight(1)
        .fontSize(12)
        .fontColor(Color.White)
        .backgroundColor(settingsActionColor(SettingsActionKind.Success))
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .margin({ left: 10 })
        .onClick(() => { this.onShowConfigJson(); })
    }
    .width('100%')
    SettingsOutputPanel({ title: '本地输出', content: this.output })
    SettingsOutputPanel({ title: '云端输出', content: this.cloudOutput })
  }

  @Builder TaskAutomationSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.TaskAutomation)
      SettingsGroupCard({
        title: 'Workflow 与日志',
        subtitle: '查看 Workflow 配置、daily-log 和运行日志',
        contentBuilder: () => { this.WorkflowLogGroup() }
      })
      SettingsGroupCard({
        title: 'PC 控制后端',
        subtitle: '启动云端 PC 控制后端供 Agent 自动化使用',
        contentBuilder: () => { this.PcBackendGroup() }
      })
    }
    .width(SETTINGS_PAGE_HORIZONTAL_PADDING)
    .margin({ top: 16, bottom: 110 })
  }

  @Builder WorkflowLogGroup() {
    SettingsActionRow({ contentBuilder: () => { this.WorkflowLogActionRow() } })
  }

  @Builder WorkflowLogActionRow() {
    SettingsActionButton({
      label: 'Workflow 文件',
      kind: SettingsActionKind.Success,
      onActionClick: () => { router.pushUrl({ url: 'pages/task/WorkflowFileViewer' }); }
    })
    SettingsActionButton({
      label: 'Runtime Logs',
      kind: SettingsActionKind.Success,
      onActionClick: () => { router.pushUrl({ url: 'pages/LogView' }); }
    })
  }

  @Builder PcBackendGroup() {
    SettingsActionRow({ contentBuilder: () => { this.PcBackendActionRow() } })
  }

  @Builder PcBackendActionRow() {
    SettingsActionButton({
      label: '启动云端 PC 控制后端',
      kind: SettingsActionKind.Special,
      onActionClick: async () => { await this.onStartCloudBackend(); }
    })
  }

  @Builder StorageAboutSection() {
    Column() {
      this.SectionTitle(SettingsSectionId.StorageAbout)
      SettingsGroupCard({
        title: '文件查看',
        subtitle: '查看截图、模型文件树和运行日志',
        contentBuilder: () => { this.FileViewerGroup() }
      })
      SettingsGroupCard({
        title: '清理操作',
        subtitle: '删除类操作会先弹窗确认',
        contentBuilder: () => { this.CleanupActionGroup() }
      })
      SettingsGroupCard({
        title: '调试工具',
        subtitle: '进入算子精度测试和 LLM Profile 页面',
        contentBuilder: () => { this.DebugToolsGroup() }
      })
      SettingsGroupCard({
        title: '关于',
        subtitle: '当前应用与设置中心说明',
        contentBuilder: () => { this.AboutSettingsGroup() }
      })
    }
    .width(SETTINGS_PAGE_HORIZONTAL_PADDING)
    .margin({ top: 16, bottom: 110 })
  }

  @Builder FileViewerGroup() {
    SettingsActionRow({ contentBuilder: () => { this.FileViewerActionRow() } })
  }

  @Builder FileViewerActionRow() {
    SettingsActionButton({
      label: '列出截图',
      kind: SettingsActionKind.Success,
      onActionClick: () => { this.onListScreenshots(); }
    })
    SettingsActionButton({
      label: '模型文件树',
      kind: SettingsActionKind.Success,
      onActionClick: () => { this.onListModelFilesTree(); }
    })
    SettingsActionButton({
      label: 'Runtime Logs',
      kind: SettingsActionKind.Success,
      onActionClick: () => { router.pushUrl({ url: 'pages/LogView' }); }
    })
  }

  @Builder CleanupActionGroup() {
    SettingsActionRow({ contentBuilder: () => { this.CleanupPrimaryActionRow() } })
    SettingsActionRow({ contentBuilder: () => { this.CleanupModelActionRow() } })
  }

  @Builder CleanupPrimaryActionRow() {
    SettingsActionButton({
      label: '清理截图',
      kind: SettingsActionKind.Danger,
      onActionClick: () => { this.confirmClearScreenshots(); }
    })
    SettingsActionButton({
      label: '清理调试输出',
      kind: SettingsActionKind.Danger,
      onActionClick: () => { this.confirmDeleteDebugOutputs(); }
    })
  }

  @Builder CleanupModelActionRow() {
    SettingsActionButton({
      label: '删除 Config',
      kind: SettingsActionKind.Danger,
      onActionClick: () => { this.confirmDeleteModelConfigJson(); }
    })
    SettingsActionButton({
      label: '删除 vision.om',
      kind: SettingsActionKind.Danger,
      onActionClick: () => { this.confirmDeleteChunkVisionOmFiles(); }
    })
  }

  @Builder DebugToolsGroup() {
    SettingsActionRow({ contentBuilder: () => { this.DebugToolsActionRow() } })
  }

  @Builder DebugToolsActionRow() {
    SettingsActionButton({
      label: 'Op Precision Test',
      kind: SettingsActionKind.Warning,
      onActionClick: () => { router.pushUrl({ url: 'pages/OpTest' }); }
    })
    SettingsActionButton({
      label: 'LLM Op Profile',
      kind: SettingsActionKind.Secondary,
      onActionClick: () => { router.pushUrl({ url: 'pages/ProfileTest' }); }
    })
  }

  @Builder AboutSettingsGroup() {
    Text('MobiInfer LLM Chat')
      .fontSize(13)
      .fontColor(SETTINGS_SECONDARY_TEXT_COLOR)
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ top: 6, bottom: 4 })
  }

  build() {
    Column() {
      if (isSettingsSectionSelected(this.selectedSectionId)) {
        this.SettingsDetailHeader()
        Scroll(this.detailScroller) {
          Column() {
            this.SelectedSectionContent()
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
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
    .backgroundColor(SETTINGS_PAGE_BACKGROUND_COLOR)
  }
}
