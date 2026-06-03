import { JSON as ArkJSON } from '@kit.ArkTS';
import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { dataManagerInfo, dataManagerWarn } from './DataManagerLog';
import {
  AggregatedRecord,
  CandidateFact,
  ConsolidatedMetadata,
  ConsolidatedState,
  DataManagerModelConfig,
  DataManagerProgressCallback,
  DedupDecision,
  SourceEntry,
  JsonMap,
  StringMap,
  createDataManagerProgress,
  createJsonMap,
  createStringMap
} from './DataManagerTypes';
import {
  createNewRecord,
  findExactExistingMatch,
  monthKeyFromDate,
  normalizeDedupText,
  normalizeFreeText,
  nowIsoLocal,
  parseDailyLogDocument,
  parseNumberedEntries,
  RECENT_MATCH_DAYS,
  RECENT_MATCH_MAX_RECORDS,
  renderConsolidatedMarkdown,
  selectRecentScopeRecords,
  sourceRef,
  stableUnique,
  stableUniqueNumbers,
  updateExistingRecord,
  workflowSceneIdFromMetadata
} from './DataManagerUtils';

export interface ConsolidationResult {
  sourceEntries: number;
  outputFiles: number;
  totalRecords: number;
  updatedAt: string;
}

interface EntryGroup {
  month: string;
  fileName: string;
  entries: SourceEntry[];
}

