import fs from '@ohos.file.fs';
import { util, JSON as ArkJSON } from '@kit.ArkTS';
import { GalleryAnalysisResult, GalleryEmbeddingRecord, GalleryScanSession } from './GalleryTypes';

const GALLERY_LOG_DIR = 'gallery-log';
const DAILY_DIR = 'daily';
const ITEMS_DIR = 'items';
const EMBEDDINGS_DIR = 'embeddings';
const THUMBNAILS_DIR = 'thumbnails';
const SCAN_SESSION_FILE = 'scan-session.json';
const METADATA_START = '<!-- GALLERY_DAILY_METADATA';
const METADATA_END = '-->';

interface GalleryDailyMetadata {
  date: string;
  category: string;
  latest_entry_index: number;
  item_count: number;
}

export class GalleryStorage {
  static rootDir(filesDir: string): string {
    return filesDir + '/' + GALLERY_LOG_DIR;
  }

  static dailyRoot(filesDir: string): string {
    return GalleryStorage.rootDir(filesDir) + '/' + DAILY_DIR;
  }

  static itemRoot(filesDir: string): string {
    return GalleryStorage.rootDir(filesDir) + '/' + ITEMS_DIR;
  }

  static embeddingRoot(filesDir: string): string {
    return GalleryStorage.rootDir(filesDir) + '/' + EMBEDDINGS_DIR;
  }

  static thumbnailRoot(filesDir: string): string {
    return GalleryStorage.rootDir(filesDir) + '/' + THUMBNAILS_DIR;
  }

  static scanSessionPath(filesDir: string): string {
    return GalleryStorage.rootDir(filesDir) + '/' + SCAN_SESSION_FILE;
  }

  static itemPath(filesDir: string, result: GalleryAnalysisResult): string {
    return GalleryStorage.itemPathById(filesDir, result.date, result.id);
  }

  static embeddingPath(filesDir: string, record: GalleryEmbeddingRecord): string {
    return GalleryStorage.embeddingPathById(filesDir, record.date, record.id);
  }

  static embeddingRef(record: GalleryEmbeddingRecord): string {
    return GalleryStorage.embeddingRefById(record.date, record.id);
  }

  static embeddingRefById(date: string, id: string): string {
    return GALLERY_LOG_DIR + '/' + EMBEDDINGS_DIR + '/' + GalleryStorage.safeDate(date) + '/' + id + '.json';
  }

  static itemPathById(filesDir: string, date: string, id: string): string {
    return GalleryStorage.itemDateDir(filesDir, date) + '/' + id + '.json';
  }

  static embeddingPathById(filesDir: string, date: string, id: string): string {
    return GalleryStorage.embeddingDateDir(filesDir, date) + '/' + id + '.json';
  }

  static thumbnailPathById(filesDir: string, date: string, id: string): string {
    return GalleryStorage.thumbnailDateDir(filesDir, date) + '/' + id + '.jpg';
  }

  static hasResult(filesDir: string, date: string, id: string): boolean {
    try {
      return fs.accessSync(GalleryStorage.itemPathById(filesDir, date, id));
    } catch (e) {
      return false;
    }
  }

  static loadResult(filesDir: string, date: string, id: string): GalleryAnalysisResult | null {
    try {
      if (!GalleryStorage.hasResult(filesDir, date, id)) {
        return null;
      }
      return ArkJSON.parse(GalleryStorage.readText(GalleryStorage.itemPathById(filesDir, date, id))) as GalleryAnalysisResult;
    } catch (e) {
      return null;
    }
  }

