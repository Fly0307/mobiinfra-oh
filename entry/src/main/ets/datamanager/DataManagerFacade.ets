import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { ConsolidationService } from './ConsolidationService';
import { IndexService } from './IndexService';
import { CollectionGroupingBuildResult, CollectionGroupingService, collectionTabSpecByIndex, heuristicCollectionGroups } from './CollectionGroupingService';
import { dataManagerInfo } from './DataManagerLog';
import {
  CollectionEventViewModel,
  CollectionGroupState,
  CollectionGroupViewModel,
  CollectionInsightViewModel,
  CollectionRowViewModel,
  CollectionViewModel,
  ConsolidatedState,
  DataManagerModelConfig,
  DOMAIN_DISPLAY_NAMES,
  DOMAIN_KEYS,
  DATA_MANAGER_CLEAR_REQUEST_FILE_NAME,
  HomeDomainViewModel,
  HomeProfileViewModel,
  HomeRecommendationViewModel,
  IndexedEvent,
  ProfileClaim,
  ProfileDomainState,
  ProfileState,
  RefreshSummary,
  DataManagerProgressCallback,
  NumberMap,
  StringMap,
  createDataManagerProgress,
  createStringMap
} from './DataManagerTypes';
import {
  displayDomainName,
  normalizeFreeText,
  nowIsoLocal,
  parseDailyLogDocument,
  parseNumberedEntries,
  sourceAppDisplayName,
  sourceDisplayName,
  stableUnique,
  summarizeText
} from './DataManagerUtils';

interface DailyLogSnapshotFile {
  path: string;
  sha256: string;
  entry_count: number;
}

interface DailyLogSnapshot {
  generated_at: string;
  root: string;
  file_count: number;
  entry_count: number;
  tree_hash: string;
  files: DailyLogSnapshotFile[];
}

const DAILY_LOG_SNAPSHOT_FILE_NAME: string = 'daily-log-snapshot.json';

export function createEmptyHomeProfileViewModel(): HomeProfileViewModel {
  return {
    updatedLabel: '暂无画像',
    completeness: 0,
    totalEvents: 0,
    domains: defaultHomeDomains(),
    recommendations: defaultRecommendations(),
    empty: true
  };
}

export function createEmptyCollectionViewModels(): CollectionViewModel[] {
  return [0, 1, 2, 3].map((index: number) => emptyCollectionViewModel(index));
}

function defaultHomeDomains(): HomeDomainViewModel[] {
  let eat: HomeDomainViewModel = { domain: 'eat', icon: 'Eat', title: '吃', desc: '等待整理', color: '#39C2A2', eventCount: 0 };
  let wear: HomeDomainViewModel = { domain: 'wear', icon: 'Wear', title: '穿', desc: '等待整理', color: '#7669FF', eventCount: 0 };
  let live: HomeDomainViewModel = { domain: 'live', icon: 'Live', title: '住', desc: '等待整理', color: '#FF963D', eventCount: 0 };
  let travel: HomeDomainViewModel = { domain: 'travel', icon: 'Go', title: '行', desc: '等待整理', color: '#4B9BFF', eventCount: 0 };
  return [eat, wear, live, travel];
}

function defaultRecommendations(): HomeRecommendationViewModel[] {
  let eat: HomeRecommendationViewModel = { id: 'empty-eat', domain: 'eat', tag: '画像待更新', title: '导入 daily-log 后生成画像', desc: '同步后展示真实偏好', meta: '0 条证据', color: '#39C2A2' };
  let travel: HomeRecommendationViewModel = { id: 'empty-travel', domain: 'travel', tag: '采集待整理', title: '采集记录会在这里汇总', desc: '按吃穿住行生成推荐', meta: '本地索引', color: '#4B9BFF' };
  let work: HomeRecommendationViewModel = { id: 'empty-work', domain: 'work', tag: '隐私本地', title: '数据保存在应用内部空间', desc: '导入导出不依赖绝对路径', meta: 'workflows', color: '#8066FF' };
  return [eat, travel, work];
}

