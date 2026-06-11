import { DataManagerStorage } from '../../datamanager/DataManagerStorage';
import { stringifyJsonCompat } from '../JsonCompat';

const WORKFLOWS_DIR: string = 'workflows';
const WECHAT_COLLECTION_DIR: string = 'wechat-collection';
const RUNS_DIR: string = 'runs';
const DAILY_LOG_DIR: string = 'daily-log';
const WECHAT_AUTO_SUMMARY_DAILY_PREFIX: string = 'com.tencent.mm__wechat_auto_summary__';

interface WechatAutoSummaryDailyMetadata {
  task_scene_id: number;
  source_app: string;
  collector: string;
  run_id: string;
  mode: string;
  days: number;
}

interface WechatAutoSummaryDailyMetadataEnvelope {
  workflow_metadata: WechatAutoSummaryDailyMetadata;
  latest_entry_index: number;
}

export function wechatAutoSummaryRunDir(filesDir: string, runId: string): string {
  let storage = new DataManagerStorage();
  return storage.join(filesDir, WORKFLOWS_DIR, WECHAT_COLLECTION_DIR, RUNS_DIR, runId);
}

export function renderWechatAutoSummaryDailyLog(runId: string, mode: string, days: number,
  entries: string[]): string {
  let metadata: WechatAutoSummaryDailyMetadata = {
    task_scene_id: 3,
    source_app: 'wechat',
    collector: 'wechat_auto_summary',
    run_id: runId,
    mode: mode,
    days: days
  };
  let envelope: WechatAutoSummaryDailyMetadataEnvelope = {
    workflow_metadata: metadata,
    latest_entry_index: entries.length
  };
  let lines: string[] = [
    '<!-- DAILY_LOG_METADATA',
    stringifyJsonCompat(envelope as Object, 2),
    '-->',
    ''
  ];
  for (let i = 0; i < entries.length; i++) {
    lines.push((i + 1).toString() + '. ' + entries[i]);
    lines.push('');
  }
  return lines.join('\n');
}

export class WechatAutoSummaryStorage {
  private filesDir: string;
  private storage: DataManagerStorage;

  constructor(filesDir: string) {
    this.filesDir = filesDir;
    this.storage = new DataManagerStorage();
  }

  // 原始采集产物按 runId 聚合，便于后续回看同一次微信采集的 dump、截图索引和服务端摘要。
  writeRawArtifact(runId: string, name: string, content: string): string {
    let path = this.storage.join(wechatAutoSummaryRunDir(this.filesDir, runId), name);
    this.storage.writeTextAtomic(path, content);
    return path;
  }

  // daily-log 使用 DataManager 既有目录结构，写入后可被后续归档和索引流程统一消费。
  writeDailyLog(runId: string, mode: string, days: number, dateKey: string, entries: string[]): string {
    let fileName = WECHAT_AUTO_SUMMARY_DAILY_PREFIX + runId + '.md';
    let path = this.storage.join(this.filesDir, WORKFLOWS_DIR, DAILY_LOG_DIR, dateKey, fileName);
    this.storage.writeTextAtomic(path, renderWechatAutoSummaryDailyLog(runId, mode, days, entries));
    return path;
  }
}
