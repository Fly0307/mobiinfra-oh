import { router } from '@kit.ArkUI';
import { AppHeader } from '../../components/AppHeader';
import { DEFAULT_ENDPOINT_CONFIG } from '../../config/DefaultEndpointConfig';
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
  DEFAULT_GALLERY_SKIP_OCR,
  DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER,
  registerGallerySettingsDefaults
} from '../../utils/gallery/GallerySettingsDefaults';
import {
  SettingsSectionId,
  settingsSectionSubtitle,
  settingsSectionTitle
} from './SettingsCenterTypes';

registerGallerySettingsDefaults();

@Component
export struct SettingsCenterPage {
  @Link autoConfirm: boolean;
  @Link cloudAutoConfirm: boolean;
  @Link threadNumInput: string;
  @Prop output: string = '';
  @Prop cloudOutput: string = '';
  @Prop downloading: boolean = false;
  @Prop connected: boolean = false;
  @Prop hdcAutoStatus: string = '';
  @Prop hdcAutoConnected: boolean = false;
  @Prop hdcAutoConnecting: boolean = false;
  @Prop hdcManualPairing: boolean = false;
  @StorageLink('serverIp') serverIp: string = DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl;
  @StorageLink('hdcServerIp') hdcServerIp: string = DEFAULT_ENDPOINT_CONFIG.hdcServerUrl;
  @StorageLink('manualHdcServerIp') manualHdcServerIp: string = '';
  @StorageLink('wirelessIp') wirelessIp: string = DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget;
  @StorageLink('cloudPlannerBaseUrl') cloudPlannerBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl;
  @StorageLink('cloudDeciderBaseUrl') cloudDeciderBaseUrl: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl;
  @StorageLink('cloudApiKey') cloudApiKey: string = DEFAULT_ENDPOINT_CONFIG.cloudApiKey;
  @StorageLink('cloudDeciderModel') cloudDeciderModel: string = DEFAULT_ENDPOINT_CONFIG.cloudDeciderModel;
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
  @StorageLink('galleryOcrConcurrency') galleryOcrConcurrency: string = DEFAULT_GALLERY_OCR_CONCURRENCY;
  @StorageLink('galleryModelConcurrency') galleryModelConcurrency: string = DEFAULT_GALLERY_MODEL_CONCURRENCY;
  @StorageLink('galleryEmbeddingConcurrency') galleryEmbeddingConcurrency: string = DEFAULT_GALLERY_EMBEDDING_CONCURRENCY;
  @StorageLink('galleryEmbeddingMode') galleryEmbeddingMode: string = DEFAULT_GALLERY_EMBEDDING_MODE;
  @StorageLink('galleryEmbeddingBaseUrl') galleryEmbeddingBaseUrl: string = DEFAULT_GALLERY_EMBEDDING_BASE_URL;
  @StorageLink('galleryEmbeddingApiKey') galleryEmbeddingApiKey: string = DEFAULT_GALLERY_EMBEDDING_API_KEY;
  @StorageLink('galleryEmbeddingModel') galleryEmbeddingModel: string = DEFAULT_GALLERY_EMBEDDING_MODEL;
  @StorageLink('galleryImageScale') galleryImageScale: string = DEFAULT_GALLERY_IMAGE_SCALE;
  @StorageLink('galleryAmapWebKey') galleryAmapWebKey: string = DEFAULT_GALLERY_AMAP_WEB_KEY;
  onCheckServer: () => void = () => {};
  onDownloadAll: () => void = () => {};
  onDeleteModelFiles: () => void = () => {};
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
      this.SettingInput('模型下载服务', this.serverIp, '默认 ' + DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl,
        (value: string) => { this.serverIp = value; })

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
        Button('Runtime Logs')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { router.pushUrl({ url: 'pages/LogView' }); })
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
    Scroll() {
      Column() {
        AppHeader({ title: '设置中心', subtitle: '统一配置服务、采集、模型、任务与存储' })
        this.PrivacySection()
        this.DataCollectionSection()
        this.ModelAgentsSection()
        this.TaskAutomationSection()
        this.StorageAboutSection()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F8FF')
  }
}