function emptyCollectionViewModel(index: number): CollectionViewModel {
  let title = ['最近聊天', '最近订单', '最近通知', '娱乐记录'][index] || '采集记录';
  return {
    title: title,
    countLabel: '0 条',
    lastUpdatedLabel: '暂无同步',
    groups: [],
    rows: [],
    insights: defaultInsights(),
    insightSummary: '导入 daily-log 后，这里会展示已整理的中层采集数据。',
    empty: true
  };
}

function defaultInsights(): CollectionInsightViewModel[] {
  let eat: CollectionInsightViewModel = { color: '#8066FF', name: '吃', value: '0%', widthValue: '0%' };
  let travel: CollectionInsightViewModel = { color: '#5B8DFF', name: '行', value: '0%', widthValue: '0%' };
  let live: CollectionInsightViewModel = { color: '#FFB14B', name: '住', value: '0%', widthValue: '0%' };
  let work: CollectionInsightViewModel = { color: '#42C995', name: '办公', value: '0%', widthValue: '0%' };
  return [eat, travel, live, work];
}

export class DataManagerFacade {
  readonly storage: DataManagerStorage;
  readonly paths: DataManagerPaths;
  private modelClient: DataPipelineModelClient;
  private consolidationService: ConsolidationService;
  private indexService: IndexService;
  private collectionGroupingService: CollectionGroupingService;

  constructor(filesDir: string) {
    this.storage = new DataManagerStorage();
    this.paths = new DataManagerPaths(filesDir, this.storage);
    this.modelClient = new DataPipelineModelClient();
    this.consolidationService = new ConsolidationService(this.paths, this.storage, this.modelClient);
    this.indexService = new IndexService(this.paths, this.storage, this.modelClient);
    this.collectionGroupingService = new CollectionGroupingService(this.paths, this.storage, this.modelClient, this.indexService);
  }

  ensureReady(): void {
    this.paths.ensureBaseDirs();
    this.applyPendingClearRequest();
    dataManagerInfo('DataManagerFacade ensureReady: root=' + this.paths.rootDir);
  }

  hasDailyLogData(): boolean {
    this.ensureReady();
    let files = this.storage.findFiles(this.paths.dailyLogRoot, '.md');
    for (let path of files) {
      let content = this.storage.readText(path, '');
      let document = parseDailyLogDocument(content);
      if (parseNumberedEntries(document.body).length > 0) {
        return true;
      }
    }
    return false;
  }

  private applyPendingClearRequest(): void {
    let markerPath = this.storage.join(this.paths.rootDir, DATA_MANAGER_CLEAR_REQUEST_FILE_NAME);
    if (!this.storage.exists(markerPath)) {
      return;
    }
    dataManagerInfo('DataManagerFacade clear request detected: ' + markerPath);
    this.storage.removeFile(markerPath);
    this.storage.removeTree(this.paths.dailyLogRoot);
    this.storage.removeTree(this.paths.consolidationRoot);
    this.storage.removeTree(this.paths.workflowRunsRoot);
    this.paths.ensureBaseDirs();
    dataManagerInfo('DataManagerFacade clear request applied');
  }

