import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util, JSON as ArkJSON } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CloudModelClient, GalleryCloudModelConfig } from '../CloudModelClient';
import { GalleryOcrService } from './GalleryOcrService';
import { GalleryEmbeddingService } from './GalleryEmbeddingService';
import { GalleryStorage } from './GalleryStorage';
import {
  GalleryAnalysisResult,
  GalleryAnalyzeOptions,
  GalleryAnalyzeOutcome,
  GalleryAnalyzerConfig,
  GalleryEmbeddingRecord,
  GalleryModelJson,
  GalleryPhotoInput,
  GalleryProgress,
  GalleryProgressHandler
} from './GalleryTypes';

const GALLERY_LOG_DOMAIN = 0x0000;
const GALLERY_LOG_TAG = 'Gallery';

class GallerySemaphore {
  private permits: number;
  private waiters: Array<() => void> = [];

  constructor(permits: number) {
    this.permits = Math.max(1, permits);
  }

  async acquire(): Promise<void> {
    if (this.permits > 0) {
      this.permits -= 1;
      return;
    }
    await new Promise<void>((resolve) => {
      this.waiters.push(resolve);
    });
  }

  release(): void {
    let next = this.waiters.shift();
    if (next) {
      next();
      return;
    }
    this.permits += 1;
  }
}

interface GalleryStageGates {
  ocr: GallerySemaphore;
  model: GallerySemaphore;
  embedding: GallerySemaphore;
}

export class GalleryAnalyzer {
  private filesDir: string;
  private cloudClient: CloudModelClient;
  private ocrService: GalleryOcrService = new GalleryOcrService();
  private embeddingService: GalleryEmbeddingService;

  constructor(filesDir: string, cloudClient: CloudModelClient) {
    this.filesDir = filesDir;
    this.cloudClient = cloudClient;
    this.embeddingService = new GalleryEmbeddingService(cloudClient);
  }

  async analyzeUris(uris: string[], config: GalleryAnalyzerConfig, onProgress: GalleryProgressHandler,
    onResult?: (result: GalleryAnalysisResult) => void, options?: GalleryAnalyzeOptions): Promise<GalleryAnalysisResult[]> {
    let inputs: GalleryPhotoInput[] = [];
    for (let i = 0; i < uris.length; i++) {
      inputs.push({ uri: uris[i] });
    }
    return this.analyzeInputs(inputs, config, onProgress, onResult, options);
  }

  async analyzeInputs(inputs: GalleryPhotoInput[], config: GalleryAnalyzerConfig, onProgress: GalleryProgressHandler,
    onResult?: (result: GalleryAnalysisResult) => void, options?: GalleryAnalyzeOptions): Promise<GalleryAnalysisResult[]> {
    this.logInfo('batch start selected=' + inputs.length +
      ' skipOcr=' + config.skipOcr +
      ' ocrConcurrency=' + config.ocrConcurrency +
      ' modelConcurrency=' + config.modelConcurrency +
      ' embeddingConcurrency=' + config.embeddingConcurrency +
      ' embeddingMode=' + config.embeddingMode);
    let batchStartedAt = new Date().getTime();
    let progress: GalleryProgress = {
      selected: inputs.length,
      processed: 0,
      skipped: 0,
      pending: inputs.length,
      ocrDone: 0,
      modelDone: 0,
      embeddingDone: 0,
      failed: 0,
      current: '准备分析'
    };
    onProgress(progress);
    let results: GalleryAnalysisResult[] = [];
    let dirtyDates: string[] = [];
    let gates: GalleryStageGates = {
      ocr: new GallerySemaphore(config.ocrConcurrency),
      model: new GallerySemaphore(config.modelConcurrency),
      embedding: new GallerySemaphore(config.embeddingConcurrency)
    };
    let limit = Math.max(1, config.ocrConcurrency, config.modelConcurrency, config.embeddingConcurrency);
    await this.runWithLimit(inputs, limit, async (input: GalleryPhotoInput, index: number): Promise<boolean> => {
      if (options && options.shouldPause && options.shouldPause()) {
        return false;
      }
      progress.current = '分析第 ' + (index + 1) + '/' + inputs.length + ' 张';
      onProgress(progress);
      let outcome = await this.analyzeOne(input, config, gates, progress, onProgress);
      let result = outcome.result;
      results.push(result);
      progress.processed += 1;
      progress.pending = Math.max(0, progress.selected - progress.processed);
      if (outcome.cached) {
        progress.skipped += 1;
      }
      onProgress(progress);
      if (outcome.cached) {
        if (options && options.onItemDone) {
          options.onItemDone(input, outcome);
        }
        if (onResult) {
          onResult(result);
        }
        return true;
      }
      this.logInfo('cache result start id=' + result.id);
      let cacheStartedAt = new Date().getTime();
      let normalized = GalleryStorage.writeResult(this.filesDir, result);
      this.pushUnique(dirtyDates, normalized.date);
      this.logInfo('cache result done id=' + result.id + ' elapsedMs=' + this.elapsed(cacheStartedAt));
      if (options && options.onItemDone) {
        options.onItemDone(input, {
          result: normalized,
          cached: false
        });
      }
      if (onResult) {
        onResult(normalized);
      }
      return true;
    });
    let dailyStartedAt = new Date().getTime();
    GalleryStorage.rebuildDailyForDates(this.filesDir, dirtyDates);
    this.logInfo('daily rebuild done dates=' + dirtyDates.length + ' elapsedMs=' + this.elapsed(dailyStartedAt));
    await this.ocrService.release();
    this.logInfo('batch done selected=' + inputs.length +
      ' results=' + results.length +
      ' failed=' + progress.failed +
      ' elapsedMs=' + this.elapsed(batchStartedAt));
    return GalleryStorage.loadResults(this.filesDir);
  }

