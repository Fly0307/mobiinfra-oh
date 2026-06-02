import { promptAction, router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { CloudModelClient } from '../../utils/CloudModelClient';
import { GalleryAnalyzer } from '../../utils/gallery/GalleryAnalyzer';
import { GalleryAutoScanner } from '../../utils/gallery/GalleryAutoScanner';
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
const DEFAULT_GALLERY_OCR_CONCURRENCY = '3';
const DEFAULT_GALLERY_MODEL_CONCURRENCY = '2';
const DEFAULT_GALLERY_EMBEDDING_CONCURRENCY = '2';
const DEFAULT_GALLERY_EMBEDDING_MODE = 'huawei_local';
const DEFAULT_GALLERY_EMBEDDING_BASE_URL = 'https://api.siliconflow.cn/v1';
const DEFAULT_GALLERY_EMBEDDING_API_KEY = 'sk-ftatcmqivwegrrazieeiiwswmotmryswxwhjuakxwsmsudrs';
const DEFAULT_GALLERY_EMBEDDING_MODEL = 'BAAI/bge-m3';

PersistentStorage.persistProp('galleryApiBaseUrl', DEFAULT_GALLERY_API_BASE_URL);
PersistentStorage.persistProp('galleryApiKey', DEFAULT_GALLERY_API_KEY);
PersistentStorage.persistProp('galleryModel', DEFAULT_GALLERY_MODEL);
PersistentStorage.persistProp('gallerySkipOcr', DEFAULT_GALLERY_SKIP_OCR);
PersistentStorage.persistProp('galleryOcrConcurrency', DEFAULT_GALLERY_OCR_CONCURRENCY);
PersistentStorage.persistProp('galleryModelConcurrency', DEFAULT_GALLERY_MODEL_CONCURRENCY);
PersistentStorage.persistProp('galleryEmbeddingConcurrency', DEFAULT_GALLERY_EMBEDDING_CONCURRENCY);
PersistentStorage.persistProp('galleryEmbeddingMode', DEFAULT_GALLERY_EMBEDDING_MODE);
PersistentStorage.persistProp('galleryEmbeddingBaseUrl', DEFAULT_GALLERY_EMBEDDING_BASE_URL);
PersistentStorage.persistProp('galleryEmbeddingApiKey', DEFAULT_GALLERY_EMBEDDING_API_KEY);
PersistentStorage.persistProp('galleryEmbeddingModel', DEFAULT_GALLERY_EMBEDDING_MODEL);

@Entry
@Component
struct GalleryPage {
  @State analyzing: boolean = false;
  @State progress: number = 0;
  @State selectedFilter: number = 0;
  @State selectedTimeFilter: number = 0;
  @State resultDisplayLimit: number = 120;
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
  @StorageLink('galleryApiBaseUrl') galleryApiBaseUrl: string = DEFAULT_GALLERY_API_BASE_URL;
  @StorageLink('galleryApiKey') galleryApiKey: string = DEFAULT_GALLERY_API_KEY;
  @StorageLink('galleryModel') galleryModel: string = DEFAULT_GALLERY_MODEL;
  @StorageLink('gallerySkipOcr') gallerySkipOcr: string = DEFAULT_GALLERY_SKIP_OCR;
  @StorageLink('galleryOcrConcurrency') galleryOcrConcurrency: string = DEFAULT_GALLERY_OCR_CONCURRENCY;
  @StorageLink('galleryModelConcurrency') galleryModelConcurrency: string = DEFAULT_GALLERY_MODEL_CONCURRENCY;
  @StorageLink('galleryEmbeddingConcurrency') galleryEmbeddingConcurrency: string = DEFAULT_GALLERY_EMBEDDING_CONCURRENCY;
  @StorageLink('galleryEmbeddingMode') galleryEmbeddingMode: string = DEFAULT_GALLERY_EMBEDDING_MODE;
  @StorageLink('galleryEmbeddingBaseUrl') galleryEmbeddingBaseUrl: string = DEFAULT_GALLERY_EMBEDDING_BASE_URL;
  @StorageLink('galleryEmbeddingApiKey') galleryEmbeddingApiKey: string = DEFAULT_GALLERY_EMBEDDING_API_KEY;
  @StorageLink('galleryEmbeddingModel') galleryEmbeddingModel: string = DEFAULT_GALLERY_EMBEDDING_MODEL;

  private filesDir: string = '';
  private cloudClient: CloudModelClient = new CloudModelClient();
  private pauseRequested: boolean = false;

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    this.ensureDefaultSettings();
    this.replaceResults(GalleryStorage.loadResults(this.filesDir));
    this.restoreLastRunFromResults();
    this.restoreScanSessionState();
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
      this.resultDisplayLimit = 120;
      this.progressText = '已选择 ' + uris.length + ' 张图片';
      this.lastRunText = '分析中';
      let analyzer = new GalleryAnalyzer(this.filesDir, this.cloudClient);
      let finalResults = await analyzer.analyzeUris(uris, this.buildAnalyzerConfig(), (next: GalleryProgress) => {
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
      this.lastRunText = this.formatDateTime(new Date().getTime());
      promptAction.showToast({ message: '图库分析完成', duration: 1500 });
    } catch (e) {
      this.analyzing = false;
      this.progressText = this.errorMessage(e);
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
      GalleryStorage.saveScanSession(this.filesDir, session);
      await this.runScanSession(session);
    } catch (e) {
      this.analyzing = false;
      this.autoScanStatus = 'failed';
      this.progressText = this.errorMessage(e);
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
      this.progressText = '自动分析完成';
      this.lastRunText = this.formatDateTime(new Date().getTime());
      return;
    }
    this.pauseRequested = false;
    this.analyzing = true;
    this.autoScanStatus = 'running';
    this.progress = session.total === 0 ? 0 : Math.floor(session.processed * 100 / session.total);
    this.selectedFilter = 0;
    this.selectedTimeFilter = 0;
    this.resultDisplayLimit = 120;
    this.lastRunText = '分析中';
    session.status = 'running';
    GalleryStorage.saveScanSession(this.filesDir, session);
    this.applyScanSession(session);

    let analyzer = new GalleryAnalyzer(this.filesDir, this.cloudClient);
    let finalResults = await analyzer.analyzeInputs(pendingInputs, this.buildAnalyzerConfig(), (next: GalleryProgress) => {
      this.updateProgress(next);
    }, (result: GalleryAnalysisResult) => {
      this.mergeResult(result);
    }, {
      shouldPause: (): boolean => this.pauseRequested,
      onItemDone: (input: GalleryPhotoInput, outcome: GalleryAnalyzeOutcome) => {
        this.markScanItem(session, input, outcome.cached, outcome.result.error);
        GalleryStorage.saveScanSession(this.filesDir, session);
        this.applyScanSession(session);
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
      this.progressText = '已暂停 · 待处理 ' + this.scanPending;
      this.lastRunText = '已暂停';
      promptAction.showToast({ message: '自动分析已暂停', duration: 1200 });
      return;
    }
    session.status = this.scanPending === 0 ? 'completed' : 'paused';
    GalleryStorage.saveScanSession(this.filesDir, session);
    this.applyScanSession(session);
    this.progress = session.total === 0 ? 100 : Math.floor(session.processed * 100 / session.total);
    this.progressText = this.scanPending === 0 ? '自动分析完成' : '已暂停 · 待处理 ' + this.scanPending;
    this.lastRunText = this.scanPending === 0 ? this.formatDateTime(new Date().getTime()) : '已暂停';
    promptAction.showToast({ message: this.scanPending === 0 ? '自动分析完成' : '自动分析已暂停', duration: 1500 });
  }

  private async ensureGalleryReadPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    let permissions: Permissions[] = ['ohos.permission.READ_IMAGEVIDEO'];
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
    nextResults.sort((left: GalleryAnalysisResult, right: GalleryAnalysisResult) => right.createdAt - left.createdAt);
    this.replaceResults(nextResults);
  }

  private replaceResults(nextResults: GalleryAnalysisResult[]): void {
    this.results = nextResults;
    this.resultRevision += 1;
  }

  private restoreLastRunFromResults(): void {
    if (this.results.length === 0) {
      this.lastRunText = '尚未开始';
      return;
    }
    let latest = 0;
    for (let i = 0; i < this.results.length; i++) {
      if (this.results[i].createdAt > latest) {
        latest = this.results[i].createdAt;
      }
    }
    this.lastRunText = latest > 0 ? this.formatDateTime(latest) : '尚未开始';
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
      if (session.items[i].status === 'queued') {
        inputs.push({
          uri: session.items[i].uri,
          id: session.items[i].id,
          date: session.items[i].date
        });
      }
    }
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
      if (session.items[i].status === 'done' || session.items[i].status === 'skipped' || session.items[i].status === 'failed') {
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
    if (this.scanPending > 0 && (session.status === 'paused' || session.status === 'pausing' || session.status === 'running')) {
      this.progressText = '可继续 · 待处理 ' + this.scanPending;
      this.lastRunText = '已暂停';
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
      this.replaceResults([]);
      this.progress = 0;
      this.selectedFilter = 0;
      this.selectedTimeFilter = 0;
      this.resultDisplayLimit = 120;
      this.scanTotal = 0;
      this.scanProcessed = 0;
      this.scanPending = 0;
      this.scanSkipped = 0;
      this.scanFailed = 0;
      this.autoScanStatus = 'idle';
      this.lastRunText = '尚未开始';
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
      return '全库分析中';
    }
    if (this.hasPausedScan()) {
      return '继续全库分析';
    }
    return '自动全库分析';
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

  @Builder ScanStatsPanel() {
    if (this.scanTotal > 0 || this.analyzing) {
      Column() {
        Row() {
          this.ScanStatCell('总数', this.scanTotal, '#151A28')
          this.ScanStatCell('已处理', this.scanProcessed, '#5B68FF')
          this.ScanStatCell('待处理', this.scanPending, '#FF8A3D')
          this.ScanStatCell('跳过', this.scanSkipped, '#39BFA3')
          this.ScanStatCell('失败', this.scanFailed, '#E5484D')
        }.width('100%')
        if (this.analyzing || this.hasPausedScan()) {
          Row() {
            if (this.analyzing) {
              Button(this.autoScanStatus === 'pausing' ? '暂停中' : '暂停')
                .height(36)
                .layoutWeight(1)
                .fontSize(12)
                .fontColor('#FF8A3D')
                .backgroundColor('#FFF3E8')
                .borderRadius(12)
                .enabled(this.autoScanStatus !== 'pausing')
                .onClick(() => { this.runAction(3); })
            } else {
              Button('继续')
                .height(36)
                .layoutWeight(1)
                .fontSize(12)
                .fontColor('#5B68FF')
                .backgroundColor('#EEF4FF')
                .borderRadius(12)
                .onClick(() => { this.runAction(0); })
            }
          }.width('100%').margin({ top: 12 })
        }
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
    if (fieldId === 5) {
      this.galleryEmbeddingBaseUrl = value;
      return;
    }
    if (fieldId === 6) {
      this.galleryEmbeddingApiKey = value;
      return;
    }
    this.galleryEmbeddingModel = value;
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
              this.ConcurrencyInput('OCR 并发请求数', this.galleryOcrConcurrency, '范围 1-6，默认 3', 6, 0)
              this.ConcurrencyInput('大模型并发请求数', this.galleryModelConcurrency, '范围 1-4，默认 2', 4, 1)
              this.SettingToggle('使用云端 Embedding API', '关闭时使用华为端侧 Embedding；开启时使用 SiliconFlow / bge-m3', this.galleryEmbeddingMode === 'remote', 4)
              this.SettingInput('Embedding Base URL', this.galleryEmbeddingBaseUrl, 'https://api.siliconflow.cn/v1', 5)
              this.SettingInput('Embedding API Key', this.galleryEmbeddingApiKey, 'SiliconFlow 服务密钥', 6)
              this.SettingInput('Embedding 模型', this.galleryEmbeddingModel, 'BAAI/bge-m3', 7)
              this.ConcurrencyInput('Embedding 并发请求数', this.galleryEmbeddingConcurrency, '范围 1-4，默认 2', 4, 2)
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
                this.galleryOcrConcurrency = DEFAULT_GALLERY_OCR_CONCURRENCY;
                this.galleryModelConcurrency = DEFAULT_GALLERY_MODEL_CONCURRENCY;
                this.galleryEmbeddingConcurrency = DEFAULT_GALLERY_EMBEDDING_CONCURRENCY;
                this.galleryEmbeddingMode = DEFAULT_GALLERY_EMBEDDING_MODE;
                this.galleryEmbeddingBaseUrl = DEFAULT_GALLERY_EMBEDDING_BASE_URL;
                this.galleryEmbeddingApiKey = DEFAULT_GALLERY_EMBEDDING_API_KEY;
                this.galleryEmbeddingModel = DEFAULT_GALLERY_EMBEDDING_MODEL;
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
        this.resultDisplayLimit = 120;
      })
  }

  @Builder InsightRow(item: GalleryAnalysisResult) {
    Row() {
      Image(this.previewUri(item)).width(62).height(62).objectFit(ImageFit.Cover).borderRadius(12)
      Column() {
        Row() {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#151A28').layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.category).fontSize(11).fontColor(this.categoryColor(item.category)).padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor('#F4F7FF').borderRadius(9)
        }.width('100%')
        Text(item.summary).fontSize(12).fontColor('#6F7584').margin({ top: 6 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(this.resultTime(item)).fontSize(11).fontColor('#7C8494').layoutWeight(1).maxLines(1)
          Text(this.resultStatus(item)).fontSize(11).fontColor('#9AA2B1').maxLines(1)
        }.width('100%').margin({ top: 5 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  private buildAnalyzerConfig(): GalleryAnalyzerConfig {
    return {
      apiBaseUrl: this.galleryApiBaseUrl.trim().length > 0 ? this.galleryApiBaseUrl.trim() : DEFAULT_GALLERY_API_BASE_URL,
      apiKey: this.galleryApiKey.trim().length > 0 ? this.galleryApiKey.trim() : DEFAULT_GALLERY_API_KEY,
      model: this.galleryModel.trim().length > 0 ? this.galleryModel.trim() : DEFAULT_GALLERY_MODEL,
      skipOcr: this.gallerySkipOcr === 'true',
      ocrConcurrency: parseInt(this.galleryOcrConcurrency),
      modelConcurrency: parseInt(this.galleryModelConcurrency),
      embeddingConcurrency: parseInt(this.galleryEmbeddingConcurrency),
      embeddingMode: this.galleryEmbeddingMode === 'remote' ? 'remote' : 'huawei_local',
      embeddingBaseUrl: this.galleryEmbeddingBaseUrl.trim().length > 0 ? this.galleryEmbeddingBaseUrl.trim() : DEFAULT_GALLERY_EMBEDDING_BASE_URL,
      embeddingApiKey: this.galleryEmbeddingApiKey.trim(),
      embeddingModel: this.galleryEmbeddingModel.trim().length > 0 ? this.galleryEmbeddingModel.trim() : DEFAULT_GALLERY_EMBEDDING_MODEL
    };
  }

  private updateProgress(next: GalleryProgress): void {
    let done = next.processed > 0 ? next.processed : next.modelDone + next.failed;
    this.progress = next.selected === 0 ? 0 : Math.floor(done * 100 / next.selected);
    this.progressText = next.current + ' · 已处理 ' + next.processed + '/' + next.selected +
      ' · 待处理 ' + next.pending +
      ' · 跳过 ' + next.skipped +
      ' · 失败 ' + next.failed;
  }

  private filteredResults(): GalleryAnalysisResult[] {
    if (this.selectedFilter === 0) {
      return this.results;
    }
    let target = this.filterCategory(this.selectedFilter);
    return this.results.filter((item: GalleryAnalysisResult) => this.matchCategory(item.category, target));
  }

  private filterCategory(index: number): string {
    if (index === 1) {
      return 'chat';
    }
    if (index === 2) {
      return 'document';
    }
    if (index === 3) {
      return 'food';
    }
    if (index === 4) {
      return 'shopping';
    }
    if (index === 5) {
      return 'travel';
    }
    if (index === 6) {
      return 'health';
    }
    if (index === 7) {
      return 'work';
    }
    return 'other';
  }

  private normalizeCategory(category: string): string {
    let value = category.trim().toLowerCase();
    if (value === '聊天') {
      return 'chat';
    }
    if (value === '文档') {
      return 'document';
    }
    if (value === '餐饮' || value === '美食') {
      return 'food';
    }
    if (value === '购物') {
      return 'shopping';
    }
    if (value === '出行' || value === '旅行') {
      return 'travel';
    }
    if (value === '健康') {
      return 'health';
    }
    if (value === '工作') {
      return 'work';
    }
    if (value === 'chat' || value === 'document' || value === 'food' || value === 'shopping' ||
      value === 'travel' || value === 'health' || value === 'work') {
      return value;
    }
    return 'other';
  }

  private matchCategory(category: string, target: string): boolean {
    return this.normalizeCategory(category) === target;
  }

  private visibleResults(): GalleryAnalysisResult[] {
    let categoryResults = this.filteredResults();
    if (this.selectedTimeFilter === 0) {
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
    return categoryResults.filter((item: GalleryAnalysisResult) => this.itemTime(item) >= startTs);
  }

  private displayedResults(items: GalleryAnalysisResult[]): GalleryAnalysisResult[] {
    if (items.length <= this.resultDisplayLimit) {
      return items;
    }
    return items.slice(0, this.resultDisplayLimit);
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
    if (value === 'food') {
      return '#39BFA3';
    }
    if (value === 'travel') {
      return '#4B8BFF';
    }
    if (value === 'shopping') {
      return '#FF8A3D';
    }
    if (value === 'health') {
      return '#765BFF';
    }
    return '#5B68FF';
  }

  private resultTime(item: GalleryAnalysisResult): string {
    let imageDate = item.date && item.date.length > 0 ? item.date : this.formatDate(item.createdAt);
    return imageDate + ' · 分析 ' + this.formatDateTime(item.createdAt);
  }

  private resultStatus(item: GalleryAnalysisResult): string {
    return item.embeddingStatus === 'ok' ? '已入库' : item.embeddingStatus;
  }

  private previewUri(item: GalleryAnalysisResult): string {
    if (item.thumbnailUri && item.thumbnailUri.length > 0) {
      return item.thumbnailUri;
    }
    return item.uri;
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
        this.resultDisplayLimit = 120;
      })
  }

  @Builder ResultsPanel(visibleItems: GalleryAnalysisResult[], revision: number) {
    Column() {
      Row() {
        Text('图库结果').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1)
        Text((this.displayedResults(visibleItems).length + revision - revision).toString() + '/' + visibleItems.length.toString()).fontSize(13).fontColor('#7F8592')
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
      .height(42)
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
      .height(40)
      .scrollable(ScrollDirection.Horizontal)
      .margin({ top: 6 })
      ForEach(this.displayedResults(visibleItems), (item: GalleryAnalysisResult, index: number) => {
        if (this.shouldShowDateHeader(this.displayedResults(visibleItems), index)) {
          Row() {
            Text(this.groupDate(item)).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#4C5260').layoutWeight(1)
          }
          .width('100%')
          .height(32)
          .margin({ top: index === 0 ? 4 : 10 })
        }
        this.InsightRow(item)
        Divider().color('#EEF0F5')
      }, (item: GalleryAnalysisResult) => item.id)
      if (visibleItems.length === 0) {
        Text(this.results.length === 0 ? '暂无图库分析结果' : '当前筛选无结果').fontSize(13).fontColor('#8B93A4').width('100%').textAlign(TextAlign.Center).margin({ top: 18, bottom: 10 })
      }
      if (visibleItems.length > this.resultDisplayLimit) {
        Button('加载更多')
          .height(40)
          .width('100%')
          .fontSize(13)
          .fontColor('#4F68FF')
          .backgroundColor('#EEF4FF')
          .borderRadius(12)
          .margin({ top: 12 })
          .onClick(() => { this.resultDisplayLimit += 120; })
      }
    }
    .width('86%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ top: 18 })
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
          Text('<')
            .fontSize(20)
            .fontColor('#4F68FF')
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .backgroundColor('#EEF4FF')
            .borderRadius(12)
            .onClick(() => { router.back(); })
          Column() {
            Text('图库采集').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#11182F').maxLines(1)
            Text('相册、截图与文档图片分析').fontSize(14).fontColor('#717684').margin({ top: 3 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })
          Text('⚙')
            .fontSize(18)
            .fontColor('#4F68FF')
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .backgroundColor('#EEF4FF')
            .borderRadius(12)
            .onClick(() => { this.settingsOpen = !this.settingsOpen; })
        }
        .width('86%')
        .margin({ top: 24 })

        Column() {
          Row() {
            this.StatCell('已分析', this.visibleCount(), '#5B68FF')
            Divider().vertical(true).height(42).color('#E7E9F0')
            this.StatCell('最近分析', this.lastRunText, '#151A28')
          }.width('100%')
          if (this.analyzing) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(6)
              .color('#5B68FF')
              .backgroundColor('#E8EDF8')
              .margin({ top: 16 })
            Text(this.progressText).fontSize(12).fontColor('#6F7584').margin({ top: 8 }).width('100%')
          }
          this.ScanStatsPanel()
        }
        .width('86%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 12 })

        Column() {
          Text('分析操作').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#11182F').width('100%')
          this.PrimaryActionButton()
          Row() {
            this.CompactActionButton(this.autoActionTitle(), '#5B68FF', 0)
            Blank().width(10)
            this.CompactActionButton('清理缓存', '#FF8A3D', 2)
          }.width('100%').margin({ top: 10 })
        }
        .width('86%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(18)
        .margin({ top: 18 })

        this.ResultsPanel(this.visibleResults(), this.resultRevision)

        Blank().height(100)
      }.width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F4F8FF')

      this.SettingsPanel()
    }
    .width('100%')
    .height('100%')
  }
}