  async refresh(modelConfig: DataManagerModelConfig, progress?: DataManagerProgressCallback, groupingModelConfig?: DataManagerModelConfig): Promise<RefreshSummary> {
    this.ensureReady();
    let groupingConfig = groupingModelConfig ? groupingModelConfig : modelConfig;
    this.emitProgress(progress, '准备', '正在准备数据目录', 0, 100, 2);
    dataManagerInfo(`DataManagerFacade refresh start: modelEnabled=${modelConfig.enabled}, groupingModelEnabled=${groupingConfig.enabled}, dailyRoot=${this.paths.dailyLogRoot}`);
    let currentSnapshot = this.buildDailyLogSnapshot();
    let previousSnapshot = this.loadDailyLogSnapshot();
    if (this.canSkipRefresh(previousSnapshot, currentSnapshot)) {
      this.emitProgress(progress, '索引', '正在更新采集分组', 96, 100, 96);
      let groups = await this.collectionGroupingService.buildAll(groupingConfig, progress);
      this.writeDailyLogSnapshot(currentSnapshot);
      let skipped = this.skippedRefreshSummary(currentSnapshot);
      dataManagerInfo(`DataManagerFacade refresh skipped: daily-log unchanged, treeHash=${currentSnapshot.tree_hash}, events=${skipped.eventCount}, collectionGroups=${groups.groupCount}, groupDocsUpdated=${groups.updatedGroupDocs}`);
      this.emitProgress(progress, '完成', 'daily-log 无新增', 100, 100, 100);
      return skipped;
    }
    let consolidation = await this.consolidationService.consolidateAll(modelConfig, 5, progress);
    this.emitProgress(progress, '索引', '开始构建索引', 0, 100, 60);
    dataManagerInfo(`DataManagerFacade consolidation done: sourceEntries=${consolidation.sourceEntries}, outputFiles=${consolidation.outputFiles}, totalRecords=${consolidation.totalRecords}`);
    let index = await this.indexService.build(modelConfig, progress);
    dataManagerInfo(`DataManagerFacade index done: sourceFiles=${index.sourceFiles}, eventCount=${index.eventCount}, profileClaimCount=${index.profileClaimCount}`);
    this.emitProgress(progress, '索引', '正在生成采集分组', 96, 100, 96);
    let collectionGroups = await this.collectionGroupingService.buildAll(groupingConfig, progress);
    dataManagerInfo(`DataManagerFacade collection groups done: tabs=${collectionGroups.tabCount}, groups=${collectionGroups.groupCount}, events=${collectionGroups.eventCount}, reused=${collectionGroups.reusedGroupDocs}, updated=${collectionGroups.updatedGroupDocs}`);
    this.writeDailyLogSnapshot(currentSnapshot);
    this.emitProgress(progress, '完成', `生成 ${index.eventCount} 条索引事件`, 100, 100, 100);
    return {
      dailyEntryCount: consolidation.sourceEntries,
      consolidatedRecordCount: consolidation.totalRecords,
      eventCount: index.eventCount,
      profileClaimCount: index.profileClaimCount,
      updatedAt: index.updatedAt,
      message: `整理 ${consolidation.sourceEntries} 条 daily-log，生成 ${index.eventCount} 条索引事件`,
      skipped: false
    };
  }

  async regroup(modelConfig: DataManagerModelConfig, progress?: DataManagerProgressCallback): Promise<string> {
    this.ensureReady();
    this.emitProgress(progress, '索引', '正在清空采集分组', 0, 100, 94);
    this.collectionGroupingService.clearPersistedGroups();
    this.emitProgress(progress, '索引', '正在重新生成采集分组', 0, 100, 96);
    let result: CollectionGroupingBuildResult = await this.collectionGroupingService.buildAll(modelConfig, progress, true);
    this.emitProgress(progress, '完成', '采集分组已重建', 100, 100, 100);
    return `重建 ${result.groupCount} 个采集分组，覆盖 ${result.eventCount} 条记录`;
  }

  private emitProgress(progress: DataManagerProgressCallback | undefined, stage: string, message: string, current: number, total: number, percent: number): void {
    if (!progress) {
      return;
    }
    progress(createDataManagerProgress(stage, message, current, total, percent));
  }

  private dailyLogSnapshotPath(): string {
    return this.storage.join(this.paths.indexesRoot, DAILY_LOG_SNAPSHOT_FILE_NAME);
  }

  private emptyDailyLogSnapshot(): DailyLogSnapshot {
    return {
      generated_at: '',
      root: 'workflows/daily-log',
      file_count: 0,
      entry_count: 0,
      tree_hash: '',
      files: []
    };
  }

