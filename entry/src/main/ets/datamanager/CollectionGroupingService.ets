import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { IndexService } from './IndexService';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { dataManagerError, dataManagerInfo } from './DataManagerLog';
import {
  BooleanMap,
  CollectionGroupState,
  CollectionGroupsDocument,
  DataManagerModelConfig,
  DataManagerProgressCallback,
  DOMAIN_DISPLAY_NAMES,
  IndexedEvent,
  NumberMap,
  QueryOptions,
  StringMap,
  createBooleanMap,
  createDataManagerProgress,
  createNumberMap,
  createStringMap
} from './DataManagerTypes';
import {
  displayDomainName,
  eventSearchText,
  normalizeFreeText,
  normalizeLookupText,
  nowIsoLocal,
  sourceDisplayName,
  stableUnique,
  summarizeText
} from './DataManagerUtils';

export interface CollectionGroupingBuildResult {
  tabCount: number;
  groupCount: number;
  eventCount: number;
  reusedGroupDocs: number;
  updatedGroupDocs: number;
}

export interface CollectionTabSpec {
  tabIndex: number;
  tabId: string;
  title: string;
  query: QueryOptions;
}

type EventMap = Record<string, IndexedEvent>;
type EventGroupMap = Record<string, IndexedEvent[]>;
type CollectionGroupMap = Record<string, CollectionGroupState[]>;

const MAX_GROUPS_PER_TAB: number = 12;

export function collectionTabSpecs(): CollectionTabSpec[] {
  return [
    {
      tabIndex: 0,
      tabId: 'chat',
      title: '最近聊天',
      query: { keywords: ['微信'], domains: [], entities: [], date: '', month: '', startDate: '', endDate: '', limit: 0 }
    },
    {
      tabIndex: 1,
      tabId: 'orders',
      title: '最近订单',
      query: { keywords: [], domains: ['eat', 'wear', 'live', 'travel'], entities: [], date: '', month: '', startDate: '', endDate: '', limit: 0 }
    },
    {
      tabIndex: 2,
      tabId: 'notifications',
      title: '最近通知',
      query: { keywords: ['通知'], domains: [], entities: [], date: '', month: '', startDate: '', endDate: '', limit: 0 }
    },
    {
      tabIndex: 3,
      tabId: 'entertainment',
      title: '娱乐记录',
      query: { keywords: ['视频'], domains: [], entities: [], date: '', month: '', startDate: '', endDate: '', limit: 0 }
    }
  ];
}

export function collectionTabSpecByIndex(index: number): CollectionTabSpec {
  let specs = collectionTabSpecs();
  if (index >= 0 && index < specs.length) {
    return specs[index];
  }
  return specs[1];
}

export function emptyCollectionGroupsDocument(spec: CollectionTabSpec): CollectionGroupsDocument {
  return {
    generated_at: '',
    tab_id: spec.tabId,
    title: spec.title,
    query: spec.query,
    input_hash: '',
    total_events: 0,
    groups: []
  };
}

export function heuristicCollectionGroups(tabId: string, title: string, events: IndexedEvent[]): CollectionGroupState[] {
  let grouped: EventGroupMap = {};
  events.forEach((event: IndexedEvent) => {
    let key = heuristicGroupKey(tabId, event);
    if (!grouped[key]) {
      grouped[key] = [];
    }
    grouped[key].push(event);
  });
  let groups: CollectionGroupState[] = [];
  Object.keys(grouped).forEach((key: string) => {
    let groupEvents = grouped[key];
    groups.push(groupFromEvents(tabId, title, '', groupEvents));
  });
  return normalizeCollectionGroups(tabId, title, events, groups);
}

