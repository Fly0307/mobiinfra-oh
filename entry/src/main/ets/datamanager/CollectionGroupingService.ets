import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { IndexService } from './IndexService';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { dataManagerError, dataManagerInfo } from './DataManagerLog';
import {
  BooleanMap,
  CollectionGroupAssignment,
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
  dateToTime,
  eventSearchText,
  normalizeFreeText,
  normalizeLookupText,
  nowIsoLocal,
  runLimitedTasks,
  sourceDisplayName,
  stableUnique,
  summarizeText
} from './DataManagerUtils';
import { memorySceneConfigs, normalizeMemorySceneId, WorkflowSceneConfig } from '../utils/WorkflowSceneConfig';

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
type CollectionAssignmentMap = Record<string, CollectionGroupAssignment>;

const COLLECTION_GROUP_ASSIGNMENT_WINDOW_DAYS: number = 7;
const DEFAULT_COLLECTION_TAB_CONCURRENCY: number = 3;

interface CollectionTabBuildResult {
  groupCount: number;
  eventCount: number;
  reusedGroupDocs: number;
  updatedGroupDocs: number;
}

export interface IncrementalCollectionGroupPlan {
  eventMap: Record<string, IndexedEvent>;
  reusedGroups: CollectionGroupState[];
  pendingEvents: IndexedEvent[];
}

export function collectionTabSpecs(): CollectionTabSpec[] {
  let scenes = memorySceneConfigs();
  return scenes.map((scene: WorkflowSceneConfig): CollectionTabSpec => {
    let spec: CollectionTabSpec = {
      tabIndex: scene.sceneId,
      tabId: scene.tabId,
      title: scene.label + '记录',
      query: { keywords: [], domains: [], entities: [], date: '', month: '', startDate: '', endDate: '', workflowSceneIds: [scene.sceneId], limit: 0 }
    };
    return spec;
  });
}