  private buildDailyLogSnapshot(): DailyLogSnapshot {
    let files: DailyLogSnapshotFile[] = [];
    this.storage.findFiles(this.paths.dailyLogRoot, '.md').forEach((path: string) => {
      let relative = this.storage.relativePath(this.paths.dailyLogRoot, path).replace(/\\/g, '/');
      let content = this.storage.readText(path, '');
      let document = parseDailyLogDocument(content);
      let entryCount = parseNumberedEntries(document.body).length;
      files.push({
        path: relative,
        sha256: this.storage.sha256Text(content),
        entry_count: entryCount
      });
    });
    files.sort((left: DailyLogSnapshotFile, right: DailyLogSnapshotFile) => left.path.localeCompare(right.path));
    let fingerprint = files.map((file: DailyLogSnapshotFile) => {
      return [file.path, file.sha256, String(file.entry_count)].join('\u001f');
    }).join('\u001e');
    let snapshot: DailyLogSnapshot = {
      generated_at: nowIsoLocal(),
      root: 'workflows/daily-log',
      file_count: files.length,
      entry_count: files.reduce((total: number, file: DailyLogSnapshotFile) => total + file.entry_count, 0),
      tree_hash: this.storage.sha256Text(fingerprint),
      files: files
    };
    return snapshot;
  }

  private loadDailyLogSnapshot(): DailyLogSnapshot {
    let snapshot = this.storage.readJson<DailyLogSnapshot>(this.dailyLogSnapshotPath(), this.emptyDailyLogSnapshot());
    if (!snapshot || !Array.isArray(snapshot.files)) {
      return this.emptyDailyLogSnapshot();
    }
    return snapshot;
  }

  private writeDailyLogSnapshot(snapshot: DailyLogSnapshot): void {
    this.storage.writeJsonAtomic(this.dailyLogSnapshotPath(), snapshot as Object);
  }

  private canSkipRefresh(previous: DailyLogSnapshot, current: DailyLogSnapshot): boolean {
    if (previous.tree_hash.length === 0 || previous.tree_hash !== current.tree_hash) {
      return false;
    }
    if (previous.file_count !== current.file_count || previous.entry_count !== current.entry_count) {
      return false;
    }
    return this.hasGeneratedDataForSnapshot(current);
  }

  private hasGeneratedDataForSnapshot(snapshot: DailyLogSnapshot): boolean {
    if (snapshot.entry_count === 0) {
      return false;
    }
    let profile = this.indexService.loadProfileState();
    let eventCount = Object.keys(this.indexService.loadEvents()).length;
    return eventCount > 0 && profile.event_count > 0;
  }

  private skippedRefreshSummary(snapshot: DailyLogSnapshot): RefreshSummary {
    let profile = this.indexService.loadProfileState();
    let events = this.indexService.loadEvents();
    return {
      dailyEntryCount: snapshot.entry_count,
      consolidatedRecordCount: this.countConsolidatedRecords(),
      eventCount: Object.keys(events).length,
      profileClaimCount: profile.claim_count,
      updatedAt: snapshot.generated_at,
      message: '无新增日志，跳过同步',
      skipped: true
    };
  }

  private countConsolidatedRecords(): number {
    let total = 0;
    this.storage.findFiles(this.paths.outputsRoot, '.md.state.json').forEach((path: string) => {
      let state = this.storage.readJson<ConsolidatedState>(path, {
        metadata: {
          source_date_range: createStringMap(),
          source_files: [],
          processed_entry_hashes: createStringMap(),
          latest_record_index: 0,
          dedup_window_size: 0,
          updated_at: '',
          total_records: 0,
          month: '',
          recent_match_days: 7,
          recent_match_max_records: 100
        },
        records: []
      });
      total += Array.isArray(state.records) ? state.records.length : 0;
    });
    return total;
  }