  static ensureDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path);
      }
    } catch (e) {
      try {
        fs.mkdirSync(path);
      } catch (err) {
      }
    }
  }

  static ensureWorkspace(filesDir: string): void {
    GalleryStorage.ensureDirectory(GalleryStorage.rootDir(filesDir));
    GalleryStorage.ensureDirectory(GalleryStorage.dailyRoot(filesDir));
    GalleryStorage.ensureDirectory(GalleryStorage.itemRoot(filesDir));
    GalleryStorage.ensureDirectory(GalleryStorage.embeddingRoot(filesDir));
    GalleryStorage.ensureDirectory(GalleryStorage.thumbnailRoot(filesDir));
  }

  static readText(path: string): string {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      let textDecoder = util.TextDecoder.create('utf-8');
      return textDecoder.decodeWithStream(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  static writeText(path: string, content: string): void {
    let byteStr = util.TextEncoder.create('utf-8').encodeInto(content);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, byteStr.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  static writeBytes(path: string, data: ArrayBuffer): void {
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
  }

  static loadResults(filesDir: string): GalleryAnalysisResult[] {
    GalleryStorage.ensureWorkspace(filesDir);
    let results: GalleryAnalysisResult[] = [];
    GalleryStorage.collectItems(GalleryStorage.itemRoot(filesDir), results);
    results.sort((left: GalleryAnalysisResult, right: GalleryAnalysisResult) => right.createdAt - left.createdAt);
    return results;
  }

  static loadScanSession(filesDir: string): GalleryScanSession | null {
    GalleryStorage.ensureWorkspace(filesDir);
    let path = GalleryStorage.scanSessionPath(filesDir);
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      return ArkJSON.parse(GalleryStorage.readText(path)) as GalleryScanSession;
    } catch (e) {
      return null;
    }
  }

  static saveScanSession(filesDir: string, session: GalleryScanSession): void {
    GalleryStorage.ensureWorkspace(filesDir);
    session.updatedAt = new Date().getTime();
    GalleryStorage.writeText(GalleryStorage.scanSessionPath(filesDir), ArkJSON.stringify(session, null, 2));
  }

  static clearScanSession(filesDir: string): void {
    try {
      fs.unlinkSync(GalleryStorage.scanSessionPath(filesDir));
    } catch (e) {
    }
  }

  static upsertResult(filesDir: string, result: GalleryAnalysisResult): GalleryAnalysisResult[] {
    GalleryStorage.writeResult(filesDir, result);
    return GalleryStorage.loadResults(filesDir);
  }

  static writeResult(filesDir: string, result: GalleryAnalysisResult): GalleryAnalysisResult {
    GalleryStorage.ensureWorkspace(filesDir);
    let normalized = GalleryStorage.normalizeResult(result);
    GalleryStorage.ensureDirectory(GalleryStorage.itemDateDir(filesDir, normalized.date));
    GalleryStorage.writeText(GalleryStorage.itemPath(filesDir, normalized), ArkJSON.stringify(normalized, null, 2));
    return normalized;
  }

  static upsertEmbedding(filesDir: string, record: GalleryEmbeddingRecord): void {
    GalleryStorage.ensureWorkspace(filesDir);
    let normalized: GalleryEmbeddingRecord = {
      id: record.id,
      uri: record.uri,
      date: GalleryStorage.safeDate(record.date),
      category: GalleryStorage.safeCategory(record.category),
      text: record.text,
      vector: record.vector,
      model: record.model,
      mode: record.mode,
      createdAt: record.createdAt
    };
    GalleryStorage.ensureDirectory(GalleryStorage.embeddingDateDir(filesDir, normalized.date));
    GalleryStorage.writeText(GalleryStorage.embeddingPath(filesDir, normalized), ArkJSON.stringify(normalized, null, 2));
  }

  static clear(filesDir: string): void {
    GalleryStorage.deletePathRecursively(GalleryStorage.rootDir(filesDir));
    GalleryStorage.ensureWorkspace(filesDir);
  }

  static rebuildDaily(filesDir: string, date: string): void {
    GalleryStorage.ensureWorkspace(filesDir);
    let safeDate = GalleryStorage.safeDate(date);
    let results = GalleryStorage.loadResultsForDate(filesDir, safeDate);
    results.sort((left: GalleryAnalysisResult, right: GalleryAnalysisResult) => {
      return left.createdAt - right.createdAt;
    });

    let dailyDir = GalleryStorage.dailyDateDir(filesDir, safeDate);
    GalleryStorage.deletePathRecursively(dailyDir);
    GalleryStorage.ensureDirectory(dailyDir);
    let categories = GalleryStorage.categoryOrder();
    for (let c = 0; c < categories.length; c++) {
      let category = categories[c];
      let group = results.filter((item: GalleryAnalysisResult) => GalleryStorage.safeCategory(item.category) === category);
      if (group.length === 0) {
        continue;
      }
      let metadata: GalleryDailyMetadata = {
        date: safeDate,
        category: category,
        latest_entry_index: group.length,
        item_count: group.length
      };
      let lines: string[] = [
        METADATA_START,
        ArkJSON.stringify(metadata, null, 2),
        METADATA_END,
        '',
        '# ' + safeDate + ' / ' + category,
        ''
      ];
      for (let j = 0; j < group.length; j++) {
        lines.push((j + 1).toString() + '. [' + group[j].id + '] ' +
          GalleryStorage.dailyInlineText(group[j].title) + ': ' +
          GalleryStorage.dailyInlineText(group[j].summary));
        lines.push('');
      }
      GalleryStorage.writeText(GalleryStorage.dailyCategoryPath(filesDir, safeDate, category), lines.join('\n'));
    }
  }

  static rebuildDailyForDates(filesDir: string, dates: string[]): void {
    let seen: Record<string, boolean> = {};
    for (let i = 0; i < dates.length; i++) {
      let date = GalleryStorage.safeDate(dates[i]);
      if (seen[date]) {
        continue;
      }
      seen[date] = true;
      GalleryStorage.rebuildDaily(filesDir, date);
    }
  }

  static formatDate(ts: number): string {
    let date = new Date(ts);
    let y = date.getFullYear();
    let m = (date.getMonth() + 1).toString().padStart(2, '0');
    let d = date.getDate().toString().padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  private static normalizeResult(result: GalleryAnalysisResult): GalleryAnalysisResult {
    let createdAt = result.createdAt > 0 ? result.createdAt : new Date().getTime();
    let category = GalleryStorage.safeCategory(result.category);
    let date = result.date && result.date.length > 0 ? GalleryStorage.safeDate(result.date) : GalleryStorage.formatDate(createdAt);
    return {
      id: result.id,
      uri: result.uri,
      thumbnailUri: result.thumbnailUri ? result.thumbnailUri : '',
      title: result.title,
      category: category,
      summary: result.summary,
      tags: result.tags ? result.tags : [],
      ocrText: result.ocrText,
      rawModelText: result.rawModelText,
      keywords: result.keywords ? result.keywords : [],
      date: date,
      embeddingRef: result.embeddingRef,
      embeddingStatus: result.embeddingStatus,
      embeddingDimension: result.embeddingDimension,
      error: result.error,
      createdAt: createdAt
    };
  }

  private static collectItems(dir: string, results: GalleryAnalysisResult[]): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      let names = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        let path = dir + '/' + names[i];
        GalleryStorage.collectItems(path, results);
      }
    } catch (e) {
      if (dir.endsWith('.json')) {
        try {
          results.push(ArkJSON.parse(GalleryStorage.readText(dir)) as GalleryAnalysisResult);
        } catch (err) {
        }
      }
    }
  }

  private static itemDateDir(filesDir: string, date: string): string {
    return GalleryStorage.itemRoot(filesDir) + '/' + GalleryStorage.safeDate(date);
  }

  private static embeddingDateDir(filesDir: string, date: string): string {
    return GalleryStorage.embeddingRoot(filesDir) + '/' + GalleryStorage.safeDate(date);
  }

  private static thumbnailDateDir(filesDir: string, date: string): string {
    return GalleryStorage.thumbnailRoot(filesDir) + '/' + GalleryStorage.safeDate(date);
  }

  private static dailyDateDir(filesDir: string, date: string): string {
    return GalleryStorage.dailyRoot(filesDir) + '/' + GalleryStorage.safeDate(date);
  }

  private static dailyCategoryPath(filesDir: string, date: string, category: string): string {
    return GalleryStorage.dailyDateDir(filesDir, date) + '/' + GalleryStorage.safeCategory(category) + '.md';
  }

  private static loadResultsForDate(filesDir: string, date: string): GalleryAnalysisResult[] {
    let results: GalleryAnalysisResult[] = [];
    GalleryStorage.collectItems(GalleryStorage.itemDateDir(filesDir, date), results);
    return results;
  }

  private static safeDate(date: string): string {
    return date.replace(/[\\/:*?"<>|]+/g, '_');
  }

  private static safeCategory(category: string): string {
    let value = category.trim().toLowerCase();
    if (value === 'chat' || value === 'food' || value === 'shopping' || value === 'travel' ||
      value === 'health' || value === 'document' || value === 'work') {
      return value;
    }
    return 'other';
  }

  private static categoryOrder(): string[] {
    return ['chat', 'food', 'shopping', 'travel', 'health', 'document', 'work', 'other'];
  }

  private static dailyInlineText(value: string): string {
    return value.replace(/[\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
  }

  private static deletePathRecursively(path: string): number {
    let deleted = 0;
    try {
      if (!fs.accessSync(path)) {
        return 0;
      }
      let names = fs.listFileSync(path);
      for (let i = 0; i < names.length; i++) {
        deleted += GalleryStorage.deletePathRecursively(path + '/' + names[i]);
      }
      fs.rmdirSync(path);
      return deleted + 1;
    } catch (e) {
      try {
        fs.unlinkSync(path);
        return deleted + 1;
      } catch (err) {
        return deleted;
      }
    }
  }
}