export function collectionTabSpecByIndex(index: number): CollectionTabSpec {
  let specs = collectionTabSpecs();
  let normalizedIndex = normalizeMemorySceneId(index);
  for (let spec of specs) {
    if (spec.tabIndex === normalizedIndex) {
      return spec;
    }
  }
  return specs[0];
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
  normalized = prepareCollectionGroupTitles(tabId, title, normalized, eventMap);
  normalized.forEach((group: CollectionGroupState, index: number) => {
    group.group_id = stableGroupId(tabId, index, group.event_ids);
    group.meta = `${group.event_ids.length} 条`;
    group.status = '已整理';
    refreshCollectionGroupHashes(group, eventMap);
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
    let completedTabs = 0;
    let tasks = specs.map((spec: CollectionTabSpec): (() => Promise<CollectionTabBuildResult>) => {
      return async (): Promise<CollectionTabBuildResult> => {
        this.emitProgress(progress, '采集分组', `生成${spec.title}分组`, completedTabs, specs.length,
          96 + Math.round(completedTabs * 2 / Math.max(1, specs.length)));
        let result = this.indexService.query(spec.query);
        let events = result.events;
        let inputHash = this.inputHash(spec, events, modelConfig);
        let previous = this.loadGroupsDocumentBySpec(spec);
        if (!force && previous.input_hash === inputHash && (previous.groups.length > 0 || events.length === 0)) {
          completedTabs++;
          this.emitProgress(progress, '采集分组', `已生成 ${completedTabs}/${specs.length} 个场景分组`, completedTabs, specs.length,
            96 + Math.round(completedTabs * 2 / Math.max(1, specs.length)));
          dataManagerInfo(`Collection groups reused: tab=${spec.tabId}, events=${events.length}, groups=${previous.groups.length}`);
          return {
            groupCount: previous.groups.length,
            eventCount: events.length,
            reusedGroupDocs: 1,
            updatedGroupDocs: 0
          };
        }
        let groups = await this.buildGroupsForTab(spec, events, modelConfig, previous);
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
        completedTabs++;
        this.emitProgress(progress, '采集分组', `已生成 ${completedTabs}/${specs.length} 个场景分组`, completedTabs, specs.length,
          96 + Math.round(completedTabs * 2 / Math.max(1, specs.length)));
        dataManagerInfo(`Collection groups built: tab=${spec.tabId}, events=${events.length}, groups=${groups.length}`);
        return {
          groupCount: groups.length,
          eventCount: events.length,
          reusedGroupDocs: 0,
          updatedGroupDocs: 1
        };
      };
    });
    let results = await runLimitedTasks<CollectionTabBuildResult>(tasks, DEFAULT_COLLECTION_TAB_CONCURRENCY);
    results.forEach((result: CollectionTabBuildResult) => {
      groupCount += result.groupCount;
      eventCount += result.eventCount;
      reusedGroupDocs += result.reusedGroupDocs;
      updatedGroupDocs += result.updatedGroupDocs;
    });
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

  private async buildGroupsForTab(spec: CollectionTabSpec, events: IndexedEvent[], modelConfig: DataManagerModelConfig,
    previous: CollectionGroupsDocument): Promise<CollectionGroupState[]> {
    if (events.length === 0) {
      return [];
    }
    if ((previous.groups || []).length > 0) {
      return await this.buildIncrementalGroupsForTab(spec, events, modelConfig, previous);
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

  private async buildIncrementalGroupsForTab(spec: CollectionTabSpec, events: IndexedEvent[], modelConfig: DataManagerModelConfig,
    previous: CollectionGroupsDocument): Promise<CollectionGroupState[]> {
    let planning = prepareIncrementalCollectionGroups(spec.tabId, spec.title, events, previous.groups || []);
    let assignments: CollectionGroupAssignment[] = [];
    if (planning.pendingEvents.length > 0 && modelConfig.enabled) {
      try {
        assignments = await this.modelClient.assignCollectionGroupEvents(spec.tabId, spec.title, planning.pendingEvents,
          planning.reusedGroups, planning.eventMap, modelConfig);
      } catch (e) {
        let err = e as Error;
        dataManagerError(`Collection assignment fallback: tab=${spec.tabId}, error=${err.message}`);
      }
    }
    let groups = applyIncrementalCollectionGroupAssignments(spec.tabId, spec.title, events, planning.reusedGroups,
      planning.pendingEvents, assignments);
    dataManagerInfo(`Collection groups incremental: tab=${spec.tabId}, reusedGroups=${planning.reusedGroups.length}, pendingEvents=${planning.pendingEvents.length}, groups=${groups.length}`);
    return groups;
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
        (event.workflow_scene_ids || []).join(','),
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

export function collectionGroupEventInputFingerprint(event: IndexedEvent): string {
  let parts: string[] = [
    event.event_id,
    event.event_date,
    event.summary,
    event.normalized_fact,
    (event.sources || []).join(','),
    (event.workflow_scene_ids || []).join(','),
    (event.domains || []).join(','),
    (event.keywords || []).join(','),
    (event.entities || []).join(',')
  ];
  return stableTextHash(parts.map((part: string): string => normalizeFreeText(part)).join('\u001f'));
}

export function collectionGroupSourceInputFingerprint(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
  let parts: string[] = [];
  stableUnique(eventIds || []).sort().forEach((id: string) => {
    let event = eventMap[id];
    if (!event) {
      return;
    }
    parts.push(id + '\u001f' + collectionGroupEventInputFingerprint(event));
  });
  return stableTextHash(parts.join('\u001e'));
}

export function prepareIncrementalCollectionGroups(tabId: string, title: string, events: IndexedEvent[],
  previousGroups: CollectionGroupState[]): IncrementalCollectionGroupPlan {
  let eventMap = eventMapFromEvents(events);
  let eventHashes: StringMap = createStringMap();
  events.forEach((event: IndexedEvent) => eventHashes[event.event_id] = collectionGroupEventInputFingerprint(event));
  let covered: BooleanMap = createBooleanMap();
  let pending: BooleanMap = createBooleanMap();
  let reusedGroups: CollectionGroupState[] = [];
  (previousGroups || []).forEach((previous: CollectionGroupState) => {
    let groupId = normalizeFreeText(previous.group_id);
    let groupTitle = normalizeFreeText(previous.title);
    if (groupId.length === 0 || groupTitle.length === 0) {
      return;
    }
    let retainedIds: string[] = [];
    stableUnique(previous.event_ids || []).forEach((id: string) => {
      let event = eventMap[id];
      if (!event) {
        return;
      }
      let previousHash = previous.event_input_hashes ? normalizeFreeText(previous.event_input_hashes[id]) : '';
      if (previousHash.length > 0 && previousHash === eventHashes[id] && covered[id] !== true) {
        retainedIds.push(id);
        covered[id] = true;
      } else {
        pending[id] = true;
      }
    });
    if (retainedIds.length === 0) {
      return;
    }
    let group = copyCollectionGroup(previous);
    group.event_ids = retainedIds;
    let refreshed = refreshCollectionGroupFromEvents(tabId, title, group, eventMap);
    if (refreshed) {
      reusedGroups.push(refreshed);
    }
  });
  events.forEach((event: IndexedEvent) => {
    if (covered[event.event_id] !== true) {
      pending[event.event_id] = true;
    }
  });
  let pendingEvents = events.filter((event: IndexedEvent): boolean => pending[event.event_id] === true && covered[event.event_id] !== true);
  return {
    eventMap: eventMap,
    reusedGroups: reusedGroups,
    pendingEvents: pendingEvents
  };
}

export function applyIncrementalCollectionGroupAssignments(tabId: string, title: string, events: IndexedEvent[],
  reusedGroups: CollectionGroupState[], pendingEvents: IndexedEvent[], assignments: CollectionGroupAssignment[]): CollectionGroupState[] {
  let eventMap = eventMapFromEvents(events);
  let activeGroups: CollectionGroupState[] = reusedGroups.map((group: CollectionGroupState): CollectionGroupState => copyCollectionGroup(group));
  let activeById: Record<string, CollectionGroupState> = new Object() as Record<string, CollectionGroupState>;
  activeGroups.forEach((group: CollectionGroupState) => {
    let id = normalizeFreeText(group.group_id);
    if (id.length > 0 && !activeById[id]) {
      activeById[id] = group;
    }
  });
  let pendingById: BooleanMap = createBooleanMap();
  pendingEvents.forEach((event: IndexedEvent) => pendingById[event.event_id] = true);
  let assignedPending: BooleanMap = createBooleanMap();
  let newBuckets: CollectionAssignmentMap = new Object() as CollectionAssignmentMap;
  let newBucketEvents: Record<string, string[]> = new Object() as Record<string, string[]>;
  let newBucketOrder: string[] = [];
  (assignments || []).forEach((assignment: CollectionGroupAssignment) => {
    let eventId = normalizeFreeText(assignment.event_id);
    let event = eventMap[eventId];
    if (!event || pendingById[eventId] !== true || assignedPending[eventId] === true) {
      return;
    }
    let targetId = normalizeFreeText(assignment.group_id);
    let existing = activeById[targetId];
    if (existing && isCollectionAssignmentCandidate(event, existing)) {
      existing.event_ids = stableUnique((existing.event_ids || []).concat([eventId]));
      assignedPending[eventId] = true;
      return;
    }
    let bucketKey = newCollectionAssignmentBucketKey(existing ? '' : targetId, assignment, eventId);
    if (!newBuckets[bucketKey]) {
      newBuckets[bucketKey] = assignment;
      newBucketEvents[bucketKey] = [];
      newBucketOrder.push(bucketKey);
    }
    newBucketEvents[bucketKey].push(eventId);
    assignedPending[eventId] = true;
  });
  let candidates: CollectionGroupState[] = activeGroups;
  newBucketOrder.forEach((key: string) => {
    let assignment = newBuckets[key];
    let group: CollectionGroupState = {
      group_id: '',
      title: normalizeFreeText(assignment.title),
      source: normalizeFreeText(assignment.source),
      time: '',
      meta: '',
      status: '',
      domain: normalizeFreeText(assignment.domain),
      event_ids: stableUnique(newBucketEvents[key] || []),
      source_input_hash: '',
      event_input_hashes: createStringMap()
    };
    candidates.push(group);
  });
  let fallbackEvents = pendingEvents.filter((event: IndexedEvent): boolean => assignedPending[event.event_id] !== true);
  if (fallbackEvents.length > 0) {
    candidates = candidates.concat(heuristicCollectionGroupsWithoutNormalize(tabId, title, fallbackEvents));
  }
  return finalizeIncrementalCollectionGroups(tabId, title, events, candidates);
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
    event_ids: ids,
    source_input_hash: '',
    event_input_hashes: createStringMap()
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

function eventMapFromEvents(events: IndexedEvent[]): EventMap {
  let eventMap: EventMap = new Object() as EventMap;
  events.forEach((event: IndexedEvent) => eventMap[event.event_id] = event);
  return eventMap;
}

function copyCollectionGroup(group: CollectionGroupState): CollectionGroupState {
  let hashes: StringMap = createStringMap();
  let sourceHashes = group.event_input_hashes || createStringMap();
  Object.keys(sourceHashes).forEach((key: string) => hashes[key] = sourceHashes[key]);
  return {
    group_id: normalizeFreeText(group.group_id),
    title: normalizeFreeText(group.title),
    source: normalizeFreeText(group.source),
    time: normalizeFreeText(group.time),
    meta: normalizeFreeText(group.meta),
    status: normalizeFreeText(group.status),
    domain: normalizeFreeText(group.domain),
    event_ids: stableUnique(group.event_ids || []),
    source_input_hash: normalizeFreeText(group.source_input_hash),
    event_input_hashes: hashes
  };
}

function refreshCollectionGroupFromEvents(tabId: string, title: string, group: CollectionGroupState,
  eventMap: EventMap): CollectionGroupState | null {
  let eventIds = stableUnique(group.event_ids || []).filter((id: string): boolean => eventMap[id] !== undefined);
  if (eventIds.length === 0) {
    return null;
  }
  let groupEvents = eventIds.map((id: string): IndexedEvent => eventMap[id]);
  let refreshed = groupFromEvents(tabId, title, group.title, groupEvents);
  refreshed.group_id = normalizeFreeText(group.group_id);
  refreshed.title = summarizeText(normalizeFreeText(group.title) || refreshed.title, 28);
  refreshCollectionGroupHashes(refreshed, eventMap);
  return refreshed;
}

function refreshCollectionGroupHashes(group: CollectionGroupState, eventMap: EventMap): void {
  let hashes: StringMap = createStringMap();
  stableUnique(group.event_ids || []).forEach((id: string) => {
    let event = eventMap[id];
    if (event) {
      hashes[id] = collectionGroupEventInputFingerprint(event);
    }
  });
  group.event_input_hashes = hashes;
  group.source_input_hash = collectionGroupSourceInputFingerprint(group.event_ids || [], eventMap);
}

function finalizeIncrementalCollectionGroups(tabId: string, title: string, events: IndexedEvent[],
  candidates: CollectionGroupState[]): CollectionGroupState[] {
  let eventMap = eventMapFromEvents(events);
  let assigned: BooleanMap = createBooleanMap();
  let usedGroupIds: BooleanMap = createBooleanMap();
  let result: CollectionGroupState[] = [];
  candidates.forEach((candidate: CollectionGroupState) => {
    let eventIds = stableUnique(candidate.event_ids || []).filter((id: string): boolean => {
      return eventMap[id] !== undefined && assigned[id] !== true;
    });
    if (eventIds.length === 0) {
      return;
    }
    eventIds.forEach((id: string) => assigned[id] = true);
    let group = copyCollectionGroup(candidate);
    group.event_ids = eventIds;
    group.group_id = nextCollectionGroupId(tabId, group, usedGroupIds);
    let refreshed = refreshCollectionGroupFromEvents(tabId, title, group, eventMap);
    if (refreshed) {
      result.push(refreshed);
    }
  });
  let missing = events.filter((event: IndexedEvent): boolean => assigned[event.event_id] !== true);
  if (missing.length > 0) {
    let fallbackGroups = heuristicCollectionGroupsWithoutNormalize(tabId, title, missing);
    fallbackGroups.forEach((fallback: CollectionGroupState) => {
      let group = copyCollectionGroup(fallback);
      group.group_id = nextCollectionGroupId(tabId, group, usedGroupIds);
      let refreshed = refreshCollectionGroupFromEvents(tabId, title, group, eventMap);
      if (refreshed) {
        result.push(refreshed);
      }
    });
  }
  return result.sort((left: CollectionGroupState, right: CollectionGroupState) => {
    if (left.time !== right.time) {
      return right.time.localeCompare(left.time);
    }
    return right.event_ids.length - left.event_ids.length;
  });
}

function nextCollectionGroupId(tabId: string, group: CollectionGroupState, usedGroupIds: BooleanMap): string {
  let existing = normalizeFreeText(group.group_id);
  if (existing.length > 0 && usedGroupIds[existing] !== true) {
    usedGroupIds[existing] = true;
    return existing;
  }
  let base = `${tabId}-g-${stableTextHash(stableUnique(group.event_ids || []).sort().join('|'))}`;
  let candidate = base;
  let index = 2;
  while (usedGroupIds[candidate] === true) {
    candidate = `${base}-${index}`;
    index++;
  }
  usedGroupIds[candidate] = true;
  return candidate;
}

function newCollectionAssignmentBucketKey(targetId: string, assignment: CollectionGroupAssignment, eventId: string): string {
  let key = normalizeFreeText(targetId);
  if (key.length > 0) {
    return key;
  }
  key = [
    normalizeLookupText(assignment.title),
    normalizeLookupText(assignment.source),
    normalizeLookupText(assignment.domain)
  ].join('|');
  if (key.replace(/\|/g, '').length > 0) {
    return key;
  }
  return eventId;
}

function isCollectionAssignmentCandidate(event: IndexedEvent, group: CollectionGroupState): boolean {
  let eventTime = dateToTime(event.event_date);
  let groupTime = dateToTime(group.time);
  if (eventTime <= 0 || groupTime <= 0) {
    return false;
  }
  return Math.abs(eventTime - groupTime) <= COLLECTION_GROUP_ASSIGNMENT_WINDOW_DAYS * 86400000;
}

function stableTextHash(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return (hash >>> 0).toString(16);
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