  loadHomeViewModel(): HomeProfileViewModel {
    let profile = this.indexService.loadProfileState();
    if (!profile || profile.event_count === 0) {
      return createEmptyHomeProfileViewModel();
    }
    let domains = defaultHomeDomains().map((item: HomeDomainViewModel) => {
      let doc = profile.domains[item.domain];
      let domain: HomeDomainViewModel = {
        domain: item.domain,
        icon: item.icon,
        title: item.title,
        desc: this.domainDescription(doc),
        color: item.color,
        eventCount: doc ? doc.event_count : 0
      };
      return domain;
    });
    let recommendations = this.profileRecommendations(profile);
    return {
      updatedLabel: this.lastSyncLabel([]),
      completeness: this.profileCompleteness(profile),
      totalEvents: profile.event_count,
      domains: domains,
      recommendations: recommendations.length > 0 ? recommendations : defaultRecommendations(),
      empty: false
    };
  }

  loadCollectionViewModels(): CollectionViewModel[] {
    return [0, 1, 2, 3].map((index: number) => this.loadCollectionViewModel(index));
  }

  loadCollectionViewModel(tabIndex: number): CollectionViewModel {
    let spec = collectionTabSpecByIndex(tabIndex);
    let result = this.indexService.query(spec.query);
    return this.collectionViewModelFromQueryResult(tabIndex, result.events, result.total_events);
  }

  loadCollectionGroupViewModel(tabIndex: number, groupId: string): CollectionGroupViewModel | null {
    let targetGroupId = normalizeFreeText(groupId);
    if (targetGroupId.length === 0) {
      return null;
    }
    let document = this.collectionGroupingService.loadGroupsDocument(tabIndex);
    for (let group of document.groups) {
      if (group.group_id === targetGroupId) {
        let eventMap = this.indexService.loadEventsByIds(group.event_ids || []);
        let view = this.collectionGroupView(group, eventMap);
        return view.events.length > 0 ? view : null;
      }
    }
    let viewModel = this.loadCollectionViewModel(tabIndex);
    for (let group of viewModel.groups) {
      if (group.id === targetGroupId) {
        return group;
      }
    }
    return null;
  }

  private collectionViewModelFromQueryResult(tabIndex: number, events: IndexedEvent[], totalEvents: number): CollectionViewModel {
    let spec = collectionTabSpecByIndex(tabIndex);
    let document = this.collectionGroupingService.loadGroupsDocument(tabIndex);
    let groupStates = document.groups.length > 0 ? document.groups : heuristicCollectionGroups(spec.tabId, spec.title, events);
    let eventMap = this.eventMapFromEvents(events);
    let groups = groupStates
      .map((group: CollectionGroupState): CollectionGroupViewModel => this.collectionGroupView(group, eventMap))
      .filter((group: CollectionGroupViewModel) => group.events.length > 0);
    if (groups.length === 0 && events.length > 0) {
      groups = heuristicCollectionGroups(spec.tabId, spec.title, events)
        .map((group: CollectionGroupState): CollectionGroupViewModel => this.collectionGroupView(group, eventMap))
        .filter((group: CollectionGroupViewModel) => group.events.length > 0);
    }
    let rows: CollectionRowViewModel[] = [];
    groups.forEach((group: CollectionGroupViewModel) => {
      group.events.forEach((event: CollectionEventViewModel) => {
        rows.push({
          id: event.id,
          title: event.summary,
          source: event.source,
          time: event.time,
          meta: event.meta,
          status: event.status,
          domain: event.domain
        });
      });
    });
    return {
      title: spec.title,
      countLabel: `${totalEvents} 条`,
      lastUpdatedLabel: this.lastSyncLabel(events),
      groups: groups,
      rows: rows,
      insights: this.collectionInsights(events),
      insightSummary: this.collectionInsightSummary(events, groups),
      empty: totalEvents === 0
    };
  }