export class ConsolidationService {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;
  private modelClient: DataPipelineModelClient;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage, modelClient: DataPipelineModelClient) {
    this.paths = paths;
    this.storage = storage;
    this.modelClient = modelClient;
  }

  async consolidateAll(modelConfig: DataManagerModelConfig, dedupWindow: number = 5, progress?: DataManagerProgressCallback): Promise<ConsolidationResult> {
    this.paths.ensureBaseDirs();
    this.emitProgress(progress, '扫描日志', '正在扫描 daily-log', 0, 100, 5);
    dataManagerInfo(`Consolidation start: dailyRoot=${this.paths.dailyLogRoot}, dedupWindow=${dedupWindow}, modelEnabled=${modelConfig.enabled}`);
    let entries = this.collectSourceEntries();
    let groups = this.groupEntriesByMonth(entries);
    this.emitProgress(progress, '扫描日志', `发现 ${entries.length} 条 daily-log`, 1, 100, 10);
    dataManagerInfo(`Consolidation collected: entries=${entries.length}, groups=${groups.length}`);
    if (entries.length === 0) {
      dataManagerWarn('Consolidation found no daily-log entries. Check fixture import path and file format.');
    }
    let totalRecords = 0;
    let outputFiles = 0;
    let groupIndex = 0;
    for (let group of groups) {
      let basePercent = 10 + Math.round(groupIndex * 45 / Math.max(1, groups.length));
      this.emitProgress(progress, '整理日志', `整理 ${group.fileName}`, groupIndex, groups.length, basePercent);
      dataManagerInfo(`Consolidation group start: month=${group.month}, file=${group.fileName}, entries=${group.entries.length}`);
      let result = await this.consolidateGroup(group, modelConfig, dedupWindow, progress, basePercent, 10 + Math.round((groupIndex + 1) * 45 / Math.max(1, groups.length)));
      dataManagerInfo(`Consolidation group done: month=${group.month}, file=${group.fileName}, records=${result.records.length}`);
      totalRecords += result.records.length;
      outputFiles++;
      groupIndex++;
    }
    this.emitProgress(progress, '整理日志', `整理完成，生成 ${totalRecords} 条记录`, 100, 100, 58);
    return {
      sourceEntries: entries.length,
      outputFiles: outputFiles,
      totalRecords: totalRecords,
      updatedAt: nowIsoLocal()
    };
  }

  private collectSourceEntries(): SourceEntry[] {
    let entries: SourceEntry[] = [];
    let dayDirs = this.storage.listDir(this.paths.dailyLogRoot)
      .filter((name: string) => /^\d{4}-\d{2}-\d{2}$/.test(name));
    dataManagerInfo(`Consolidation daily dirs: count=${dayDirs.length}, names=${dayDirs.slice(0, 8).join(',')}`);
    for (let day of dayDirs) {
      let dayDir = this.storage.join(this.paths.dailyLogRoot, day);
      let files = this.storage.listDir(dayDir).filter((name: string) => name.endsWith('.md'));
      dataManagerInfo(`Consolidation day scan: day=${day}, mdFiles=${files.length}`);
      for (let fileName of files) {
        let path = this.storage.join(dayDir, fileName);
        let content = this.storage.readText(path, '');
        if (content.length === 0) {
          continue;
        }
        let document = parseDailyLogDocument(content);
        let body = normalizeFreeText(document.body);
        let rawBody = document.body;
        let numberedEntries = parseNumberedEntries(rawBody);
        for (let item of numberedEntries) {
          let index = Number(item.index);
          let text = normalizeFreeText(item.text);
          if (text.length === 0 || isNaN(index)) {
            continue;
          }
          let metadata: JsonMap = document.workflow_metadata || createJsonMap();
          entries.push({
            source_date: day,
            file_name: fileName,
            entry_index: index,
            entry_text: text,
            workflow_metadata: metadata,
            workflow_scene_id: workflowSceneIdFromMetadata(metadata),
            source_ref: sourceRef(day, fileName, index)
          });
        }
      }
    }
    entries.sort((left: SourceEntry, right: SourceEntry) => {
      return `${left.source_date}/${left.file_name}#${left.entry_index}`.localeCompare(`${right.source_date}/${right.file_name}#${right.entry_index}`);
    });
    return entries;
  }

  private groupEntriesByMonth(entries: SourceEntry[]): EntryGroup[] {
    let groups: Record<string, EntryGroup> = {};
    for (let entry of entries) {
      let month = monthKeyFromDate(entry.source_date);
      if (month.length === 0) {
        continue;
      }
      let key = month + '\n' + entry.file_name;
      if (!groups[key]) {
        let entryGroup: EntryGroup = {
          month: month,
          fileName: entry.file_name,
          entries: []
        };
        groups[key] = entryGroup;
      }
      groups[key].entries.push(entry);
    }
    return Object.keys(groups).sort().map((key: string) => groups[key]);
  }

  private async consolidateGroup(group: EntryGroup, modelConfig: DataManagerModelConfig, dedupWindow: number, progress?: DataManagerProgressCallback, startPercent: number = 12, endPercent: number = 55): Promise<ConsolidatedState> {
    let statePath = this.paths.outputStatePath(group.month, group.fileName);
    let markdownPath = this.paths.outputMarkdownPath(group.month, group.fileName);
    let state = this.readConsolidatedState(statePath);
    let records = state.records;
    let nextRecordId = this.nextRecordId(records);
    let pendingEntries = this.pendingEntries(group.entries, state);
    if (pendingEntries.length === 0) {
      this.emitProgress(progress, '整理日志', `跳过 ${group.fileName}`, group.entries.length, group.entries.length, endPercent);
      dataManagerInfo(`Consolidation group skipped: month=${group.month}, file=${group.fileName}, entries=${group.entries.length}`);
      return state;
    }
    this.emitProgress(progress, '拆分事实', `批量拆分 ${pendingEntries.length} 条日志`, 0, pendingEntries.length, startPercent);
    let factsBySource = await this.modelClient.splitEntriesIntoFacts(pendingEntries, modelConfig);
    let totalFacts = 0;
    pendingEntries.forEach((entry: SourceEntry) => {
      totalFacts += (factsBySource[entry.source_ref] || []).length;
    });
    let processedFacts = 0;
    for (let entry of pendingEntries) {
      let facts = factsBySource[entry.source_ref] || [];
      for (let fact of facts) {
        processedFacts++;
        let percent = startPercent + Math.round((endPercent - startPercent) * processedFacts / Math.max(1, totalFacts));
        this.emitProgress(progress, '语义去重', `整理 ${group.fileName} (${processedFacts}/${Math.max(1, totalFacts)})`, processedFacts, Math.max(1, totalFacts), percent);
        let scopedRecords = selectRecentScopeRecords(records, fact);
        let exactMatch = findExactExistingMatch(scopedRecords, fact);
        if (exactMatch !== null) {
          let exactDecision: DedupDecision = {
            decision: 'duplicate',
            matched_record_ids: [exactMatch.record_id],
            reason: 'exact_existing_match',
            merged_summary: '',
            merged_fact: '',
            merged_tags: []
          };
          updateExistingRecord(exactMatch, fact, exactDecision);
          continue;
        }
        let decision = await this.modelClient.decideDedup(fact, scopedRecords, modelConfig, dedupWindow);
        let matchedRecord = this.findMatchedRecord(records, decision);
        let decisionText = normalizeFreeText(decision.decision);
        if ((decisionText === 'duplicate' || decisionText === 'merge_with_existing') && matchedRecord !== null) {
          updateExistingRecord(matchedRecord, fact, decision);
        } else if (decisionText === 'skip_ambiguous') {
          continue;
        } else {
          records.push(createNewRecord(nextRecordId, fact, decision));
          nextRecordId++;
        }
      }
    }
    records.sort((left: AggregatedRecord, right: AggregatedRecord) => {
      if (left.first_seen_date !== right.first_seen_date) {
        return left.first_seen_date.localeCompare(right.first_seen_date);
      }
      return left.record_id - right.record_id;
    });
    let metadata = this.buildMetadata(group, records, dedupWindow);
    let nextState: ConsolidatedState = {
      metadata: metadata,
      records: records
    };
    this.storage.writeJsonAtomic(statePath, nextState as Object);
    this.storage.writeTextAtomic(markdownPath, renderConsolidatedMarkdown(records));
    return nextState;
  }

  private emitProgress(progress: DataManagerProgressCallback | undefined, stage: string, message: string, current: number, total: number, percent: number): void {
    if (!progress) {
      return;
    }
    progress(createDataManagerProgress(stage, message, current, total, percent));
  }

  private readConsolidatedState(statePath: string): ConsolidatedState {
    let empty: ConsolidatedState = {
      metadata: this.emptyMetadata('', [], 5),
      records: []
    };
    let payload = this.storage.readJson<ConsolidatedState>(statePath, empty);
    if (!payload || !Array.isArray(payload.records)) {
      return empty;
    }
    let records: AggregatedRecord[] = [];
    for (let item of payload.records) {
      if (!item || typeof item !== 'object') {
        continue;
      }
      item.dedup_text = normalizeDedupText(item.dedup_text || item.normalized_fact || '');
      item.source_refs = Array.isArray(item.source_refs) ? item.source_refs : [];
      item.source_dates = Array.isArray(item.source_dates) ? item.source_dates : [];
      item.workflow_scene_ids = Array.isArray(item.workflow_scene_ids) ? stableUniqueNumbers(item.workflow_scene_ids) : [];
      item.raw_excerpts = Array.isArray(item.raw_excerpts) ? item.raw_excerpts : [];
      item.tags = Array.isArray(item.tags) ? item.tags : [];
      item.model_notes = Array.isArray(item.model_notes) ? item.model_notes : [];
      records.push(item);
    }
    return {
      metadata: this.normalizeMetadata(payload.metadata || empty.metadata),
      records: records
    };
  }

  private normalizeMetadata(metadata: ConsolidatedMetadata): ConsolidatedMetadata {
    if (!metadata.processed_entry_hashes) {
      metadata.processed_entry_hashes = createStringMap();
    }
    return metadata;
  }

  private pendingEntries(entries: SourceEntry[], state: ConsolidatedState): SourceEntry[] {
    let processedByHash = state.metadata.processed_entry_hashes || createStringMap();
    let processedRefs: Record<string, boolean> = new Object() as Record<string, boolean>;
    state.records.forEach((record: AggregatedRecord) => {
      (record.source_refs || []).forEach((ref: string) => processedRefs[ref] = true);
    });
    return entries.filter((entry: SourceEntry) => {
      let currentHash = this.storage.sha256Text(entry.entry_text);
      let previousHash = processedByHash[entry.source_ref] || '';
      if (previousHash.length > 0) {
        return previousHash !== currentHash;
      }
      return processedRefs[entry.source_ref] !== true;
    });
  }

  private nextRecordId(records: AggregatedRecord[]): number {
    let maxId = 0;
    for (let record of records) {
      if (record.record_id > maxId) {
        maxId = record.record_id;
      }
    }
    return maxId + 1;
  }

  private findMatchedRecord(records: AggregatedRecord[], decision: DedupDecision): AggregatedRecord | null {
    let ids = decision.matched_record_ids;
    if (ids.length === 0) {
      return null;
    }
    let id = Number(ids[0]);
    if (isNaN(id)) {
      return null;
    }
    for (let record of records) {
      if (record.record_id === id) {
        return record;
      }
    }
    return null;
  }

  private buildMetadata(group: EntryGroup, records: AggregatedRecord[], dedupWindow: number): ConsolidatedMetadata {
    let dates = stableUnique(group.entries.map((entry: SourceEntry) => entry.source_date)).sort();
    let dateRange: StringMap = createStringMap();
    dateRange['start_date'] = dates.length > 0 ? dates[0] : '';
    dateRange['end_date'] = dates.length > 0 ? dates[dates.length - 1] : '';
    let entryHashes: StringMap = createStringMap();
    group.entries.forEach((entry: SourceEntry) => {
      entryHashes[entry.source_ref] = this.storage.sha256Text(entry.entry_text);
    });
    let metadata: ConsolidatedMetadata = {
      source_date_range: dateRange,
      source_files: [group.fileName],
      processed_entry_hashes: entryHashes,
      latest_record_index: this.nextRecordId(records) - 1,
      dedup_window_size: dedupWindow,
      updated_at: nowIsoLocal(),
      total_records: records.length,
      month: group.month,
      recent_match_days: RECENT_MATCH_DAYS,
      recent_match_max_records: RECENT_MATCH_MAX_RECORDS
    };
    return metadata;
  }

  private emptyMetadata(month: string, sourceFiles: string[], dedupWindow: number): ConsolidatedMetadata {
    let dateRange: StringMap = createStringMap();
    let metadata: ConsolidatedMetadata = {
      source_date_range: dateRange,
      source_files: sourceFiles,
      processed_entry_hashes: createStringMap(),
      latest_record_index: 0,
      dedup_window_size: dedupWindow,
      updated_at: '',
      total_records: 0,
      month: month,
      recent_match_days: RECENT_MATCH_DAYS,
      recent_match_max_records: RECENT_MATCH_MAX_RECORDS
    };
    return metadata;
  }
}

