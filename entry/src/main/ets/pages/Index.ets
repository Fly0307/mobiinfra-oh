import { promptAction, router } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { JSON as ArkJSON, util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import mnnllm from 'libentry.so';
import { CollectionPage } from './collection/CollectionPage';
import { ChatPage } from './chat/ChatPage';
import { CHAT_MODE_CLOUD_AGENT } from './chat/ChatPageTypes';
import { HomePage } from './home/HomePage';
import { mainTabIcon, mainTabLabel, MainTabIndex } from './main/MainTabConfig';
import { SettingsCenterPage } from './settings/SettingsCenterPage';
import { TaskPage } from './task/TaskPage';
import { AgentRouterServer } from '../utils/AgentRouterServer';
import { CloudModelClient, CloudModelConfig } from '../utils/CloudModelClient';
import {
  createEmptyCollectionViewModels,
  createEmptyHomeProfileViewModel,
  DataManagerFacade
} from '../datamanager/DataManagerFacade';
import {
  CollectionViewModel,
  DataManagerModelConfig,
  DataManagerProgress,
  HomeDomainViewModel,
  HomeProfileViewModel
} from '../datamanager/DataManagerTypes';
import {
  AvatarGenerateRequest,
  AvatarGenerationMode,
  AvatarHomeViewModel,
  AvatarProviderConfig,
  AvatarVersionViewModel
} from '../datamanager/avatar/AvatarTypes';
import { dataManagerError, dataManagerInfo, dataManagerWarn } from '../datamanager/DataManagerLog';
import { AgentExecutionController } from '../utils/AgentExecutionController';
import { WorkflowRunner } from '../utils/WorkflowRunner';
import { WorkflowStorage } from '../utils/WorkflowStorage';
import { WorkflowTask, WorkflowRunResult } from '../utils/WorkflowTypes';
import { DEFAULT_ENDPOINT_CONFIG, LEGACY_ENDPOINT_CONFIG } from '../config/DefaultEndpointConfig';

// 首页总入口：负责把“数据归家”业务 UI、本地端侧推理、云端 Planner/Decider、
// 模型下载/调试工具和 PC 侧 HDC Agent 控制入口串起来。各业务 tab 的展示 UI
// 下沉到 home/collection/task，避免 Index.ets 继续膨胀。
const AUTO_HDC_SERVER_URL: string = 'http://127.0.0.1:19124';

interface ServerFile {
  name: string;
  size: number;
}

interface HdcConnectRequest {
  target: string;
  kill_others: boolean;
  prefer_wired: boolean;
}

interface HdcHealthResponse {
  status: string;
  message?: string;
  hdc_connected?: boolean;
  target?: string;
  tunnel_ready?: boolean;
  fport_ready?: boolean;
  rport_ready?: boolean;
  app_server_url?: string;
  loop_alive?: boolean;
}

interface HdcConnectAttempt {
  ok: boolean;
  responseCode: number;
  body: string;
  message: string;
  health?: HdcHealthResponse;
}

interface CloudAgentTaskSubmitResult {
  success: boolean;
  error: string;
}

type JsonValue = Object | string | number | boolean | null;
type JsonMap = Record<string, JsonValue>;

PersistentStorage.persistProp('wirelessIp', DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget);
PersistentStorage.persistProp('serverIp', DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl);
PersistentStorage.persistProp('hdcServerIp', DEFAULT_ENDPOINT_CONFIG.hdcServerUrl);
PersistentStorage.persistProp('manualHdcServerIp', '');
PersistentStorage.persistProp('cloudPlannerBaseUrl', DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl);
PersistentStorage.persistProp('cloudDeciderBaseUrl', DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl);
PersistentStorage.persistProp('cloudApiKey', DEFAULT_ENDPOINT_CONFIG.cloudApiKey);
PersistentStorage.persistProp('cloudDeciderModel', DEFAULT_ENDPOINT_CONFIG.cloudDeciderModel);
PersistentStorage.persistProp('avatarImageBaseUrl', DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl);
PersistentStorage.persistProp('avatarImageApiKey', '');
PersistentStorage.persistProp('avatarTextToImageModel', DEFAULT_ENDPOINT_CONFIG.avatarImageModel);
PersistentStorage.persistProp('avatarImageToImageModel', DEFAULT_ENDPOINT_CONFIG.avatarImageModel);
PersistentStorage.persistProp('avatarImageSize', DEFAULT_ENDPOINT_CONFIG.avatarImageSize);
PersistentStorage.persistProp('avatarImageResponseFormat', DEFAULT_ENDPOINT_CONFIG.avatarImageResponseFormat);
PersistentStorage.persistProp('avatarImageOutputFormat', DEFAULT_ENDPOINT_CONFIG.avatarImageOutputFormat);
PersistentStorage.persistProp('avatarSequentialImageGeneration', 'disabled');
PersistentStorage.persistProp('avatarImageStream', false);
PersistentStorage.persistProp('avatarImageWatermark', DEFAULT_ENDPOINT_CONFIG.avatarImageWatermark);
PersistentStorage.persistProp('avatarImageTimeoutMs', 60000);
PersistentStorage.persistProp('endpointDefault.serverIp', '');
PersistentStorage.persistProp('endpointDefault.hdcServerIp', '');
PersistentStorage.persistProp('endpointDefault.wirelessIp', '');
PersistentStorage.persistProp('endpointDefault.cloudPlannerBaseUrl', '');
PersistentStorage.persistProp('endpointDefault.cloudDeciderBaseUrl', '');
PersistentStorage.persistProp('endpointDefault.cloudApiKey', '');
PersistentStorage.persistProp('endpointDefault.cloudDeciderModel', '');

@Entry
@Component
struct Index {
  @State output: string = '请先检查服务器连接';
  @State chatHistory: string = '';
  @State userInput: string = '';
  @State downloading: boolean = false;
  @State modelLoaded: boolean = false;
  @State connected: boolean = false;
  @State autoConfirm: boolean = true;
  @State debugImagePath: string = '';
  @State selectedModelVariant: string = '';
  @State customOppReady: boolean = false;
  @State threadNumInput: string = '4';
  @State backendTypeInput: string = 'cpu';
  @State mllmBackendTypeInput: string = 'cpu';
  @State currentTab: number = 0;
  @State chatMode: string = CHAT_MODE_CLOUD_AGENT;
  @State collectionModule: number = 0;
  @State taskScene: number = 0;
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
  @StorageLink('avatarImageResponseFormat') avatarImageResponseFormat: string = DEFAULT_ENDPOINT_CONFIG.avatarImageResponseFormat;
  @StorageLink('avatarImageOutputFormat') avatarImageOutputFormat: string = DEFAULT_ENDPOINT_CONFIG.avatarImageOutputFormat;
  @StorageLink('avatarSequentialImageGeneration') avatarSequentialImageGeneration: string = 'disabled';
  @StorageLink('avatarImageStream') avatarImageStream: boolean = false;
  @StorageLink('avatarImageWatermark') avatarImageWatermark: boolean = DEFAULT_ENDPOINT_CONFIG.avatarImageWatermark;
  @StorageLink('avatarImageTimeoutMs') avatarImageTimeoutMs: number = 60000;
  @State isThinking: boolean = false;
  @State cloudOutput: string = '请先配置 Planner 和 Decider 云端服务';
  @State cloudUserInput: string = '';
  @State cloudDebugImagePath: string = '';
  @State cloudAutoConfirm: boolean = true;
  @State cloudThinking: boolean = false;
  @State hdcAutoConnected: boolean = false;
  @State hdcAutoConnecting: boolean = false;
  @State hdcManualPairing: boolean = false;
  @State hdcAutoStatus: string = 'HDC Server will be auto-discovered after startup.';
  @State dataManagerRefreshing: boolean = false;
  @State dataManagerProgressStage: string = '准备';
  @State dataManagerProgressMessage: string = '准备整理数据';
  @State dataManagerProgressPercent: number = 0;
  @State homeProfile: HomeProfileViewModel = createEmptyHomeProfileViewModel();
  @State collectionViews: CollectionViewModel[] = createEmptyCollectionViewModels();
  @State avatarVersions: AvatarVersionViewModel[] = [];

  private filesDir: string = '';
  private modelDir: string = '';
  private serverFiles: ServerFile[] = [];
  private totalBytesAll: number = 0;
  private dataManagerFacade: DataManagerFacade | null = null;
  
  // PC 控制服务端单例。AgentRouterServer 在本地模型和云端模型之间切换同一个 9126 入口。
  private agentRouter: AgentRouterServer = new AgentRouterServer();
  private cloudClient: CloudModelClient = new CloudModelClient();

  // 云端 Agent 日志会同步写入 AppStorage，便于日志页/浮窗读取最近状态。
  private appendCloudLog(message: string): void {
    let stamp = new Date().toLocaleTimeString();
    let line = `[${stamp}] ${message}`;
    let nextLogs = this.cloudOutput.length > 0 ? this.cloudOutput + '\n' + line : line;
    if (nextLogs.length > 60000) {
      nextLogs = nextLogs.substring(nextLogs.length - 60000);
    }
    this.cloudOutput = nextLogs;
    AppStorage.setOrCreate('cloudAgentLogs', this.cloudOutput);
  }

  private resetCloudLog(message: string): void {
    let stamp = new Date().toLocaleTimeString();
    this.cloudOutput = `[${stamp}] ${message}`;
    AppStorage.setOrCreate('cloudAgentLogs', this.cloudOutput);
  }

  private getDataManagerModelConfig(): DataManagerModelConfig {
    return {
      baseUrl: this.cloudPlannerBaseUrl,
      apiKey: this.cloudApiKey,
      enabled: this.cloudPlannerBaseUrl.trim().length > 0
    };
  }

  private getAvatarProviderConfig(): AvatarProviderConfig {
    let textModel = this.avatarTextToImageModel.trim().length > 0 ? this.avatarTextToImageModel :
      DEFAULT_ENDPOINT_CONFIG.avatarImageModel;
    let imageModel = this.avatarImageToImageModel.trim().length > 0 ? this.avatarImageToImageModel : textModel;
    return {
      imageBaseUrl: this.avatarImageBaseUrl.trim().length > 0 ? this.avatarImageBaseUrl :
        DEFAULT_ENDPOINT_CONFIG.avatarImageBaseUrl,
      apiKey: this.avatarImageApiKey,
      textToImageModel: textModel,
      imageToImageModel: imageModel,
      size: this.avatarImageSize.trim().length > 0 ? this.avatarImageSize : DEFAULT_ENDPOINT_CONFIG.avatarImageSize,
      responseFormat: this.avatarImageResponseFormat.trim().length > 0 ? this.avatarImageResponseFormat :
        DEFAULT_ENDPOINT_CONFIG.avatarImageResponseFormat,
      outputFormat: this.avatarImageOutputFormat.trim().length > 0 ? this.avatarImageOutputFormat :
        DEFAULT_ENDPOINT_CONFIG.avatarImageOutputFormat,
      sequentialImageGeneration: this.avatarSequentialImageGeneration.trim().length > 0 ?
        this.avatarSequentialImageGeneration : 'disabled',
      stream: this.avatarImageStream,
      watermark: this.avatarImageWatermark,
      timeoutMs: this.avatarImageTimeoutMs > 0 ? this.avatarImageTimeoutMs : 60000
    };
  }

  private mergeHomeAvatarView(avatar: AvatarHomeViewModel): void {
    this.homeProfile = {
      avatarUri: avatar.avatarUri,
      avatarStatus: avatar.avatarStatus,
      avatarUpdatedLabel: avatar.avatarUpdatedLabel,
      avatarActionLabel: avatar.avatarActionLabel,
      avatarVersionId: avatar.avatarVersionId,
      updatedLabel: this.homeProfile.updatedLabel,
      completeness: this.homeProfile.completeness,
      totalEvents: this.homeProfile.totalEvents,
      domains: this.homeProfile.domains,
      recommendations: this.homeProfile.recommendations,
      empty: this.homeProfile.empty
    };
  }

  private async confirmUnchangedAvatarRegeneration(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      promptAction.showDialog({
        title: '画像未变化',
        message: '当前画像内容与上次生成数字分身时一致，继续生成可能会得到相似结果。是否仍要重新生成？',
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '继续生成', color: '#8066FF' }
        ]
      }).then((data: promptAction.ShowDialogSuccessResponse) => {
        resolve(data.index === 1);
      }).catch(() => {
        resolve(false);
      });
    });
  }

  private async avatarProviderSourceImage(mode: AvatarGenerationMode, sourceImage: string): Promise<string> {
    if (mode !== 'image_to_image') {
      return '';
    }
    let normalized = sourceImage.trim();
    if (normalized.length === 0) {
      throw new Error('请先选择参考照片');
    }
    if (normalized.startsWith('data:image/') || normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    return await this.imageUriToJpegDataUrl(normalized);
  }

  private async imageUriToJpegDataUrl(uri: string): Promise<string> {
    let imageFile: fileIo.File | null = null;
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      imageFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(imageFile.fd);
      pixelMap = await imageSource.createPixelMap();
      packer = image.createImagePacker();
      let data = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 90
      });
      let helper = new util.Base64Helper();
      return 'data:image/jpeg;base64,' + helper.encodeToStringSync(new Uint8Array(data));
    } finally {
      if (packer !== null) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
      if (pixelMap !== null) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (imageSource !== null) {
        try {
          await imageSource.release();
        } catch (e) {
        }
      }
      if (imageFile !== null) {
        try {
          await fileIo.close(imageFile);
        } catch (e) {
        }
      }
    }
  }

  private async generateHomeAvatar(mode: AvatarGenerationMode, sourceImage: string): Promise<void> {
    if (this.dataManagerFacade === null) {
      dataManagerWarn('generateHomeAvatar skipped: facade is null');
      promptAction.showToast({ message: '数据管理服务未就绪', duration: 1500 });
      throw new Error('数据管理服务未就绪');
    }
    if (this.dataManagerFacade.isAvatarProfileSnapshotUnchanged()) {
      let confirmed = await this.confirmUnchangedAvatarRegeneration();
      if (!confirmed) {
        dataManagerInfo('generateHomeAvatar cancelled: profile snapshot unchanged');
        throw new Error('已取消生成');
      }
    }
    let config = this.getAvatarProviderConfig();
    if (config.apiKey.trim().length === 0) {
      dataManagerWarn('generateHomeAvatar skipped: missing avatar api key');
      promptAction.showToast({ message: '请先配置数字分身图片 API Key', duration: 1800 });
      throw new Error('缺少数字分身图片 API Key');
    }
    dataManagerInfo(`generateHomeAvatar start: mode=${mode}, baseUrl=${config.imageBaseUrl}, model=${config.textToImageModel}`);
    try {
      let providerSourceImage = await this.avatarProviderSourceImage(mode, sourceImage);
      let request: AvatarGenerateRequest =
        this.dataManagerFacade.buildAvatarGenerateRequest(mode, providerSourceImage, new Date().toISOString(), sourceImage);
      let avatar = await this.dataManagerFacade.generateAvatar(config, request);
      this.mergeHomeAvatarView(avatar);
      this.reloadDataManagerViewModels();
      promptAction.showToast({ message: '数字分身已生成', duration: 1500 });
      dataManagerInfo(`generateHomeAvatar success: version=${avatar.avatarVersionId}`);
    } catch (e) {
      let err = e as Error;
      this.reloadDataManagerViewModels();
      dataManagerError('generateHomeAvatar failed: ' + err.message);
      this.appendCloudLog('Avatar generation failed: ' + err.message);
      promptAction.showToast({ message: '数字分身生成失败：' + err.message, duration: 2200 });
      throw err;
    }
  }

  private initDataManager(): void {
    if (this.filesDir.length === 0) {
      dataManagerWarn('initDataManager skipped: filesDir is empty');
      return;
    }
    dataManagerInfo('initDataManager start: filesDir=' + this.filesDir);
    this.dataManagerFacade = new DataManagerFacade(this.filesDir);
    this.dataManagerFacade.ensureReady();
    this.reloadDataManagerViewModels();
    dataManagerInfo('initDataManager done');
  }

  private reloadDataManagerViewModels(): void {
    if (this.dataManagerFacade === null) {
      dataManagerWarn('reloadDataManagerViewModels skipped: facade is null');
      return;
    }
    this.homeProfile = this.dataManagerFacade.loadHomeViewModel();
    this.collectionViews = this.dataManagerFacade.loadCollectionViewModels();
    this.avatarVersions = this.dataManagerFacade.listAvatarVersions();
    dataManagerInfo(`reloadDataManagerViewModels done: homeEvents=${this.homeProfile.totalEvents}, domains=${this.homeProfile.domains.map((item: HomeDomainViewModel) => item.domain + ':' + item.desc).join('|')}, collectionTabs=${this.collectionViews.length}`);
  }

  private updateDataManagerProgress(progress: DataManagerProgress): void {
    this.dataManagerProgressStage = progress.percent < 60 ? '正在整理日志' : '正在构建索引';
    this.dataManagerProgressMessage = progress.message;
    this.dataManagerProgressPercent = Math.max(0, Math.min(100, progress.percent));
  }

  private async refreshDataManager(): Promise<void> {
    dataManagerInfo(`refreshDataManager invoked: hasFacade=${this.dataManagerFacade !== null}, refreshing=${this.dataManagerRefreshing}`);
    if (this.dataManagerFacade === null) {
      dataManagerWarn('refreshDataManager skipped: facade is null');
      return;
    }
    if (this.dataManagerRefreshing) {
      dataManagerWarn('refreshDataManager skipped: already refreshing');
      return;
    }
    if (!this.dataManagerFacade.hasDailyLogData()) {
      dataManagerInfo('refreshDataManager skipped: no daily-log data');
      promptAction.showToast({ message: '暂无数据', duration: 1500 });
      return;
    }
    this.dataManagerRefreshing = true;
    this.dataManagerProgressStage = '正在整理日志';
    this.dataManagerProgressMessage = '';
    this.dataManagerProgressPercent = 0;
    try {
      let modelConfig = this.getDataManagerModelConfig();
      dataManagerInfo(`refreshDataManager start: modelEnabled=${modelConfig.enabled}, baseUrl=${modelConfig.baseUrl}`);
      let summary = await this.dataManagerFacade.refresh(modelConfig, (progress: DataManagerProgress) => {
        this.updateDataManagerProgress(progress);
      });
      this.reloadDataManagerViewModels();
      this.appendCloudLog('DataManager refresh: ' + summary.message);
      this.dataManagerProgressStage = '完成';
      this.dataManagerProgressMessage = summary.message;
      this.dataManagerProgressPercent = 100;
      if (summary.skipped) {
        promptAction.showToast({ message: '已是最新数据', duration: 1500 });
      }
      dataManagerInfo('refreshDataManager success: ' + summary.message);
    } catch (e) {
      let err = e as Error;
      this.appendCloudLog('DataManager refresh failed: ' + err.message);
      this.dataManagerProgressStage = '失败';
      this.dataManagerProgressMessage = '整理失败: ' + err.message;
      this.dataManagerProgressPercent = 100;
      dataManagerError('refreshDataManager failed: ' + err.message);
    } finally {
      this.dataManagerRefreshing = false;
      dataManagerInfo('refreshDataManager finished');
    }
  }

  aboutToAppear() {
    // 页面启动时先修正旧版本持久化默认值，再初始化模型目录、日志捕获、自定义算子和 Agent 路由。
    this.migrateDefaultEndpointValues();
    if (this.manualHdcServerIp.trim().length === 0 && !this.isAutoHdcUrl(this.hdcServerIp)) {
      this.manualHdcServerIp = this.hdcServerIp;
    }
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    dataManagerInfo('Index aboutToAppear: filesDir=' + this.filesDir);
    this.syncModelDir();
    try {
      mnnllm.initLogFile(this.filesDir + '/mnn_runtime.log');
    } catch (e) {
      let err = e as Error;
      console.error('initLogFile failed: ' + err.message);
    }
    this.prepareCustomOpp();
    this.initDataManager();
    this.agentRouter.configureLocal(mnnllm as Record<string, Function>, (msg: string) => {
      this.output = msg;
      let match = msg.match(/<img>(.*?)<hw>/);
      if (match && match[1]) {
        this.debugImagePath = 'file://' + match[1];
      }
    }, async (response: string) => {
      if (this.autoConfirm) { return true; }
      return new Promise<boolean>((resolve) => {
        promptAction.showDialog({
          title: '大模型返回确认',
          message: '模型推理结果：\n' + response + '\n\n是否同意执行？',
          buttons: [
            { text: '拒绝', color: '#ff0000' },
            { text: '同意', color: '#00cc00' }
          ]
        }).then((data: promptAction.ShowDialogSuccessResponse) => { resolve(data.index === 1); }).catch(() => { resolve(false); });
      });
    });
    this.agentRouter.configureCloud(this.cloudClient, () => this.getCloudConfig(), (msg: string) => {
      this.appendCloudLog(msg);
      let match = msg.match(/agent_snapshot_.*?\.jpg/);
      if (match && match[0]) {
        this.cloudDebugImagePath = 'file://' + this.filesDir + '/' + match[0];
      }
    }, async (response: string) => {
      if (this.cloudAutoConfirm) {
        this.appendCloudLog('自动同意已开启，模型动作已放行给 PC 执行。');
        return true;
      }
      this.appendCloudLog('等待用户确认模型动作。PC 会停在 Sending step request，直到点击同意。');
      return new Promise<boolean>((resolve) => {
        promptAction.showDialog({
          title: '云端模型返回确认',
          message: '模型推理结果:\n' + response + '\n\n是否同意执行？',
          buttons: [
            { text: '拒绝', color: '#ff0000' },
            { text: '同意', color: '#00cc00' }
          ]
        }).then((data: promptAction.ShowDialogSuccessResponse) => {
          let approved = data.index === 1;
          this.appendCloudLog(approved ? '用户已同意，动作返回 PC。' : '用户已拒绝，任务终止。');
          resolve(approved);
        }).catch(() => {
          this.appendCloudLog('确认弹窗关闭或失败，动作按拒绝处理。');
          resolve(false);
        });
      });
    });
    // 浮窗终止按钮只发取消信号；真正的模型上下文清理由当前路由的 LlmServer 完成。
    AgentExecutionController.registerLocalCancelHandler(async () => {
      if (this.agentRouter.getRouteMode() !== 'local') {
        return;
      }
      await this.agentRouter.requestTaskCancellation();
      this.output = '用户已通过悬浮窗终止本地 Agent 任务。';
    });
    AgentExecutionController.registerCloudCancelHandler(async () => {
      if (this.agentRouter.getRouteMode() !== 'cloud') {
        return;
      }
      await this.agentRouter.requestTaskCancellation();
      this.appendCloudLog('用户已通过悬浮窗终止云端 Agent 任务。');
    });
    this.discoverHdcServer(false, false).catch(() => {
      this.hdcAutoConnecting = false;
    });
  }

  private migrateDefaultEndpointValues(): void {
    // 兼容历史版本写入 PersistentStorage 的默认地址，并跟踪上一次应用的默认值。
    this.serverIp = this.migrateEndpointValue(this.serverIp, DEFAULT_ENDPOINT_CONFIG.modelDownloadServerUrl,
      LEGACY_ENDPOINT_CONFIG.modelDownloadServerUrls, 'endpointDefault.serverIp');
    this.hdcServerIp = this.migrateEndpointValue(this.hdcServerIp, DEFAULT_ENDPOINT_CONFIG.hdcServerUrl,
      LEGACY_ENDPOINT_CONFIG.hdcServerUrls, 'endpointDefault.hdcServerIp');
    this.wirelessIp = this.migrateEndpointValue(this.wirelessIp, DEFAULT_ENDPOINT_CONFIG.wirelessHdcTarget,
      LEGACY_ENDPOINT_CONFIG.wirelessHdcTargets, 'endpointDefault.wirelessIp');
    this.cloudPlannerBaseUrl = this.migrateEndpointValue(this.cloudPlannerBaseUrl, DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl,
      LEGACY_ENDPOINT_CONFIG.cloudPlannerBaseUrls, 'endpointDefault.cloudPlannerBaseUrl');
    this.cloudDeciderBaseUrl = this.migrateEndpointValue(this.cloudDeciderBaseUrl, DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl,
      LEGACY_ENDPOINT_CONFIG.cloudDeciderBaseUrls, 'endpointDefault.cloudDeciderBaseUrl');
    this.cloudApiKey = this.migrateEndpointValue(this.cloudApiKey, DEFAULT_ENDPOINT_CONFIG.cloudApiKey,
      LEGACY_ENDPOINT_CONFIG.cloudApiKeys, 'endpointDefault.cloudApiKey');
    this.cloudDeciderModel = this.migrateEndpointValue(this.cloudDeciderModel, DEFAULT_ENDPOINT_CONFIG.cloudDeciderModel,
      LEGACY_ENDPOINT_CONFIG.cloudDeciderModels, 'endpointDefault.cloudDeciderModel', false);
  }

  private migrateEndpointValue(currentValue: string, configuredDefault: string, legacyDefaults: string[],
    snapshotKey: string, treatEmptyAsDefault: boolean = true): string {
    let lastAppliedDefault = AppStorage.get(snapshotKey) as string;
    let shouldUseConfiguredDefault = legacyDefaults.includes(currentValue) ||
      (lastAppliedDefault !== undefined && lastAppliedDefault.length > 0 && currentValue === lastAppliedDefault);
    if (treatEmptyAsDefault && currentValue.trim().length === 0) {
      shouldUseConfiguredDefault = true;
    }
    let nextValue = shouldUseConfiguredDefault ? configuredDefault : currentValue;
    AppStorage.setOrCreate(snapshotKey, configuredDefault);
    return nextValue;
  }

  private prepareCustomOpp(): boolean {
    let ctx = getContext(this) as common.UIAbilityContext;
    try {
      let res = mnnllm.prepareCustomOpp(ctx.resourceManager, this.filesDir + '/custom_opp');
      this.customOppReady = (res === 'ok');
      if (!this.customOppReady) {
        this.output = '自定义算子准备失败: ' + res;
      }
      return this.customOppReady;
    } catch (e) {
      let err = e as Error;
      this.customOppReady = false;
      this.output = '自定义算子准备异常: ' + err.message;
      return false;
    }
  }

  private getCurrentModelFolderName(): string {
    return this.selectedModelVariant.length > 0 ? this.selectedModelVariant : 'model';
  }

  private syncModelDir(): void {
    this.modelDir = `${this.filesDir}/${this.getCurrentModelFolderName()}`;
  }

  private switchModelVariant(variant: string): void {
    let nextVariant = '';
    if (variant === 'modelv2' || variant === 'modelv3' || variant === 'modelv4' || variant === 'model_omc') {
      nextVariant = variant;
    }
    if (this.selectedModelVariant === nextVariant) {
      return;
    }
    this.selectedModelVariant = nextVariant;
    this.syncModelDir();
    this.modelLoaded = false;
    this.output = `模型路径已切换至: ${this.getCurrentModelFolderName()}`;
  }

  formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes}B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)}KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)}MB`;
    return `${(bytes / 1073741824).toFixed(2)}GB`;
  }

  clearScreenshots() {
    try {
      let files = fs.listFileSync(this.filesDir);
      let count = 0;
      for (let f of files) {
        if (f.startsWith('agent_') || f.toLowerCase().endsWith('.jpg') || f.toLowerCase().endsWith('.jpeg')) {
          try {
            fs.unlinkSync(`${this.filesDir}/${f}`);
            count++;
          } catch (e) {
            this.appendCloudLog(`删除截图失败：${f}，${String(e)}`);
          }
        }
      }
      this.output = `清理成功，删除了 ${count} 张缓存截图。`;
      this.debugImagePath = '';
      this.cloudDebugImagePath = '';
      this.appendCloudLog(`已删除 App 中保存的截图：${count} 张`);
    } catch(e) {
      this.output = `清理截图失败: ${e}`;
    }
  }

  listScreenshots() {
    try {
      let files = fs.listFileSync(this.filesDir);
      let screenshots = files.filter(f => f.toLowerCase().endsWith('.jpg') || f.toLowerCase().endsWith('.jpeg') || f.startsWith('agent_'));
      if (screenshots.length > 0) {
        this.output = `====== 沙箱内截图文件列表 ======\n${screenshots.join('\n')}`;
      } else {
        this.output = '沙箱内当前没有截图文件。';
      }
    } catch (e) {
      this.output = `列出截图失败: ${e}`;
    }
  }

  deleteModelFiles() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = '模型目录不存在，无需删除。';
        return;
      }
      let deletedCount = this.deletePathRecursively(this.modelDir);
      this.modelLoaded = false;
      this.output = `模型删除成功\n已删除 ${this.getCurrentModelFolderName()} 目录及其内容（共 ${deletedCount} 项）。`;
    } catch (e) {
      this.output = `模型删除失败: ${e}`;
    }
  }

  deleteModelConfigJson() {
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型文件夹不存在: ${this.modelDir}`;
        return;
      }
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}\n无需删除。`;
        return;
      }
      fs.unlinkSync(cfgPath);
      this.modelLoaded = false;
      this.output = `已删除 ${this.getCurrentModelFolderName()}/config.json。\n其他模型文件保留，可重新下载补齐 config.json。`;
    } catch (e) {
      this.output = `删除 config.json 失败: ${e}`;
    }
  }

  private deletePathRecursively(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let deleted = 0;
      for (let name of children) {
        deleted += this.deletePathRecursively(`${path}/${name}`);
      }
      fs.rmdirSync(path);
      return deleted + 1;
    } catch {
      fs.unlinkSync(path);
      return 1;
    }
  }

  private calcPathSize(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let sum = 0;
      for (let name of children) {
        let childPath = `${path}/${name}`;
        sum += this.calcPathSize(childPath);
      }
      return sum;
    } catch {
      try {
        return fs.statSync(path).size;
      } catch {
        return 0;
      }
    }
  }

  private buildFileTree(path: string, depth: number, out: string[]): void {
    let indent = '';
    for (let i = 0; i < depth; i++) {
      indent += '  ';
    }
    try {
      let children = fs.listFileSync(path);
      let dirSize = this.calcPathSize(path);
      let baseName = path.substring(path.lastIndexOf('/') + 1);
      out.push(`${indent}[D] ${baseName}/ (${this.formatSize(dirSize)})`);
      children.sort();
      for (let name of children) {
        this.buildFileTree(`${path}/${name}`, depth + 1, out);
      }
    } catch {
      let fileSize = 0;
      try { fileSize = fs.statSync(path).size; } catch {}
      let baseName = path.substring(path.lastIndexOf('/') + 1);
      out.push(`${indent}[F] ${baseName} (${this.formatSize(fileSize)})`);
    }
  }

  listModelFilesTree() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型目录不存在: ${this.modelDir}`;
        return;
      }
      let lines: string[] = [];
      this.buildFileTree(this.modelDir, 0, lines);
      this.output = `====== ${this.getCurrentModelFolderName()} 文件树 ======\n` +
        `根目录: ${this.modelDir}\n` +
        lines.join('\n');
    } catch (e) {
      this.output = `查看模型文件树失败: ${e}`;
    }
  }

  private deleteChunkVisionOmUnder(path: string): number {
    let deleted = 0;
    let children: string[] = [];
    try {
      children = fs.listFileSync(path);
    } catch {
      return 0;
    }
    for (let name of children) {
      let childPath = `${path}/${name}`;
      if (name.startsWith('chunk_')) {
        let visionPath = `${childPath}/vision.om`;
        try {
          if (fs.accessSync(visionPath)) {
            fs.unlinkSync(visionPath);
            deleted++;
          }
        } catch {}
      }
      deleted += this.deleteChunkVisionOmUnder(childPath);
    }
    return deleted;
  }

  deleteChunkVisionOmFiles() {
    try {
      if (!fs.accessSync(this.modelDir)) {
        this.output = `模型目录不存在: ${this.modelDir}`;
        return;
      }
      let count = this.deleteChunkVisionOmUnder(this.modelDir);
      this.output = `已在 ${this.getCurrentModelFolderName()} 下删除 ${count} 个 chunk_*/vision.om`;
    } catch (e) {
      this.output = `删除 chunk_*/vision.om 失败: ${e}`;
    }
  }

  deleteDebugOutputs() {
    let variants = ['model', 'modelv2', 'modelv3', 'modelv4', 'model_omc'];
    let totalDeleted = 0;
    let results: string[] = [];
    for (let variant of variants) {
      let debugDir = `${this.filesDir}/${variant}/debug_outputs`;
      try {
        if (!fs.accessSync(debugDir)) {
          continue;
        }
        let files = fs.listFileSync(debugDir);
        let count = 0;
        for (let f of files) {
          try {
            fs.unlinkSync(`${debugDir}/${f}`);
            count++;
          } catch {}
        }
        try {
          fs.rmdirSync(debugDir);
        } catch {}
        totalDeleted += count;
        results.push(`${variant}/debug_outputs: ${count} files`);
      } catch {
        // directory doesn't exist, skip
      }
    }
    if (totalDeleted === 0) {
      this.output = '所有 model 目录下均无 debug_outputs';
    } else {
      this.output = `已删除 ${totalDeleted} 个调试输出文件\n${results.join('\n')}`;
    }
  }

  showConfigJson() {
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}\n请先下载模型`;
        return;
      }
      let file = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      this.output = `====== ${this.getCurrentModelFolderName()}/config.json ======\n${content}`;
    } catch (e) {
      this.output = `读取 config.json 失败: ${e}`;
    }
  }

  updateConfigThreadNum() {
    let num = parseInt(this.threadNumInput);
    if (isNaN(num) || num <= 0) {
      this.output = '请输入有效的线程数（正整数）';
      return;
    }
    
    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}`;
        return;
      }
      
      // 读取文件。
      let fileRead = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(fileRead.fd, buf);
      fs.closeSync(fileRead);
      
      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      
      // 修改 JSON。
      let configObj = ArkJSON.parse(content) as JsonMap;
      configObj['thread_num'] = num;
      if (configObj['mllm']) {
        let mllmObj = configObj['mllm'] as JsonMap;
        mllmObj['thread_num'] = num;
      }
      
      // 写入文件。
      let newStr = ArkJSON.stringify(configObj, null, 4);
      let byteStr = util.TextEncoder.create('utf-8').encodeInto(newStr);
      let fileWrite = fs.openSync(cfgPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(fileWrite.fd, byteStr.buffer);
      fs.closeSync(fileWrite);
      
      this.output = `更新线程数成功: ${num}\n====== 新配置 ======\n${newStr}`;
    } catch (e) {
      this.output = `更新 config.json 失败: ${e}`;
    }
  }

  updateConfigBackendType(target: string) {
    let value = (target === 'mllm') ? this.mllmBackendTypeInput.trim() : this.backendTypeInput.trim();
    if (value.length === 0) {
      this.output = '请输入有效的 backend_type';
      return;
    }

    let cfgPath = this.modelDir + '/config.json';
    try {
      if (!fs.accessSync(cfgPath)) {
        this.output = `文件不存在: ${cfgPath}`;
        return;
      }

      let fileRead = fs.openSync(cfgPath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(cfgPath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(fileRead.fd, buf);
      fs.closeSync(fileRead);

      let textDecoder = util.TextDecoder.create('utf-8');
      let content = textDecoder.decodeWithStream(new Uint8Array(buf));
      let configObj = ArkJSON.parse(content) as JsonMap;

      if (target === 'mllm') {
        if (configObj['mllm']) {
          let mllmObj = configObj['mllm'] as JsonMap;
          mllmObj['backend_type'] = value;
        } else {
          this.output = 'config.json 中不存在 mllm 字段';
          return;
        }
      } else {
        configObj['backend_type'] = value;
      }

      let newStr = ArkJSON.stringify(configObj, null, 4);
      let byteStr = util.TextEncoder.create('utf-8').encodeInto(newStr);
      let fileWrite = fs.openSync(cfgPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(fileWrite.fd, byteStr.buffer);
      fs.closeSync(fileWrite);

      let label = (target === 'mllm') ? 'mllm.backend_type' : 'backend_type';
      this.output = `更新 ${label} 成功: ${value}\n====== 新配置 ======\n${newStr}`;
    } catch (e) {
      this.output = `更新 config.json 失败: ${e}`;
    }
  }

  async testAndConnectHdc() {
    if (this.wirelessIp.trim().length === 0) {
      this.output = '请先填写当前手机的无线 HDC 地址，例如 192.168.x.x:端口';
      return;
    }
    let serverUrl = this.manualHdcServerUrl();
    if (serverUrl.length === 0) {
      this.output = '请先填写 PC HDC Server 地址。';
      return;
    }
    this.hdcServerIp = serverUrl;
    this.manualHdcServerIp = serverUrl;
    this.hdcManualPairing = true;
    this.hdcAutoConnected = false;
    this.hdcAutoStatus = 'Manual HDC pairing is running...';
    this.output = `正在请求远程服务执行 HDC 连接测试: ${this.wirelessIp}...`;
    let attempt = await this.requestManualHdcConnect(serverUrl, this.wirelessIp.trim());
    if (attempt.ok && attempt.health) {
      this.applyManualHdcSuccess(serverUrl, attempt.health, 'Manual HDC pairing succeeded');
      this.output = `远程连接测试请求成功!\n${attempt.body}`;
      return;
    }
    this.applyManualHdcFailure(serverUrl, attempt.message, 'Manual HDC pairing failed');
    this.output = `HDC 请求出错: ${attempt.message}\n请确认远端服务 ${serverUrl}/api/hdc/connect 已运行。`;
  }

  // ========== Step 1: Check connection, list files ==========
  async checkServer() {
    this.output = `正在连接 ${this.serverIp} ...`;
    // 每个 httpRequest 对应一个 HTTP 请求任务，不复用。
    let httpReq = http.createHttp();
    try {
      let listOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING,
      };
      let resp = await httpReq.request(`${this.serverIp}/api/files`, listOptions);
      if (resp.responseCode !== 200) {
        this.output = `连接失败: HTTP ${resp.responseCode}`;
        return;
      }
      let files: ServerFile[] = ArkJSON.parse(resp.result as string) as ServerFile[];
      this.serverFiles = files.filter((f: ServerFile) => f.name !== 'serve_model.py');
      this.totalBytesAll = 0;

      let listing = '服务器连接成功\n\n文件列表:\n';
      listing += '----------------------------------------\n';
      for (let f of this.serverFiles) {
        this.totalBytesAll += f.size;
        let pad = ' '.repeat(Math.max(1, 28 - f.name.length));
        listing += `  ${f.name}${pad}${this.formatSize(f.size)}\n`;
      }
      listing += '----------------------------------------\n';
      listing += `共 ${this.serverFiles.length} 个文件，总大小: ${this.formatSize(this.totalBytesAll)}\n\n`;
      listing += '点击“下载全部”开始下载';
      this.output = listing;
      this.connected = true;
    } catch (err) {
      let e = err as BusinessError;
      this.output = `连接失败: code=${e.code} ${e.message}\n\n请检查:\n1. 服务器 python serve_model.py 是否运行\n2. 防火墙是否开放端口\n3. 手机网络是否可达服务器`;
      this.connected = false;
    } finally {
      httpReq.destroy();
    }
  }

  // ========== Step 2: Stream-download one file ==========
  private downloadOneFile(file: ServerFile, index: number, fileCount: number,
    completedBytes: number): Promise<number> {
    const url = `${this.serverIp}/${file.name}`;
    const savePath = `${this.modelDir}/${file.name}`;

    // Skip if exists with correct size
    try {
      let st = fs.statSync(savePath);
      if (st.size === file.size) {
        this.output = `[${index + 1}/${fileCount}] ${file.name}\n` +
          `已存在 (${this.formatSize(st.size)})，跳过\n` +
          `总进度: ${this.formatSize(completedBytes + file.size)} / ${this.formatSize(this.totalBytesAll)}`;
        return Promise.resolve(file.size);
      }
    } catch {
      // not exists
    }

    this.output = `[${index + 1}/${fileCount}] 连接: ${file.name}`;
    let self = this;
    let idx = index;
    let completed = completedBytes;

    return new Promise<number>((resolve) => {
      // 每个 httpRequest 对应一个 HTTP 请求任务，不复用。
      let httpReq = http.createHttp();
      let fileHandle: fs.File;
      let failed = false;
      let resolved = false;

      try {
        fileHandle = fs.openSync(savePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY |
        fs.OpenMode.TRUNC);
      } catch {
        self.output = `[${idx + 1}/${fileCount}] 创建文件失败: ${file.name}`;
        httpReq.destroy();
        resolve(-1);
        return;
      }

      // Helper: cleanup and resolve
      let finish = (size: number): void => {
        if (resolved) return;
        resolved = true;
        httpReq.off('dataReceive');
        httpReq.off('dataReceiveProgress');
        httpReq.off('dataEnd');
        try { fs.closeSync(fileHandle); } catch {}
        httpReq.destroy();
        resolve(size);
      };

      // Subscribe: stream data -> write to file
      httpReq.on('dataReceive', (data: ArrayBuffer) => {
        if (!failed) {
          try {
            fs.writeSync(fileHandle.fd, data);
          } catch {
            failed = true;
          }
        }
      });

      // Subscribe: download progress
      httpReq.on('dataReceiveProgress', (data: http.DataReceiveProgressInfo) => {
        if (failed) return;
        let filePct = data.totalSize > 0 ? Math.floor(data.receiveSize * 100 / data.totalSize)
          : 0;
        let overallRecv = completed + data.receiveSize;
        let overallPct = self.totalBytesAll > 0
          ? Math.floor(overallRecv * 100 / self.totalBytesAll) : 0;
        self.output =
          `[${idx + 1}/${fileCount}] ${file.name}\n` +
            `文件: ${self.formatSize(data.receiveSize)} / ${self.formatSize(data.totalSize)} ${filePct}%\n` +
            `总量: ${self.formatSize(overallRecv)} / ${self.formatSize(self.totalBytesAll)} ${overallPct}%`;
      });

      // Subscribe: data receive complete
      httpReq.on('dataEnd', () => {
        if (failed) {
          self.output = `[${idx + 1}/${fileCount}] ${file.name} 写入失败`;
          finish(-1);
        } else {
          let fileSize = 0;
          try {
            fs.closeSync(fileHandle);
            fileSize = fs.statSync(savePath).size;
          } catch {}
          self.output = `[${idx + 1}/${fileCount}] ${file.name} 完成 (${self.formatSize(fileSize)})`;
          if (resolved) return;
          resolved = true;
          httpReq.off('dataReceive');
          httpReq.off('dataReceiveProgress');
          httpReq.off('dataEnd');
          httpReq.destroy();
          resolve(fileSize);
        }
      });

      // Issue stream request
      let streamOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 60000,
        readTimeout: 7200000, // 2 hours for large files
      };
      httpReq.requestInStream(url, streamOptions).then((code: number) => {
        if (code !== 200) {
          failed = true;
          self.output = `[${idx + 1}/${fileCount}] ${file.name} HTTP ${code}`;
          finish(-1);
        }
        // if 200, wait for dataEnd
      }).catch((err: BusinessError) => {
        failed = true;
        self.output = `[${idx + 1}/${fileCount}] ${file.name} 错误: code=${err.code} ${err.message}`;
        finish(-1);
      });
    });
  }

  // ========== Step 3: Download all files ==========
  async downloadAll() {
    if (this.serverFiles.length === 0) {
      this.output = '请先检查服务器连接';
      return;
    }
    this.downloading = true;
    try { fs.mkdirSync(this.modelDir); } catch {}

    let completedBytes = 0;
    let failed: string[] = [];

    for (let i = 0; i < this.serverFiles.length; i++) {
      let size = await this.downloadOneFile(this.serverFiles[i], i, this.serverFiles.length,
        completedBytes);
      if (size < 0) {
        failed.push(this.serverFiles[i].name);
      } else {
        completedBytes += size;
      }
    }

    if (failed.length === 0) {
      this.output = `全部下载完成!\n模型总大小: ${this.formatSize(completedBytes)}\n\n点击“加载大模型”开始使用`;
    } else {
      this.output = `${failed.length} 个失败: ${failed.join(', ')}\n已下载: ${this.formatSize(completedBytes)}\n再次点击可继续，已有文件会跳过。`;
    }
    this.downloading = false;
  }

  private getCloudConfig(): CloudModelConfig {
    let config: CloudModelConfig = {
      plannerBaseUrl: this.cloudPlannerBaseUrl,
      deciderBaseUrl: this.cloudDeciderBaseUrl,
      apiKey: this.cloudApiKey,
      deciderModel: this.cloudDeciderModel
    };
    return config;
  }

  private isCloudConfigReady(): boolean {
    return this.cloudPlannerBaseUrl.trim().length > 0 &&
      this.cloudDeciderBaseUrl.trim().length > 0 &&
      this.cloudApiKey.trim().length > 0;
  }

  async testCloudPlanner() {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return;
    }
    this.cloudThinking = true;
    this.appendCloudLog(`测试 Planner：${this.cloudPlannerBaseUrl}`);
    try {
      let response = await this.cloudClient.chatPlanner('请只回复 ok', this.getCloudConfig());
      this.appendCloudLog(`Planner 测试返回：\n${response}`);
    } catch (err) {
      let e = err as Error;
      this.appendCloudLog('Planner 连接失败：' + e.message);
    } finally {
      this.cloudThinking = false;
    }
  }

  async runCloudPlannerOnce() {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return;
    }
    if (this.cloudUserInput.trim().length === 0 || this.cloudThinking) {
      return;
    }
    this.cloudThinking = true;
    this.appendCloudLog(`手动调用 Planner，任务：${this.cloudUserInput}`);
    try {
      let response = await this.cloudClient.chatPlanner(this.cloudUserInput, this.getCloudConfig());
      this.appendCloudLog(`Planner 手动返回：\n${response}`);
    } catch (err) {
      let e = err as Error;
      this.appendCloudLog('云端 Planner 推理失败：' + e.message);
    } finally {
      this.cloudThinking = false;
    }
  }

  private hdcServerApiUrl(path: string): string {
    return this.hdcApiUrl(this.hdcServerIp, path);
  }

  private normalizeHdcUrl(rawUrl: string): string {
    let url = rawUrl.trim();
    if (url.length === 0) {
      return '';
    }
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      url = 'http://' + url;
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  private hdcApiUrl(baseUrl: string, path: string): string {
    let url = this.normalizeHdcUrl(baseUrl);
    return url + path;
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
      return '#4F68FF';
    }
    return '#D26B31';
  }

  private addHdcCandidate(candidates: string[], value: string): void {
    let normalized = this.normalizeHdcUrl(value);
    if (normalized.length > 0 && candidates.indexOf(normalized) < 0) {
      candidates.push(normalized);
    }
  }

  private hdcDiscoveryCandidates(): string[] {
    let candidates: string[] = [];
    this.addHdcCandidate(candidates, AUTO_HDC_SERVER_URL);
    this.addHdcCandidate(candidates, 'http://localhost:19124');
    return candidates;
  }

  private isAutoHdcUrl(value: string): boolean {
    let normalized = this.normalizeHdcUrl(value);
    return normalized === this.normalizeHdcUrl(AUTO_HDC_SERVER_URL) ||
      normalized === this.normalizeHdcUrl('http://localhost:19124');
  }

  private manualHdcServerUrl(): string {
    let savedManual = this.normalizeHdcUrl(this.manualHdcServerIp);
    if (savedManual.length > 0 && !this.isAutoHdcUrl(savedManual)) {
      return savedManual;
    }

    let current = this.normalizeHdcUrl(this.hdcServerIp);
    if (current.length > 0 && !this.isAutoHdcUrl(current)) {
      return current;
    }

    let configured = this.normalizeHdcUrl(DEFAULT_ENDPOINT_CONFIG.hdcServerUrl);
    if (configured.length > 0 && !this.isAutoHdcUrl(configured)) {
      return configured;
    }
    return '';
  }

  private async requestHdcHealth(baseUrl: string): Promise<HdcHealthResponse | null> {
    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 2500,
        readTimeout: 5000,
        expectDataType: http.HttpDataType.STRING
      };
      let resp = await httpReq.request(this.hdcApiUrl(baseUrl, '/api/health'), options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return null;
      }
      return ArkJSON.parse(String(resp.result)) as HdcHealthResponse;
    } catch (e) {
      return null;
    } finally {
      httpReq.destroy();
    }
  }

  private hdcHealthReady(health: HdcHealthResponse): boolean {
    return health.status === 'ok' && health.hdc_connected === true && health.tunnel_ready !== false;
  }

  private hdcHealthMessage(health: HdcHealthResponse, fallback: string): string {
    if (health.message && health.message.length > 0) {
      return health.message;
    }
    return fallback;
  }

  private async requestManualHdcConnect(serverUrl: string, target: string): Promise<HdcConnectAttempt> {
    let httpReq = http.createHttp();
    try {
      let connectPayload: HdcConnectRequest = {
        target: target,
        kill_others: true,
        prefer_wired: true
      };
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: ArkJSON.stringify(connectPayload),
        connectTimeout: 5000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING
      };
      let resp = await httpReq.request(this.hdcApiUrl(serverUrl, '/api/hdc/connect'), options);
      let body = String(resp.result);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        return {
          ok: false,
          responseCode: resp.responseCode,
          body: body,
          message: 'HTTP ' + resp.responseCode + ' ' + body
        };
      }

      try {
        let parsed = ArkJSON.parse(body) as HdcHealthResponse;
        if (parsed.status !== 'ok') {
          return {
            ok: false,
            responseCode: resp.responseCode,
            body: body,
            message: parsed.message || body,
            health: parsed
          };
        }
        return {
          ok: true,
          responseCode: resp.responseCode,
          body: body,
          message: parsed.message || body,
          health: parsed
        };
      } catch (parseErr) {
        let e = parseErr as Error;
        return {
          ok: false,
          responseCode: resp.responseCode,
          body: body,
          message: 'Invalid HDC connect response: ' + e.message
        };
      }
    } catch (err) {
      let e = err as Error;
      return {
        ok: false,
        responseCode: 0,
        body: '',
        message: e.message
      };
    } finally {
      httpReq.destroy();
    }
  }

  private applyManualHdcSuccess(serverUrl: string, health: HdcHealthResponse, statusPrefix: string): void {
    this.manualHdcServerIp = serverUrl;
    if (health.tunnel_ready === true && health.app_server_url && health.app_server_url.length > 0) {
      this.hdcServerIp = health.app_server_url;
      this.hdcAutoConnected = true;
      this.hdcManualPairing = false;
      let targetText = health.target && health.target.length > 0 ? ', target=' + health.target : '';
      this.hdcAutoStatus = statusPrefix + ' and auto tunnel is ready: ' + this.hdcServerIp + targetText;
      return;
    }

    this.hdcServerIp = serverUrl;
    this.hdcAutoConnected = false;
    this.hdcManualPairing = true;
    this.hdcAutoStatus = statusPrefix + '; using PC Server URL.';
  }

  private applyManualHdcFailure(serverUrl: string, message: string, statusPrefix: string): void {
    this.hdcServerIp = serverUrl;
    this.manualHdcServerIp = serverUrl;
    this.hdcAutoConnected = false;
    this.hdcManualPairing = true;
    this.hdcAutoStatus = statusPrefix + ': ' + message;
  }

  private async connectManualHdcTarget(useCloudLog: boolean): Promise<boolean> {
    let serverUrl = this.manualHdcServerUrl();
    let target = this.wirelessIp.trim();
    if (serverUrl.length === 0) {
      this.logAgentLoopReady('Manual HDC fallback skipped: PC HDC Server URL is not configured.', useCloudLog);
      return false;
    }
    if (target.length === 0) {
      this.logAgentLoopReady('Manual HDC fallback skipped: phone wireless HDC target is not configured.', useCloudLog);
      return false;
    }

    this.logAgentLoopReady('Auto HDC failed; trying manual HDC pairing: server=' + serverUrl + ', target=' + target, useCloudLog);
    this.hdcAutoStatus = 'Manual HDC fallback is running...';
    let attempt = await this.requestManualHdcConnect(serverUrl, target);
    if (!attempt.ok || !attempt.health) {
      this.applyManualHdcFailure(serverUrl, attempt.message, 'Manual HDC fallback failed');
      this.logAgentLoopReady(this.hdcAutoStatus, useCloudLog);
      return false;
    }

    this.applyManualHdcSuccess(serverUrl, attempt.health, 'Manual HDC fallback succeeded');
    this.logAgentLoopReady(this.hdcAutoStatus, useCloudLog);
    return true;
  }

  private setHdcManualPairing(): void {
    this.hdcManualPairing = true;
    this.hdcAutoConnected = false;
    if (this.normalizeHdcUrl(this.hdcServerIp) === this.normalizeHdcUrl(AUTO_HDC_SERVER_URL)) {
      this.hdcServerIp = this.manualHdcServerUrl();
    }
    this.hdcAutoStatus = 'Manual HDC pairing enabled. Enter PC HDC Server and phone wireless HDC target.';
  }

  private markHdcManualEditing(): void {
    if (!this.hdcManualPairing) {
      this.hdcManualPairing = true;
    }
    this.hdcAutoConnected = false;
    this.hdcAutoStatus = 'Manual HDC pairing is being edited.';
  }

  private async discoverHdcServer(useCloudLog: boolean = false, force: boolean = false): Promise<boolean> {
    if (this.hdcAutoConnecting && !force) {
      return this.hdcAutoConnected;
    }

    this.hdcAutoConnecting = true;
    this.hdcAutoStatus = 'Auto-discovering HDC Server...';
    let candidates = this.hdcDiscoveryCandidates();
    let lastMessage = '';
    try {
      for (let i = 0; i < candidates.length; i++) {
        let candidate = candidates[i];
        let health = await this.requestHdcHealth(candidate);
        if (!health) {
          lastMessage = 'No response from ' + candidate;
          continue;
        }
        if (this.hdcHealthReady(health)) {
          this.hdcServerIp = candidate;
          this.hdcAutoConnected = true;
          this.hdcManualPairing = false;
          let targetText = health.target && health.target.length > 0 ? ', target=' + health.target : '';
          this.hdcAutoStatus = 'Auto HDC connected: ' + candidate + targetText;
          this.logAgentLoopReady(this.hdcAutoStatus, useCloudLog);
          return true;
        }
        lastMessage = this.hdcHealthMessage(health, 'HDC target is not connected');
      }
      this.hdcAutoConnected = false;
      this.hdcAutoStatus = 'Auto HDC discovery failed. Use manual pairing if needed. ' + lastMessage;
      this.logAgentLoopReady(this.hdcAutoStatus, useCloudLog);
      return false;
    } finally {
      this.hdcAutoConnecting = false;
    }
  }

  private async ensureHdcServerReadyForTask(useCloudLog: boolean): Promise<boolean> {
    if (await this.discoverHdcServer(useCloudLog, true)) {
      return true;
    }

    if (await this.connectManualHdcTarget(useCloudLog)) {
      return true;
    }

    this.logAgentLoopReady('HDC connection failed: automatic tunnel and manual HDC pairing both failed.', useCloudLog);
    return false;
  }

  private logAgentLoopReady(message: string, useCloudLog: boolean): void {
    if (useCloudLog) {
      this.appendCloudLog(message);
      return;
    }
    this.output = message;
  }

  private async ensurePcAgentLoopReady(useCloudLog: boolean): Promise<boolean> {
    if (!await this.ensureHdcServerReadyForTask(useCloudLog)) {
      return false;
    }
    if (this.hdcServerIp.trim().length === 0) {
      this.logAgentLoopReady('HDC Server 未配置，无法恢复 PC Agent loop。', useCloudLog);
      return false;
    }

    let httpReq = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: '{}',
        connectTimeout: 5000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      };
      let resp = await httpReq.request(this.hdcServerApiUrl('/api/agent_loop/ensure'), options);
      let body = String(resp.result);
      let message = body;
      try {
        let parsed = ArkJSON.parse(body) as JsonMap;
        let parsedMessage = parsed['message'];
        if (typeof parsedMessage === 'string') {
          message = parsedMessage;
        }
      } catch (e) {
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        this.logAgentLoopReady('PC Agent loop 已恢复：' + message, useCloudLog);
        return true;
      }
      this.logAgentLoopReady('PC Agent loop 恢复失败：HTTP ' + resp.responseCode + ' ' + message, useCloudLog);
      return false;
    } catch (err) {
      let e = err as BusinessError;
      this.logAgentLoopReady('PC Agent loop 恢复请求失败：' + e.message, useCloudLog);
      return false;
    } finally {
      httpReq.destroy();
    }
  }

  async startCloudBackend(): Promise<boolean> {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return false;
    }
    this.appendCloudLog(`准备切换到云端 Agent 路由，复用 ${DEFAULT_ENDPOINT_CONFIG.agentRouterPort}...`);
    // 云端模式仍复用 PC 侧同一套 TCP 协议；区别是 App 通过 AgentRouterServer 转发到云端模型。
    this.agentRouter.useCloud();
    return await this.agentRouter.ensureStarted(DEFAULT_ENDPOINT_CONFIG.agentRouterPort, this.filesDir);
  }

  private async ensureLocalModelLoaded(): Promise<boolean> {
    // 本地 Agent 启动前自动加载模型，减少用户遗漏“加载大模型”按钮导致的失败。
    if (this.modelLoaded) {
      return true;
    }

    let cfg = this.modelDir + '/config.json';
    if (!this.prepareCustomOpp()) {
      return false;
    }

    this.output = '未检测到已加载模型，正在自动加载大模型...';
    try {
      this.output = await mnnllm.loadModel(cfg);
      this.modelLoaded = this.output === 'ok';
      if (!this.modelLoaded) {
        this.output = `自动加载模型失败: ${this.output}`;
      }
      return this.modelLoaded;
    } catch (err) {
      let e = err as Error;
      this.output = '自动加载模型失败: ' + e.message;
      return false;
    }
  }

  private async startLocalBackend(): Promise<boolean> {
    // 本地模式下 9126 请求会进入 libentry.so/MNN，本函数只负责切换路由并启动监听。
    this.agentRouter.useLocal();
    return await this.agentRouter.ensureStarted(DEFAULT_ENDPOINT_CONFIG.agentRouterPort, this.filesDir);
  }

  private async ensureLocalAgentReady(): Promise<boolean> {
    if (!await this.ensureLocalModelLoaded()) {
      return false;
    }

    this.agentRouter.useLocal();
    if (!await this.startLocalBackend()) {
      return false;
    }
    return await this.ensurePcAgentLoopReady(false);
  }

  private async ensureCloudAgentBackend(): Promise<boolean> {
    // 云端任务下发前确保路由已切换到 cloud 且 9126 正在监听。
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('配置不完整：请先填写 Planner / Decider 的服务地址和 API Key。');
      return false;
    }

    this.agentRouter.useCloud();
    if (!await this.startCloudBackend()) {
      return false;
    }
    return await this.ensurePcAgentLoopReady(true);
  }

  private async runHomeRecommendationAgentTask(taskText: string): Promise<void> {
    let result = await this.submitDirectCloudAgentTask(taskText);
    if (!result.success) {
      throw new Error(result.error.length > 0 ? result.error : '云端 Agent 后端未就绪');
    }
    this.currentTab = MainTabIndex.Chat;
  }

  private async submitDirectCloudAgentTask(taskText: string): Promise<CloudAgentTaskSubmitResult> {
    let task = taskText.trim();
    if (task.length === 0) {
      return { success: false, error: '请先输入云端 Agent 任务。' };
    }
    if (!await this.ensureCloudAgentBackend()) {
      return { success: false, error: '' };
    }
    this.agentRouter.submitCloudTask(task);
    AgentExecutionController.beginExecution('等待 PC 控制云端任务...');
    this.resetCloudLog('任务已下发：' + task);
    this.appendCloudLog(`等待 PC 侧 harmony_agent.py 轮询 ${DEFAULT_ENDPOINT_CONFIG.agentRouterPort}。若没有后续 [Cloud Poll]，说明 PC 没连到 App 后端。`);
    this.appendCloudLog(`Planner=${this.cloudPlannerBaseUrl}, Decider=${this.cloudDeciderBaseUrl}`);
    return { success: true, error: '' };
  }

  private async runWorkflowTask(task: WorkflowTask): Promise<void> {
    if (!this.isCloudConfigReady()) {
      this.appendCloudLog('Workflow 无法启动：请先填写 Planner / Decider 的服务地址和 API Key。');
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, '失败', '云端模型配置不完整');
      return;
    }
    if (!await this.ensureHdcServerReadyForTask(true)) {
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, 'failed', 'HDC Server auto-discovery failed');
      return;
    }
    if (this.hdcServerIp.trim().length === 0) {
      this.appendCloudLog('Workflow 无法启动：请先配置 HDC Server。');
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, '失败', 'HDC Server 未配置');
      return;
    }

    this.currentTab = MainTabIndex.Chat;
    this.resetCloudLog('准备执行 Workflow：' + task.title);
    this.appendCloudLog('Workflow 编排将在 App 沙箱内执行；PC 端仅负责 HDC 截图和动作桥接。');
    this.appendCloudLog('HDC Server=' + this.hdcServerIp);
    let runner = new WorkflowRunner(this.filesDir, this.cloudClient, () => this.getCloudConfig(),
      this.hdcServerIp, (msg: string) => { this.appendCloudLog(msg); });
    try {
      let result: WorkflowRunResult = await runner.runTask(task);
      let message = result.message;
      if (result.dailyLogPath.length > 0) {
        message += '，daily-log 已生成';
      }
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, result.status, message);
      this.appendCloudLog('Workflow 运行摘要：' + result.runDir);
    } catch (err) {
      let e = err as Error;
      WorkflowStorage.updateTaskRun(this.filesDir, task.id, 'failed', e.message);
      this.appendCloudLog('Workflow 执行异常：' + e.message);
      AgentExecutionController.finishExecution('Workflow failed');
    }
  }

  private async sendLocalChatMessage(): Promise<void> {
    if (!this.modelLoaded || this.userInput.length === 0 || this.isThinking) {
      if (!this.modelLoaded) {
        this.output = '请先加载模型';
      }
      return;
    }
    let msg = this.userInput;
    this.userInput = '';
    this.chatHistory += `\nUser: ${msg}\nAssistant: 思考中...`;
    this.isThinking = true;
    try {
      let reply = await mnnllm.chat(msg);
      this.chatHistory = this.chatHistory.replace('Assistant: 思考中...', `Assistant: ${reply}\n`);
    } catch (err) {
      let e = err as Error;
      this.chatHistory = this.chatHistory.replace('Assistant: 思考中...', `Assistant: [错误] ${e.message}\n`);
    } finally {
      this.isThinking = false;
    }
  }

  private async submitLocalAgentTask(): Promise<void> {
    if (this.userInput.length === 0) {
      this.output = '请在输入框输入任务目标，例如：去淘宝买手机';
      return;
    }
    if (!await this.ensureLocalAgentReady()) {
      return;
    }
    this.agentRouter.submitLocalTask(this.userInput);
    AgentExecutionController.beginExecution('等待 PC 控制本地任务...');
    this.output = `====== 等待 PC 截图 ======\n当前任务已设定为: ${this.userInput}\nPC 脚本检测到任务后将自动开始。`;
  }

  private async submitCurrentCloudTask(): Promise<void> {
    let result = await this.submitDirectCloudAgentTask(this.cloudUserInput);
    if (!result.success && result.error.length > 0) {
      this.appendCloudLog(result.error);
    }
  }

  private clearCloudDebugImage(): void {
    this.cloudDebugImagePath = '';
  }

  private clearLocalDebugImage(): void {
    this.debugImagePath = '';
  }

  @Builder TabItem(icon: string, label: string, index: number) {
    Column() {
      Text(icon)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentTab === index ? Color.White : '#747B87')
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.currentTab === index ? '#4F68FF' : '#00FFFFFF')
        .borderRadius(16)
      Text(label)
        .fontSize(13)
        .fontColor(this.currentTab === index ? '#4F68FF' : '#747B87')
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Regular)
        .margin({ top: 2 })
        .maxLines(1)
    }.width(72).height(58).justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder DataManagerProgressOverlay() {
    if (this.dataManagerRefreshing) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          Text(this.dataManagerProgressStage)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .maxLines(1)
          Progress({ value: this.dataManagerProgressPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(8)
            .color('#4F68FF')
            .backgroundColor('#E7EBF5')
            .margin({ top: 18 })
          Row() {
            Text(`${Math.round(this.dataManagerProgressPercent)}%`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4F68FF')
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('78%')
        .padding({ left: 22, right: 22, top: 24, bottom: 22 })
        .backgroundColor('#FFFFFFFF')
        .borderRadius(18)
        .shadow({ radius: 22, color: '#33000000', offsetX: 0, offsetY: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')
      .zIndex(99)
      .onClick(() => {})
    }
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          HomePage({
            profile: this.homeProfile,
            avatarVersions: this.avatarVersions,
            onExecuteAgentTask: async (taskDescription: string) => {
              await this.runHomeRecommendationAgentTask(taskDescription);
            },
            onGenerateAvatar: async (mode: AvatarGenerationMode, sourceImage: string) => {
              await this.generateHomeAvatar(mode, sourceImage);
            }
          })
        }.tabBar(this.TabItem(mainTabIcon(MainTabIndex.Home), mainTabLabel(MainTabIndex.Home), MainTabIndex.Home))
        TabContent() {
          CollectionPage({
            collectionModule: $collectionModule,
            viewModels: this.collectionViews,
            refreshing: this.dataManagerRefreshing,
            onRefresh: () => { this.refreshDataManager(); }
          })
        }.tabBar(this.TabItem(mainTabIcon(MainTabIndex.Summary), mainTabLabel(MainTabIndex.Summary), MainTabIndex.Summary))
        TabContent() {
          ChatPage({
            chatMode: $chatMode,
            cloudUserInput: $cloudUserInput,
            userInput: $userInput,
            cloudOutput: this.cloudOutput,
            cloudDebugImagePath: this.cloudDebugImagePath,
            cloudThinking: this.cloudThinking,
            localOutput: this.output,
            localDebugImagePath: this.debugImagePath,
            chatHistory: this.chatHistory,
            localThinking: this.isThinking,
            modelLoaded: this.modelLoaded,
            onRunCloudPlanner: async () => { await this.runCloudPlannerOnce(); },
            onSubmitCloudTask: async () => { await this.submitCurrentCloudTask(); },
            onSendLocalMessage: async () => { await this.sendLocalChatMessage(); },
            onSubmitLocalTask: async () => { await this.submitLocalAgentTask(); },
            onClearCloudDebugImage: () => { this.clearCloudDebugImage(); },
            onClearLocalDebugImage: () => { this.clearLocalDebugImage(); },
            onOpenRuntimeLogs: () => { router.pushUrl({ url: 'pages/LogView' }); }
          })
        }.tabBar(this.TabItem(mainTabIcon(MainTabIndex.Chat), mainTabLabel(MainTabIndex.Chat), MainTabIndex.Chat))
        TabContent() {
          TaskPage({
            taskScene: $taskScene,
            onRunWorkflow: async (task: WorkflowTask) => { await this.runWorkflowTask(task); }
          })
        }.tabBar(this.TabItem(mainTabIcon(MainTabIndex.Task), mainTabLabel(MainTabIndex.Task), MainTabIndex.Task))
        TabContent() {
          SettingsCenterPage({
            autoConfirm: $autoConfirm,
            cloudAutoConfirm: $cloudAutoConfirm,
            threadNumInput: $threadNumInput,
            backendTypeInput: $backendTypeInput,
            mllmBackendTypeInput: $mllmBackendTypeInput,
            output: this.output,
            cloudOutput: this.cloudOutput,
            downloading: this.downloading,
            connected: this.connected,
            hdcAutoStatus: this.hdcAutoStatus,
            hdcAutoConnected: this.hdcAutoConnected,
            hdcAutoConnecting: this.hdcAutoConnecting,
            hdcManualPairing: this.hdcManualPairing,
            selectedModelVariant: this.selectedModelVariant,
            onCheckServer: () => { this.checkServer(); },
            onDownloadAll: () => { this.downloadAll(); },
            onDeleteModelFiles: () => { this.deleteModelFiles(); },
            onUpdateConfigThreadNum: () => { this.updateConfigThreadNum(); },
            onShowConfigJson: () => { this.showConfigJson(); },
            onDiscoverHdc: async () => {
              this.hdcManualPairing = false;
              await this.discoverHdcServer(true, true);
            },
            onSetHdcManualPairing: () => { this.setHdcManualPairing(); },
            onMarkHdcManualEditing: () => { this.markHdcManualEditing(); },
            onTestAndConnectHdc: async () => { await this.testAndConnectHdc(); },
            onTestCloudPlanner: async () => { await this.testCloudPlanner(); },
            onStartCloudBackend: async () => { await this.startCloudBackend(); },
            onClearScreenshots: () => { this.clearScreenshots(); },
            onDeleteDebugOutputs: () => { this.deleteDebugOutputs(); },
            onSwitchModelVariant: (variant: string) => { this.switchModelVariant(variant); },
            onListScreenshots: () => { this.listScreenshots(); },
            onDeleteModelConfigJson: () => { this.deleteModelConfigJson(); },
            onListModelFilesTree: () => { this.listModelFilesTree(); },
            onDeleteChunkVisionOmFiles: () => { this.deleteChunkVisionOmFiles(); },
            onUpdateConfigBackendType: (target: string) => { this.updateConfigBackendType(target); }
          })
        }.tabBar(this.TabItem(mainTabIcon(MainTabIndex.Settings), mainTabLabel(MainTabIndex.Settings), MainTabIndex.Settings))
      }
      .onChange((index: number) => { this.currentTab = index; })
      .width('100%')
      .height('100%')
      .backgroundColor('#F4F8FF')

      this.DataManagerProgressOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