  private collectionEventView(event: IndexedEvent): CollectionEventViewModel {
    let primaryDomain = event.domains.length > 0 ? event.domains[0] : 'other';
    let fullText = normalizeFreeText(event.normalized_fact || event.summary);
    let summary = normalizeFreeText(event.summary || event.normalized_fact);
    let row: CollectionEventViewModel = {
      id: event.event_id,
      summary: summary,
      fullText: fullText.length > 0 ? fullText : summary,
      source: event.sources.length > 0 ? event.sources.join('、') : sourceDisplayName(event.source_state_file),
      time: event.event_date,
      meta: this.eventMeta(event),
      status: '已整理',
      domain: primaryDomain
    };
    return row;
  }

  private eventMapFromEvents(events: IndexedEvent[]): Record<string, IndexedEvent> {
    let eventMap: Record<string, IndexedEvent> = new Object() as Record<string, IndexedEvent>;
    events.forEach((event: IndexedEvent) => eventMap[event.event_id] = event);
    return eventMap;
  }

  private collectionGroupView(group: CollectionGroupState, eventMap: Record<string, IndexedEvent>): CollectionGroupViewModel {
    let events: CollectionEventViewModel[] = [];
    group.event_ids.forEach((eventId: string) => {
      let event = eventMap[eventId];
      if (!event) {
        return;
      }
      events.push(this.collectionEventView(event));
    });
    let view: CollectionGroupViewModel = {
      id: group.group_id,
      title: group.title,
      source: this.collectionGroupAppSource(group, eventMap),
      time: group.time,
      meta: group.meta.length > 0 ? group.meta : `${events.length} 条`,
      status: group.status.length > 0 ? group.status : '已整理',
      domain: group.domain,
      eventCount: events.length,
      events: events
    };
    return view;
  }

  private collectionGroupAppSource(group: CollectionGroupState, eventMap: Record<string, IndexedEvent>): string {
    let appSources: string[] = [];
    (group.event_ids || []).forEach((eventId: string) => {
      let event = eventMap[eventId];
      if (event) {
        appSources.push(sourceAppDisplayName(event.source_state_file));
      }
    });
    let unique = stableUnique(appSources);
    return unique.length > 0 ? unique.join('、') : group.source;
  }

  private eventMeta(event: IndexedEvent): string {
    if (event.entities.length > 0) {
      return event.entities[0].split(':').slice(1).join(':');
    }
    if (event.keywords.length > 0) {
      return event.keywords.slice(0, 2).join('、');
    }
    return displayDomainName(event.domains.length > 0 ? event.domains[0] : 'other');
  }

  private latestEventLabel(events: IndexedEvent[]): string {
    if (events.length === 0) {
      return '暂无同步';
    }
    let latest = events[0].event_date;
    for (let event of events) {
      if (event.event_date > latest) {
        latest = event.event_date;
      }
    }
    return latest;
  }

  private lastSyncLabel(events: IndexedEvent[]): string {
    let snapshot = this.loadDailyLogSnapshot();
    if (normalizeFreeText(snapshot.generated_at).length > 0) {
      return this.formatHomeUpdatedLabel(snapshot.generated_at);
    }
    let profile = this.indexService.loadProfileState();
    if (normalizeFreeText(profile.generated_at).length > 0) {
      return this.formatHomeUpdatedLabel(profile.generated_at);
    }
    return this.latestEventLabel(events);
  }

  private collectionInsights(events: IndexedEvent[]): CollectionInsightViewModel[] {
    if (events.length === 0) {
      return defaultInsights();
    }
    let colors: StringMap = createStringMap();
    colors['eat'] = '#8066FF';
    colors['travel'] = '#5B8DFF';
    colors['live'] = '#FFB14B';
    colors['work'] = '#42C995';
    colors['wear'] = '#FF6B96';
    colors['other'] = '#8B93A4';
    let counts: NumberMap = {};
    events.forEach((event: IndexedEvent) => {
      let domains = event.domains.length > 0 ? event.domains : ['other'];
      domains.forEach((domain: string) => {
        counts[domain] = (counts[domain] || 0) + 1;
      });
    });
    return Object.keys(counts).sort((a: string, b: string) => counts[b] - counts[a]).slice(0, 4).map((domain: string) => {
      let percent = Math.round(counts[domain] * 100 / Math.max(1, events.length));
      let insight: CollectionInsightViewModel = {
        color: colors[domain] || '#8B93A4',
        name: DOMAIN_DISPLAY_NAMES[domain] || domain,
        value: `${percent}%`,
        widthValue: `${Math.max(8, percent)}%`
      };
      return insight;
    });
  }