  private async runWithLimit(items: GalleryPhotoInput[], limit: number, worker: (item: GalleryPhotoInput, index: number) => Promise<boolean>): Promise<void> {
    let nextIndex = 0;
    let workers: Promise<void>[] = [];
    let count = Math.min(limit, items.length);
    for (let i = 0; i < count; i++) {
      workers.push((async () => {
        while (nextIndex < items.length) {
          let index = nextIndex;
          nextIndex += 1;
          let keepGoing = await worker(items[index], index);
          if (!keepGoing) {
            return;
          }
        }
      })());
    }
    await Promise.all(workers);
  }

  private async analyzeOne(input: GalleryPhotoInput, config: GalleryAnalyzerConfig, gates: GalleryStageGates, progress: GalleryProgress,
    onProgress: GalleryProgressHandler): Promise<GalleryAnalyzeOutcome> {
    let uri = input.uri;
    let id = this.stableId(uri);
    let inputId = input.id;
    if (inputId !== undefined && inputId.length > 0) {
      id = inputId;
    }
    let pixelMap: image.PixelMap | null = null;
    let imageSource: image.ImageSource | null = null;
    let imageFile: fileIo.File | null = null;
    let itemStartedAt = new Date().getTime();
    let date = this.resolveImageDate(uri, itemStartedAt);
    let inputDate = input.date;
    if (inputDate !== undefined && inputDate.length > 0) {
      date = inputDate;
    }
    this.logInfo('item start id=' + id + ' uri=' + uri);
    let cached = GalleryStorage.loadResult(this.filesDir, date, id);
    if (cached) {
      if (!cached.thumbnailUri || cached.thumbnailUri.length === 0) {
        cached.thumbnailUri = await this.ensureThumbnail(uri, date, id);
        if (cached.thumbnailUri.length > 0) {
          GalleryStorage.writeResult(this.filesDir, cached);
        }
      }
      progress.ocrDone += 1;
      progress.modelDone += 1;
      progress.embeddingDone += 1;
      onProgress(progress);
      this.logInfo('item skipped cached id=' + id + ' date=' + date + ' path=' + GalleryStorage.itemPathById(this.filesDir, date, id));
      return {
        result: cached,
        cached: true
      };
    }
    try {
      let decodeStartedAt = new Date().getTime();
      this.logInfo('decode start id=' + id);
      imageFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(imageFile.fd);
      pixelMap = await imageSource.createPixelMap();
      this.logInfo('decode done id=' + id + ' elapsedMs=' + this.elapsed(decodeStartedAt));
      let thumbnailUri = await this.writeThumbnail(pixelMap, date, id);

      await gates.ocr.acquire();
      let ocrText = '';
      try {
        if (!config.skipOcr) {
          let ocrStartedAt = new Date().getTime();
          this.logInfo('ocr start id=' + id);
          ocrText = await this.ocrService.recognize(pixelMap);
          this.logInfo('ocr done id=' + id + ' chars=' + ocrText.length + ' elapsedMs=' + this.elapsed(ocrStartedAt));
        } else {
          this.logInfo('ocr skipped id=' + id);
        }
      } finally {
        gates.ocr.release();
      }
      progress.ocrDone += 1;
      onProgress(progress);

      let packStartedAt = new Date().getTime();
      this.logInfo('pack image start id=' + id);
      let imageBase64 = await this.pixelMapToJpegBase64(pixelMap);
      this.logInfo('pack image done id=' + id + ' base64Chars=' + imageBase64.length + ' elapsedMs=' + this.elapsed(packStartedAt));
      await gates.model.acquire();
      let rawModelText = '';
      try {
        let modelStartedAt = new Date().getTime();
        this.logInfo('model start id=' + id + ' baseUrl=' + config.apiBaseUrl + ' model=' + config.model);
        rawModelText = await this.cloudClient.analyzeGalleryImage(imageBase64, ocrText, this.toCloudConfig(config));
        this.logInfo('model done id=' + id + ' chars=' + rawModelText.length + ' elapsedMs=' + this.elapsed(modelStartedAt));
      } finally {
        gates.model.release();
      }
      progress.modelDone += 1;
      onProgress(progress);

      let modelJson = this.parseModelJson(rawModelText);
      let category = this.nonEmpty(modelJson.category, 'other');
      let tags = modelJson.tags ? modelJson.tags : [];
      let keywords = this.keywordsFrom(tags, ocrText);
      let resultText = this.resultText(modelJson, ocrText);
      let embeddingStatus = 'skipped';
      let embeddingDimension = 0;
      let embeddingRef = '';
      if (resultText.length > 0) {
        await gates.embedding.acquire();
        try {
          let embeddingStartedAt = new Date().getTime();
          this.logInfo('embedding start id=' + id + ' mode=' + config.embeddingMode + ' model=' +
            (config.embeddingMode === 'huawei_local' ? 'huawei_local_basic' : config.embeddingModel));
          let vector = await this.embeddingService.embedText(resultText, config, this.filesDir);
          embeddingDimension = vector.length;
          embeddingStatus = 'ok';
          this.logInfo('embedding done id=' + id + ' dimension=' + embeddingDimension + ' elapsedMs=' + this.elapsed(embeddingStartedAt));
          let embedding: GalleryEmbeddingRecord = {
            id: id,
            uri: uri,
            date: date,
            category: category,
            text: resultText,
            vector: vector,
            model: config.embeddingMode === 'huawei_local' ? 'huawei_local_basic' : config.embeddingModel,
            mode: config.embeddingMode,
            createdAt: new Date().getTime()
          };
          GalleryStorage.upsertEmbedding(this.filesDir, embedding);
          embeddingRef = GalleryStorage.embeddingRef(embedding);
        } catch (e) {
          embeddingStatus = 'failed: ' + this.errorMessage(e);
          this.logError('embedding failed id=' + id + ' error=' + this.errorMessage(e));
        } finally {
          gates.embedding.release();
        }
      } else {
        this.logInfo('embedding skipped id=' + id + ' emptyText=true');
      }
      progress.embeddingDone += 1;
      onProgress(progress);

      let result: GalleryAnalysisResult = {
        id: id,
        uri: uri,
        thumbnailUri: thumbnailUri,
        title: this.nonEmpty(modelJson.title, '图库图片'),
        category: category,
        summary: this.nonEmpty(modelJson.summary, ocrText.length > 0 ? ocrText.substring(0, Math.min(80, ocrText.length)) : '未识别到明确文本'),
        tags: tags,
        ocrText: ocrText,
        rawModelText: rawModelText,
        keywords: keywords,
        date: date,
        embeddingRef: embeddingRef,
        embeddingStatus: embeddingStatus,
        embeddingDimension: embeddingDimension,
        error: '',
        createdAt: new Date().getTime()
      };
      this.logInfo('item done id=' + id + ' elapsedMs=' + this.elapsed(itemStartedAt));
      return {
        result: result,
        cached: false
      };
    } catch (e) {
      progress.failed += 1;
      onProgress(progress);
      this.logError('item failed id=' + id + ' elapsedMs=' + this.elapsed(itemStartedAt) + ' error=' + this.errorMessage(e));
      let result: GalleryAnalysisResult = {
        id: id,
        uri: uri,
        thumbnailUri: pixelMap ? await this.writeThumbnail(pixelMap, date, id) : '',
        title: '分析失败',
        category: 'other',
        summary: this.errorMessage(e),
        tags: [],
        ocrText: '',
        rawModelText: '',
        keywords: [],
        date: date,
        embeddingRef: '',
        embeddingStatus: 'skipped',
        embeddingDimension: 0,
        error: this.errorMessage(e),
        createdAt: new Date().getTime()
      };
      return {
        result: result,
        cached: false
      };
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (imageSource) {
        try {
          await imageSource.release();
        } catch (e) {
        }
      }
      if (imageFile) {
        try {
          await fileIo.close(imageFile);
        } catch (e) {
        }
      }
    }
  }