export function normalizeCollectionGroups(tabId: string, title: string, events: IndexedEvent[], candidateGroups: CollectionGroupState[]): CollectionGroupState[] {
  let eventMap: EventMap = {};
  events.forEach((event: IndexedEvent) => eventMap[event.event_id] = event);
  let assigned: BooleanMap = createBooleanMap();
  let normalized: CollectionGroupState[] = [];
  candidateGroups.forEach((candidate: CollectionGroupState) => {
    let eventIds = stableUnique((candidate.event_ids || [])
      .map((id: string) => normalizeFreeText(id))
      .filter((id: string) => eventMap[id] !== undefined && assigned[id] !== true));
    if (eventIds.length === 0) {
      return;
    }
    eventIds.forEach((id: string) => assigned[id] = true);
    let groupEvents = eventIds.map((id: string) => eventMap[id]);
    let group = groupFromEvents(tabId, title, candidate.title, groupEvents);
    group.source = normalizeFreeText(candidate.source) || group.source;
    group.domain = normalizeFreeText(candidate.domain) || group.domain;
    group.status = normalizeFreeText(candidate.status) || group.status;
    group.event_ids = eventIds;
    normalized.push(group);
  });

  let missing: IndexedEvent[] = [];
  events.forEach((event: IndexedEvent) => {
    if (assigned[event.event_id] !== true) {
      missing.push(event);
    }
  });
  if (missing.length > 0) {
    let fallbackGroups = heuristicCollectionGroupsWithoutNormalize(tabId, title, missing);
    fallbackGroups.forEach((fallback: CollectionGroupState) => {
      let eventIds = stableUnique((fallback.event_ids || []).filter((id: string) => eventMap[id] !== undefined && assigned[id] !== true));
      if (eventIds.length === 0) {
        return;
      }
      eventIds.forEach((id: string) => assigned[id] = true);
      let groupEvents = eventIds.map((id: string) => eventMap[id]);
      normalized.push(groupFromEvents(tabId, title, fallback.title, groupEvents));
    });
  }

  normalized = prepareCollectionGroupTitles(tabId, title, normalized, eventMap);
  normalized = mergeGroupsByTitle(normalized, eventMap, tabId, title);
  normalized = normalized.sort((left: CollectionGroupState, right: CollectionGroupState) => {
    if (left.time !== right.time) {
      return right.time.localeCompare(left.time);
    }
    return right.event_ids.length - left.event_ids.length;
  });
  normalized = compactCollectionGroups(tabId, title, normalized, eventMap);
  normalized = prepareCollectionGroupTitles(tabId, title, normalized, eventMap);
  normalized.forEach((group: CollectionGroupState, index: number) => {
    group.group_id = stableGroupId(tabId, index, group.event_ids);
    group.meta = `${group.event_ids.length} 条`;
    group.status = '已整理';
  });
  return normalized;
}

