import { promptAction, router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import {
  CloudModelClient,
  GalleryCloudModelConfig,
  GalleryMonthSummaryResult
} from '../../utils/CloudModelClient';
import { GalleryAnalyzer } from '../../utils/gallery/GalleryAnalyzer';
import { GalleryAutoScanner } from '../../utils/gallery/GalleryAutoScanner';
import {
  GalleryMonthlyCategoryCount,
  GalleryMonthlyInsight,
  GalleryMonthlyInsights
} from '../../utils/gallery/GalleryMonthlyInsights';
import { GalleryPhotoPicker } from '../../utils/gallery/GalleryPhotoPicker';
import { GalleryStorage } from '../../utils/gallery/GalleryStorage';
import {
  GalleryAnalysisResult,
  GalleryAnalyzeOutcome,
  GalleryAnalyzerConfig,
  GalleryPhotoInput,
  GalleryProgress,
  GalleryScanItem,
  GalleryScanSession
} from '../../utils/gallery/GalleryTypes';

const DEFAULT_GALLERY_API_BASE_URL = 'https://api.modelbest.cn/v1';
const DEFAULT_GALLERY_API_KEY = 'sk-pQ8L2zF3XmR5kY9wV4jB7hN1tC6vM0xG3aD5sH2bJ9lK4cZ8';
const DEFAULT_GALLERY_MODEL = 'MiniCPM-V-4.6-Instruct';
const DEFAULT_GALLERY_SKIP_OCR = 'false';
const DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER = 'true';
const DEFAULT_GALLERY_OCR_CONCURRENCY = '3';
const DEFAULT_GALLERY_MODEL_CONCURRENCY = '2';
const DEFAULT_GALLERY_EMBEDDING_CONCURRENCY = '2';
const DEFAULT_GALLERY_EMBEDDING_MODE = 'huawei_local';
const DEFAULT_GALLERY_EMBEDDING_BASE_URL = 'https://api.siliconflow.cn/v1';
const DEFAULT_GALLERY_EMBEDDING_API_KEY = 'sk-ftatcmqivwegrrazieeiiwswmotmryswxwhjuakxwsmsudrs';
const DEFAULT_GALLERY_EMBEDDING_MODEL = 'BAAI/bge-m3';
const DEFAULT_GALLERY_IMAGE_SCALE = '0.25';
const GALLERY_RESULT_PAGE_SIZE = 10;

PersistentStorage.persistProp('galleryApiBaseUrl', DEFAULT_GALLERY_API_BASE_URL);
PersistentStorage.persistProp('galleryApiKey', DEFAULT_GALLERY_API_KEY);
PersistentStorage.persistProp('galleryModel', DEFAULT_GALLERY_MODEL);
PersistentStorage.persistProp('gallerySkipOcr', DEFAULT_GALLERY_SKIP_OCR);
PersistentStorage.persistProp('galleryUseOcrKeywordFilter', DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER);
PersistentStorage.persistProp('galleryOcrConcurrency', DEFAULT_GALLERY_OCR_CONCURRENCY);
PersistentStorage.persistProp('galleryModelConcurrency', DEFAULT_GALLERY_MODEL_CONCURRENCY);
PersistentStorage.persistProp('galleryEmbeddingConcurrency', DEFAULT_GALLERY_EMBEDDING_CONCURRENCY);
PersistentStorage.persistProp('galleryEmbeddingMode', DEFAULT_GALLERY_EMBEDDING_MODE);
PersistentStorage.persistProp('galleryEmbeddingBaseUrl', DEFAULT_GALLERY_EMBEDDING_BASE_URL);
PersistentStorage.persistProp('galleryEmbeddingApiKey', DEFAULT_GALLERY_EMBEDDING_API_KEY);
PersistentStorage.persistProp('galleryEmbeddingModel', DEFAULT_GALLERY_EMBEDDING_MODEL);
PersistentStorage.persistProp('galleryImageScale', DEFAULT_GALLERY_IMAGE_SCALE);

@Entry
@Component
struct GalleryPage {
  @State analyzing: boolean = false;
  @State progress: number = 0;
  @State selectedFilter: number = 0;
  @State selectedTimeFilter: number = 0;
  @State resultDisplayLimit: number = GALLERY_RESULT_PAGE_SIZE;
  @State lastRunText: string = '尚未开始';
  @State settingsOpen: boolean = false;
  @State progressText: string = '等待选择图库图片';
  @State autoScanStatus: string = 'idle';
  @State scanTotal: number = 0;
  @State scanProcessed: number = 0;
  @State scanPending: number = 0;
  @State scanSkipped: number = 0;
  @State scanFailed: number = 0;
  @State results: GalleryAnalysisResult[] = [];
  @State resultRevision: number = 0;
  @State selectedMonthKey: string = '';
  @State monthlyAiSummaries: Record<string, GalleryMonthSummaryResult> = {};
  @State monthlyAiLoadingKey: string = '';
  @State monthlyAiErrorKey: string = '';
  @State monthlyAiErrorText: string = '';
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

  private filesDir: string = '';
  private cloudClient: CloudModelClient = new CloudModelClient();
  private pauseRequested: boolean = false;
  private lastRunAt: number = 0;
  private lastRunTimerId: number = -1;

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    this.ensureDefaultSettings();
    this.replaceResults(GalleryStorage.loadResults(this.filesDir));
    this.restoreLastRunFromResults();
    this.restoreScanSessionState();
    this.startLastRunTimer();
  }

  aboutToDisappear(): void {
    this.stopLastRunTimer();
  }

  private ensureDefaultSettings(): void {
    if (this.galleryApiKey.trim().length === 0) {
      this.galleryApiKey = DEFAULT_GALLERY_API_KEY;
    }
    if (this.galleryModel.trim().length === 0) {
      this.galleryModel = DEFAULT_GALLERY_MODEL;
    }
    if (this.galleryApiBaseUrl.trim().length === 0) {
      this.galleryApiBaseUrl = DEFAULT_GALLERY_API_BASE_URL;
    }
    if (this.galleryEmbeddingMode.trim().length === 0) {
      this.galleryEmbeddingMode = DEFAULT_GALLERY_EMBEDDING_MODE;
    }
    if (this.galleryEmbeddingApiKey.trim().length === 0) {
      this.galleryEmbeddingApiKey = DEFAULT_GALLERY_EMBEDDING_API_KEY;
    }
    if (this.galleryUseOcrKeywordFilter.trim().length === 0) {
      this.galleryUseOcrKeywordFilter = DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER;
    }
    this.galleryImageScale = this.normalizeScale(this.galleryImageScale, DEFAULT_GALLERY_IMAGE_SCALE);
  }

  private visibleCount(): string {
    return this.visibleResults().length.toString() + ' 张';
  }

  private async startManualAnalyze(): Promise<void> {
    if (this.analyzing) {
      promptAction.showToast({ message: '图库分析正在进行', duration: 1200 });
      return;
    }
    try {
      let picker = new GalleryPhotoPicker();
      let uris = await picker.selectImageUris(9);
      if (uris.length === 0) {
        promptAction.showToast({ message: '未选择图片', duration: 1200 });
        return;
      }
      this.analyzing = true;
      this.progress = 0;
      this.selectedFilter = 0;
      this.selectedTimeFilter = 0;
      this.resultDisplayLimit = GALLERY_RESULT_PAGE_SIZE;
      this.clearMonthlyAiState();
      this.progressText = '已选择 ' + uris.length + ' 张图片';
      this.setLastRunLabel('分析中');
      let analyzer = new GalleryAnalyzer(this.filesDir, this.cloudClient);
      let finalResults = await analyzer.analyzeUris(uris, this.buildAnalyzerConfig(false), (next: GalleryProgress) => {
        this.updateProgress(next);
      }, (result: GalleryAnalysisResult) => {
        this.mergeResult(result);
      });
      let storedResults = GalleryStorage.loadResults(this.filesDir);
      if (storedResults.length > 0) {
        this.replaceResults(storedResults);
      } else if (finalResults.length > 0) {
        this.replaceResults(finalResults);
      }
      this.analyzing = false;
      this.progress = 100;
      this.progressText = '分析完成';
      this.setLastRun(new Date().getTime());
      promptAction.showToast({ message: '图库分析完成', duration: 1500 });
    } catch (e) {
      this.analyzing = false;
      this.progressText = this.errorMessage(e);
      this.setLastRunLabel('分析失败');
      promptAction.showToast({ message: '图库分析失败：' + this.errorMessage(e), duration: 2000 });
    }
  }

  private async startAutoAnalyze(): Promise<void> {
    if (this.analyzing) {
      promptAction.showToast({ message: '图库分析正在进行', duration: 1200 });
      return;
    }
    try {
      let ctx = getContext(this) as common.UIAbilityContext;
      let granted = await this.ensureGalleryReadPermission(ctx);
      if (!granted) {
        promptAction.showToast({ message: '未获得图库读取权限', duration: 1600 });
        return;
      }
      let scanner = new GalleryAutoScanner();
      let inputs = await scanner.scanAllImages(ctx);
      if (inputs.length === 0) {
        promptAction.showToast({ message: '未扫描到图库图片', duration: 1200 });
        return;
      }
      let session = this.createScanSession(inputs);
      this.clearMonthlyAiState();
      GalleryStorage.saveScanSession(this.filesDir, session);
      await this.runScanSession(session);
    } catch (e) {
      this.analyzing = false;
      this.autoScanStatus = 'failed';
      this.progressText = this.errorMessage(e);
      this.setLastRunLabel('分析失败');
      promptAction.showToast({ message: '自动分析失败：' + this.errorMessage(e), duration: 2000 });
    }
  }

  private async continueAutoAnalyze(): Promise<void> {
    if (this.analyzing) {
      promptAction.showToast({ message: '图库分析正在进行', duration: 1200 });
      return;
    }
    let session = GalleryStorage.loadScanSession(this.filesDir);
    if (!session) {
      promptAction.showToast({ message: '没有可继续的扫描任务', duration: 1200 });
      return;
    }
    await this.runScanSession(session);
  }

  private requestPauseAutoAnalyze(): void {
    if (!this.analyzing) {
      return;
    }
    this.pauseRequested = true;
    this.autoScanStatus = 'pausing';
    this.progressText = '正在暂停，等待当前请求完成';
    let session = GalleryStorage.loadScanSession(this.filesDir);
    if (session) {
      session.status = 'pausing';
      GalleryStorage.saveScanSession(this.filesDir, session);
    }
  }

  private async runScanSession(session: GalleryScanSession): Promise<void> {
    let pendingInputs = this.pendingInputs(session);
    if (pendingInputs.length === 0) {
      session.status = 'completed';
      GalleryStorage.saveScanSession(this.filesDir, session);
      this.applyScanSession(session);
      this.progress = 100;
      this.updateScanProgressText('自动分析完成', session);
      this.setLastRun(new Date().getTime());
      return;
    }
    this.pauseRequested = false;
    this.analyzing = true;
    this.autoScanStatus = 'running';
    this.progress = session.total === 0 ? 0 : Math.floor(session.processed * 100 / session.total);
    this.selectedFilter = 0;
    this.selectedTimeFilter = 0;
    this.resultDisplayLimit = GALLERY_RESULT_PAGE_SIZE;
    this.setLastRunLabel('分析中');
    session.status = 'running';
    GalleryStorage.saveScanSession(this.filesDir, session);
    this.applyScanSession(session);
    this.updateScanProgressText('准备分析', session);

    let analyzer = new GalleryAnalyzer(this.filesDir, this.cloudClient);
    let finalResults = await analyzer.analyzeInputs(pendingInputs, this.buildAnalyzerConfig(true), (next: GalleryProgress) => {
      this.updateAutoProgress(session);
    }, (result: GalleryAnalysisResult) => {
      this.mergeResult(result);
    }, {
      shouldPause: (): boolean => this.pauseRequested,
      onItemDone: (input: GalleryPhotoInput, outcome: GalleryAnalyzeOutcome) => {
        this.markScanItem(session, input, outcome.cached, outcome.result.error);
        GalleryStorage.saveScanSession(this.filesDir, session);
        this.applyScanSession(session);
        this.updateScanProgressText(this.scanItemStatusText(input, outcome), session);
      }
    });
    let storedResults = GalleryStorage.loadResults(this.filesDir);
    if (storedResults.length > 0) {
      this.replaceResults(storedResults);
    } else if (finalResults.length > 0) {
      this.replaceResults(finalResults);
    }

    this.analyzing = false;
    if (this.pauseRequested) {
      session.status = 'paused';
      GalleryStorage.saveScanSession(this.filesDir, session);
      this.autoScanStatus = 'paused';
      this.applyScanSession(session);
      this.updateScanProgressText('已暂停', session);
      this.setLastRunLabel('已暂停');
      promptAction.showToast({ message: '自动分析已暂停', duration: 1200 });
      return;
    }
    this.recountScanSession(session);
    let sessionCompleted = session.processed >= session.total;
    session.status = sessionCompleted ? 'completed' : 'paused';
    GalleryStorage.saveScanSession(this.filesDir, session);
    this.applyScanSession(session);
    this.progress = session.total === 0 ? 100 : Math.floor(session.processed * 100 / session.total);
    this.updateScanProgressText(sessionCompleted ? '自动分析完成' : '已暂停', session);
    if (sessionCompleted) {
      this.setLastRun(new Date().getTime());
    } else {
      this.setLastRunLabel('已暂停');
    }
    promptAction.showToast({ message: sessionCompleted ? '自动分析完成' : '自动分析已暂停', duration: 1500 });
  }

  private async ensureGalleryReadPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    let permissions: Permissions[] = ['ohos.permission.READ_IMAGEVIDEO', 'ohos.permission.MEDIA_LOCATION'];
    let atManager = abilityAccessCtrl.createAtManager();
    let result = await atManager.requestPermissionsFromUser(ctx, permissions);
    if (!result.authResults || result.authResults.length === 0) {
      return false;
    }
    return result.authResults[0] === 0;
  }

  private mergeResult(result: GalleryAnalysisResult): void {
    let nextResults: GalleryAnalysisResult[] = [];
    let inserted = false;
    for (let i = 0; i < this.results.length; i++) {
      if (this.results[i].id === result.id) {
        nextResults.push(result);
        inserted = true;
      } else {
        nextResults.push(this.results[i]);
      }
    }
    if (!inserted) {
      nextResults.push(result);
    }
    this.sortResultsByRecent(nextResults);
    this.replaceResults(nextResults);
  }

  private replaceResults(nextResults: GalleryAnalysisResult[]): void {
    this.sortResultsByRecent(nextResults);
    this.results = nextResults;
    this.resultRevision += 1;
    this.ensureSelectedMonth();
  }

  private monthlyInsights(): GalleryMonthlyInsight[] {
    return GalleryMonthlyInsights.build(this.results);
  }

  private ensureSelectedMonth(): void {
    let insights = this.monthlyInsights();
    if (insights.length === 0) {
      this.selectedMonthKey = '';
      return;
    }
    for (let i = 0; i < insights.length; i++) {
      if (insights[i].key === this.selectedMonthKey) {
        return;
      }
    }
    this.selectedMonthKey = insights[0].key;
  }

  private selectedMonthlyInsight(): GalleryMonthlyInsight | null {
    let insights = this.monthlyInsights();
    if (insights.length === 0) {
      return null;
    }
    for (let i = 0; i < insights.length; i++) {
      if (insights[i].key === this.selectedMonthKey) {
        return insights[i];
      }
    }
    return insights[0];
  }

  private selectedMonthlyInsightList(): GalleryMonthlyInsight[] {
    let insight = this.selectedMonthlyInsight();
    if (insight === null) {
      return [];
    }
    return [insight];
  }

  private monthlyAiSummary(insight: GalleryMonthlyInsight): GalleryMonthSummaryResult | undefined {
    return this.monthlyAiSummaries[insight.key];
  }

  private monthlyTitle(insight: GalleryMonthlyInsight): string {
    let summary = this.monthlyAiSummary(insight);
    if (summary && summary.title && summary.title.length > 0) {
      return summary.title;
    }
    return insight.label;
  }

  private monthlySummaryText(insight: GalleryMonthlyInsight): string {
    let summary = this.monthlyAiSummary(insight);
    if (summary && summary.summary && summary.summary.length > 0) {
      return summary.summary;
    }
    return insight.summary;
  }

  private monthlySuggestionText(insight: GalleryMonthlyInsight): string {
    let summary = this.monthlyAiSummary(insight);
    if (summary && summary.suggestion && summary.suggestion.length > 0) {
      return summary.suggestion;
    }
    return '';
  }

  private monthlyAiButtonText(insight: GalleryMonthlyInsight): string {
    if (this.monthlyAiLoadingKey === insight.key) {
      return '生成中';
    }
    return this.monthlyAiSummary(insight) ? '重生成' : 'AI 总结';
  }

  private monthlyAiError(insight: GalleryMonthlyInsight): string {
    if (this.monthlyAiErrorKey === insight.key) {
      return this.monthlyAiErrorText;
    }
    return '';
  }

  private clearMonthlyAiState(): void {
    this.monthlyAiSummaries = {};
    this.monthlyAiLoadingKey = '';
    this.monthlyAiErrorKey = '';
    this.monthlyAiErrorText = '';
  }

  private galleryCloudModelConfig(): GalleryCloudModelConfig {
    return {
      baseUrl: this.galleryApiBaseUrl.trim().length > 0 ? this.galleryApiBaseUrl.trim() : DEFAULT_GALLERY_API_BASE_URL,
      apiKey: this.galleryApiKey.trim().length > 0 ? this.galleryApiKey.trim() : DEFAULT_GALLERY_API_KEY,
      model: this.galleryModel.trim().length > 0 ? this.galleryModel.trim() : DEFAULT_GALLERY_MODEL
    };
  }

  private async generateAiMonthlySummary(insight: GalleryMonthlyInsight): Promise<void> {
    if (this.monthlyAiLoadingKey.length > 0) {
      return;
    }
    this.monthlyAiLoadingKey = insight.key;
    this.monthlyAiErrorKey = '';
    this.monthlyAiErrorText = '';
    try {
      let result = await this.cloudClient.summarizeGalleryMonth(this.galleryCloudModelConfig(),
        GalleryMonthlyInsights.buildLlmInput(insight));
      let next: Record<string, GalleryMonthSummaryResult> = {};
      let keys = Object.keys(this.monthlyAiSummaries);
      for (let i = 0; i < keys.length; i++) {
        next[keys[i]] = this.monthlyAiSummaries[keys[i]];
      }
      next[insight.key] = result;
      this.monthlyAiSummaries = next;
    } catch (e) {
      this.monthlyAiErrorKey = insight.key;
      this.monthlyAiErrorText = this.errorMessage(e);
      promptAction.showToast({ message: 'AI 月度总结失败：' + this.errorMessage(e), duration: 1800 });
    }
    this.monthlyAiLoadingKey = '';
  }

  private restoreLastRunFromResults(): void {
    if (this.results.length === 0) {
      this.setLastRunLabel('尚未开始');
      return;
    }
    let latest = 0;
    for (let i = 0; i < this.results.length; i++) {
      if (this.results[i].createdAt > latest) {
        latest = this.results[i].createdAt;
      }
    }
    if (latest > 0) {
      this.setLastRun(latest);
    } else {
      this.setLastRunLabel('尚未开始');
    }
  }

  private setLastRun(ts: number): void {
    this.lastRunAt = ts;
    this.lastRunText = this.relativeTimeText(ts);
  }

  private setLastRunLabel(label: string): void {
    this.lastRunAt = 0;
    this.lastRunText = label;
  }

  private startLastRunTimer(): void {
    if (this.lastRunTimerId !== -1) {
      return;
    }
    this.lastRunTimerId = setInterval(() => {
      if (this.lastRunAt > 0) {
        this.lastRunText = this.relativeTimeText(this.lastRunAt);
      }
    }, 60 * 1000);
  }

  private stopLastRunTimer(): void {
    if (this.lastRunTimerId !== -1) {
      clearInterval(this.lastRunTimerId);
      this.lastRunTimerId = -1;
    }
  }

  private relativeTimeText(ts: number): string {
    let diffMs = new Date().getTime() - ts;
    if (diffMs < 0) {
      diffMs = 0;
    }
    let minuteMs = 60 * 1000;
    let hourMs = 60 * minuteMs;
    let dayMs = 24 * hourMs;
    let monthMs = 30 * dayMs;
    if (diffMs < 2 * minuteMs) {
      return '刚刚';
    }
    if (diffMs < 30 * minuteMs) {
      return Math.max(1, Math.floor(diffMs / minuteMs)).toString() + '分钟前';
    }
    if (diffMs < hourMs) {
      return '半小时前';
    }
    if (diffMs < dayMs) {
      return Math.max(1, Math.floor(diffMs / hourMs)).toString() + '小时前';
    }
    if (diffMs < monthMs) {
      return Math.max(1, Math.floor(diffMs / dayMs)).toString() + '天前';
    }
    if (diffMs < 12 * monthMs) {
      return Math.max(1, Math.floor(diffMs / monthMs)).toString() + '个月前';
    }
    return Math.max(1, Math.floor(diffMs / (12 * monthMs))).toString() + '年前';
  }

  private createScanSession(inputs: GalleryPhotoInput[]): GalleryScanSession {
    let items: GalleryScanItem[] = [];
    for (let i = 0; i < inputs.length; i++) {
      let input = inputs[i];
      let id = this.stableId(input.uri);
      let inputId = input.id;
      if (inputId !== undefined && inputId.length > 0) {
        id = inputId;
      }
      let date = this.formatDate(new Date().getTime());
      let inputDate = input.date;
      if (inputDate !== undefined && inputDate.length > 0) {
        date = inputDate;
      }
      items.push({
        uri: input.uri,
        id: id,
        date: date,
        status: 'queued',
        error: ''
      });
    }
    let now = new Date().getTime();
    return {
      id: 'gallery_scan_' + now.toString(),
      status: 'queued',
      createdAt: now,
      updatedAt: now,
      total: items.length,
      processed: 0,
      skipped: 0,
      failed: 0,
      items: items
    };
  }

  private pendingInputs(session: GalleryScanSession): GalleryPhotoInput[] {
    let inputs: GalleryPhotoInput[] = [];
    for (let i = 0; i < session.items.length; i++) {
      if (session.items[i].status === 'queued' || session.items[i].status === 'failed') {
        if (session.items[i].status === 'failed') {
          session.items[i].status = 'queued';
          session.items[i].error = '';
        }
        inputs.push({
          uri: session.items[i].uri,
          id: session.items[i].id,
          date: session.items[i].date
        });
      }
    }
    this.recountScanSession(session);
    return inputs;
  }

  private markScanItem(session: GalleryScanSession, input: GalleryPhotoInput, cached: boolean, error: string): void {
    let inputId = input.id;
    let inputDate = input.date;
    if (inputId === undefined || inputDate === undefined) {
      return;
    }
    for (let i = 0; i < session.items.length; i++) {
      if (session.items[i].id === inputId && session.items[i].date === inputDate) {
        if (error && error.length > 0) {
          session.items[i].status = 'failed';
          session.items[i].error = error;
        } else {
          session.items[i].status = cached ? 'skipped' : 'done';
          session.items[i].error = '';
        }
        break;
      }
    }
    this.recountScanSession(session);
  }

  private recountScanSession(session: GalleryScanSession): void {
    let processed = 0;
    let skipped = 0;
    let failed = 0;
    for (let i = 0; i < session.items.length; i++) {
      if (session.items[i].status === 'done' || session.items[i].status === 'skipped') {
        processed += 1;
      }
      if (session.items[i].status === 'skipped') {
        skipped += 1;
      }
      if (session.items[i].status === 'failed') {
        failed += 1;
      }
    }
    session.total = session.items.length;
    session.processed = processed;
    session.skipped = skipped;
    session.failed = failed;
  }

  private applyScanSession(session: GalleryScanSession): void {
    this.recountScanSession(session);
    this.scanTotal = session.total;
    this.scanProcessed = session.processed;
    this.scanSkipped = session.skipped;
    this.scanFailed = session.failed;
    this.scanPending = Math.max(0, session.total - session.processed);
    this.autoScanStatus = session.status;
    this.progress = session.total === 0 ? 0 : Math.floor(session.processed * 100 / session.total);
  }

  private restoreScanSessionState(): void {
    let session = GalleryStorage.loadScanSession(this.filesDir);
    if (!session) {
      this.autoScanStatus = 'idle';
      return;
    }
    this.applyScanSession(session);
    if (this.scanPending > 0 && session.status === 'completed') {
      session.status = 'paused';
      GalleryStorage.saveScanSession(this.filesDir, session);
      this.applyScanSession(session);
    }
    if (this.scanPending > 0 && (session.status === 'paused' || session.status === 'pausing' || session.status === 'running')) {
      this.updateScanProgressText('可继续', session);
      this.setLastRunLabel('已暂停');
    }
  }

  private stableId(uri: string): string {
    let hash = 0;
    for (let i = 0; i < uri.length; i++) {
      hash = ((hash << 5) - hash) + uri.charCodeAt(i);
      hash = hash & hash;
    }
    return 'gallery_' + Math.abs(hash).toString();
  }

  private normalizeConcurrency(value: string, fallback: string, maxValue: number): string {
    let digits = '';
    for (let i = 0; i < value.length; i++) {
      let ch = value.charAt(i);
      if (ch >= '0' && ch <= '9') {
        digits += ch;
      }
    }
    if (digits.length === 0) {
      return fallback;
    }
    let num = parseInt(digits);
    if (num < 1) {
      num = 1;
    }
    if (num > maxValue) {
      num = maxValue;
    }
    return num.toString();
  }

  private normalizeScale(value: string, fallback: string): string {
    let parsed = parseFloat(value);
    if (isNaN(parsed)) {
      parsed = parseFloat(fallback);
    }
    if (isNaN(parsed)) {
      parsed = 0.25;
    }
    if (parsed < 0.1) {
      parsed = 0.1;
    }
    if (parsed > 1) {
      parsed = 1;
    }
    return parsed.toFixed(2);
  }

  @Builder StatCell(label: string, value: string, color: string) {
    Column() {
      Text(label).fontSize(12).fontColor('#737987').maxLines(1)
      Text(value)
        .fontSize(label === '最近分析' ? 14 : 21)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 5 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  private runAction(actionId: number): void {
    if (actionId === 0) {
      if (this.hasPausedScan()) {
        this.continueAutoAnalyze();
      } else {
        this.startAutoAnalyze();
      }
      return;
    }
    if (actionId === 1) {
      this.startManualAnalyze();
      return;
    }
    if (actionId === 3) {
      this.requestPauseAutoAnalyze();
      return;
    }
    if (!this.analyzing) {
      GalleryStorage.clear(this.filesDir);
      GalleryStorage.clearScanSession(this.filesDir);
      this.replaceResults([]);
      this.clearMonthlyAiState();
      this.progress = 0;
      this.selectedFilter = 0;
      this.selectedTimeFilter = 0;
      this.resultDisplayLimit = GALLERY_RESULT_PAGE_SIZE;
      this.scanTotal = 0;
      this.scanProcessed = 0;
      this.scanPending = 0;
      this.scanSkipped = 0;
      this.scanFailed = 0;
      this.autoScanStatus = 'idle';
      this.setLastRunLabel('尚未开始');
      this.progressText = '缓存已清理';
      promptAction.showToast({ message: '图库缓存已清理', duration: 1200 });
    }
  }

  private hasPausedScan(): boolean {
    return !this.analyzing && this.scanPending > 0 &&
      (this.autoScanStatus === 'paused' || this.autoScanStatus === 'pausing' || this.autoScanStatus === 'running');
  }

  private autoActionTitle(): string {
    if (this.analyzing) {
      return '分析中';
    }
    if (this.hasPausedScan()) {
      return '继续分析';
    }
    return '图库分析';
  }

  @Builder PrimaryActionButton() {
    Row() {
      Text('选择图片分析').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1).maxLines(1)
      Text('>')
        .fontSize(18)
        .fontColor('#39BFA3')
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .backgroundColor(Color.White)
        .borderRadius(15)
    }
    .width('100%')
    .height(50)
    .padding({ left: 16, right: 14 })
    .backgroundColor('#39BFA3')
    .borderRadius(15)
    .margin({ top: 10 })
    .onClick(() => { this.runAction(1); })
  }

  @Builder HeaderIconButton(label: string, actionId: number) {
    Text(label)
      .fontSize(18)
      .fontColor('#2F5BEA')
      .width(38)
      .height(38)
      .textAlign(TextAlign.Center)
      .backgroundColor('#EEF3FF')
      .borderRadius(10)
      .onClick(() => {
        if (actionId === 0) {
          router.back();
          return;
        }
        this.settingsOpen = !this.settingsOpen;
      })
  }

  @Builder ToolbarAction(title: string, color: string, bg: string, actionId: number) {
    Button(title)
      .height(38)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(color)
      .backgroundColor(bg)
      .borderRadius(9)
      .enabled(!(this.analyzing && actionId !== 3))
      .onClick(() => { this.runAction(actionId); })
  }

  @Builder ActionToolbar(analyzedText: string, lastRunText: string) {
    Column() {
      Row() {
        this.StatCell('已分析', analyzedText, '#2F5BEA')
        Divider().vertical(true).height(38).color('#E5E8F0')
        this.StatCell('最近分析', lastRunText, '#202636')
      }.width('100%')

      Row() {
        this.ToolbarAction('选择图片', '#FFFFFF', '#2F5BEA', 1)
        Blank().width(8)
        this.ToolbarAction(this.autoActionTitle(), '#2F5BEA', '#EEF3FF', 0)
        Blank().width(8)
        if (this.analyzing) {
          this.ToolbarAction(this.autoScanStatus === 'pausing' ? '暂停中' : '暂停', '#B55A00', '#FFF4E8', 3)
        } else {
          this.ToolbarAction('清理缓存', '#B55A00', '#FFF4E8', 2)
        }
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('90%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ top: 14 })
  }

  private shouldShowProgressStrip(): boolean {
    return this.analyzing || this.hasPausedScan() || this.scanTotal > 0;
  }

  private progressTitle(): string {
    if (this.analyzing) {
      return this.autoScanStatus === 'pausing' ? '暂停中' : '分析中';
    }
    if (this.hasPausedScan()) {
      return '已暂停';
    }
    if (this.scanTotal > 0 && this.scanPending === 0) {
      return '已完成';
    }
    return '分析进度';
  }

  @Builder ProgressStrip(scanTotal: number, scanProcessed: number, scanPending: number, scanSkipped: number,
    scanFailed: number, progressValue: number, progressText: string, title: string, visible: boolean,
    analyzing: boolean) {
    if (visible) {
      Column() {
        Row() {
          Text(title)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202636')
            .layoutWeight(1)
          Text(progressValue.toString() + '%')
            .fontSize(12)
            .fontColor('#667085')
        }.width('100%')
        Progress({ value: progressValue, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(5)
          .color('#2F5BEA')
          .backgroundColor('#E8EDF7')
          .margin({ top: 8 })
        Text(progressText)
          .fontSize(12)
          .fontColor('#667085')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 8 })
        this.ScanStatsPanel(scanTotal, scanProcessed, scanPending, scanSkipped, scanFailed, analyzing)
      }
      .width('90%')
      .padding(14)
      .backgroundColor(Color.White)
      .borderRadius(12)
      .margin({ top: 10 })
    }
  }

  @Builder CompactActionButton(title: string, color: string, actionId: number) {
    Row() {
      Text(title).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('>')
        .fontSize(15)
        .fontColor(color)
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
    }
    .height(44)
    .layoutWeight(1)
    .padding({ left: 12, right: 10 })
    .backgroundColor('#F8FAFE')
    .borderRadius(13)
    .onClick(() => { this.runAction(actionId); })
  }

  @Builder ScanStatCell(label: string, value: number, color: string) {
    Column() {
      Text(label).fontSize(11).fontColor('#7C8494').maxLines(1)
      Text(value.toString()).fontSize(16).fontWeight(FontWeight.Bold).fontColor(color).margin({ top: 3 }).maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder ScanStatsPanel(scanTotal: number, scanProcessed: number, scanPending: number,
    scanSkipped: number, scanFailed: number, analyzing: boolean) {
    if (scanTotal > 0 || analyzing) {
      Column() {
        Row() {
          this.ScanStatCell('总数', scanTotal, '#151A28')
          this.ScanStatCell('已完成', scanProcessed, '#5B68FF')
          this.ScanStatCell('未完成', scanPending, '#FF8A3D')
          this.ScanStatCell('跳过', scanSkipped, '#39BFA3')
          this.ScanStatCell('失败', scanFailed, '#E5484D')
        }.width('100%')
      }
      .width('100%')
      .margin({ top: 14 })
    }
  }

  private updateSetting(fieldId: number, value: string): void {
    if (fieldId === 0) {
      this.galleryApiBaseUrl = value;
      return;
    }
    if (fieldId === 1) {
      this.galleryApiKey = value;
      return;
    }
    if (fieldId === 2) {
      this.galleryModel = value;
      return;
    }
    if (fieldId === 3) {
      this.gallerySkipOcr = value;
      return;
    }
    if (fieldId === 4) {
      this.galleryEmbeddingMode = value === 'true' ? 'remote' : 'huawei_local';
      return;
    }
    if (fieldId === 9) {
      this.galleryUseOcrKeywordFilter = value;
      return;
    }
    if (fieldId === 5) {
      this.galleryEmbeddingBaseUrl = value;
      return;
    }
    if (fieldId === 6) {
      this.galleryEmbeddingApiKey = value;
      return;
    }
    if (fieldId === 7) {
      this.galleryEmbeddingModel = value;
      return;
    }
    this.galleryImageScale = this.normalizeScale(value, this.galleryImageScale);
  }

  private updateConcurrency(fieldId: number, value: string, maxValue: number): void {
    if (fieldId === 0) {
      this.galleryOcrConcurrency = this.normalizeConcurrency(value, this.galleryOcrConcurrency, maxValue);
      return;
    }
    if (fieldId === 1) {
      this.galleryModelConcurrency = this.normalizeConcurrency(value, this.galleryModelConcurrency, maxValue);
      return;
    }
    this.galleryEmbeddingConcurrency = this.normalizeConcurrency(value, this.galleryEmbeddingConcurrency, maxValue);
  }

  @Builder SettingInput(label: string, value: string, placeholder: string, fieldId: number) {
    Column() {
      Text(label).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#2F3645').width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(42)
        .fontSize(12)
        .backgroundColor('#F7F9FE')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .margin({ top: 8 })
        .onChange((next: string) => { this.updateSetting(fieldId, next); })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder ConcurrencyInput(label: string, value: string, rangeText: string, maxValue: number, fieldId: number) {
    Column() {
      Row() {
        Text(label).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#2F3645').layoutWeight(1)
        Text(rangeText).fontSize(11).fontColor('#8A92A3')
      }.width('100%')
      TextInput({ placeholder: value, text: value })
        .width('100%')
        .height(42)
        .fontSize(12)
        .backgroundColor('#F7F9FE')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .margin({ top: 8 })
        .onChange((next: string) => { this.updateConcurrency(fieldId, next, maxValue); })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder SettingToggle(label: string, desc: string, enabled: boolean, fieldId: number) {
    Row() {
      Column() {
        Text(label).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#2F3645').width('100%')
        Text(desc).fontSize(11).fontColor('#8A92A3').margin({ top: 4 }).width('100%')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .selectedColor('#5B68FF')
        .onChange((next: boolean) => { this.updateSetting(fieldId, next ? 'true' : 'false'); })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder SettingsPanel() {
    if (this.settingsOpen) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => { this.settingsOpen = false; })

        Column() {
          Row() {
            Column() {
              Text('图库采集设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#11182F')
              Text('云端模型、OCR 与索引写入并发').fontSize(12).fontColor('#7B8290').margin({ top: 4 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('关闭')
              .fontSize(13)
              .fontColor('#5B68FF')
              .onClick(() => { this.settingsOpen = false; })
          }.width('100%')

          Scroll() {
            Column() {
              this.SettingInput('云端 API Base URL', this.galleryApiBaseUrl, 'https://api.example.com/v1', 0)
              this.SettingInput('API Key', this.galleryApiKey, 'Bearer token 或服务密钥', 1)
              this.SettingInput('大模型名称', this.galleryModel, 'MiniCPM-V-4.6-Instruct', 2)
              this.SettingToggle('跳过本地 OCR', '模拟器不支持 CoreVision OCR 时开启，直接让大模型分析图片', this.gallerySkipOcr === 'true', 3)
              this.SettingToggle('OCR 关键词预筛', '自动全库分析时先用 OCR 关键词过滤，手动选择图片不受影响', this.galleryUseOcrKeywordFilter === 'true', 9)
              this.ConcurrencyInput('OCR 并发请求数', this.galleryOcrConcurrency, '范围 1-6，默认 3', 6, 0)
              this.ConcurrencyInput('大模型并发请求数', this.galleryModelConcurrency, '范围 1-4，默认 2', 4, 1)
              this.SettingToggle('使用云端 Embedding API', '关闭时使用华为端侧 Embedding；开启时使用 SiliconFlow / bge-m3', this.galleryEmbeddingMode === 'remote', 4)
              this.SettingInput('Embedding Base URL', this.galleryEmbeddingBaseUrl, 'https://api.siliconflow.cn/v1', 5)
              this.SettingInput('Embedding API Key', this.galleryEmbeddingApiKey, 'SiliconFlow 服务密钥', 6)
              this.SettingInput('Embedding 模型', this.galleryEmbeddingModel, 'BAAI/bge-m3', 7)
              this.ConcurrencyInput('Embedding 并发请求数', this.galleryEmbeddingConcurrency, '范围 1-4，默认 2', 4, 2)
              this.SettingInput('图片分析缩放比例', this.galleryImageScale, '0.10 - 1.00，默认 0.25', 8)
            }.width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 6 })

          Row() {
            Button('恢复默认')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#EEF4FF')
              .fontColor('#4F68FF')
              .borderRadius(12)
              .onClick(() => {
                this.galleryApiBaseUrl = DEFAULT_GALLERY_API_BASE_URL;
                this.galleryApiKey = DEFAULT_GALLERY_API_KEY;
                this.galleryModel = DEFAULT_GALLERY_MODEL;
                this.gallerySkipOcr = DEFAULT_GALLERY_SKIP_OCR;
                this.galleryUseOcrKeywordFilter = DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER;
                this.galleryOcrConcurrency = DEFAULT_GALLERY_OCR_CONCURRENCY;
                this.galleryModelConcurrency = DEFAULT_GALLERY_MODEL_CONCURRENCY;
                this.galleryEmbeddingConcurrency = DEFAULT_GALLERY_EMBEDDING_CONCURRENCY;
                this.galleryEmbeddingMode = DEFAULT_GALLERY_EMBEDDING_MODE;
                this.galleryEmbeddingBaseUrl = DEFAULT_GALLERY_EMBEDDING_BASE_URL;
                this.galleryEmbeddingApiKey = DEFAULT_GALLERY_EMBEDDING_API_KEY;
                this.galleryEmbeddingModel = DEFAULT_GALLERY_EMBEDDING_MODEL;
                this.galleryImageScale = DEFAULT_GALLERY_IMAGE_SCALE;
              })
            Button('保存')
              .height(40)
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#5B68FF')
              .borderRadius(12)
              .margin({ left: 10 })
              .onClick(() => {
                this.settingsOpen = false;
                promptAction.showToast({ message: '图库采集设置已保存', duration: 1200 });
              })
          }.width('100%').margin({ top: 16 })
        }
        .width('86%')
        .height('82%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .shadow({ radius: 24, color: '#24000000', offsetX: 0, offsetY: 10 })
      }
      .width('100%')
      .height('100%')
    }
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
      .onClick(() => {
        this.selectedFilter = index;
        this.resultDisplayLimit = GALLERY_RESULT_PAGE_SIZE;
      })
  }

  private categoryLabel(category: string): string {
    let value = this.normalizeCategory(category);
    return value;
  }

  private categoryBg(category: string): string {
    let value = this.normalizeCategory(category);
    if (value === '餐饮') {
      return '#EAF8F3';
    }
    if (value === '出行') {
      return '#EAF1FF';
    }
    if (value === '购物') {
      return '#FFF1E7';
    }
    if (value === '健康') {
      return '#F0ECFF';
    }
    return '#EEF3FF';
  }

  private statusColor(status: string): string {
    let value = status ? status : '';
    if (value === 'ok' || value === '已入库') {
      return '#267A54';
    }
    if (value.indexOf('failed') === 0 || value.indexOf('失败') !== -1) {
      return '#B42318';
    }
    return '#667085';
  }

  private statusBg(status: string): string {
    let value = status ? status : '';
    if (value === 'ok' || value === '已入库') {
      return '#EAF8F3';
    }
    if (value.indexOf('failed') === 0 || value.indexOf('失败') !== -1) {
      return '#FDECEC';
    }
    return '#F2F4F7';
  }

  private tagAt(item: GalleryAnalysisResult, index: number): string {
    if (!item.tags || item.tags.length <= index) {
      return '';
    }
    let value = item.tags[index];
    if (!value) {
      return '';
    }
    return String(value);
  }

  private hasAnyDisplayTag(item: GalleryAnalysisResult): boolean {
    return this.tagAt(item, 0).length > 0 || this.tagAt(item, 1).length > 0 || this.tagAt(item, 2).length > 0;
  }

  private detailAt(item: GalleryAnalysisResult, index: number): string {
    if (!item.details || item.details.length <= index) {
      return '';
    }
    let value = item.details[index];
    if (!value) {
      return '';
    }
    return String(value);
  }

  private hasAnyDisplayDetail(item: GalleryAnalysisResult): boolean {
    return this.detailAt(item, 0).length > 0 || this.detailAt(item, 1).length > 0 || this.detailAt(item, 2).length > 0;
  }

  @Builder TagChip(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor('#596273')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor('#F4F6FA')
      .borderRadius(7)
      .margin({ right: 6, top: 6 })
  }

  @Builder InsightCard(item: GalleryAnalysisResult) {
    Row() {
      Image(this.previewUri(item))
        .width(92)
        .height(92)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
      Column() {
        Row() {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.categoryLabel(item.category))
            .fontSize(11)
            .fontColor(this.categoryColor(item.category))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.categoryBg(item.category))
            .borderRadius(8)
        }.width('100%')
        Text(item.summary)
          .fontSize(12)
          .fontColor('#596273')
          .margin({ top: 7 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.hasAnyDisplayDetail(item)) {
          Column() {
            if (this.detailAt(item, 0).length > 0) {
              Text('· ' + this.detailAt(item, 0)).fontSize(11).fontColor('#667085').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.detailAt(item, 1).length > 0) {
              Text('· ' + this.detailAt(item, 1)).fontSize(11).fontColor('#667085').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
            }
            if (this.detailAt(item, 2).length > 0) {
              Text('· ' + this.detailAt(item, 2)).fontSize(11).fontColor('#667085').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 6 })
        }
        if (this.hasAnyDisplayTag(item)) {
          Row() {
            if (this.tagAt(item, 0).length > 0) {
              this.TagChip(this.tagAt(item, 0))
            }
            if (this.tagAt(item, 1).length > 0) {
              this.TagChip(this.tagAt(item, 1))
            }
            if (this.tagAt(item, 2).length > 0) {
              this.TagChip(this.tagAt(item, 2))
            }
          }
          .width('100%')
          .height(24)
        }
        Row() {
          Text(this.resultTime(item))
            .fontSize(10)
            .fontColor('#858C99')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.resultStatus(item))
            .fontSize(10)
            .fontColor(this.statusColor(this.resultStatus(item)))
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.statusBg(this.resultStatus(item)))
            .borderRadius(7)
            .maxLines(1)
        }.width('100%').margin({ top: 4 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ top: 10 })
  }

  private buildAnalyzerConfig(useOcrKeywordFilter: boolean): GalleryAnalyzerConfig {
    return {
      apiBaseUrl: this.galleryApiBaseUrl.trim().length > 0 ? this.galleryApiBaseUrl.trim() : DEFAULT_GALLERY_API_BASE_URL,
      apiKey: this.galleryApiKey.trim().length > 0 ? this.galleryApiKey.trim() : DEFAULT_GALLERY_API_KEY,
      model: this.galleryModel.trim().length > 0 ? this.galleryModel.trim() : DEFAULT_GALLERY_MODEL,
      skipOcr: this.gallerySkipOcr === 'true',
      useOcrKeywordFilter: useOcrKeywordFilter && this.gallerySkipOcr !== 'true' && this.galleryUseOcrKeywordFilter === 'true',
      ocrConcurrency: parseInt(this.galleryOcrConcurrency),
      modelConcurrency: parseInt(this.galleryModelConcurrency),
      embeddingConcurrency: parseInt(this.galleryEmbeddingConcurrency),
      embeddingMode: this.galleryEmbeddingMode === 'remote' ? 'remote' : 'huawei_local',
      embeddingBaseUrl: this.galleryEmbeddingBaseUrl.trim().length > 0 ? this.galleryEmbeddingBaseUrl.trim() : DEFAULT_GALLERY_EMBEDDING_BASE_URL,
      embeddingApiKey: this.galleryEmbeddingApiKey.trim(),
      embeddingModel: this.galleryEmbeddingModel.trim().length > 0 ? this.galleryEmbeddingModel.trim() : DEFAULT_GALLERY_EMBEDDING_MODEL,
      imageScale: parseFloat(this.normalizeScale(this.galleryImageScale, DEFAULT_GALLERY_IMAGE_SCALE))
    };
  }

  private updateProgress(next: GalleryProgress): void {
    let done = next.processed > 0 ? next.processed : next.modelDone + next.failed;
    this.progress = next.selected === 0 ? 0 : Math.floor(done * 100 / next.selected);
    this.progressText = next.current + ' · 已完成 ' + next.processed + '/' + next.selected +
      ' · 未完成 ' + next.pending +
      ' · 跳过 ' + next.skipped +
      ' · 失败 ' + next.failed;
  }

  private updateAutoProgress(session: GalleryScanSession): void {
    this.recountScanSession(session);
    this.progress = session.total === 0 ? 0 : Math.floor(session.processed * 100 / session.total);
    this.updateScanProgressText('分析中', session);
  }

  private updateScanProgressText(current: string, session: GalleryScanSession): void {
    this.recountScanSession(session);
    this.progressText = current +
      ' · 已完成 ' + session.processed + '/' + session.total +
      ' · 未完成 ' + Math.max(0, session.total - session.processed) +
      ' · 跳过 ' + session.skipped +
      ' · 失败 ' + session.failed;
  }

  private scanItemStatusText(input: GalleryPhotoInput, outcome: GalleryAnalyzeOutcome): string {
    let label = input.id && input.id.length > 0 ? input.id : '当前图片';
    if (outcome.result.error && outcome.result.error.length > 0) {
      return '分析失败 ' + label;
    }
    if (outcome.cached) {
      return '跳过缓存 ' + label;
    }
    return '完成分析 ' + label;
  }

  private filteredResults(): GalleryAnalysisResult[] {
    if (this.selectedFilter === 0) {
      return this.results.slice(0);
    }
    let target = this.filterCategory(this.selectedFilter);
    return this.results.filter((item: GalleryAnalysisResult) => this.matchCategory(item.category, target));
  }

  private filterCategory(index: number): string {
    if (index === 1) {
      return '聊天';
    }
    if (index === 2) {
      return '文档';
    }
    if (index === 3) {
      return '餐饮';
    }
    if (index === 4) {
      return '购物';
    }
    if (index === 5) {
      return '出行';
    }
    if (index === 6) {
      return '健康';
    }
    if (index === 7) {
      return '工作';
    }
    return '其他';
  }

  private normalizeCategory(category: string): string {
    let value = category ? String(category).trim() : '';
    if (value === '聊天' || value === '文档' || value === '餐饮' || value === '购物' ||
      value === '出行' || value === '健康' || value === '工作') {
      return value;
    }
    return '其他';
  }

  private matchCategory(category: string, target: string): boolean {
    return this.normalizeCategory(category) === target;
  }

  private visibleResults(): GalleryAnalysisResult[] {
    let categoryResults = this.filteredResults();
    if (this.selectedTimeFilter === 0) {
      this.sortResultsByRecent(categoryResults);
      return categoryResults;
    }
    let now = new Date().getTime();
    let startTs = 0;
    if (this.selectedTimeFilter === 1) {
      startTs = now - 7 * 24 * 60 * 60 * 1000;
    } else if (this.selectedTimeFilter === 2) {
      startTs = now - 30 * 24 * 60 * 60 * 1000;
    } else {
      let yearStart = new Date(new Date().getFullYear(), 0, 1);
      startTs = yearStart.getTime();
    }
    let results = categoryResults.filter((item: GalleryAnalysisResult) => this.itemTime(item) >= startTs);
    this.sortResultsByRecent(results);
    return results;
  }

  private displayedResults(items: GalleryAnalysisResult[]): GalleryAnalysisResult[] {
    if (items.length <= this.resultDisplayLimit) {
      return items;
    }
    return items.slice(0, this.resultDisplayLimit);
  }

  private resultPanelCountText(): string {
    let visibleItems = this.visibleResults();
    return this.displayedResults(visibleItems).length.toString() + '/' + visibleItems.length.toString();
  }

  private itemTime(item: GalleryAnalysisResult): number {
    let dateText = item.date && item.date.length > 0 ? item.date : '';
    if (dateText.length >= 10) {
      let parsed = new Date(dateText + ' 00:00:00').getTime();
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
    return item.createdAt;
  }

  private sortResultsByRecent(items: GalleryAnalysisResult[]): void {
    items.sort((left: GalleryAnalysisResult, right: GalleryAnalysisResult) => {
      let rightTime = this.itemTime(right);
      let leftTime = this.itemTime(left);
      if (rightTime !== leftTime) {
        return rightTime - leftTime;
      }
      return right.createdAt - left.createdAt;
    });
  }

  private shouldShowDateHeader(items: GalleryAnalysisResult[], index: number): boolean {
    if (index === 0) {
      return true;
    }
    return this.groupDate(items[index]) !== this.groupDate(items[index - 1]);
  }

  private groupDate(item: GalleryAnalysisResult): string {
    if (item.date && item.date.length >= 10) {
      return item.date.substring(0, 10);
    }
    return this.formatDate(item.createdAt);
  }

  private formatDate(ts: number): string {
    let date = new Date(ts);
    let y = date.getFullYear();
    let m = (date.getMonth() + 1).toString().padStart(2, '0');
    let d = date.getDate().toString().padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  private formatDateTime(ts: number): string {
    let date = new Date(ts);
    let hh = date.getHours().toString().padStart(2, '0');
    let mm = date.getMinutes().toString().padStart(2, '0');
    return this.formatDate(ts) + ' ' + hh + ':' + mm;
  }

  private categoryColor(category: string): string {
    let value = this.normalizeCategory(category);
    if (value === '餐饮') {
      return '#39BFA3';
    }
    if (value === '出行') {
      return '#4B8BFF';
    }
    if (value === '购物') {
      return '#FF8A3D';
    }
    if (value === '健康') {
      return '#765BFF';
    }
    return '#5B68FF';
  }

  private resultTime(item: GalleryAnalysisResult): string {
    let imageDate = item.date && item.date.length > 0 ? item.date : this.formatDate(item.createdAt);
    return imageDate + ' · 分析 ' + this.formatDateTime(item.createdAt);
  }

  private resultStatus(item: GalleryAnalysisResult): string {
    if (item.error && item.error.length > 0) {
      return '分析失败';
    }
    let status = item.embeddingStatus ? item.embeddingStatus : '';
    if (status === 'ok') {
      return '已入库';
    }
    if (status === 'skipped' || status.length === 0) {
      return '未入库';
    }
    if (status.indexOf('failed') === 0) {
      return '入库失败';
    }
    return status;
  }

  private previewUri(item: GalleryAnalysisResult): string {
    return item.uri;
  }

  private monthlyCategoryColor(label: string): string {
    let colors = ['#4B8BFF', '#39BFA3', '#FF8A3D', '#765BFF', '#D14B7A', '#667085'];
    return colors[this.monthlyTagColorIndex(label)];
  }

  private monthlyCategoryBg(label: string): string {
    let colors = ['#EAF1FF', '#EAF8F3', '#FFF1E7', '#F0ECFF', '#FCECF3', '#F2F4F7'];
    return colors[this.monthlyTagColorIndex(label)];
  }

  private monthlyTagColorIndex(label: string): number {
    let hash = 0;
    let text = label && label.length > 0 ? label : 'tag';
    for (let i = 0; i < text.length; i++) {
      hash = (hash + text.charCodeAt(i)) % 6;
    }
    return hash;
  }

  private monthlyCategoryPercent(count: number, total: number): string {
    if (total <= 0) {
      return '0%';
    }
    let percent = Math.floor(count * 100 / total);
    if (percent < 6 && count > 0) {
      percent = 6;
    }
    return percent.toString() + '%';
  }

  @Builder MonthChip(insight: GalleryMonthlyInsight) {
    Column() {
      Text(insight.label)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selectedMonthKey === insight.key ? Color.White : '#4C5260')
        .maxLines(1)
      Text(insight.totalCount.toString() + ' 张')
        .fontSize(11)
        .fontColor(this.selectedMonthKey === insight.key ? '#EAF1FF' : '#7C8494')
        .margin({ top: 3 })
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .height(48)
    .padding({ left: 13, right: 13 })
    .backgroundColor(this.selectedMonthKey === insight.key ? '#4B8BFF' : '#F1F4FA')
    .borderRadius(12)
    .margin({ right: 8 })
    .onClick(() => {
      this.selectedMonthKey = insight.key;
    })
  }

  @Builder MonthlyCategoryBar(item: GalleryMonthlyCategoryCount, total: number) {
    Column() {
      Row() {
        Text(item.label)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2F3645')
          .layoutWeight(1)
          .maxLines(1)
        Text(item.count.toString() + ' 张')
          .fontSize(12)
          .fontColor('#7C8494')
          .maxLines(1)
      }.width('100%')
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(7)
          .backgroundColor('#EEF0F5')
          .borderRadius(4)
        Row()
          .width(this.monthlyCategoryPercent(item.count, total))
          .height(7)
          .backgroundColor(this.monthlyCategoryColor(item.label))
          .borderRadius(4)
      }
      .width('100%')
      .height(7)
      .margin({ top: 5 })
    }
    .width('100%')
    .margin({ top: 9 })
  }

  @Builder MonthlyCategoryChip(item: GalleryMonthlyCategoryCount) {
    Text(item.label + ' ' + item.count.toString())
      .fontSize(11)
      .fontColor(this.monthlyCategoryColor(item.label))
      .fontWeight(FontWeight.Bold)
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(this.monthlyCategoryBg(item.label))
      .borderRadius(8)
      .margin({ right: 7, top: 7 })
  }

  @Builder MonthlyRepresentativeImage(item: GalleryAnalysisResult) {
    Image(this.previewUri(item))
      .width(64)
      .height(64)
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .margin({ right: 8 })
  }

  @Builder MonthlyInsightsPanel(revision: number) {
    if (!this.analyzing && this.monthlyInsights().length > 0) {
      Column() {
        Row() {
          Text('月度洞察').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1)
          Text(this.monthlyInsights().length.toString() + ' 个月').fontSize(13).fontColor('#7F8592')
        }.width('100%')
        Scroll() {
          Row() {
            ForEach(this.monthlyInsights(), (insight: GalleryMonthlyInsight) => {
              this.MonthChip(insight)
            }, (insight: GalleryMonthlyInsight) => revision.toString() + '_' + insight.key)
          }
        }
        .width('100%')
        .height(56)
        .scrollable(ScrollDirection.Horizontal)
        .margin({ top: 12 })

        ForEach(this.selectedMonthlyInsightList(), (insight: GalleryMonthlyInsight) => {
          this.MonthlyInsightDetail(insight, revision)
        }, (insight: GalleryMonthlyInsight) => revision.toString() + '_' + insight.key + '_detail')
      }
      .width('86%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(18)
      .margin({ top: 18 })
    }
  }

  @Builder MonthlyInsightDetail(insight: GalleryMonthlyInsight, revision: number) {
    Column() {
      Row() {
        Column() {
          Text(this.monthlyTitle(insight))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#151A28')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(insight.totalCount.toString() + ' 张分析结果')
            .fontSize(12)
            .fontColor('#7C8494')
            .margin({ top: 3 })
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ right: 10 })
        Button(this.monthlyAiButtonText(insight))
          .height(34)
          .width(74)
          .fontSize(12)
          .fontColor('#4B8BFF')
          .backgroundColor('#EEF4FF')
          .borderRadius(10)
          .enabled(this.monthlyAiLoadingKey.length === 0)
          .onClick(() => {
            this.generateAiMonthlySummary(insight);
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Text(this.monthlySummaryText(insight))
        .fontSize(13)
        .fontColor('#596273')
        .lineHeight(20)
        .margin({ top: 10 })
        .width('100%')
        .maxLines(8)

      if (this.monthlySuggestionText(insight).length > 0) {
        Text('整理建议：' + this.monthlySuggestionText(insight))
          .fontSize(12)
          .fontColor('#4B5F9F')
          .lineHeight(18)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor('#F2F6FF')
          .borderRadius(10)
          .margin({ top: 10 })
          .width('100%')
          .maxLines(5)
      }

      if (this.monthlyAiError(insight).length > 0) {
        Text('AI 总结失败：' + this.monthlyAiError(insight))
          .fontSize(12)
          .fontColor('#B42318')
          .margin({ top: 8 })
          .width('100%')
      }

      ForEach(insight.categoryCounts.slice(0, Math.min(4, insight.categoryCounts.length)),
        (item: GalleryMonthlyCategoryCount) => {
          this.MonthlyCategoryBar(item, insight.totalCount)
        }, (item: GalleryMonthlyCategoryCount) => revision.toString() + '_' + insight.key + '_bar_' + item.label)

      Scroll() {
        Row() {
          ForEach(insight.representativeItems, (item: GalleryAnalysisResult) => {
            this.MonthlyRepresentativeImage(item)
          }, (item: GalleryAnalysisResult) => revision.toString() + '_' + insight.key + '_img_' + item.id)
        }
      }
      .width('100%')
      .height(72)
      .scrollable(ScrollDirection.Horizontal)
      .margin({ top: 12 })

      Row() {
        ForEach(insight.categoryCounts, (item: GalleryMonthlyCategoryCount) => {
          this.MonthlyCategoryChip(item)
        }, (item: GalleryMonthlyCategoryCount) => revision.toString() + '_' + insight.key + '_chip_' + item.label)
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
  }

  @Builder TimeFilterChip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.selectedTimeFilter === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.selectedTimeFilter === index ? '#151A28' : '#596071')
      .height(34)
      .padding({ left: 12, right: 12 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.selectedTimeFilter === index ? '#E8EEFF' : '#F1F4FA')
      .borderRadius(17)
      .margin({ right: 8 })
      .onClick(() => {
        this.selectedTimeFilter = index;
        this.resultDisplayLimit = GALLERY_RESULT_PAGE_SIZE;
      })
  }

  @Builder ResultsPanel(revision: number) {
    Column() {
      Row() {
        Column() {
          Text('图库结果').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#11182F')
          Text(this.resultPanelCountText() + ' 条可见').fontSize(12).fontColor('#7F8592').margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }.width('100%')
      Scroll() {
        Row() {
          this.FilterChip('全部', 0)
          this.FilterChip('聊天', 1)
          this.FilterChip('文档', 2)
          this.FilterChip('餐饮', 3)
          this.FilterChip('购物', 4)
          this.FilterChip('出行', 5)
          this.FilterChip('健康', 6)
          this.FilterChip('工作', 7)
          this.FilterChip('其他', 8)
        }
      }
      .width('100%')
      .height(40)
      .scrollable(ScrollDirection.Horizontal)
      .margin({ top: 12 })
      Scroll() {
        Row() {
          this.TimeFilterChip('全部时间', 0)
          this.TimeFilterChip('近7天', 1)
          this.TimeFilterChip('近30天', 2)
          this.TimeFilterChip('今年', 3)
        }
      }
      .width('100%')
      .height(38)
      .scrollable(ScrollDirection.Horizontal)
      .margin({ top: 4 })
      ForEach(this.displayedResults(this.visibleResults()), (item: GalleryAnalysisResult, index: number) => {
        if (this.shouldShowDateHeader(this.displayedResults(this.visibleResults()), index)) {
          Row() {
            Text(this.groupDate(item)).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#4C5260').layoutWeight(1)
          }
          .width('100%')
          .height(28)
          .margin({ top: index === 0 ? 6 : 14 })
        }
        this.InsightCard(item)
      }, (item: GalleryAnalysisResult) => revision.toString() + '_' + item.id)
      if (this.visibleResults().length === 0) {
        Column() {
          Text(this.results.length === 0 ? '暂无图库分析结果' : '当前筛选无结果')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#303746')
          Text(this.results.length === 0 ? '选择图片或启动全库分析后，这里会展示图片洞察。' : '换一个分类或时间范围看看。')
            .fontSize(12)
            .fontColor('#7B8393')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ top: 28, bottom: 24, left: 18, right: 18 })
        .backgroundColor('#F7F9FC')
        .borderRadius(12)
        .margin({ top: 16 })
      }
      if (this.visibleResults().length > this.resultDisplayLimit) {
        Button('加载更多')
          .height(40)
          .width('100%')
          .fontSize(13)
          .fontColor('#4F68FF')
          .backgroundColor('#EEF4FF')
          .borderRadius(12)
          .margin({ top: 12 })
          .onClick(() => { this.resultDisplayLimit += GALLERY_RESULT_PAGE_SIZE; })
      }
    }
    .width('90%')
    .padding(14)
    .backgroundColor('#F2F5FA')
    .borderRadius(12)
    .margin({ top: 14 })
  }

  private errorMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }

  build() {
    Stack() {
      Scroll() {
      Column() {
        Row() {
          this.HeaderIconButton('<', 0)
          Column() {
            Text('图库分析').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#11182F').maxLines(1)
            Text('相册、截图与文档图片洞察').fontSize(13).fontColor('#717684').margin({ top: 3 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })
          this.HeaderIconButton('⚙', 1)
        }
        .width('90%')
        .margin({ top: 24 })

        this.ActionToolbar(this.results.length.toString() + ' 张', this.lastRunText)
        this.ProgressStrip(this.scanTotal, this.scanProcessed, this.scanPending, this.scanSkipped, this.scanFailed,
          this.progress, this.progressText, this.progressTitle(), this.shouldShowProgressStrip(), this.analyzing)
        this.MonthlyInsightsPanel(this.resultRevision)
        this.ResultsPanel(this.resultRevision)

        Blank().height(100)
      }.width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F6F7FA')

      this.SettingsPanel()
    }
    .width('100%')
    .height('100%')
  }
}
