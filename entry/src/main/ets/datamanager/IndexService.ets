import { JSON as ArkJSON } from '@kit.ArkTS';
import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { dataManagerInfo, dataManagerWarn } from './DataManagerLog';
import {
  AggregatedRecord,
  BooleanMap,
  ConsolidatedState,
  DataManagerModelConfig,
  DataManagerProgressCallback,
  DOMAIN_DESCRIPTIONS,
  DOMAIN_DISPLAY_NAMES,
  DOMAIN_KEYS,
  EntityMention,
  EventPartition,
  IndexedEvent,
  JsonMap,
  NumberedEntry,
  ProfileClaim,
  ProfileDomainState,
  ProfileModelPayload,
  ProfileState,
  QueryOptions,
  QueryResult,
  RawProfileClaim,
  NumberMap,
  StringArrayMap,
  StringMap,
  createDataManagerProgress,
  createStringMap
} from './DataManagerTypes';
import {
  dateToTime,
  deriveProfileDomains,
  displayDomainName,
  entityDisplayKey,
  entityLookupKey,
  eventSearchText,
  eventSourceNames,
  indexTerms,
  isIsoDate,
  monthKeyFromDate,
  normalizeEntityName,
  normalizeDomains,
  normalizeEntityMentions,
  normalizeFreeText,
  normalizeLookupText,
  nowIsoLocal,
  parseNumberedEntries,
  publicEvent,
  sourceSearchText,
  stableUnique,
  summarizeText
} from './DataManagerUtils';

export interface IndexBuildResult {
  sourceFiles: number;
  eventCount: number;
  profileClaimCount: number;
  updatedAt: string;
}

interface TemporalSummary {
  text: string;
  input_hash: string;
  generation: string;
}

type EventMap = Record<string, IndexedEvent>;
type ObjectMap = Record<string, Object>;

interface SourceManifestEntry {
  sha256: string;
  event_ids: string[];
}

type SourceManifestMap = Record<string, SourceManifestEntry>;

interface EnrichmentManifest {
  mode: string;
  base_url: string;
}

interface IndexManifest {
  generated_at: string;
  input_root: string;
  index_dir: string;
  run_root: string;
  enrichment: EnrichmentManifest;
  domains: string[];
  entity_types: string[];
  sources: SourceManifestMap;
  event_count: number;
  profile_generated_at: string;
  profile_claim_count: number;
  profile_domains: NumberMap;
}

type EventGroupMap = Record<string, IndexedEvent[]>;
type TemporalDayMap = Record<string, TemporalDayNode[]>;
type TemporalDocumentMap = Record<string, TemporalDocument>;
type ProfileDomainMap = Record<string, ProfileDomainState>;

interface InvertedDocument {
  normalization: string;
  postings: StringArrayMap;
}

interface SourceDocument {
  normalization: string;
  sources: StringArrayMap;
  postings: StringArrayMap;
}

interface DomainDocument {
  domains: StringMap;
  postings: StringArrayMap;
}

interface EntityDefinition {
  type: string;
  name: string;
  aliases: string[];
  event_ids: string[];
}

type EntityDefinitionMap = Record<string, EntityDefinition>;

interface EntityDocument {
  types: string[];
  type_descriptions: StringMap;
  entity_types: string[];
  entities: EntityDefinitionMap;
  alias_postings: StringArrayMap;
}

interface ImageReferenceCandidate {
  summary: string;
  image_path: string;
  used: boolean;
}

type ImageReferenceCandidateMap = Record<string, ImageReferenceCandidate[]>;

const ENTITY_TYPE_KEYS: string[] = ['person', 'place', 'merchant'];
const ENTITY_TYPE_DESCRIPTIONS: StringMap = createStringMap();
ENTITY_TYPE_DESCRIPTIONS['person'] = '现实中的个人或联系人';
ENTITY_TYPE_DESCRIPTIONS['place'] = '现实地点、地址、场馆或地理位置';
ENTITY_TYPE_DESCRIPTIONS['merchant'] = '提供商品或服务的商户、门店或商业品牌';

const PROFILE_MODEL_MAX_TOKENS: number = 3000;
const PROFILE_MODEL_PROMPT_CHAR_LIMIT: number = 12000;
const PROFILE_MODEL_MERGE_CHAR_LIMIT: number = 10000;

interface TemporalDayNode {
  date: string;
  event_ids: string[];
  summary: TemporalSummary;
}

interface TemporalWeekNode {
  week_id: string;
  start_date: string;
  end_date: string;
  event_ids: string[];
  summary: TemporalSummary;
  days: TemporalDayNode[];
}

interface TemporalDocument {
  month: string;
  event_ids: string[];
  summary: TemporalSummary;
  weeks: TemporalWeekNode[];
}

export function resolveQueryLimit(selectedLength: number, requestedLimit: number): number {
  return requestedLimit > 0 ? requestedLimit : selectedLength;
}

export function isQueryResultTruncated(selectedLength: number, requestedLimit: number): boolean {
  return requestedLimit > 0 && selectedLength > requestedLimit;
}