  private collectionInsightSummary(events: IndexedEvent[], groups: CollectionGroupViewModel[]): string {
    if (events.length === 0) {
      return '暂无可展示的采集数据。';
    }
    if (groups.length > 0) {
      return `已整理 ${groups.length} 个分组，覆盖 ${events.length} 条记录。`;
    }
    let latest = events[0];
    return `最近整理了 ${events.length} 条记录，最新来自 ${latest.sources.join('、') || '本地日志'}。`;
  }

  private domainDescription(doc: ProfileDomainState | undefined): string {
    if (!doc || doc.event_count === 0) {
      return '暂无数据';
    }
    if (doc.summary.length > 0) {
      return summarizeText(doc.summary, 18);
    }
    if (doc.claims.length > 0) {
      return summarizeText(doc.claims[0].statement, 8);
    }
    return '暂无数据';
  }

  private formatHomeUpdatedLabel(value: string): string {
    let normalized = normalizeFreeText(value);
    if (normalized.length === 0) {
      return '已生成画像';
    }
    let date = this.parseLocalDate(normalized);
    if (isNaN(date.getTime())) {
      return normalized.length > 16 ? normalized.substring(0, 16).replace('T', ' ') : normalized.replace('T', ' ');
    }
    let now = new Date();
    let hour = String(date.getHours());
    let minute = String(date.getMinutes()).padStart(2, '0');
    if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()) {
      return `今天${hour}:${minute}`;
    }
    let month = String(date.getMonth() + 1);
    let day = String(date.getDate());
    if (date.getFullYear() === now.getFullYear()) {
      return `${month}-${day} ${hour}:${minute}`;
    }
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  private parseLocalDate(value: string): Date {
    let normalized = value.replace('T', ' ');
    let match = /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?/.exec(normalized);
    if (match) {
      return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6] || '0'));
    }
    return new Date(value);
  }

  private profileCompleteness(profile: ProfileState): number {
    let lifestyleDomains = ['eat', 'wear', 'live', 'travel'];
    let score = 0;
    lifestyleDomains.forEach((domain: string) => {
      let doc = profile.domains[domain];
      if (!doc || doc.event_count === 0) {
        return;
      }
      score += 18;
      if (normalizeFreeText(doc.summary).length > 0 || doc.claims.length > 0) {
        score += 7;
      }
    });
    return Math.min(100, score);
  }

  private profileRecommendations(profile: ProfileState): HomeRecommendationViewModel[] {
    let colors: StringMap = createStringMap();
    colors['eat'] = '#39C2A2';
    colors['wear'] = '#7669FF';
    colors['live'] = '#FF963D';
    colors['travel'] = '#4B9BFF';
    colors['work'] = '#8066FF';
    colors['other'] = '#8B93A4';
    let result: HomeRecommendationViewModel[] = [];
    DOMAIN_KEYS.forEach((domain: string) => {
      let doc = profile.domains[domain];
      if (!doc || doc.claims.length === 0) {
        return;
      }
      doc.claims.slice(0, 2).forEach((claim: ProfileClaim, index: number) => {
        let recommendation: HomeRecommendationViewModel = {
          id: domain + '-' + index,
          domain: domain,
          tag: `${DOMAIN_DISPLAY_NAMES[domain] || domain}画像`,
          title: summarizeText(claim.statement, 18),
          desc: normalizeFreeText(claim.example) || doc.summary || `${doc.event_count} 条事件支持`,
          meta: `${claim.evidence_count} 条证据`,
          color: colors[domain] || '#8066FF'
        };
        result.push(recommendation);
      });
    });
    return result.slice(0, 6);
  }
}