  private toCloudConfig(config: GalleryAnalyzerConfig): GalleryCloudModelConfig {
    return {
      baseUrl: config.apiBaseUrl,
      apiKey: config.apiKey,
      model: config.model
    };
  }

  private async pixelMapToJpegBase64(pixelMap: image.PixelMap): Promise<string> {
    let packer = image.createImagePacker();
    try {
      let data = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 85
      });
      let helper = new util.Base64Helper();
      return helper.encodeToStringSync(new Uint8Array(data));
    } finally {
      try {
        await packer.release();
      } catch (e) {
      }
    }
  }

  private async writeThumbnail(pixelMap: image.PixelMap, date: string, id: string): Promise<string> {
    let packer = image.createImagePacker();
    try {
      let data = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 72
      });
      let path = GalleryStorage.thumbnailPathById(this.filesDir, date, id);
      let dir = path.substring(0, path.lastIndexOf('/'));
      GalleryStorage.ensureDirectory(dir);
      GalleryStorage.writeBytes(path, data);
      return path;
    } catch (e) {
      this.logError('thumbnail failed id=' + id + ' error=' + this.errorMessage(e));
      return '';
    } finally {
      try {
        await packer.release();
      } catch (e) {
      }
    }
  }

  private async ensureThumbnail(uri: string, date: string, id: string): Promise<string> {
    let imageFile: fileIo.File | null = null;
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      imageFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(imageFile.fd);
      pixelMap = await imageSource.createPixelMap();
      return await this.writeThumbnail(pixelMap, date, id);
    } catch (e) {
      this.logError('cached thumbnail failed id=' + id + ' error=' + this.errorMessage(e));
      return '';
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (e) {
        }
      }
      if (imageSource) {
        try {
          await imageSource.release();
        } catch (e) {
        }
      }
      if (imageFile) {
        try {
          await fileIo.close(imageFile);
        } catch (e) {
        }
      }
    }
  }

  private parseModelJson(raw: string): GalleryModelJson {
    let text = raw.trim();
    if (text.startsWith('```')) {
      let first = text.indexOf('\n');
      let last = text.lastIndexOf('```');
      if (first >= 0 && last > first) {
        text = text.substring(first + 1, last).trim();
      }
    }
    let start = text.indexOf('{');
    let end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }
    try {
      return ArkJSON.parse(text) as GalleryModelJson;
    } catch (e) {
      return {
        title: '图库图片',
        category: 'other',
        summary: raw.length > 140 ? raw.substring(0, 140) : raw,
        tags: []
      };
    }
  }

  private resultText(modelJson: GalleryModelJson, ocrText: string): string {
    let parts: string[] = [];
    if (modelJson.title && modelJson.title.length > 0) {
      parts.push(modelJson.title);
    }
    if (modelJson.category && modelJson.category.length > 0) {
      parts.push(modelJson.category);
    }
    if (modelJson.summary && modelJson.summary.length > 0) {
      parts.push(modelJson.summary);
    }
    if (ocrText.length > 0) {
      parts.push(ocrText);
    }
    return parts.join('\n');
  }

  private resolveImageDate(uri: string, fallbackTs: number): string {
    if (uri.length === 0) {
      return GalleryStorage.formatDate(fallbackTs);
    }
    return GalleryStorage.formatDate(fallbackTs);
  }

  private keywordsFrom(tags: string[], ocrText: string): string[] {
    let result: string[] = [];
    for (let i = 0; i < tags.length; i++) {
      this.pushUnique(result, tags[i]);
    }
    let normalized = ocrText.replace(/[，。！？、；：,.!?;:\n\r\t]+/g, ' ');
    let pieces = normalized.split(' ');
    for (let j = 0; j < pieces.length && result.length < 12; j++) {
      let value = pieces[j].trim();
      if (value.length >= 2 && value.length <= 16) {
        this.pushUnique(result, value);
      }
    }
    return result;
  }

  private pushUnique(items: string[], value: string): void {
    let normalized = value.trim();
    if (normalized.length === 0) {
      return;
    }
    for (let i = 0; i < items.length; i++) {
      if (items[i] === normalized) {
        return;
      }
    }
    items.push(normalized);
  }

  private stableId(uri: string): string {
    let hash = 0;
    for (let i = 0; i < uri.length; i++) {
      hash = ((hash << 5) - hash) + uri.charCodeAt(i);
      hash = hash & hash;
    }
    return 'gallery_' + Math.abs(hash).toString();
  }

  private nonEmpty(value: string | undefined, fallback: string): string {
    if (value && value.trim().length > 0) {
      return value.trim();
    }
    return fallback;
  }

  private errorMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }

  private elapsed(startedAt: number): number {
    return new Date().getTime() - startedAt;
  }

  private logInfo(message: string): void {
    hilog.info(GALLERY_LOG_DOMAIN, GALLERY_LOG_TAG, '%{public}s', message);
  }

  private logError(message: string): void {
    hilog.error(GALLERY_LOG_DOMAIN, GALLERY_LOG_TAG, '%{public}s', message);
  }
}