export class CollectionGroupingService {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;
  private modelClient: DataPipelineModelClient;
  private indexService: IndexService;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage, modelClient: DataPipelineModelClient, indexService: IndexService) {
    this.paths = paths;
    this.storage = storage;
    this.modelClient = modelClient;
    this.indexService = indexService;
  }

  async buildAll(modelConfig: DataManagerModelConfig, progress?: DataManagerProgressCallback, force: boolean = false): Promise<CollectionGroupingBuildResult> {
    this.paths.ensureBaseDirs();
    let specs = collectionTabSpecs();
    let groupCount = 0;
    let eventCount = 0;
    let reusedGroupDocs = 0;
    let updatedGroupDocs = 0;
    for (let index = 0; index < specs.length; index++) {
      let spec = specs[index];
      this.emitProgress(progress, '采集分组', `生成${spec.title}分组`, index, specs.length, 96 + Math.round(index * 2 / Math.max(1, specs.length)));
      let result = this.indexService.query(spec.query);
      let events = result.events;
      eventCount += events.length;
      let inputHash = this.inputHash(spec, events, modelConfig);
      let previous = this.loadGroupsDocumentBySpec(spec);
      if (!force && previous.input_hash === inputHash && previous.groups.length > 0) {
        groupCount += previous.groups.length;
        reusedGroupDocs++;
        dataManagerInfo(`Collection groups reused: tab=${spec.tabId}, events=${events.length}, groups=${previous.groups.length}`);
        continue;
      }
      let groups = await this.buildGroupsForTab(spec, events, modelConfig);
      let document: CollectionGroupsDocument = {
        generated_at: nowIsoLocal(),
        tab_id: spec.tabId,
        title: spec.title,
        query: spec.query,
        input_hash: inputHash,
        total_events: events.length,
        groups: groups
      };
      this.storage.writeJsonAtomic(this.paths.collectionGroupsPath(spec.tabId), document as Object);
      groupCount += groups.length;
      updatedGroupDocs++;
      dataManagerInfo(`Collection groups built: tab=${spec.tabId}, events=${events.length}, groups=${groups.length}`);
    }
    this.emitProgress(progress, '采集分组', '采集分组完成', specs.length, specs.length, 99);
    return {
      tabCount: specs.length,
      groupCount: groupCount,
      eventCount: eventCount,
      reusedGroupDocs: reusedGroupDocs,
      updatedGroupDocs: updatedGroupDocs
    };
  }

  loadGroupsDocument(tabIndex: number): CollectionGroupsDocument {
    return this.loadGroupsDocumentBySpec(collectionTabSpecByIndex(tabIndex));
  }

  clearPersistedGroups(): void {
    this.storage.removeTree(this.paths.collectionGroupsRoot);
    this.paths.ensureBaseDirs();
    dataManagerInfo('Collection groups cleared: ' + this.paths.collectionGroupsRoot);
  }

  private async buildGroupsForTab(spec: CollectionTabSpec, events: IndexedEvent[], modelConfig: DataManagerModelConfig): Promise<CollectionGroupState[]> {
    if (events.length === 0) {
      return [];
    }
    try {
      let planned = await this.modelClient.planCollectionGroups(spec.tabId, spec.title, events, modelConfig);
      let groups = normalizeCollectionGroups(spec.tabId, spec.title, events, planned);
      if (groups.length > 0) {
        return groups;
      }
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Collection grouping planner fallback: tab=${spec.tabId}, error=${err.message}`);
    }
    return heuristicCollectionGroups(spec.tabId, spec.title, events);
  }

  private loadGroupsDocumentBySpec(spec: CollectionTabSpec): CollectionGroupsDocument {
    return this.storage.readJson<CollectionGroupsDocument>(this.paths.collectionGroupsPath(spec.tabId), emptyCollectionGroupsDocument(spec));
  }

  private inputHash(spec: CollectionTabSpec, events: IndexedEvent[], modelConfig: DataManagerModelConfig): string {
    let parts: string[] = [
      spec.tabId,
      spec.title,
      modelConfig.enabled ? 'model' : 'heuristic',
      modelConfig.enabled ? modelConfig.baseUrl : ''
    ];
    events.forEach((event: IndexedEvent) => {
      parts.push([
        event.event_id,
        event.event_date,
        event.summary,
        event.normalized_fact,
        (event.sources || []).join(','),
        (event.domains || []).join(','),
        (event.keywords || []).join(','),
        (event.entities || []).join(',')
      ].join('\u001f'));
    });
    return this.storage.sha256Text(parts.join('\u001e'));
  }

  private emitProgress(progress: DataManagerProgressCallback | undefined, stage: string, message: string, current: number, total: number, percent: number): void {
    if (!progress) {
      return;
    }
    progress(createDataManagerProgress(stage, message, current, total, percent));
  }
}

function heuristicCollectionGroupsWithoutNormalize(tabId: string, title: string, events: IndexedEvent[]): CollectionGroupState[] {
  let grouped: EventGroupMap = {};
  events.forEach((event: IndexedEvent) => {
    let key = heuristicGroupKey(tabId, event);
    if (!grouped[key]) {
      grouped[key] = [];
    }
    grouped[key].push(event);
  });
  let groups: CollectionGroupState[] = [];
  Object.keys(grouped).forEach((key: string) => {
    groups.push(groupFromEvents(tabId, title, '', grouped[key]));
  });
  return groups;
}

function heuristicGroupKey(tabId: string, event: IndexedEvent): string {
  let source = firstText(event.sources, sourceDisplayName(event.source_state_file));
  let domain = firstText(event.domains, 'other');
  let entity = firstEntityName(event);
  let keyword = firstMeaningfulKeyword(event);
  if (tabId === 'chat') {
    let contact = chatContactName([event], source, entity);
    return contact || source || keyword || 'chat';
  }
  if (tabId === 'orders') {
    return [entity || source || displayDomainName(domain), domain].join('|');
  }
  if (tabId === 'notifications') {
    return [source, keyword || '提醒'].join('|');
  }
  if (tabId === 'entertainment') {
    return [keyword || source, domain].join('|');
  }
  return [source, domain, keyword].join('|');
}

function groupFromEvents(tabId: string, title: string, preferredTitle: string, events: IndexedEvent[]): CollectionGroupState {
  let sorted = events.slice().sort((left: IndexedEvent, right: IndexedEvent) => {
    if (left.event_date !== right.event_date) {
      return right.event_date.localeCompare(left.event_date);
    }
    return right.event_id.localeCompare(left.event_id);
  });
  let domain = dominantDomain(sorted);
  let source = dominantSource(sorted);
  let groupTitle = normalizeFreeText(preferredTitle) || deriveGroupTitle(tabId, title, sorted, source, domain);
  let ids = sorted.map((event: IndexedEvent) => event.event_id);
  let group: CollectionGroupState = {
    group_id: '',
    title: summarizeText(groupTitle, 28),
    source: source,
    time: sorted.length > 0 ? sorted[0].event_date : '',
    meta: `${ids.length} 条`,
    status: '已整理',
    domain: domain,
    event_ids: ids
  };
  return group;
}

function deriveGroupTitle(tabId: string, title: string, events: IndexedEvent[], source: string, domain: string): string {
  let entity = events.length > 0 ? firstEntityName(events[0]) : '';
  let keyword = events.length > 0 ? firstMeaningfulKeyword(events[0]) : '';
  if (tabId === 'chat') {
    let contact = chatContactName(events, source, entity);
    if (contact.length > 0) {
      return `与${contact}的对话`;
    }
    if (keyword.length > 0) {
      return `${keyword}沟通`;
    }
    return '聊天整理';
  }
  if (tabId === 'orders') {
    if (entity.length > 0) {
      return `${entity}相关订单`;
    }
    if (keyword.length > 0) {
      return `${keyword}记录`;
    }
    return `${displayDomainName(domain)}类订单`;
  }
  if (tabId === 'notifications') {
    if (keyword.length > 0) {
      return `${keyword}提醒`;
    }
    return source.length > 0 ? `${source}通知` : '通知记录';
  }
  if (tabId === 'entertainment') {
    if (keyword.length > 0) {
      return `${keyword}记录`;
    }
    return source.length > 0 ? `${source}娱乐记录` : '娱乐记录';
  }
  return title;
}

function prepareCollectionGroupTitles(tabId: string, title: string, groups: CollectionGroupState[], eventMap: EventMap): CollectionGroupState[] {
  groups.forEach((group: CollectionGroupState) => {
    if (!shouldReplaceGroupTitle(tabId, group.title)) {
      return;
    }
    let groupEvents = eventsForGroup(group, eventMap);
    let replacement = deriveGroupTitle(tabId, title, groupEvents, group.source, group.domain);
    group.title = summarizeText(replacement, 28);
  });
  return groups;
}

function shouldReplaceGroupTitle(tabId: string, value: string): boolean {
  if (isGenericGroupTitle(tabId, value)) {
    return true;
  }
  if (tabId !== 'chat') {
    return false;
  }
  return isLowInformationChatTitle(value);
}

function mergeGroupsByTitle(groups: CollectionGroupState[], eventMap: EventMap, tabId: string, title: string): CollectionGroupState[] {
  if (groups.length <= 1) {
    return groups;
  }
  let grouped: CollectionGroupMap = new Object() as CollectionGroupMap;
  let order: string[] = [];
  groups.forEach((group: CollectionGroupState) => {
    let key = normalizeLookupText(group.title);
    if (key.length === 0) {
      key = stableUnique(group.event_ids || []).join('|');
    }
    if (!grouped[key]) {
      grouped[key] = [];
      order.push(key);
    }
    grouped[key].push(group);
  });
  let merged: CollectionGroupState[] = [];
  order.forEach((key: string) => {
    let sourceGroups = grouped[key];
    if (sourceGroups.length === 1) {
      merged.push(sourceGroups[0]);
      return;
    }
    let ids: string[] = [];
    sourceGroups.forEach((group: CollectionGroupState) => {
      ids = ids.concat(group.event_ids || []);
    });
    let mergedEvents: IndexedEvent[] = [];
    stableUnique(ids).forEach((id: string) => {
      let event = eventMap[id];
      if (event) {
        mergedEvents.push(event);
      }
    });
    if (mergedEvents.length === 0) {
      return;
    }
    merged.push(groupFromEvents(tabId, title, sourceGroups[0].title, mergedEvents));
  });
  return merged;
}

function eventsForGroup(group: CollectionGroupState, eventMap: EventMap): IndexedEvent[] {
  let events: IndexedEvent[] = [];
  stableUnique(group.event_ids || []).forEach((id: string) => {
    let event = eventMap[id];
    if (event) {
      events.push(event);
    }
  });
  return events;
}

function isGenericGroupTitle(tabId: string, value: string): boolean {
  let title = normalizeLookupText(value);
  if (title.length === 0) {
    return true;
  }
  let generic = [
    '微信聊天记录',
    '工作相关聊天记录',
    '工作聊天记录',
    '聊天记录',
    '微信记录',
    '微信聊天',
    '通知记录',
    '视频记录',
    '订单记录',
    '购物记录',
    '娱乐记录',
    '微信聊天记录讨论',
    '工作相关聊天记录讨论',
    '工作聊天记录讨论',
    '微信记录讨论'
  ];
  if (generic.indexOf(title) >= 0) {
    return true;
  }
  if (tabId !== 'chat') {
    return false;
  }
  return /^(微信|聊天|工作|记录)(讨论|沟通|记录)?$/.test(title) || /^\d+(讨论|沟通|记录)?$/.test(title);
}

function isLowInformationChatTitle(value: string): boolean {
  let title = normalizeFreeText(value);
  let lookup = normalizeLookupText(title);
  if (lookup.length === 0 || /^\d+(讨论|沟通|记录)?$/.test(lookup)) {
    return true;
  }
  if (/^[a-z0-9]+(讨论|沟通|记录)$/i.test(title)) {
    return true;
  }
  let stem = title.replace(/(讨论|沟通|记录|整理)$/g, '');
  if (/^(图片|截图|贴图|表情包|消息|记录|页面|界面)$/i.test(stem)) {
    return true;
  }
  return false;
}

function chatContactName(events: IndexedEvent[], source: string, fallbackEntity: string): string {
  for (let event of events) {
    let detail = sourceDetailName(event);
    if (detail.length > 0) {
      return detail;
    }
  }
  let sourceName = normalizeFreeText(source);
  if (sourceName.length > 0 && sourceName !== '微信聊天' && sourceName !== '本地日志') {
    return sourceName;
  }
  let entity = normalizeFreeText(fallbackEntity);
  if (entity.length > 0) {
    return entity;
  }
  for (let event of events) {
    let name = firstEntityName(event);
    if (name.length > 0) {
      return name;
    }
  }
  return '';
}

function sourceDetailName(event: IndexedEvent): string {
  let sources = event.sources || [];
  for (let index = 1; index < sources.length; index++) {
    let source = normalizeFreeText(sources[index]);
    if (source.length > 0) {
      return source;
    }
  }
  return '';
}

function compactCollectionGroups(tabId: string, title: string, groups: CollectionGroupState[], eventMap: EventMap): CollectionGroupState[] {
  if (groups.length <= MAX_GROUPS_PER_TAB) {
    return groups;
  }
  let kept = groups.slice(0, MAX_GROUPS_PER_TAB - 1);
  let remainderIds: string[] = [];
  groups.slice(MAX_GROUPS_PER_TAB - 1).forEach((group: CollectionGroupState) => {
    remainderIds = remainderIds.concat(group.event_ids || []);
  });
  let remainderEvents: IndexedEvent[] = [];
  stableUnique(remainderIds).forEach((id: string) => {
    let event = eventMap[id];
    if (event) {
      remainderEvents.push(event);
    }
  });
  if (remainderEvents.length > 0) {
    kept.push(groupFromEvents(tabId, title, '其他已整理记录', remainderEvents));
  }
  return kept;
}

function stableGroupId(tabId: string, index: number, eventIds: string[]): string {
  let joined = eventIds.slice().sort().join('|');
  let hash = 2166136261;
  for (let i = 0; i < joined.length; i++) {
    hash ^= joined.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return `${tabId}-${index + 1}-${(hash >>> 0).toString(16)}`;
}

function dominantSource(events: IndexedEvent[]): string {
  let counts: NumberMap = createNumberMap();
  events.forEach((event: IndexedEvent) => {
    let source = firstText(event.sources, sourceDisplayName(event.source_state_file));
    counts[source] = (counts[source] || 0) + 1;
  });
  return topCountKey(counts, '本地日志');
}

function dominantDomain(events: IndexedEvent[]): string {
  let counts: NumberMap = createNumberMap();
  events.forEach((event: IndexedEvent) => {
    let domain = firstText(event.domains, 'other');
    counts[domain] = (counts[domain] || 0) + 1;
  });
  return topCountKey(counts, 'other');
}

function topCountKey(counts: NumberMap, fallback: string): string {
  let best = fallback;
  let bestCount = -1;
  Object.keys(counts).forEach((key: string) => {
    if (counts[key] > bestCount) {
      best = key;
      bestCount = counts[key];
    }
  });
  return best;
}

function firstText(values: string[], fallback: string): string {
  if (!values || values.length === 0) {
    return fallback;
  }
  let text = normalizeFreeText(values[0]);
  return text.length > 0 ? text : fallback;
}

function firstEntityName(event: IndexedEvent): string {
  if (event.entity_mentions && event.entity_mentions.length > 0) {
    let name = normalizeFreeText(event.entity_mentions[0].name);
    if (name.length > 0) {
      return name;
    }
  }
  if (event.entities && event.entities.length > 0) {
    let parts = normalizeFreeText(event.entities[0]).split(':');
    let name = parts.length > 1 ? parts.slice(1).join(':') : parts[0];
    return normalizeFreeText(name);
  }
  return '';
}

function firstMeaningfulKeyword(event: IndexedEvent): string {
  let blocked: StringMap = createStringMap();
  [
    '微信',
    '通知',
    '视频',
    '记录',
    '页面',
    '显示',
    '订单',
    '聊天',
    '截图',
    '图片',
    '贴图',
    '表情包',
    '消息',
    '当前界面'
  ].forEach((value: string) => blocked[normalizeLookupText(value)] = value);
  for (let keyword of event.keywords || []) {
    let text = normalizeFreeText(keyword);
    if (text.length === 0 || isLowValueKeyword(text) || blocked[normalizeLookupText(text)] !== undefined) {
      continue;
    }
    return text;
  }
  let terms = eventSearchText(event).split(/\s+/).filter((item: string) => {
    let text = normalizeFreeText(item);
    return text.length > 1 && !isLowValueKeyword(text) && blocked[normalizeLookupText(text)] === undefined;
  });
  return terms.length > 0 ? normalizeFreeText(terms[0]) : '';
}

function isLowValueKeyword(value: string): boolean {
  let text = normalizeFreeText(value);
  let lookup = normalizeLookupText(text);
  if (lookup.length === 0 || /^\d+$/.test(lookup) || /^[0-9:.年月日/-]+$/.test(text)) {
    return true;
  }
  if (text.indexOf('微信聊天记录') >= 0 || text.indexOf('当前界面') >= 0 || text.indexOf('截图') >= 0) {
    return true;
  }
  return false;
}