export class IndexService {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;
  private modelClient: DataPipelineModelClient;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage, modelClient: DataPipelineModelClient) {
    this.paths = paths;
    this.storage = storage;
    this.modelClient = modelClient;
  }

  async build(modelConfig: DataManagerModelConfig, progress?: DataManagerProgressCallback): Promise<IndexBuildResult> {
    this.paths.ensureBaseDirs();
    let statePaths = this.storage.findFiles(this.paths.outputsRoot, '.md.state.json');
    this.emitProgress(progress, '索引', `发现 ${statePaths.length} 个整理文件`, 0, Math.max(1, statePaths.length), 62);
    dataManagerInfo(`Index build start: stateFiles=${statePaths.length}, outputsRoot=${this.paths.outputsRoot}, modelEnabled=${modelConfig.enabled}`);
    if (statePaths.length === 0) {
      dataManagerWarn('Index build found no consolidated state files.');
    }
    let enrichment = this.currentEnrichment(modelConfig);
    let previousManifest = this.loadManifest();
    let previousEvents = this.loadEvents();
    let reuseAllowed = this.canReuseIndex(previousManifest, enrichment);
    let imageReferences = this.buildImageReferenceMap();
    let events: EventMap = {};
    let sources: SourceManifestMap = {};
    let reusedEvents = 0;
    let enrichedEventsCount = 0;
    let stateIndex = 0;
    for (let statePath of statePaths) {
      let relativePath = this.storage.relativePath(this.paths.outputsRoot, statePath);
      let content = this.storage.readText(statePath, '');
      let digest = this.storage.sha256Text(content);
      let indexPercent = 62 + Math.round(stateIndex * 22 / Math.max(1, statePaths.length));
      this.emitProgress(progress, '索引增强', `批量增强 ${relativePath}`, stateIndex, statePaths.length, indexPercent);
      let eventIds: string[] = [];
      let previousSource = previousManifest.sources ? previousManifest.sources[relativePath] : undefined;
      let canReuseSource = this.canReuseSource(previousSource, digest, previousEvents);
      if (reuseAllowed && canReuseSource && previousSource) {
        for (let eventId of previousSource.event_ids) {
          let reused = this.copyEvent(previousEvents[eventId]);
          reused.sources = eventSourceNames(reused.source_refs || [], relativePath);
          reused.image_paths = this.imagePathsForSourceRefs(reused.source_refs || [], imageReferences);
          reused.profile_domains = deriveProfileDomains(reused);
          events[reused.event_id] = reused;
          eventIds.push(reused.event_id);
        }
        reusedEvents += eventIds.length;
        dataManagerInfo(`Index source reused: relative=${relativePath}, events=${eventIds.length}`);
      } else {
        let baseEvents = this.baseEventsFromState(statePath, relativePath, imageReferences);
        dataManagerInfo(`Index source state: relative=${relativePath}, baseEvents=${baseEvents.length}`);
        let enrichedEvents = await this.modelClient.enrichEvents(baseEvents, modelConfig);
        for (let enriched of enrichedEvents) {
          enriched.profile_domains = deriveProfileDomains(enriched);
          events[enriched.event_id] = enriched;
          eventIds.push(enriched.event_id);
        }
        enrichedEventsCount += eventIds.length;
      }
      let sourceEntry: SourceManifestEntry = {
        sha256: digest,
        event_ids: eventIds
      };
      sources[relativePath] = sourceEntry;
      stateIndex++;
    }

    this.emitProgress(progress, '写入索引', '正在写入事件索引', 85, 100, 85);
    this.writeEventPartitions(events);
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'inverted', 'index.json'), this.buildInvertedDocument(events));
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'source', 'index.json'), this.buildSourceDocument(events));
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'domain', 'index.json'), this.buildDomainDocument(events));
    let previousEntity = this.storage.readJson<EntityDocument>(this.storage.join(this.paths.indexesRoot, 'entity', 'index.json'), this.emptyEntityDocument());
    let currentIds = Object.keys(events).sort();
    let previousIds = Object.keys(previousEvents).sort();
    let entityDocument = reuseAllowed && enrichedEventsCount === 0 && this.sameStringArrays(currentIds, previousIds) &&
      this.sameStringArrays(this.entityTypeList(previousEntity), ENTITY_TYPE_KEYS) ? previousEntity : await this.buildEntityDocument(events, modelConfig);
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'entity', 'index.json'), entityDocument);
    await this.writeTemporalDocuments(events, modelConfig, reuseAllowed);
    this.emitProgress(progress, '生成画像', '正在生成用户画像', 90, 100, 90);
    let profile = await this.buildProfileDocument(events, modelConfig, reuseAllowed, progress);
    dataManagerInfo(`Index profile built: eventCount=${profile.event_count}, claimCount=${profile.claim_count}`);
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'profile', 'state.json'), profile as Object);
    this.storage.writeTextAtomic(this.storage.join(this.paths.indexesRoot, 'profile', 'profile.md'), this.renderProfileMarkdown(profile));

    let manifest: IndexManifest = {
      generated_at: nowIsoLocal(),
      input_root: 'workflows/profile-consolidation/outputs',
      index_dir: 'workflows/profile-consolidation/indexes',
      run_root: 'workflows/runs',
      enrichment: enrichment,
      domains: DOMAIN_KEYS,
      entity_types: ENTITY_TYPE_KEYS,
      sources: sources,
      event_count: Object.keys(events).length,
      profile_generated_at: profile.generated_at,
      profile_claim_count: profile.claim_count,
      profile_domains: this.profileDomainCounts(profile)
    };
    this.storage.writeJsonAtomic(this.storage.join(this.paths.indexesRoot, 'manifest.json'), manifest);
    dataManagerInfo(`Index build done: events=${Object.keys(events).length}, reused=${reusedEvents}, enriched=${enrichedEventsCount}, manifest=${this.storage.join(this.paths.indexesRoot, 'manifest.json')}`);
    this.emitProgress(progress, '写入索引', '索引写入完成', 98, 100, 98);
    return {
      sourceFiles: statePaths.length,
      eventCount: Object.keys(events).length,
      profileClaimCount: profile.claim_count,
      updatedAt: profile.generated_at
    };
  }

  query(options: QueryOptions): QueryResult {
    let candidateIds = this.queryCandidateIds(options);
    let events = this.loadEventsByIds(candidateIds);
    return this.queryWithEvents(options, events);
  }

  queryWithEvents(options: QueryOptions, events: Record<string, IndexedEvent>): QueryResult {
    let ids = Object.keys(events);
    dataManagerInfo(`Index query: events=${ids.length}, keywords=${options.keywords.join(',')}, domains=${options.domains.join(',')}, limit=${options.limit}`);
    let matching: BooleanMap = {};
    ids.forEach((id: string) => matching[id] = true);

    if (options.date.length > 0) {
      ids.forEach((id: string) => matching[id] = matching[id] && events[id].event_date === options.date);
    } else if (options.month.length > 0) {
      ids.forEach((id: string) => matching[id] = matching[id] && events[id].event_date.startsWith(options.month + '-'));
    } else if (options.startDate.length > 0 || options.endDate.length > 0) {
      let lower = options.startDate.length > 0 ? options.startDate : '0000-01-01';
      let upper = options.endDate.length > 0 ? options.endDate : '9999-12-31';
      ids.forEach((id: string) => matching[id] = matching[id] && events[id].event_date >= lower && events[id].event_date <= upper);
    }

    if (options.keywords.length > 0) {
      let inverted = this.storage.readJson<InvertedDocument>(this.storage.join(this.paths.indexesRoot, 'inverted', 'index.json'), this.emptyInvertedDocument());
      let sourceDocument = this.storage.readJson<SourceDocument>(this.storage.join(this.paths.indexesRoot, 'source', 'index.json'), this.emptySourceDocument());
      let invertedPostings = inverted.postings || {};
      let sourcePostings = sourceDocument.postings || {};
      for (let keyword of options.keywords) {
        let contentIds = this.indexedTextMatchIds(keyword, events, invertedPostings, eventSearchText);
        let sourceIds = this.indexedTextMatchIds(keyword, events, sourcePostings, sourceSearchText);
        ids.forEach((id: string) => matching[id] = matching[id] && (contentIds[id] === true || sourceIds[id] === true));
      }
    }

    if (options.domains.length > 0) {
      let domainDocument = this.storage.readJson<DomainDocument>(this.storage.join(this.paths.indexesRoot, 'domain', 'index.json'), this.emptyDomainDocument());
      let postings = domainDocument.postings || {};
      let domainIds: BooleanMap = {};
      options.domains.forEach((domain: string) => {
        (postings[domain] || []).forEach((id: string) => domainIds[id] = true);
      });
      ids.forEach((id: string) => matching[id] = matching[id] && domainIds[id] === true);
    }

    if (options.entities.length > 0) {
      let entityIds = this.entityMatchIds(options.entities);
      ids.forEach((id: string) => matching[id] = matching[id] && entityIds[id] === true);
    }

    let selected = ids
      .filter((id: string) => matching[id])
      .map((id: string) => events[id])
      .sort((left: IndexedEvent, right: IndexedEvent) => {
        if (left.event_date !== right.event_date) {
          return right.event_date.localeCompare(left.event_date);
        }
        return right.event_id.localeCompare(left.event_id);
      });
    let limit = resolveQueryLimit(selected.length, options.limit);
    return {
      total_events: selected.length,
      events: selected.slice(0, limit).map((event: IndexedEvent) => publicEvent(event)),
      events_truncated: isQueryResultTruncated(selected.length, options.limit)
    };
  }

  loadProfileState(): ProfileState {
    return this.storage.readJson<ProfileState>(this.storage.join(this.paths.indexesRoot, 'profile', 'state.json'), this.emptyProfileState());
  }

  loadEvents(): EventMap {
    let result: EventMap = {};
    let eventDir = this.storage.join(this.paths.indexesRoot, 'events');
    this.storage.listDir(eventDir)
      .filter((name: string) => name.endsWith('.json'))
      .forEach((name: string) => {
        let partition = this.storage.readJson<EventPartition>(this.storage.join(eventDir, name), { month: '', events: [] });
        if (partition && Array.isArray(partition.events)) {
          partition.events.forEach((event: IndexedEvent) => {
            result[event.event_id] = event;
          });
        }
      });
    return result;
  }

  loadEventsByIds(eventIds: string[]): EventMap {
    let result: EventMap = {};
    let uniqueIds = stableUnique(eventIds);
    if (uniqueIds.length === 0) {
      return result;
    }
    let wanted: BooleanMap = {};
    uniqueIds.forEach((id: string) => wanted[id] = true);
    let eventDir = this.storage.join(this.paths.indexesRoot, 'events');
    let months = this.eventMonthsForIds(wanted);
    let loadedPartitions: BooleanMap = {};
    let partitionNames = months.length > 0 ? months.map((month: string) => month + '.json') :
      this.storage.listDir(eventDir).filter((name: string) => name.endsWith('.json'));
    partitionNames.forEach((name: string) => {
      loadedPartitions[name] = true;
      this.readWantedEventsFromPartition(this.storage.join(eventDir, name), wanted, result);
    });
    if (Object.keys(result).length < uniqueIds.length) {
      this.storage.listDir(eventDir)
        .filter((name: string) => name.endsWith('.json') && loadedPartitions[name] !== true)
        .forEach((name: string) => this.readWantedEventsFromPartition(this.storage.join(eventDir, name), wanted, result));
    }
    return result;
  }

  private queryCandidateIds(options: QueryOptions): string[] {
    let candidate: BooleanMap | null = null;
    let temporalIds = this.temporalCandidateIds(options);
    if (temporalIds !== null) {
      candidate = this.intersectCandidate(candidate, temporalIds);
    }

    if (options.keywords.length > 0) {
      let inverted = this.storage.readJson<InvertedDocument>(this.storage.join(this.paths.indexesRoot, 'inverted', 'index.json'), this.emptyInvertedDocument());
      let sourceDocument = this.storage.readJson<SourceDocument>(this.storage.join(this.paths.indexesRoot, 'source', 'index.json'), this.emptySourceDocument());
      let invertedPostings = inverted.postings || {};
      let sourcePostings = sourceDocument.postings || {};
      for (let keyword of options.keywords) {
        let keywordIds = this.keywordCandidateIds(keyword, invertedPostings, sourcePostings);
        if (keywordIds !== null) {
          candidate = this.intersectCandidate(candidate, keywordIds);
        }
      }
    }

    if (options.domains.length > 0) {
      let domainDocument = this.storage.readJson<DomainDocument>(this.storage.join(this.paths.indexesRoot, 'domain', 'index.json'), this.emptyDomainDocument());
      let postings = domainDocument.postings || {};
      let domainIds: BooleanMap = {};
      options.domains.forEach((domain: string) => {
        (postings[domain] || []).forEach((id: string) => domainIds[id] = true);
      });
      candidate = this.intersectCandidate(candidate, domainIds);
    }

    if (options.entities.length > 0) {
      candidate = this.intersectCandidate(candidate, this.entityMatchIds(options.entities));
    }

    if (candidate === null) {
      return this.allEventIds();
    }
    return Object.keys(candidate).filter((id: string) => candidate![id] === true).sort();
  }

  private keywordCandidateIds(keyword: string, invertedPostings: StringArrayMap, sourcePostings: StringArrayMap): BooleanMap | null {
    let contentIds = this.postingCandidateIds(keyword, invertedPostings);
    let sourceIds = this.postingCandidateIds(keyword, sourcePostings);
    if (contentIds === null && sourceIds === null) {
      return null;
    }
    return this.unionCandidates(contentIds, sourceIds);
  }

  private postingCandidateIds(keyword: string, postings: StringArrayMap): BooleanMap | null {
    let compactKeyword = normalizeLookupText(keyword);
    if (compactKeyword.length === 0) {
      return null;
    }
    let terms = indexTerms(compactKeyword);
    if (terms.length === 0) {
      return null;
    }
    let candidate: BooleanMap | null = null;
    terms.forEach((term: string) => {
      candidate = this.intersectCandidate(candidate, this.setFromIds(postings[term] || []));
    });
    return candidate === null ? {} : candidate;
  }

  private temporalCandidateIds(options: QueryOptions): BooleanMap | null {
    if (options.date.length === 0 && options.month.length === 0 && options.startDate.length === 0 && options.endDate.length === 0) {
      return null;
    }
    let documents = this.loadTemporalDocuments();
    if (Object.keys(documents).length === 0) {
      return null;
    }
    if (options.date.length > 0) {
      return this.setFromIds(this.eventIdsForDate(options.date, documents));
    }
    if (options.month.length > 0) {
      let document = documents[options.month];
      return this.setFromIds(document ? (document.event_ids || []) : []);
    }
    let lower = options.startDate.length > 0 ? options.startDate : '0000-01-01';
    let upper = options.endDate.length > 0 ? options.endDate : '9999-12-31';
    let ids: string[] = [];
    Object.keys(documents).sort().forEach((month: string) => {
      let document = documents[month];
      let days = this.temporalDays(document);
      if (days.length === 0) {
        if (this.monthOverlapsRange(month, lower, upper)) {
          ids = ids.concat(document.event_ids || []);
        }
        return;
      }
      days.forEach((day: TemporalDayNode) => {
        if (day.date >= lower && day.date <= upper) {
          ids = ids.concat(day.event_ids || []);
        }
      });
    });
    return this.setFromIds(ids);
  }

  private eventIdsForDate(date: string, documents: TemporalDocumentMap): string[] {
    let month = monthKeyFromDate(date);
    if (month.length === 0) {
      return [];
    }
    let document = documents[month];
    if (!document) {
      return [];
    }
    let ids: string[] = [];
    this.temporalDays(document).forEach((day: TemporalDayNode) => {
      if (day.date === date) {
        ids = ids.concat(day.event_ids || []);
      }
    });
    return ids;
  }

  private temporalDays(document: TemporalDocument): TemporalDayNode[] {
    let days: TemporalDayNode[] = [];
    (document.weeks || []).forEach((week: TemporalWeekNode) => {
      days = days.concat(week.days || []);
    });
    return days;
  }

  private monthOverlapsRange(month: string, lower: string, upper: string): boolean {
    let first = month + '-01';
    let last = this.monthLastDate(month);
    return first <= upper && last >= lower;
  }

  private allEventIds(): string[] {
    let documents = this.loadTemporalDocuments();
    let ids: string[] = [];
    Object.keys(documents).sort().forEach((month: string) => {
      ids = ids.concat(documents[month].event_ids || []);
    });
    ids = stableUnique(ids).sort();
    return ids.length > 0 ? ids : Object.keys(this.loadEvents()).sort();
  }

  private eventMonthsForIds(wanted: BooleanMap): string[] {
    let documents = this.loadTemporalDocuments();
    let months: string[] = [];
    Object.keys(documents).sort().forEach((month: string) => {
      let document = documents[month];
      for (let id of document.event_ids || []) {
        if (wanted[id] === true) {
          months.push(month);
          break;
        }
      }
    });
    return stableUnique(months).sort();
  }

  private readWantedEventsFromPartition(path: string, wanted: BooleanMap, out: EventMap): void {
    let partition = this.storage.readJson<EventPartition>(path, { month: '', events: [] });
    if (!partition || !Array.isArray(partition.events)) {
      return;
    }
    partition.events.forEach((event: IndexedEvent) => {
      if (wanted[event.event_id] === true) {
        out[event.event_id] = event;
      }
    });
  }

  private setFromIds(ids: string[]): BooleanMap {
    let result: BooleanMap = {};
    ids.forEach((id: string) => result[id] = true);
    return result;
  }

  private intersectCandidate(left: BooleanMap | null, right: BooleanMap): BooleanMap {
    if (left === null) {
      return this.setFromIds(Object.keys(right).filter((id: string) => right[id] === true));
    }
    let result: BooleanMap = {};
    Object.keys(left).forEach((id: string) => {
      if (left[id] === true && right[id] === true) {
        result[id] = true;
      }
    });
    return result;
  }

  private unionCandidates(left: BooleanMap | null, right: BooleanMap | null): BooleanMap {
    let result: BooleanMap = {};
    if (left !== null) {
      Object.keys(left).forEach((id: string) => {
        if (left[id] === true) {
          result[id] = true;
        }
      });
    }
    if (right !== null) {
      Object.keys(right).forEach((id: string) => {
        if (right[id] === true) {
          result[id] = true;
        }
      });
    }
    return result;
  }

  private currentEnrichment(modelConfig: DataManagerModelConfig): EnrichmentManifest {
    let enrichment: EnrichmentManifest = {
      mode: modelConfig.enabled ? 'model' : 'heuristic',
      base_url: modelConfig.baseUrl
    };
    return enrichment;
  }

  private loadManifest(): IndexManifest {
    return this.storage.readJson<IndexManifest>(this.storage.join(this.paths.indexesRoot, 'manifest.json'), this.emptyManifest());
  }

  private canReuseIndex(previousManifest: IndexManifest, enrichment: EnrichmentManifest): boolean {
    if (!previousManifest || !previousManifest.enrichment || !previousManifest.sources) {
      return false;
    }
    return previousManifest.input_root === 'workflows/profile-consolidation/outputs' &&
      previousManifest.index_dir === 'workflows/profile-consolidation/indexes' &&
      previousManifest.enrichment.mode === enrichment.mode &&
      previousManifest.enrichment.base_url === enrichment.base_url &&
      this.sameStringArrays(previousManifest.entity_types || [], ENTITY_TYPE_KEYS);
  }

  private canReuseSource(previousSource: SourceManifestEntry | undefined, digest: string, previousEvents: EventMap): boolean {
    if (!previousSource || previousSource.sha256 !== digest || !Array.isArray(previousSource.event_ids) || previousSource.event_ids.length === 0) {
      return false;
    }
    for (let eventId of previousSource.event_ids) {
      if (!previousEvents[eventId]) {
        return false;
      }
    }
    return true;
  }

  private sameStringArrays(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index++) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private copyEvent(event: IndexedEvent): IndexedEvent {
    let copied: IndexedEvent = {
      event_id: event.event_id,
      source_state_file: event.source_state_file,
      record_id: event.record_id,
      event_date: event.event_date,
      last_seen_date: event.last_seen_date,
      summary: event.summary,
      normalized_fact: event.normalized_fact,
      tags: (event.tags || []).slice(),
      source_refs: (event.source_refs || []).slice(),
      sources: (event.sources || []).slice(),
      image_paths: (event.image_paths || []).slice(),
      keywords: (event.keywords || []).slice(),
      domains: (event.domains || []).slice(),
      entity_mentions: (event.entity_mentions || []).slice(),
      enrichment_method: event.enrichment_method,
      entities: (event.entities || []).slice(),
      profile_domains: (event.profile_domains || []).slice()
    };
    return copied;
  }

  private baseEventsFromState(statePath: string, relativePath: string, imageReferences: StringArrayMap): IndexedEvent[] {
    let state = this.storage.readJson<ConsolidatedState>(statePath, this.emptyConsolidatedState());
    let events: IndexedEvent[] = [];
    if (!state || !Array.isArray(state.records)) {
      return events;
    }
    for (let record of state.records) {
      if (!this.isValidRecord(record)) {
        continue;
      }
      let eventId = `${relativePath}#${record.record_id}`;
      let eventDate = isIsoDate(record.first_seen_date) ? record.first_seen_date : '';
      if (eventDate.length === 0) {
        continue;
      }
      let lastSeenDate = isIsoDate(record.last_seen_date) ? record.last_seen_date : eventDate;
      events.push({
        event_id: eventId,
        source_state_file: relativePath,
        record_id: record.record_id,
        event_date: eventDate,
        last_seen_date: lastSeenDate,
        summary: normalizeFreeText(record.summary || record.normalized_fact),
        normalized_fact: normalizeFreeText(record.normalized_fact),
        tags: stableUnique(record.tags || []),
        source_refs: stableUnique(record.source_refs || []),
        sources: eventSourceNames(record.source_refs || [], relativePath),
        image_paths: this.imagePathsForSourceRefs(record.source_refs || [], imageReferences),
        keywords: [],
        domains: [],
        entity_mentions: [],
        enrichment_method: '',
        entities: [],
        profile_domains: []
      });
    }
    return events;
  }

  private buildImageReferenceMap(): StringArrayMap {
    let candidates: ImageReferenceCandidateMap = new Object() as ImageReferenceCandidateMap;
    this.storage.listDir(this.paths.workflowRunsRoot).forEach((runName: string) => {
      let summaryPath = this.storage.join(this.paths.workflowRunsRoot, runName, 'run_summary.json');
      if (!this.storage.exists(summaryPath)) {
        return;
      }
      let payload = this.storage.readJson<JsonMap>(summaryPath, new Object() as JsonMap);
      let stepsValue = payload['steps'];
      if (!stepsValue || typeof stepsValue !== 'object') {
        return;
      }
      let steps = stepsValue as Record<string, JsonMap>;
      Object.keys(steps).forEach((stepKey: string) => {
        let step = steps[stepKey];
        let outputValue = step['output'];
        if (!outputValue || typeof outputValue !== 'object') {
          return;
        }
        let output = outputValue as JsonMap;
        if (normalizeFreeText(output['tool_name']) !== 'vlm_qa' || normalizeFreeText(output['mode']) !== 'summary') {
          return;
        }
        let logRelative = this.pathAfterDirectory(output['daily_log_path'], 'daily-log');
        let imagePath = this.workflowImageRelativePath(output['image'], runName);
        let summary = this.summaryOutputText(output);
        if (logRelative.length === 0 || imagePath.length === 0 || summary.length === 0) {
          return;
        }
        if (!candidates[logRelative]) {
          candidates[logRelative] = [];
        }
        candidates[logRelative].push({
          summary: summary,
          image_path: imagePath,
          used: false
        });
      });
    });

    let imageReferences: StringArrayMap = new Object() as StringArrayMap;
    this.storage.listDir(this.paths.dailyLogRoot)
      .filter((day: string) => /^\d{4}-\d{2}-\d{2}$/.test(day))
      .forEach((day: string) => {
        let dayDir = this.storage.join(this.paths.dailyLogRoot, day);
        this.storage.listDir(dayDir)
          .filter((name: string) => name.endsWith('.md'))
          .forEach((fileName: string) => {
            let relative = day + '/' + fileName;
            let available = candidates[relative] || [];
            if (available.length === 0) {
              return;
            }
            let text = this.storage.readText(this.storage.join(dayDir, fileName), '');
            let body = text.indexOf('-->') >= 0 ? text.substring(text.indexOf('-->') + 3) : text;
            parseNumberedEntries(body).forEach((entry: NumberedEntry) => {
              let entryText = normalizeFreeText(entry.text);
              for (let candidate of available) {
                if (!candidate.used && candidate.summary === entryText) {
                  candidate.used = true;
                  imageReferences[relative + '#' + entry.index] = [candidate.image_path];
                  break;
                }
              }
            });
          });
      });
    return imageReferences;
  }

  private pathAfterDirectory(value: Object | string | number | boolean | null | undefined, directoryName: string): string {
    let normalized = normalizeFreeText(value).replace(/\\/g, '/');
    if (normalized.length === 0) {
      return '';
    }
    let parts = normalized.split('/').filter((part: string) => part.length > 0);
    let position = -1;
    for (let index = 0; index < parts.length; index++) {
      if (parts[index] === directoryName) {
        position = index;
      }
    }
    if (position < 0 || position >= parts.length - 1) {
      return '';
    }
    return parts.slice(position + 1).join('/');
  }

  private workflowImageRelativePath(value: Object | string | number | boolean | null | undefined, runName: string): string {
    let pathText = normalizeFreeText(value).replace(/\\/g, '/');
    if (pathText.length === 0) {
      return '';
    }
    let marker = '/' + runName + '/';
    if (pathText.indexOf(marker) >= 0) {
      let relative = 'runs/' + runName + '/' + pathText.split(marker)[1];
      return this.storage.exists(this.paths.fromDataManagerRelative(relative)) ? relative : '';
    }
    let workflowMarker = '/workflows/';
    if (pathText.indexOf(workflowMarker) >= 0) {
      let relative = pathText.split(workflowMarker)[1];
      return this.storage.exists(this.paths.fromDataManagerRelative(relative)) ? relative : '';
    }
    return '';
  }

  private summaryOutputText(output: JsonMap): string {
    let structured = output['structured_output'];
    if (structured && typeof structured === 'object') {
      let structuredMap = structured as JsonMap;
      let summary = normalizeFreeText(structuredMap['summary']);
      if (summary.length > 0) {
        return summary;
      }
    }
    return normalizeFreeText(output['response']);
  }

  private imagePathsForSourceRefs(sourceRefs: string[], imageReferences: StringArrayMap): string[] {
    let paths: string[] = [];
    sourceRefs.forEach((sourceRef: string) => {
      paths = paths.concat(imageReferences[sourceRef] || []);
    });
    return stableUnique(paths);
  }

  private isValidRecord(record: AggregatedRecord): boolean {
    return record && typeof record.record_id === 'number' &&
      normalizeFreeText(record.summary || record.normalized_fact).length > 0 &&
      normalizeFreeText(record.normalized_fact).length > 0;
  }

  private writeEventPartitions(events: EventMap): void {
    let partitions: EventGroupMap = {};
    Object.keys(events).forEach((eventId: string) => {
      let event = events[eventId];
      let month = monthKeyFromDate(event.event_date);
      if (month.length === 0) {
        return;
      }
      if (!partitions[month]) {
        partitions[month] = [];
      }
      partitions[month].push(event);
    });
    let desired: ObjectMap = {};
    Object.keys(partitions).sort().forEach((month: string) => {
      let monthEvents = partitions[month].sort((left: IndexedEvent, right: IndexedEvent) => {
        if (left.event_date !== right.event_date) {
          return left.event_date.localeCompare(right.event_date);
        }
        return left.event_id.localeCompare(right.event_id);
      });
      let partition: EventPartition = {
        month: month,
        events: monthEvents
      };
      desired[month + '.json'] = partition as Object;
    });
    this.storage.syncJsonDirectory(this.storage.join(this.paths.indexesRoot, 'events'), desired);
  }

  private buildInvertedDocument(events: EventMap): InvertedDocument {
    let postings: StringArrayMap = {};
    Object.keys(events).forEach((eventId: string) => {
      indexTerms(eventSearchText(events[eventId])).forEach((term: string) => {
        if (!postings[term]) {
          postings[term] = [];
        }
        postings[term].push(eventId);
      });
    });
    Object.keys(postings).forEach((term: string) => postings[term] = stableUnique(postings[term]).sort());
    let document: InvertedDocument = {
      normalization: 'lowercase compact text with adjacent CJK/alphanumeric bigram postings; one-character queries scan searchable text',
      postings: postings
    };
    return document;
  }

  private buildSourceDocument(events: EventMap): SourceDocument {
    let postings: StringArrayMap = {};
    let sources: StringArrayMap = {};
    Object.keys(events).forEach((eventId: string) => {
      let event = events[eventId];
      event.sources.forEach((source: string) => {
        if (!sources[source]) {
          sources[source] = [];
        }
        sources[source].push(eventId);
      });
      indexTerms(sourceSearchText(event)).forEach((term: string) => {
        if (!postings[term]) {
          postings[term] = [];
        }
        postings[term].push(eventId);
      });
    });
    Object.keys(postings).forEach((term: string) => postings[term] = stableUnique(postings[term]).sort());
    Object.keys(sources).forEach((source: string) => sources[source] = stableUnique(sources[source]).sort());
    let document: SourceDocument = {
      normalization: 'lowercase compact text with adjacent CJK/alphanumeric bigram postings; one-character queries scan searchable text',
      sources: sources,
      postings: postings
    };
    return document;
  }

  private buildDomainDocument(events: EventMap): DomainDocument {
    let postings: StringArrayMap = {};
    DOMAIN_KEYS.forEach((domain: string) => postings[domain] = []);
    Object.keys(events).sort().forEach((eventId: string) => {
      let domains = normalizeDomains(events[eventId].domains || []);
      if (domains.length === 0) {
        domains = ['other'];
      }
      domains.forEach((domain: string) => {
        if (!postings[domain]) {
          postings[domain] = [];
        }
        postings[domain].push(eventId);
      });
    });
    Object.keys(postings).forEach((domain: string) => postings[domain] = stableUnique(postings[domain]).sort());
    let document: DomainDocument = {
      domains: DOMAIN_DESCRIPTIONS,
      postings: postings
    };
    return document;
  }

  private async buildEntityDocument(events: EventMap, modelConfig: DataManagerModelConfig): Promise<EntityDocument> {
    let mentionsByType: Record<string, Record<string, EntityMention>> = {};
    ENTITY_TYPE_KEYS.forEach((type: string) => mentionsByType[type] = new Object() as Record<string, EntityMention>);
    Object.keys(events).forEach((eventId: string) => {
      let event = events[eventId];
      let mentions = normalizeEntityMentions(event.entity_mentions || []);
      event.entity_mentions = mentions;
      mentions.forEach((mention: EntityMention) => {
        let token = this.entityNameToken(mention.name);
        if (token.length === 0) {
          return;
        }
        let existing = mentionsByType[mention.type][token];
        if (!existing) {
          mentionsByType[mention.type][token] = {
            type: mention.type,
            name: mention.name,
            aliases: stableUnique(mention.aliases || [])
          };
        } else {
          existing.aliases = this.uniqueEntityNames(existing.aliases.concat(mention.aliases || []));
        }
      });
    });

    let assignments: StringMap = createStringMap();
    let entities: EntityDefinitionMap = {};
    for (let entityType of ENTITY_TYPE_KEYS) {
      let mentionMap = mentionsByType[entityType];
      let tokens = Object.keys(mentionMap);
      if (tokens.length === 0) {
        continue;
      }
      let sourceDisplay: StringMap = createStringMap();
      tokens.forEach((token: string) => {
        let mention = mentionMap[token];
        [mention.name].concat(mention.aliases || []).forEach((name: string) => {
          let nameToken = this.entityNameToken(name);
          if (nameToken.length > 0 && sourceDisplay[nameToken] === undefined) {
            sourceDisplay[nameToken] = normalizeEntityName(name);
          }
        });
      });

      let resolved = await this.modelClient.resolveEntities(entityType, tokens.map((token: string): EntityMention => mentionMap[token]), modelConfig);
      resolved.forEach((mention: EntityMention) => {
        let canonicalToken = this.entityNameToken(mention.name);
        if (sourceDisplay[canonicalToken] === undefined) {
          return;
        }
        let coveredTokens: string[] = [canonicalToken];
        (mention.aliases || []).forEach((alias: string) => {
          let aliasToken = this.entityNameToken(alias);
          if (sourceDisplay[aliasToken] !== undefined) {
            coveredTokens.push(aliasToken);
          }
        });
        coveredTokens = stableUnique(coveredTokens);
        let key = this.addEntityDefinition(entities, entityType, sourceDisplay[canonicalToken],
          coveredTokens.filter((token: string) => token !== canonicalToken).map((token: string) => sourceDisplay[token]));
        coveredTokens.forEach((token: string) => assignments[entityType + '\n' + token] = key);
      });

      tokens.forEach((token: string) => {
        let assignmentKey = entityType + '\n' + token;
        if (assignments[assignmentKey] === undefined) {
          assignments[assignmentKey] = this.addEntityDefinition(entities, entityType, mentionMap[token].name, []);
        }
      });
    }

    let aliasPostings: StringArrayMap = {};
    Object.keys(events).sort().forEach((eventId: string) => {
      let event = events[eventId];
      let mentions = normalizeEntityMentions(event.entity_mentions || []);
      let displayKeys: string[] = [];
      mentions.forEach((mention: EntityMention) => {
        let key = assignments[mention.type + '\n' + this.entityNameToken(mention.name)];
        let existing = key ? entities[key] : undefined;
        if (!existing) {
          return;
        }
        existing.event_ids = stableUnique((existing.event_ids || []).concat([eventId])).sort();
        displayKeys.push(key);
      });
      event.entities = stableUnique(displayKeys);
    });
    Object.keys(entities).forEach((key: string) => {
      let definition = entities[key];
      definition.event_ids = stableUnique(definition.event_ids || []).sort();
      if (definition.event_ids.length === 0) {
        return;
      }
      [definition.name].concat(definition.aliases || []).forEach((name: string) => {
        let lookup = entityLookupKey(definition.type, name);
        if (!aliasPostings[lookup]) {
          aliasPostings[lookup] = [];
        }
        aliasPostings[lookup].push(key);
      });
    });
    Object.keys(aliasPostings).forEach((key: string) => aliasPostings[key] = stableUnique(aliasPostings[key]).sort());
    let document: EntityDocument = {
      types: ENTITY_TYPE_KEYS,
      type_descriptions: ENTITY_TYPE_DESCRIPTIONS,
      entity_types: ENTITY_TYPE_KEYS,
      entities: this.nonEmptyEntityDefinitions(entities),
      alias_postings: aliasPostings
    };
    return document;
  }

  private addEntityDefinition(definitions: EntityDefinitionMap, entityType: string, name: string, aliases: string[]): string {
    let key = entityDisplayKey(entityType, name);
    let existing = definitions[key];
    if (!existing) {
      existing = {
        type: entityType,
        name: normalizeEntityName(name),
        aliases: [],
        event_ids: []
      };
      definitions[key] = existing;
    }
    existing.aliases = this.uniqueEntityNames((existing.aliases || []).concat(aliases))
      .filter((alias: string) => this.entityNameToken(alias) !== this.entityNameToken(existing.name));
    return key;
  }

  private nonEmptyEntityDefinitions(definitions: EntityDefinitionMap): EntityDefinitionMap {
    let result: EntityDefinitionMap = {};
    Object.keys(definitions).sort().forEach((key: string) => {
      if ((definitions[key].event_ids || []).length > 0) {
        result[key] = definitions[key];
      }
    });
    return result;
  }

  private uniqueEntityNames(values: string[]): string[] {
    let result: string[] = [];
    let seen: BooleanMap = {};
    values.forEach((value: string) => {
      let name = normalizeEntityName(value);
      let token = this.entityNameToken(name);
      if (name.length > 0 && token.length > 0 && !seen[token]) {
        seen[token] = true;
        result.push(name);
      }
    });
    return result;
  }

  private entityNameToken(value: string): string {
    return normalizeLookupText(normalizeEntityName(value));
  }

  private async writeTemporalDocuments(events: EventMap, modelConfig: DataManagerModelConfig, reuseAllowed: boolean): Promise<void> {
    let monthGroups: EventGroupMap = {};
    Object.keys(events).forEach((eventId: string) => {
      let event = events[eventId];
      let month = monthKeyFromDate(event.event_date);
      if (month.length === 0) {
        return;
      }
      if (!monthGroups[month]) {
        monthGroups[month] = [];
      }
      monthGroups[month].push(event);
    });
    let previousDocuments = reuseAllowed ? this.loadTemporalDocuments() : new Object() as TemporalDocumentMap;
    let desired: ObjectMap = {};
    for (let month of Object.keys(monthGroups).sort()) {
      let monthEvents = monthGroups[month].sort((left: IndexedEvent, right: IndexedEvent) => {
        if (left.event_date !== right.event_date) {
          return left.event_date.localeCompare(right.event_date);
        }
        return left.event_id.localeCompare(right.event_id);
      });
      let dayMap: EventGroupMap = {};
      monthEvents.forEach((event: IndexedEvent) => {
        if (!dayMap[event.event_date]) {
          dayMap[event.event_date] = [];
        }
        dayMap[event.event_date].push(event);
      });
      let previousDocument = previousDocuments[month];
      let previousDays: Record<string, TemporalDayNode> = {};
      let previousWeeks: Record<string, TemporalWeekNode> = {};
      if (previousDocument && Array.isArray(previousDocument.weeks)) {
        previousDocument.weeks.forEach((week: TemporalWeekNode) => {
          previousWeeks[week.week_id] = week;
          (week.days || []).forEach((day: TemporalDayNode) => previousDays[day.date] = day);
        });
      }
      let dayNodes: TemporalDayNode[] = [];
      for (let day of Object.keys(dayMap).sort()) {
        let dayEvents = dayMap[day];
        let dayInputHash = this.storage.sha256Text(dayEvents.map((event: IndexedEvent) => event.event_id + '\u001f' + event.summary + '\u001f' + event.normalized_fact).join('\u001e'));
        let dayNode: TemporalDayNode = {
          date: day,
          event_ids: dayEvents.map((event: IndexedEvent) => event.event_id),
          summary: await this.generateTemporalSummary('day',
            dayEvents.map((event: IndexedEvent) => event.summary || event.normalized_fact),
            dayEvents.length,
            dayInputHash,
            previousDays[day] ? previousDays[day].summary : undefined,
            modelConfig)
        };
        dayNodes.push(dayNode);
      }
      let weekMap: TemporalDayMap = {};
      dayNodes.forEach((node: TemporalDayNode) => {
        let day = node.date;
        let week = this.weekGroupKey(day);
        if (!weekMap[week]) {
          weekMap[week] = [];
        }
        weekMap[week].push(node);
      });
      let weekNodes: TemporalWeekNode[] = [];
      for (let week of Object.keys(weekMap).sort()) {
        let days = weekMap[week];
        let eventIds: string[] = [];
        days.forEach((node: TemporalDayNode) => {
          eventIds = eventIds.concat(node.event_ids || []);
        });
        let weekInputHash = this.storage.sha256Text(days.map((node: TemporalDayNode) => node.date + '\u001f' + node.summary.text + '\u001f' + (node.event_ids || []).join(',')).join('\u001e'));
        let weekNode: TemporalWeekNode = {
          week_id: week,
          start_date: this.weekStartDate(week, month),
          end_date: this.weekEndDate(week, month),
          event_ids: stableUnique(eventIds),
          summary: await this.generateTemporalSummary('week',
            days.map((node: TemporalDayNode) => node.summary.text),
            eventIds.length,
            weekInputHash,
            previousWeeks[week] ? previousWeeks[week].summary : undefined,
            modelConfig),
          days: days
        };
        weekNodes.push(weekNode);
      }
      let monthInputHash = this.storage.sha256Text(weekNodes.map((node: TemporalWeekNode) => node.week_id + '\u001f' + node.summary.text + '\u001f' + (node.event_ids || []).join(',')).join('\u001e'));
      let temporalDocument: TemporalDocument = {
        month: month,
        event_ids: monthEvents.map((event: IndexedEvent) => event.event_id),
        summary: await this.generateTemporalSummary('month',
          weekNodes.map((node: TemporalWeekNode) => node.summary.text),
          monthEvents.length,
          monthInputHash,
          previousDocument ? previousDocument.summary : undefined,
          modelConfig),
        weeks: weekNodes
      };
      desired[month + '.json'] = temporalDocument as Object;
    }
    this.storage.syncJsonDirectory(this.storage.join(this.paths.indexesRoot, 'temporal'), desired);
  }

  private loadTemporalDocuments(): TemporalDocumentMap {
    let result: TemporalDocumentMap = new Object() as TemporalDocumentMap;
    let temporalDir = this.storage.join(this.paths.indexesRoot, 'temporal');
    this.storage.listDir(temporalDir)
      .filter((name: string) => name.endsWith('.json'))
      .forEach((name: string) => {
        let document = this.storage.readJson<TemporalDocument>(this.storage.join(temporalDir, name), this.emptyTemporalDocument());
        if (document && document.month.length > 0) {
          result[document.month] = document;
        }
      });
    return result;
  }

  private async generateTemporalSummary(level: string, items: string[], eventCount: number, inputHash: string,
    previous: TemporalSummary | undefined, modelConfig: DataManagerModelConfig): Promise<TemporalSummary> {
    if (previous && previous.input_hash === inputHash && normalizeFreeText(previous.text).length > 0) {
      return previous;
    }
    let modelText = await this.modelClient.generateSummary(level, items, eventCount, modelConfig);
    if (modelText.length > 0) {
      return {
        text: modelText,
        input_hash: inputHash,
        generation: 'model'
      };
    }
    return this.heuristicSummary(level, items, eventCount, inputHash, modelConfig.enabled ? 'heuristic_fallback' : 'heuristic');
  }

  private async buildProfileDocument(events: EventMap, modelConfig: DataManagerModelConfig, reuseAllowed: boolean, progress?: DataManagerProgressCallback): Promise<ProfileState> {
    let byDomain: EventGroupMap = {};
    DOMAIN_KEYS.forEach((domain: string) => byDomain[domain] = []);
    Object.keys(events).forEach((eventId: string) => {
      let event = events[eventId];
      let domains = normalizeDomains(event.profile_domains || event.domains || []);
      if (domains.length === 0) {
        domains = ['other'];
      }
      domains.forEach((domain: string) => {
        if (!byDomain[domain]) {
          byDomain[domain] = [];
        }
        byDomain[domain].push(event);
      });
    });
    let previous = this.loadProfileState();
    let domainsState: ProfileDomainMap = {};
    let domainIndex = 0;
    for (let domain of DOMAIN_KEYS) {
      this.emitProgress(progress, '生成画像', `生成${displayDomainName(domain)}画像`, domainIndex, DOMAIN_KEYS.length, 90 + Math.round(domainIndex * 7 / Math.max(1, DOMAIN_KEYS.length)));
      let domainEvents = byDomain[domain] || [];
      domainEvents.sort((left: IndexedEvent, right: IndexedEvent) => {
        if (left.event_date !== right.event_date) {
          return left.event_date.localeCompare(right.event_date);
        }
        return left.event_id.localeCompare(right.event_id);
      });
      let previousClaims = previous.domains && previous.domains[domain] ? previous.domains[domain].claims : [];
      let eventIds = domainEvents.map((event: IndexedEvent) => event.event_id);
      let inputHash = this.profileDomainInputHash(domain, domainEvents, modelConfig);
      let previousDomain = previous.domains && previous.domains[domain] ? previous.domains[domain] : undefined;
      let domainState: ProfileDomainState;
      if (reuseAllowed && previousDomain && previousDomain.input_hash === inputHash && Array.isArray(previousDomain.claims)) {
        domainState = this.copyProfileDomain(previousDomain);
        domainState.event_ids = eventIds;
        domainState.event_count = eventIds.length;
        domainState.date_range = this.eventDateRange(domainEvents);
        dataManagerInfo(`Profile domain reused: domain=${domain}, events=${eventIds.length}, claims=${domainState.claims.length}`);
      } else if (domainEvents.length === 0) {
        domainState = {
          domain: domain,
          display_name: DOMAIN_DISPLAY_NAMES[domain] || domain,
          input_hash: inputHash,
          event_ids: [],
          event_count: 0,
          date_range: this.eventDateRange(domainEvents),
          summary: '',
          claims: [],
          generation: 'empty'
        };
      } else {
        let payload: ProfileModelPayload = await this.modelClient.generateProfile(domain, domainEvents, previousClaims, modelConfig);
        let claims = this.normalizeProfileClaims(payload.claims, domainEvents, domain);
        domainState = {
          domain: domain,
          display_name: DOMAIN_DISPLAY_NAMES[domain] || domain,
          input_hash: inputHash,
          event_ids: eventIds,
          event_count: domainEvents.length,
          date_range: this.eventDateRange(domainEvents),
          summary: normalizeFreeText(payload.summary),
          claims: claims,
          generation: modelConfig.enabled ? 'model' : 'heuristic'
        };
        if (domainState.summary.length === 0 && claims.length > 0) {
          domainState.summary = this.profileSummaryFromClaims(domain, claims);
        }
      }
      domainsState[domain] = domainState;
      domainIndex++;
    }
    let profile: ProfileState = {
      generated_at: nowIsoLocal(),
      event_count: Object.keys(events).length,
      event_date_range: this.eventDateRange(Object.keys(events).map((eventId: string) => events[eventId])),
      domains: domainsState,
      claim_count: 0
    };
    profile.claim_count = this.profileClaimCount(profile);
    return profile;
  }

  private emitProgress(progress: DataManagerProgressCallback | undefined, stage: string, message: string, current: number, total: number, percent: number): void {
    if (!progress) {
      return;
    }
    progress(createDataManagerProgress(stage, message, current, total, percent));
  }

  private profileDomainInputHash(domain: string, domainEvents: IndexedEvent[], modelConfig: DataManagerModelConfig): string {
    let parts: string[] = [
      domain,
      modelConfig.enabled ? 'model' : 'heuristic',
      modelConfig.enabled ? String(PROFILE_MODEL_MAX_TOKENS) : '0',
      modelConfig.enabled ? String(PROFILE_MODEL_PROMPT_CHAR_LIMIT) : '0',
      modelConfig.enabled ? String(PROFILE_MODEL_MERGE_CHAR_LIMIT) : '0'
    ];
    domainEvents.forEach((event: IndexedEvent) => {
      parts.push([
        event.event_id,
        event.event_date,
        summarizeText(event.summary, 220),
        summarizeText(event.normalized_fact, 260),
        (event.domains || []).join(','),
        (event.sources || []).slice(0, 3).join(','),
        (event.entities || []).slice(0, 8).join(','),
        (event.keywords || []).slice(0, 12).join(',')
      ].join('\u001f'));
    });
    return this.storage.sha256Text(parts.join('\u001e'));
  }

  private copyProfileDomain(domain: ProfileDomainState): ProfileDomainState {
    let range: StringMap = createStringMap();
    range.start_date = domain.date_range ? domain.date_range.start_date || '' : '';
    range.end_date = domain.date_range ? domain.date_range.end_date || '' : '';
    let copied: ProfileDomainState = {
      domain: domain.domain,
      display_name: domain.display_name,
      input_hash: domain.input_hash,
      event_ids: (domain.event_ids || []).slice(),
      event_count: domain.event_count,
      date_range: range,
      summary: domain.summary,
      claims: (domain.claims || []).map((claim: ProfileClaim): ProfileClaim => {
        let item: ProfileClaim = {
          statement: claim.statement,
          kind: claim.kind,
          confidence: claim.confidence,
          event_ids: (claim.event_ids || []).slice(),
          evidence_count: claim.evidence_count,
          start_date: claim.start_date,
          end_date: claim.end_date,
          example: claim.example
        };
        return item;
      }),
      generation: domain.generation
    };
    return copied;
  }

  private normalizeProfileClaims(rawClaims: RawProfileClaim[], domainEvents: IndexedEvent[], domain: string): ProfileClaim[] {
    let eventMap: EventMap = {};
    domainEvents.forEach((event: IndexedEvent) => eventMap[event.event_id] = event);
    let result: ProfileClaim[] = [];
    let seen: BooleanMap = {};
    for (let raw of rawClaims) {
      let statement = normalizeFreeText(raw.statement || raw.claim || raw.summary);
      if (statement.length === 0 || seen[normalizeLookupText(statement)]) {
        continue;
      }
      let ids = stableUnique(raw.event_ids || []).filter((id: string) => eventMap[id] !== undefined);
      if (ids.length === 0) {
        continue;
      }
      let evidenceEvents = ids.map((id: string) => eventMap[id]).filter((event: IndexedEvent) => event !== undefined);
      let dateRange = this.eventDateRange(evidenceEvents);
      let claim: ProfileClaim = {
        statement: statement,
        kind: this.normalizeProfileKind(raw.kind),
        confidence: this.normalizeConfidence(raw.confidence),
        event_ids: ids,
        evidence_count: ids.length,
        start_date: dateRange.start_date,
        end_date: dateRange.end_date,
        example: normalizeFreeText(raw.example) || (evidenceEvents.length > 0 ? evidenceEvents[evidenceEvents.length - 1].summary : '')
      };
      if (!this.isProfileClaimWorthy(claim, domain)) {
        continue;
      }
      result.push(claim);
      seen[normalizeLookupText(statement)] = true;
      if (result.length >= 8) {
        break;
      }
    }
    return result;
  }

  private normalizeProfileKind(value: string): string {
    let kind = normalizeFreeText(value);
    return ['preference', 'habit', 'topic', 'service', 'relation', 'place', 'observation'].indexOf(kind) >= 0 ? kind : 'observation';
  }

  private normalizeConfidence(value: string): string {
    let confidence = normalizeFreeText(value);
    return ['high', 'medium', 'low'].indexOf(confidence) >= 0 ? confidence : 'low';
  }

  private isProfileClaimWorthy(claim: ProfileClaim, domain: string): boolean {
    let statement = normalizeFreeText(claim.statement);
    if (statement.length === 0 || claim.evidence_count < 2) {
      return false;
    }
    if (this.looksLikeEventDetail(statement)) {
      return false;
    }
    if (domain !== 'other' && claim.kind === 'relation') {
      return false;
    }
    return true;
  }

  private looksLikeEventDetail(statement: string): boolean {
    if (/\d{4}年|\d{4}-\d{2}-\d{2}|\d{1,2}月\d{1,2}日|\d+(?:\.\d+)?元|¥\s*\d/.test(statement)) {
      return true;
    }
    let markers = ['订单状态', '实付', '下单时间', '当前页面', '记录显示', '分别为', '之前', '正在尝试', '这块'];
    for (let marker of markers) {
      if (statement.indexOf(marker) >= 0) {
        return true;
      }
    }
    return false;
  }

  private profileSummaryFromClaims(domain: string, claims: ProfileClaim[]): string {
    let statements = claims
      .map((claim: ProfileClaim) => normalizeFreeText(claim.statement).replace(/。$/g, ''))
      .filter((statement: string) => statement.length > 0);
    if (statements.length === 0) {
      return '';
    }
    return `${DOMAIN_DISPLAY_NAMES[domain] || domain}领域呈现出这些倾向：${statements.slice(0, 3).join('；')}。`;
  }

  private renderProfileMarkdown(profile: ProfileState): string {
    let range = profile.event_date_range || createStringMap();
    let startDate = normalizeFreeText(range.start_date) || '-';
    let endDate = normalizeFreeText(range.end_date) || '-';
    let lines: string[] = [
      '# 用户画像',
      '',
      `- 生成时间：${profile.generated_at || '-'}`,
      `- 覆盖事件：${profile.event_count} 条`,
      `- 时间范围：${startDate} ~ ${endDate}`,
      `- 画像条目：${profile.claim_count} 条`,
      ''
    ];
    DOMAIN_KEYS.forEach((domain: string) => {
      let doc = profile.domains[domain];
      lines.push(`## ${displayDomainName(domain)}`, '');
      if (!doc) {
        lines.push(`当前记录还不足以形成稳定的${displayDomainName(domain)}领域画像。`, '');
        return;
      }
      let summary = normalizeFreeText(doc.summary);
      if (summary.length > 0) {
        lines.push(summary, '');
      }
      if (doc.claims.length === 0) {
        if (summary.length === 0) {
          lines.push(`当前记录还不足以形成稳定的${displayDomainName(domain)}领域画像。`, '');
        }
      } else {
        doc.claims.forEach((claim: ProfileClaim) => {
          lines.push(`- ${claim.statement}`);
        });
        lines.push('');
      }
    });
    return lines.join('\n');
  }

  private indexedTextMatchIds(keyword: string, events: EventMap, postings: StringArrayMap, textGetter: (event: IndexedEvent) => string): BooleanMap {
    let compactKeyword = normalizeLookupText(keyword);
    let result: BooleanMap = {};
    if (compactKeyword.length === 0) {
      Object.keys(events).forEach((id: string) => result[id] = true);
      return result;
    }
    let terms = indexTerms(compactKeyword);
    if (terms.length === 0) {
      Object.keys(events).forEach((id: string) => {
        if (normalizeLookupText(textGetter(events[id])).indexOf(compactKeyword) >= 0) {
          result[id] = true;
        }
      });
      return result;
    }
    let candidate: BooleanMap | null = null;
    terms.forEach((term: string) => {
      let ids: BooleanMap = {};
      (postings[term] || []).forEach((id: string) => ids[id] = true);
      if (candidate === null) {
        candidate = ids;
      } else {
        Object.keys(candidate).forEach((id: string) => {
          candidate![id] = candidate![id] && ids[id] === true;
        });
      }
    });
    if (candidate === null) {
      return result;
    }
    Object.keys(candidate).forEach((id: string) => {
      if ((candidate as BooleanMap)[id] && events[id] &&
        normalizeLookupText(textGetter(events[id])).indexOf(compactKeyword) >= 0) {
        result[id] = true;
      }
    });
    return result;
  }

  private entityMatchIds(selectors: string[]): BooleanMap {
    let document = this.storage.readJson<EntityDocument>(this.storage.join(this.paths.indexesRoot, 'entity', 'index.json'), this.emptyEntityDocument());
    let entities = document.entities || {};
    let aliasPostings = document.alias_postings || {};
    let result: BooleanMap = {};
    selectors.forEach((selector: string) => {
      let parts = selector.split(':');
      if (parts.length < 2) {
        return;
      }
      let lookup = entityLookupKey(parts[0], parts.slice(1).join(':'));
      (aliasPostings[lookup] || []).forEach((entityKey: string) => {
        let definition = entities[entityKey];
        if (!definition) {
          return;
        }
        definition.event_ids.forEach((id: string) => result[id] = true);
      });
    });
    return result;
  }

  private heuristicSummary(level: string, items: string[], eventCount: number, inputHash: string, generation: string): TemporalSummary {
    let prefix = level === 'day' ? '当天' : (level === 'week' ? '本周' : '本月');
    let details = items.map((item: string) => summarizeText(item, 90)).filter((item: string) => item.length > 0).join('；');
    let text = `${prefix}共${eventCount}条事件：${details.length > 0 ? details : '无事件'}`;
    return {
      text: summarizeText(text, 360),
      input_hash: inputHash,
      generation: generation
    };
  }

  private weekGroupKey(day: string): string {
    let time = dateToTime(day);
    if (time <= 0) {
      return day;
    }
    let date = new Date(time);
    let weekday = date.getDay();
    let delta = weekday === 0 ? -6 : 1 - weekday;
    return new Date(time + delta * 86400000).toISOString().substring(0, 10);
  }

  private weekStartDate(weekStart: string, month: string): string {
    return weekStart < month + '-01' ? month + '-01' : weekStart;
  }

  private weekEndDate(weekStart: string, month: string): string {
    let start = dateToTime(weekStart);
    if (start <= 0) {
      return weekStart;
    }
    let end = new Date(start + 6 * 86400000).toISOString().substring(0, 10);
    let monthLast = this.monthLastDate(month);
    return end <= monthLast ? end : monthLast;
  }

  private monthLastDate(month: string): string {
    let first = dateToTime(month + '-01');
    if (first <= 0) {
      return month + '-31';
    }
    let date = new Date(first);
    let year = date.getUTCFullYear();
    let monthIndex = date.getUTCMonth();
    return new Date(Date.UTC(year, monthIndex + 1, 0)).toISOString().substring(0, 10);
  }

  private eventDateRange(events: IndexedEvent[]): StringMap {
    let dates = events.map((event: IndexedEvent) => event.event_date).filter((date: string) => isIsoDate(date)).sort();
    let range: StringMap = createStringMap();
    range['start_date'] = '';
    range['end_date'] = '';
    if (dates.length > 0) {
      range.start_date = dates[0];
      range.end_date = dates[dates.length - 1];
    }
    return range;
  }

  private profileClaimCount(profile: ProfileState): number {
    let count = 0;
    DOMAIN_KEYS.forEach((domain: string) => {
      let doc = profile.domains[domain];
      count += doc ? doc.claims.length : 0;
    });
    return count;
  }

  private profileDomainCounts(profile: ProfileState): NumberMap {
    let result: NumberMap = {};
    DOMAIN_KEYS.forEach((domain: string) => {
      result[domain] = profile.domains[domain] ? profile.domains[domain].claims.length : 0;
    });
    return result;
  }

  private emptyProfileState(): ProfileState {
    let domains: ProfileDomainMap = {};
    DOMAIN_KEYS.forEach((domain: string) => {
      let range: StringMap = createStringMap();
      range['start_date'] = '';
      range['end_date'] = '';
      let domainState: ProfileDomainState = {
        domain: domain,
        display_name: DOMAIN_DISPLAY_NAMES[domain] || domain,
        input_hash: '',
        event_ids: [],
        event_count: 0,
        date_range: range,
        summary: '',
        claims: [],
        generation: 'empty'
      };
      domains[domain] = domainState;
    });
    let eventRange: StringMap = createStringMap();
    eventRange['start_date'] = '';
    eventRange['end_date'] = '';
    return {
      generated_at: '',
      event_count: 0,
      event_date_range: eventRange,
      domains: domains,
      claim_count: 0
    };
  }

  private emptyManifest(): IndexManifest {
    let sources: SourceManifestMap = {};
    let enrichment: EnrichmentManifest = {
      mode: '',
      base_url: ''
    };
    let profileDomains: NumberMap = {};
    DOMAIN_KEYS.forEach((domain: string) => profileDomains[domain] = 0);
    let manifest: IndexManifest = {
      generated_at: '',
      input_root: '',
      index_dir: '',
      run_root: '',
      enrichment: enrichment,
      domains: [],
      entity_types: [],
      sources: sources,
      event_count: 0,
      profile_generated_at: '',
      profile_claim_count: 0,
      profile_domains: profileDomains
    };
    return manifest;
  }

  private emptyInvertedDocument(): InvertedDocument {
    let postings: StringArrayMap = {};
    let document: InvertedDocument = {
      normalization: '',
      postings: postings
    };
    return document;
  }

  private emptySourceDocument(): SourceDocument {
    let sources: StringArrayMap = {};
    let postings: StringArrayMap = {};
    let document: SourceDocument = {
      normalization: '',
      sources: sources,
      postings: postings
    };
    return document;
  }

  private emptyDomainDocument(): DomainDocument {
    let postings: StringArrayMap = {};
    DOMAIN_KEYS.forEach((domain: string) => postings[domain] = []);
    let document: DomainDocument = {
      domains: DOMAIN_DESCRIPTIONS,
      postings: postings
    };
    return document;
  }

  private emptyEntityDocument(): EntityDocument {
    let entities: EntityDefinitionMap = {};
    let aliasPostings: StringArrayMap = {};
    let document: EntityDocument = {
      types: ENTITY_TYPE_KEYS,
      type_descriptions: ENTITY_TYPE_DESCRIPTIONS,
      entity_types: ENTITY_TYPE_KEYS,
      entities: entities,
      alias_postings: aliasPostings
    };
    return document;
  }

  private entityTypeList(document: EntityDocument): string[] {
    return (document.types && document.types.length > 0) ? document.types : (document.entity_types || []);
  }

  private emptyTemporalDocument(): TemporalDocument {
    let summary: TemporalSummary = {
      text: '',
      input_hash: '',
      generation: ''
    };
    return {
      month: '',
      event_ids: [],
      summary: summary,
      weeks: []
    };
  }

  private emptyConsolidatedState(): ConsolidatedState {
    let dateRange: StringMap = createStringMap();
    let state: ConsolidatedState = {
      metadata: {
        source_date_range: dateRange,
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
    };
    return state;
  }
}

