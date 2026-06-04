import { JSON as ArkJSON } from '@kit.ArkTS';
import { CloudChatMessage, CloudModelClient } from '../utils/CloudModelClient';
import {
  DOMAIN_DESCRIPTIONS,
  DOMAIN_DISPLAY_NAMES,
  AggregatedRecord,
  CandidateFact,
  CollectionGroupState,
  DataManagerModelConfig,
  DedupDecision,
  EntityMention,
  IndexedEvent,
  JsonMap,
  NumberMap,
  ProfileClaim,
  ProfileModelPayload,
  RawProfileClaim,
  StringArrayMap,
  SourceEntry
} from './DataManagerTypes';
import {
  atomicizeCandidateFacts,
  deriveRuleDomains,
  deriveRuleEntities,
  deriveRuleKeywords,
  extractAmountTokens,
  heuristicSplit,
  normalizeDedupText,
  normalizeDomains,
  normalizeEntityMentions,
  normalizeFreeText,
  normalizeProfileShortSummary,
  normalizedSimilarityKey,
  normalizedTransactionSignature,
  profileShortSummaryFromText,
  selectCandidateRecords,
  sourceDisplayName,
  stableUnique,
  summarizeText
} from './DataManagerUtils';
import { dataManagerError, dataManagerInfo } from './DataManagerLog';

interface BatchSplitEntryPromptPayload {
  source_date: string;
  source_ref: string;
  file_name: string;
  entry_index: number;
  workflow_metadata: JsonMap;
  entry_text: string;
}

interface BatchSplitPromptPayload {
  entries: BatchSplitEntryPromptPayload[];
}

interface DedupCandidatePayload {
  summary: string;
  normalized_fact: string;
  event_date: string;
  tags: string[];
}

interface DedupExistingPayload {
  record_id: number;
  first_seen_date: string;
  last_seen_date: string;
  summary: string;
  normalized_fact: string;
  tags: string[];
}

interface DedupPromptPayload {
  candidate: DedupCandidatePayload;
  existing_records: DedupExistingPayload[];
}

interface EventPromptPayload {
  summary: string;
  normalized_fact: string;
}

interface SummaryPromptPayload {
  level: string;
  event_count: number;
  items: string[];
}

interface BatchEventPromptPayload {
  event_id: string;
  summary: string;
  normalized_fact: string;
}

interface BatchEnrichPromptPayload {
  events: BatchEventPromptPayload[];
}

interface ProfileEventPromptPayload {
  event_id: string;
  date: string;
  summary: string;
  sources: string[];
  entities: string[];
  keywords: string[];
  normalized_fact?: string;
  domains?: string[];
}

interface ProfileChunkPayload {
  index: number;
  count: number;
}

interface ProfilePromptPayload {
  domain: string;
  domain_description: string;
  event_count: number;
  included_event_count: number;
  events: ProfileEventPromptPayload[];
  previous_claims: ProfileClaim[];
  selection_note: string;
  chunk?: ProfileChunkPayload;
}

interface ProfileMergePromptPayload {
  domain: string;
  domain_description: string;
  round: number;
  candidate_claims: RawProfileClaim[];
  previous_claims: ProfileClaim[];
  batch?: ProfileChunkPayload;
}

interface ProfileMergeResult {
  short_summary: string;
  claims: RawProfileClaim[];
}

interface EntityResolutionPromptPayload {
  type: string;
  mentions: EntityMention[];
}

interface CollectionPlannerEventPromptPayload {
  event_id: string;
  date: string;
  summary: string;
  normalized_fact: string;
  source: string;
  domains: string[];
  entities: string[];
  keywords: string[];
}

interface CollectionPlannerPromptPayload {
  tab_id: string;
  title: string;
  events: CollectionPlannerEventPromptPayload[];
}

interface CollectionPlannerMergeGroupPromptPayload {
  group_id: string;
  title: string;
  source: string;
  domain: string;
  event_count: number;
  event_ids: string[];
}

interface CollectionPlannerMergePromptPayload {
  tab_id: string;
  title: string;
  groups: CollectionPlannerMergeGroupPromptPayload[];
}

const BATCH_FACT_SPLIT_SYSTEM_PROMPT: string =
  '你是一个日志整理助手。你会批量处理 daily-log entries，把每条 entry 拆分成 1 到多个可去重事实。' +
  '输入包含 entries，每条都有 source_ref/source_date/file_name/entry_index/workflow_metadata/entry_text。返回严格 JSON：' +
  '{"items":[{"source_ref":"原样返回","facts":[{"summary":"一句话摘要","normalized_fact":"适合长期画像沉淀的整理后表述","event_date":"YYYY-MM-DD 或空字符串","tags":["标签1"],"model_notes":"简短说明"}]}]}。' +
  '必须为每个输入 source_ref 返回一个 item。订单、账单、交易、消费记录必须保留商家、商品/服务、金额、时间、状态等关键细节。不要输出 markdown。';

const DEDUP_SYSTEM_PROMPT: string =
  '你是一个日志去重助手。比较一条候选事实和若干历史记录，判断它是否应该新增、重复、合并或跳过。' +
  '返回严格 JSON：{"decision":"new | duplicate | merge_with_existing | skip_ambiguous","matched_record_ids":[1],"reason":"简短理由","merged_summary":"","merged_fact":"","merged_tags":["标签1"]}。' +
  'matched_record_ids 最多返回一个最相关历史记录。不要把多笔账单或多段聊天合并成一个大记录。不要输出 markdown。';

const ENRICH_SYSTEM_PROMPT: string =
  '你是本地个人数据索引助手。请为事件提取关键词、领域和实体。返回严格 JSON：' +
  '{"keywords":["关键词"],"domains":["eat|wear|live|travel|work|other"],"entities":[{"type":"person|place|merchant","name":"名称","aliases":["别名"]}]}。' +
  'domains 可多选；实体只抽取现实联系人、地点、商户。不要输出 markdown。';

const BATCH_ENRICH_SYSTEM_PROMPT: string =
  '你是本地个人数据索引助手。请批量为事件提取关键词、领域和实体。输入包含 events，每条都有 event_id/summary/normalized_fact。' +
  '返回严格 JSON：{"events":[{"event_id":"原样返回","keywords":["关键词"],"domains":["eat|wear|live|travel|work|other"],"entities":[{"type":"person|place|merchant","name":"名称","aliases":["别名"]}]}]}。' +
  '必须为每个输入 event_id 返回一个结果。domains 可多选；实体只抽取现实联系人、地点、商户。不要输出 markdown。';

const ENTITY_RESOLUTION_SYSTEM_PROMPT: string =
  '你是个人事件实体归并助手。输入是同一种类别下、从不同事件提取出的实体候选。' +
  '将明确指向同一现实对象的候选合并，以便跨来源查询；仅在证据充分时合并，不要因名称相近而猜测。' +
  '返回严格 JSON：{"entities":[{"name":"规范显示名","aliases":["同一对象的其他候选名称"]}]}。' +
  '输出名称和别名必须来自输入候选，不要补充输入中不存在的名称，不要输出 markdown 或解释。';

const SUMMARY_SYSTEM_PROMPT: string =
  '你是个人事件摘要助手。根据输入的一组事件或下级摘要，生成简短、可检索的中文概括。' +
  '只返回严格 JSON：{"summary":"摘要文本"}。' +
  '摘要应陈述事实，不猜测，不遗漏主要活动类型，不输出 markdown。' +
  'summary 最多 160 个汉字，只概括主要活动类型和显著事件，不要逐条复述输入。';

const PROFILE_SYSTEM_PROMPT: string =
  '你是用户画像总结助手。输入是一组同一领域的个人事件，以及上一版该领域画像结论。' +
  '请归并历史画像并基于当前事件证据生成适合 App 前端展示的凝练用户画像，返回严格 JSON：' +
  '{"short_summary":"严格4个中文字符的首页摘要","summary":"该领域 1-2 句话的高层画像总结","claims":[{"statement":"一条短 insight，不要逐条复述事实","kind":"preference|habit|topic|service|relation|place|observation","confidence":"high|medium|low","event_ids":["支持该结论的输入事件 id"],"example":"一个最能说明该结论的事件摘要"}]}。' +
  'short_summary 必须严格为 4 个中文字符，像“清淡轻食”“简约舒适”“整洁有序”“地铁通勤”，不要标点、空格、数字或解释。summary 应像产品中的个人画像卡片，概括整体倾向，不要列举订单、聊天或浏览事实。' +
  'claims 只保留 2 到 5 条高层 insight，可以描述偏好、习惯、近期关注话题、常用服务/商户、稳定联系人或地点，但每条必须由至少 2 条输入事件直接支持。' +
  '不要推断职业、收入、性格、身份等事件没有证明的信息。证据少或只出现一次时，使用“最近出现”“曾记录”等保守表述；只有多条独立事件支持时才使用“经常”“偏好”“常用”等强表述。' +
  '合并上一版画像时，只保留仍有当前事件证据支持的结论；相近结论应合并，不要重复输出。event_ids 必须来自输入事件，不要编造 id；每条结论至少包含 1 个 event_id。' +
  '每个领域最多输出 5 条高价值结论；没有足够证据时返回空 summary 和空 claims。不要在 summary 或 statement 中写金额、订单状态、具体日期、证据数量或“事件 id”；这些细节只用于内部证据。' +
  '不要把单次转账、单次订单、单次 PR、单次浏览记录写成画像；它们只能作为证据，不是画像本身。' +
  'relation 类 insight 只适合 other 领域；吃、穿、住、行、办公领域不要输出联系人关系画像。不要硬编码任何品牌、应用、群聊、支付、金融或测试数据词；只依据输入事件内容归纳。不要输出 markdown。';

const PROFILE_MERGE_SYSTEM_PROMPT: string =
  '你是用户画像归并助手。输入是同一领域内多个分块已经生成的候选画像结论，以及上一版该领域画像结论。' +
  '请去重、合并相近含义，并输出适合 App 前端展示的最终用户画像，返回严格 JSON：' +
  '{"short_summary":"严格4个中文字符的首页摘要","summary":"该领域 1-2 句话的高层画像总结","claims":[{"statement":"一条短 insight，不要逐条复述事实","kind":"preference|habit|topic|service|relation|place|observation","confidence":"high|medium|low","event_ids":["支持该结论的输入事件 id"],"example":"一个最能说明该结论的事件摘要"}]}。' +
  '只能基于 candidate_claims 和 previous_claims 中已有信息归并，不要创造新的品牌、实体、话题或事件 id。' +
  'claims 只保留 2 到 5 条高层 insight；相近结论必须合并，单次事件陈述不能作为画像。' +
  '每条结论必须至少由 2 个 event_ids 支持；event_ids 必须来自输入候选结论。合并上一版画像时，只保留仍被候选结论支持的内容。' +
  'short_summary 必须严格为 4 个中文字符，不要标点、空格、数字或解释。不要在 summary 或 statement 中写金额、订单状态、具体日期、证据数量或“事件 id”。relation 类 insight 只适合 other 领域；吃、穿、住、行、办公领域不要输出联系人关系画像。不要输出 markdown 或解释。';

const PROFILE_MODEL_PROMPT_CHAR_LIMIT: number = 12000;
const PROFILE_MODEL_MERGE_CHAR_LIMIT: number = 10000;
const PROFILE_MODEL_MERGE_ROUND_LIMIT: number = 4;

const COLLECTION_GROUPING_SYSTEM_PROMPT: string =
  '你是 App 采集页的 Planner。请把检索回来的事件组织成适合手机列表展示的少量分组。分组应来自事件本身的语义相近性、上下文连续性、联系人/商户/来源、用户意图或主题，而不是来自固定模板。' +
  '返回严格 JSON：{"groups":[{"title":"短标题，14字以内","source":"主要来源","domain":"eat|wear|live|travel|work|other","event_ids":["输入中的事件id"]}]}。' +
  '每个事件 id 只能出现一次；只能使用输入中存在的 event_id；不要逐条复述事件；尽量把同一联系人、商户、主题、通知来源或兴趣内容放在同一组；分组数量通常 3 到 8 个，最多 12 个。' +
  '标题必须有信息量，尽量表达“对象/来源 + 主题/意图/状态”。聊天 tab 必须按语义接近和上下文连贯性分组，输入事件顺序就是对话线索；不要按日期、单条截图、平台名或泛泛的“聊天记录/工作记录”切组。' +
  '避免低信息标题：平台名、纯数字、日期时间、单个技术词、单个截图/图片/贴图/表情包等界面元素、或“微信聊天记录”“工作相关聊天记录”“聊天记录”“通知记录”“视频记录”“订单记录”这类泛称。不要输出 markdown。';

const COLLECTION_GROUP_MERGE_SYSTEM_PROMPT: string =
  '你是 App 采集页的 Planner。输入是已经分批生成的临时分组，请把相同主题、联系人、商户、来源或兴趣方向的分组合并成更少的列表分组。' +
  '返回严格 JSON：{"groups":[{"title":"短标题，14字以内","source":"主要来源","domain":"eat|wear|live|travel|work|other","group_ids":["输入中的临时分组id"]}]}。' +
  '每个 group_id 最多出现一次；只能使用输入中存在的 group_id；分组数量最多 12 个。合并后的标题必须保留具体对象/来源和主题/意图，避免平台名、日期、纯数字、单个技术词或界面元素等低信息标题。不要输出 markdown。';

export class DataPipelineModelClient {
  private cloudClient: CloudModelClient = new CloudModelClient();

  async splitEntryIntoFacts(entry: SourceEntry, config: DataManagerModelConfig): Promise<CandidateFact[]> {
    let batch = await this.splitEntriesIntoFacts([entry], config);
    return batch[entry.source_ref] || heuristicSplit(entry);
  }

  async splitEntriesIntoFacts(entries: SourceEntry[], config: DataManagerModelConfig): Promise<Record<string, CandidateFact[]>> {
    let result: Record<string, CandidateFact[]> = {};
    entries.forEach((entry: SourceEntry) => {
      result[entry.source_ref] = heuristicSplit(entry);
    });
    if (!this.isEnabled(config) || entries.length === 0) {
      return result;
    }
    let chunks = this.chunkSourceEntries(entries, 12);
    for (let chunk of chunks) {
      let entryMap: Record<string, SourceEntry> = {};
      let promptEntries: BatchSplitEntryPromptPayload[] = chunk.map((entry: SourceEntry): BatchSplitEntryPromptPayload => {
        entryMap[entry.source_ref] = entry;
        let item: BatchSplitEntryPromptPayload = {
          source_date: entry.source_date,
          source_ref: entry.source_ref,
          file_name: entry.file_name,
          entry_index: entry.entry_index,
          workflow_metadata: entry.workflow_metadata,
          entry_text: entry.entry_text
        };
        return item;
      });
      let promptPayload: BatchSplitPromptPayload = {
        entries: promptEntries
      };
      try {
        dataManagerInfo(`Batch split request: entries=${chunk.length}`);
        let payload = await this.callJson(config, BATCH_FACT_SPLIT_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
        let rawItems = Array.isArray(payload['items']) ? payload['items'] as JsonMap[] : [];
        rawItems.forEach((rawItem: JsonMap) => {
          let sourceRef = normalizeFreeText(rawItem['source_ref']);
          let entry = entryMap[sourceRef];
          if (!entry) {
            return;
          }
          let rawFacts = Array.isArray(rawItem['facts']) ? rawItem['facts'] as JsonMap[] : [];
          let facts = this.normalizeFactPayloads(rawFacts, entry, 'model_batch_split');
          result[sourceRef] = facts.length > 0 ? facts : heuristicSplit(entry);
        });
      } catch (e) {
        let err = e as Error;
        dataManagerError('Batch split fallback: ' + err.message);
      }
    }
    return result;
  }

  async decideDedup(fact: CandidateFact, records: AggregatedRecord[], config: DataManagerModelConfig, dedupWindow: number): Promise<DedupDecision> {
    let candidates = selectCandidateRecords(records, fact, dedupWindow);
    if (candidates.length === 0 || !this.isEnabled(config)) {
      return candidates.length === 0 ? this.newDecision('no_recent_records') : this.heuristicDedupDecision(fact, candidates, 'model_disabled');
    }
    let existingRecords: DedupExistingPayload[] = candidates.map((record: AggregatedRecord): DedupExistingPayload => {
      let item: DedupExistingPayload = {
        record_id: record.record_id,
        first_seen_date: record.first_seen_date,
        last_seen_date: record.last_seen_date,
        summary: record.summary,
        normalized_fact: record.normalized_fact,
        tags: record.tags
      };
      return item;
    });
    let promptPayload: DedupPromptPayload = {
      candidate: {
        summary: fact.summary,
        normalized_fact: fact.normalized_fact,
        event_date: fact.event_date,
        tags: fact.tags
      },
      existing_records: existingRecords
    };
    let prompt = ArkJSON.stringify(promptPayload, null, 2);
    try {
      let payload = await this.callJson(config, DEDUP_SYSTEM_PROMPT, prompt);
      let decision = normalizeFreeText(payload['decision']);
      if (['new', 'duplicate', 'merge_with_existing', 'skip_ambiguous'].indexOf(decision) < 0) {
        decision = 'new';
      }
      let result: DedupDecision = {
        decision: decision,
        matched_record_ids: this.normalizeNumberArray(payload['matched_record_ids']),
        reason: normalizeFreeText(payload['reason']) || 'model_dedup',
        merged_summary: normalizeFreeText(payload['merged_summary']),
        merged_fact: normalizeFreeText(payload['merged_fact']),
        merged_tags: this.normalizeStringArray(payload['merged_tags'])
      };
      return result;
    } catch (e) {
      return this.heuristicDedupDecision(fact, candidates, 'model_dedup_fallback');
    }
  }

  async enrichEvent(event: IndexedEvent, config: DataManagerModelConfig): Promise<IndexedEvent> {
    let enriched: IndexedEvent = this.heuristicEnrichEvent(event, 'heuristic');
    if (!this.isEnabled(config)) {
      return enriched;
    }
    let eventPayload: EventPromptPayload = {
      summary: event.summary,
      normalized_fact: event.normalized_fact
    };
    let prompt = ArkJSON.stringify(eventPayload, null, 2);
    try {
      let payload = await this.callJson(config, ENRICH_SYSTEM_PROMPT, prompt);
      return this.enrichEventFromPayload(event, payload, 'model');
    } catch (e) {
      enriched.enrichment_method = 'heuristic_fallback';
      return enriched;
    }
  }

  async enrichEvents(events: IndexedEvent[], config: DataManagerModelConfig): Promise<IndexedEvent[]> {
    let result: Record<string, IndexedEvent> = {};
    events.forEach((event: IndexedEvent) => {
      result[event.event_id] = this.heuristicEnrichEvent(event, this.isEnabled(config) ? 'heuristic_batch_fallback' : 'heuristic');
    });
    if (!this.isEnabled(config) || events.length === 0) {
      return events.map((event: IndexedEvent) => result[event.event_id]);
    }
    let chunks = this.chunkEvents(events, 16);
    for (let chunk of chunks) {
      let eventMap: Record<string, IndexedEvent> = {};
      let promptEvents: BatchEventPromptPayload[] = chunk.map((event: IndexedEvent): BatchEventPromptPayload => {
        eventMap[event.event_id] = event;
        let item: BatchEventPromptPayload = {
          event_id: event.event_id,
          summary: event.summary,
          normalized_fact: event.normalized_fact
        };
        return item;
      });
      let promptPayload: BatchEnrichPromptPayload = {
        events: promptEvents
      };
      try {
        dataManagerInfo(`Batch enrich request: events=${chunk.length}`);
        let payload = await this.callJson(config, BATCH_ENRICH_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
        let rawEvents = Array.isArray(payload['events']) ? payload['events'] as JsonMap[] : [];
        rawEvents.forEach((rawEvent: JsonMap) => {
          let eventId = normalizeFreeText(rawEvent['event_id']);
          let event = eventMap[eventId];
          if (!event) {
            return;
          }
          result[eventId] = this.enrichEventFromPayload(event, rawEvent, 'model_batch');
        });
      } catch (e) {
        let err = e as Error;
        dataManagerError('Batch enrich fallback: ' + err.message);
      }
    }
    return events.map((event: IndexedEvent) => result[event.event_id]);
  }

  async generateSummary(level: string, items: string[], eventCount: number, config: DataManagerModelConfig): Promise<string> {
    if (!this.isEnabled(config)) {
      return '';
    }
    let promptPayload: SummaryPromptPayload = {
      level: level,
      event_count: eventCount,
      items: items.map((item: string) => summarizeText(item, 280))
    };
    try {
      let payload = await this.callJson(config, SUMMARY_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload));
      return normalizeFreeText(payload['summary']);
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Summary fallback: level=${level}, error=${err.message}`);
      return '';
    }
  }

  async resolveEntities(entityType: string, mentions: EntityMention[], config: DataManagerModelConfig): Promise<EntityMention[]> {
    if (!this.isEnabled(config) || mentions.length === 0) {
      return [];
    }
    let promptPayload: EntityResolutionPromptPayload = {
      type: entityType,
      mentions: mentions
    };
    try {
      let payload = await this.callJson(config, ENTITY_RESOLUTION_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
      let rawEntities = Array.isArray(payload['entities']) ? payload['entities'] as JsonMap[] : [];
      let resolved: EntityMention[] = [];
      rawEntities.forEach((raw: JsonMap) => {
        let name = normalizeFreeText(raw['name']);
        if (name.length === 0) {
          return;
        }
        let mention: EntityMention = {
          type: entityType,
          name: name,
          aliases: this.normalizeStringArray(raw['aliases'])
        };
        resolved.push(mention);
      });
      return normalizeEntityMentions(resolved);
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Entity resolution fallback: type=${entityType}, error=${err.message}`);
      return [];
    }
  }

  async generateProfile(domain: string, events: IndexedEvent[], previousClaims: ProfileClaim[], config: DataManagerModelConfig): Promise<ProfileModelPayload> {
    if (!this.isEnabled(config) || events.length === 0) {
      return this.heuristicProfile(domain, events);
    }
    try {
      let promptPayloads = this.profileModelPromptChunks(domain, events, previousClaims);
      if (promptPayloads.length === 1) {
        let payload = await this.callJson(config, PROFILE_SYSTEM_PROMPT, this.profilePromptText(promptPayloads[0]));
        let parsed = this.normalizeProfilePayload(payload);
        let claims = this.normalizeGeneratedProfileClaims(parsed.claims, events, domain, 8);
        if (claims.length === 0) {
          return this.heuristicProfile(domain, events);
        }
        let summary = this.profileSummaryFromRawClaims(domain, claims);
        return {
          short_summary: this.profileShortSummary(domain, parsed.short_summary, summary, claims, events),
          summary: summary,
          claims: claims
        };
      }
      let candidateClaims: RawProfileClaim[] = [];
      for (let promptPayload of promptPayloads) {
        let payload = await this.callJson(config, PROFILE_SYSTEM_PROMPT, this.profilePromptText(promptPayload));
        let parsed = this.normalizeProfilePayload(payload);
        candidateClaims = candidateClaims.concat(this.normalizeGeneratedProfileClaims(parsed.claims, events, domain, 8));
      }
      let merged = await this.mergeProfileClaimsWithModel(domain, candidateClaims, previousClaims, events, config);
      if (merged.claims.length === 0) {
        return this.heuristicProfile(domain, events);
      }
      let summary = this.profileSummaryFromRawClaims(domain, merged.claims);
      return {
        short_summary: this.profileShortSummary(domain, merged.short_summary, summary, merged.claims, events),
        summary: summary,
        claims: merged.claims
      };
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Profile fallback: domain=${domain}, error=${err.message}`);
      return this.heuristicProfile(domain, events);
    }
  }

  async planCollectionGroups(tabId: string, title: string, events: IndexedEvent[], config: DataManagerModelConfig): Promise<CollectionGroupState[]> {
    if (!this.isEnabled(config) || events.length === 0) {
      return [];
    }
    let planningEvents = this.collectionPlanningEvents(tabId, events);
    let chunks = this.chunkEvents(planningEvents, 80);
    let plannedGroups: CollectionGroupState[] = [];
    let chunkIndex = 0;
    for (let chunk of chunks) {
      try {
        dataManagerInfo(`Collection planner request: tab=${tabId}, chunk=${chunkIndex + 1}/${chunks.length}, events=${chunk.length}`);
        let groups = await this.planCollectionGroupChunk(tabId, title, chunk, config, 'chunk' + chunkIndex);
        plannedGroups = plannedGroups.concat(groups);
      } catch (e) {
        let err = e as Error;
        dataManagerError(`Collection planner chunk failed: tab=${tabId}, chunk=${chunkIndex}, error=${err.message}`);
      }
      chunkIndex++;
    }
    if (plannedGroups.length === 0) {
      return [];
    }
    if (chunks.length <= 1) {
      return plannedGroups;
    }
    try {
      dataManagerInfo(`Collection planner merge request: tab=${tabId}, groups=${plannedGroups.length}`);
      return await this.mergeCollectionGroups(tabId, title, plannedGroups, config);
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Collection planner merge fallback: tab=${tabId}, error=${err.message}`);
      return plannedGroups;
    }
  }

  private async planCollectionGroupChunk(tabId: string, title: string, events: IndexedEvent[], config: DataManagerModelConfig, idPrefix: string): Promise<CollectionGroupState[]> {
    let promptEvents: CollectionPlannerEventPromptPayload[] = events.map((event: IndexedEvent): CollectionPlannerEventPromptPayload => {
      let item: CollectionPlannerEventPromptPayload = {
        event_id: event.event_id,
        date: event.event_date,
        summary: summarizeText(event.summary || event.normalized_fact, 120),
        normalized_fact: summarizeText(event.normalized_fact || event.summary, 180),
        source: event.sources.length > 0 ? event.sources.join('、') : sourceDisplayName(event.source_state_file),
        domains: (event.domains || []).slice(0, 4),
        entities: (event.entities || []).slice(0, 8),
        keywords: (event.keywords || []).slice(0, 8)
      };
      return item;
    });
    let promptPayload: CollectionPlannerPromptPayload = {
      tab_id: tabId,
      title: title,
      events: promptEvents
    };
    let payload = await this.callJson(config, COLLECTION_GROUPING_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
    return this.normalizeCollectionPlannerGroups(payload, tabId, idPrefix);
  }

  private collectionPlanningEvents(tabId: string, events: IndexedEvent[]): IndexedEvent[] {
    let ordered = events.slice();
    if (tabId === 'chat') {
      ordered.sort((left: IndexedEvent, right: IndexedEvent) => {
        if (left.event_date !== right.event_date) {
          return left.event_date.localeCompare(right.event_date);
        }
        return left.event_id.localeCompare(right.event_id);
      });
    }
    return ordered;
  }

  private async mergeCollectionGroups(tabId: string, title: string, groups: CollectionGroupState[], config: DataManagerModelConfig): Promise<CollectionGroupState[]> {
    let groupMap: Record<string, CollectionGroupState> = {};
    let promptGroups: CollectionPlannerMergeGroupPromptPayload[] = groups.map((group: CollectionGroupState): CollectionPlannerMergeGroupPromptPayload => {
      groupMap[group.group_id] = group;
      let item: CollectionPlannerMergeGroupPromptPayload = {
        group_id: group.group_id,
        title: group.title,
        source: group.source,
        domain: group.domain,
        event_count: group.event_ids.length,
        event_ids: group.event_ids
      };
      return item;
    });
    let promptPayload: CollectionPlannerMergePromptPayload = {
      tab_id: tabId,
      title: title,
      groups: promptGroups
    };
    let payload = await this.callJson(config, COLLECTION_GROUP_MERGE_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
    let rawGroups = Array.isArray(payload['groups']) ? payload['groups'] as JsonMap[] : [];
    let merged: CollectionGroupState[] = [];
    rawGroups.forEach((rawGroup: JsonMap, index: number) => {
      let groupIds = this.normalizeStringArray(rawGroup['group_ids']);
      let eventIds: string[] = [];
      let source = normalizeFreeText(rawGroup['source']);
      let domain = normalizeFreeText(rawGroup['domain']);
      groupIds.forEach((groupId: string) => {
        let existing = groupMap[groupId];
        if (!existing) {
          return;
        }
        eventIds = eventIds.concat(existing.event_ids);
        if (source.length === 0) {
          source = existing.source;
        }
        if (domain.length === 0) {
          domain = existing.domain;
        }
      });
      eventIds = stableUnique(eventIds);
      if (eventIds.length === 0) {
        return;
      }
      let group: CollectionGroupState = {
        group_id: tabId + '-merge-' + String(index + 1),
        title: normalizeFreeText(rawGroup['title']),
        source: source,
        time: '',
        meta: '',
        status: '',
        domain: domain,
        event_ids: eventIds
      };
      merged.push(group);
    });
    return merged.length > 0 ? merged : groups;
  }

  private normalizeCollectionPlannerGroups(payload: JsonMap, tabId: string, idPrefix: string): CollectionGroupState[] {
    let rawGroups = Array.isArray(payload['groups']) ? payload['groups'] as JsonMap[] : [];
    let groups: CollectionGroupState[] = [];
    rawGroups.forEach((rawGroup: JsonMap, index: number) => {
      let ids = this.normalizeStringArray(rawGroup['event_ids']);
      if (ids.length === 0) {
        ids = this.normalizeStringArray(rawGroup['events']);
      }
      if (ids.length === 0) {
        return;
      }
      let group: CollectionGroupState = {
        group_id: tabId + '-' + idPrefix + '-' + String(index + 1),
        title: normalizeFreeText(rawGroup['title']),
        source: normalizeFreeText(rawGroup['source']),
        time: '',
        meta: '',
        status: '',
        domain: normalizeFreeText(rawGroup['domain']),
        event_ids: ids
      };
      groups.push(group);
    });
    return groups;
  }

  private normalizeFactPayloads(rawFacts: JsonMap[], entry: SourceEntry, notesFallback: string): CandidateFact[] {
    let facts: CandidateFact[] = [];
    for (let raw of rawFacts) {
      let normalizedFact = normalizeFreeText(raw['normalized_fact']) || normalizeFreeText(raw['summary']);
      if (normalizedFact.length === 0) {
        continue;
      }
      let eventDate = normalizeFreeText(raw['event_date']);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(eventDate)) {
        eventDate = entry.source_date;
      }
      let fact: CandidateFact = {
        summary: summarizeText(normalizeFreeText(raw['summary']) || normalizedFact),
        normalized_fact: normalizedFact,
        event_date: eventDate,
        tags: this.normalizeStringArray(raw['tags']).slice(0, 20),
        model_notes: normalizeFreeText(raw['model_notes']) || notesFallback,
        raw_excerpt: entry.entry_text,
        source_ref: entry.source_ref,
        source_date: entry.source_date,
        workflow_scene_id: entry.workflow_scene_id,
        dedup_text: normalizeDedupText(normalizedFact)
      };
      facts.push(fact);
    }
    return atomicizeCandidateFacts(entry, facts);
  }

  private heuristicEnrichEvent(event: IndexedEvent, method: string): IndexedEvent {
    let enriched: IndexedEvent = this.copyEvent(event);
    let ruleKeywords = deriveRuleKeywords(event);
    let ruleDomains = deriveRuleDomains(event);
    let ruleEntities = deriveRuleEntities(event);
    enriched.keywords = ruleKeywords;
    enriched.domains = ruleDomains;
    enriched.entity_mentions = ruleEntities;
    enriched.entities = ruleEntities.map((entity: EntityMention) => `${entity.type}:${entity.name}`);
    enriched.profile_domains = normalizeDomains(enriched.domains);
    enriched.enrichment_method = method;
    return enriched;
  }

  private enrichEventFromPayload(event: IndexedEvent, payload: JsonMap, method: string): IndexedEvent {
    let enriched: IndexedEvent = this.copyEvent(event);
    let ruleKeywords = deriveRuleKeywords(event);
    let ruleDomains = deriveRuleDomains(event);
    let ruleEntities = deriveRuleEntities(event);
    let keywords = stableUnique(this.normalizeStringArray(payload['keywords']).concat(ruleKeywords)).slice(0, 40);
    let domains = normalizeDomains(this.normalizeStringArray(payload['domains']).concat(ruleDomains));
    let modelEntities = this.normalizeEntityArray(payload['entities']);
    let entityMentions = normalizeEntityMentions(modelEntities.concat(ruleEntities));
    enriched.keywords = keywords;
    enriched.domains = domains.length > 0 ? domains : ['other'];
    enriched.entity_mentions = entityMentions;
    enriched.entities = entityMentions.map((entity: EntityMention) => `${entity.type}:${entity.name}`);
    enriched.profile_domains = normalizeDomains(enriched.domains);
    enriched.enrichment_method = method;
    return enriched;
  }

  private chunkSourceEntries(entries: SourceEntry[], size: number): SourceEntry[][] {
    let chunks: SourceEntry[][] = [];
    for (let index = 0; index < entries.length; index += size) {
      chunks.push(entries.slice(index, index + size));
    }
    return chunks;
  }

  private chunkEvents(events: IndexedEvent[], size: number): IndexedEvent[][] {
    let chunks: IndexedEvent[][] = [];
    for (let index = 0; index < events.length; index += size) {
      chunks.push(events.slice(index, index + size));
    }
    return chunks;
  }

  private profilePromptText(payload: Object): string {
    return ArkJSON.stringify(payload);
  }

  private profilePromptCharCount(payload: Object): number {
    return this.profilePromptText(payload).length;
  }

  private profileEventPayload(event: IndexedEvent, compact: boolean): ProfileEventPromptPayload {
    let item: ProfileEventPromptPayload = {
      event_id: event.event_id,
      date: event.event_date,
      summary: summarizeText(event.summary, compact ? 110 : 220),
      sources: event.sources.slice(0, 3),
      entities: event.entities.slice(0, 8),
      keywords: event.keywords.slice(0, compact ? 6 : 12)
    };
    if (!compact) {
      item.normalized_fact = summarizeText(event.normalized_fact, 260);
      item.domains = event.domains.slice();
    }
    return item;
  }

  private compactPreviousClaims(previousClaims: ProfileClaim[]): ProfileClaim[] {
    return previousClaims.slice(0, 8).map((claim: ProfileClaim): ProfileClaim => {
      let item: ProfileClaim = {
        statement: summarizeText(claim.statement, 120),
        kind: claim.kind,
        confidence: claim.confidence,
        event_ids: (claim.event_ids || []).slice(0, 6),
        evidence_count: claim.evidence_count,
        start_date: claim.start_date,
        end_date: claim.end_date,
        example: ''
      };
      return item;
    });
  }

  private profilePayloadFromEvents(domain: string, eventCount: number, eventPayloads: ProfileEventPromptPayload[],
    previousClaims: ProfileClaim[], chunkIndex: number, chunkCount: number): ProfilePromptPayload {
    let payload: ProfilePromptPayload = {
      domain: domain,
      domain_description: DOMAIN_DESCRIPTIONS[domain] || domain,
      event_count: eventCount,
      included_event_count: eventPayloads.length,
      events: eventPayloads,
      previous_claims: this.compactPreviousClaims(previousClaims),
      selection_note: chunkIndex <= 0 ? 'all compact events are included because this domain fits the prompt budget' :
        'this is one prompt-budgeted chunk of the domain; generate only conclusions directly supported by events in this chunk'
    };
    if (chunkIndex > 0) {
      payload.chunk = {
        index: chunkIndex,
        count: chunkCount
      };
    }
    return payload;
  }

  private profileModelPromptChunks(domain: string, events: IndexedEvent[], previousClaims: ProfileClaim[]): ProfilePromptPayload[] {
    let fullPayload = this.profilePayloadFromEvents(domain, events.length,
      events.map((event: IndexedEvent): ProfileEventPromptPayload => this.profileEventPayload(event, true)), previousClaims, 0, 0);
    if (this.profilePromptCharCount(fullPayload) <= PROFILE_MODEL_PROMPT_CHAR_LIMIT) {
      return [fullPayload];
    }
    let batches: ProfileEventPromptPayload[][] = [];
    let current: ProfileEventPromptPayload[] = [];
    let budget = Math.max(1, Math.floor(PROFILE_MODEL_PROMPT_CHAR_LIMIT * 0.95));
    let compactEvents = events.map((event: IndexedEvent): ProfileEventPromptPayload => this.profileEventPayload(event, true));
    for (let eventPayload of compactEvents) {
      let candidate = current.concat([eventPayload]);
      let testPayload = this.profilePayloadFromEvents(domain, events.length, candidate, [], 1, 1);
      if (current.length > 0 && this.profilePromptCharCount(testPayload) > budget) {
        batches.push(current);
        current = [eventPayload];
      } else {
        current = candidate;
      }
    }
    if (current.length > 0) {
      batches.push(current);
    }
    let result: ProfilePromptPayload[] = [];
    let chunkCount = batches.length;
    for (let index = 0; index < batches.length; index++) {
      result.push(this.profilePayloadFromEvents(domain, events.length, batches[index], [], index + 1, chunkCount));
    }
    return result;
  }

  private profileMergePayload(domain: string, candidateClaims: RawProfileClaim[], previousClaims: ProfileClaim[],
    round: number, batchIndex: number, batchCount: number): ProfileMergePromptPayload {
    let payload: ProfileMergePromptPayload = {
      domain: domain,
      domain_description: DOMAIN_DESCRIPTIONS[domain] || domain,
      round: round,
      candidate_claims: candidateClaims.map((claim: RawProfileClaim): RawProfileClaim => {
        let item: RawProfileClaim = {
          statement: summarizeText(claim.statement, 140),
          kind: claim.kind,
          confidence: claim.confidence,
          event_ids: (claim.event_ids || []).slice(0, 10),
          example: ''
        };
        return item;
      }),
      previous_claims: this.compactPreviousClaims(previousClaims)
    };
    if (batchIndex > 0) {
      payload.batch = {
        index: batchIndex,
        count: batchCount
      };
    }
    return payload;
  }

  private profileModelMergePayloads(domain: string, candidateClaims: RawProfileClaim[], previousClaims: ProfileClaim[],
    round: number): ProfileMergePromptPayload[] {
    let fullPayload = this.profileMergePayload(domain, candidateClaims, previousClaims, round, 0, 0);
    if (this.profilePromptCharCount(fullPayload) <= PROFILE_MODEL_MERGE_CHAR_LIMIT) {
      return [fullPayload];
    }
    let batches: RawProfileClaim[][] = [];
    let current: RawProfileClaim[] = [];
    let budget = Math.max(1, Math.floor(PROFILE_MODEL_MERGE_CHAR_LIMIT * 0.95));
    for (let claim of candidateClaims) {
      let candidate = current.concat([claim]);
      let testPayload = this.profileMergePayload(domain, candidate, [], round, 1, 1);
      if (current.length > 0 && this.profilePromptCharCount(testPayload) > budget) {
        batches.push(current);
        current = [claim];
      } else {
        current = candidate;
      }
    }
    if (current.length > 0) {
      batches.push(current);
    }
    let result: ProfileMergePromptPayload[] = [];
    let batchCount = batches.length;
    for (let index = 0; index < batches.length; index++) {
      result.push(this.profileMergePayload(domain, batches[index], [], round, index + 1, batchCount));
    }
    return result;
  }

  private async mergeProfileClaimsWithModel(domain: string, candidateClaims: RawProfileClaim[], previousClaims: ProfileClaim[],
    events: IndexedEvent[], config: DataManagerModelConfig): Promise<ProfileMergeResult> {
    let pending = this.normalizeGeneratedProfileClaims(candidateClaims, events, domain, 80);
    if (pending.length === 0) {
      return { short_summary: '', claims: [] };
    }
    let currentPrevious = previousClaims;
    for (let round = 1; round <= PROFILE_MODEL_MERGE_ROUND_LIMIT; round++) {
      let payloads = this.profileModelMergePayloads(domain, pending, currentPrevious, round);
      let merged: RawProfileClaim[] = [];
      let shortSummary = '';
      for (let payload of payloads) {
        let raw = await this.callJson(config, PROFILE_MERGE_SYSTEM_PROMPT, this.profilePromptText(payload));
        let parsed = this.normalizeProfilePayload(raw);
        if (shortSummary.length === 0) {
          shortSummary = parsed.short_summary;
        }
        merged = merged.concat(this.normalizeGeneratedProfileClaims(parsed.claims, events, domain, 16));
      }
      merged = this.normalizeGeneratedProfileClaims(merged, events, domain, 80);
      if (merged.length === 0) {
        return { short_summary: '', claims: pending.slice(0, 8) };
      }
      if (payloads.length === 1 || merged.length >= pending.length) {
        return { short_summary: shortSummary, claims: merged.slice(0, 8) };
      }
      pending = merged;
      currentPrevious = [];
    }
    return { short_summary: '', claims: pending.slice(0, 8) };
  }

  private normalizeGeneratedProfileClaims(rawClaims: RawProfileClaim[], events: IndexedEvent[], domain: string, limit: number): RawProfileClaim[] {
    let eventMap: Record<string, IndexedEvent> = {};
    events.forEach((event: IndexedEvent) => eventMap[event.event_id] = event);
    let result: RawProfileClaim[] = [];
    let seen: Record<string, boolean> = {};
    for (let raw of rawClaims) {
      let statement = normalizeFreeText(raw.statement || raw.claim || raw.summary);
      let key = statement.toLowerCase().replace(/\s+/g, '');
      if (statement.length === 0 || seen[key]) {
        continue;
      }
      let ids = stableUnique(raw.event_ids || []).filter((id: string) => eventMap[id] !== undefined).sort((left: string, right: string) => {
        let leftEvent = eventMap[left];
        let rightEvent = eventMap[right];
        if (leftEvent.event_date !== rightEvent.event_date) {
          return leftEvent.event_date.localeCompare(rightEvent.event_date);
        }
        return left.localeCompare(right);
      });
      if (ids.length < 2 || this.looksLikeProfileEventDetail(statement) || (domain !== 'other' && normalizeFreeText(raw.kind) === 'relation')) {
        continue;
      }
      let evidenceEvents = ids.map((id: string) => eventMap[id]);
      let claim: RawProfileClaim = {
        statement: statement,
        kind: this.normalizeProfileKind(raw.kind),
        confidence: this.normalizeConfidence(raw.confidence),
        event_ids: ids,
        example: normalizeFreeText(raw.example) || (evidenceEvents.length > 0 ? evidenceEvents[evidenceEvents.length - 1].summary : '')
      };
      result.push(claim);
      seen[key] = true;
      if (result.length >= limit) {
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

  private looksLikeProfileEventDetail(statement: string): boolean {
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

  private profileSummaryFromRawClaims(domain: string, claims: RawProfileClaim[]): string {
    let statements = claims
      .map((claim: RawProfileClaim) => normalizeFreeText(claim.statement).replace(/。$/g, ''))
      .filter((statement: string) => statement.length > 0);
    if (statements.length === 0) {
      return '';
    }
    return summarizeText(`${DOMAIN_DISPLAY_NAMES[domain] || domain}领域呈现出这些倾向：${statements.slice(0, 3).join('；')}。`, 180);
  }

  private profileShortSummary(domain: string, modelShortSummary: string, summary: string, claims: RawProfileClaim[], events: IndexedEvent[]): string {
    let normalized = normalizeProfileShortSummary(modelShortSummary);
    if (normalized.length > 0) {
      return normalized;
    }
    for (let claim of claims) {
      let fromClaim = profileShortSummaryFromText(domain, claim.statement, '');
      if (fromClaim.length === 4) {
        return fromClaim;
      }
    }
    let fromSummary = profileShortSummaryFromText(domain, summary, '');
    if (fromSummary.length === 4) {
      return fromSummary;
    }
    for (let event of events) {
      let fromEvent = profileShortSummaryFromText(domain, event.summary || event.normalized_fact, '');
      if (fromEvent.length === 4) {
        return fromEvent;
      }
    }
    return profileShortSummaryFromText(domain, '', '近期记录');
  }

  private heuristicProfile(domain: string, events: IndexedEvent[]): ProfileModelPayload {
    if (events.length === 0) {
      let empty: ProfileModelPayload = { short_summary: '', summary: '', claims: [] };
      return empty;
    }
    let sourceCounter: NumberMap = {};
    let keywordCounter: NumberMap = {};
    let keywordEvents: StringArrayMap = {};
    for (let event of events) {
      event.sources.forEach((source: string) => {
        sourceCounter[source] = (sourceCounter[source] || 0) + 1;
      });
      event.keywords.slice(0, 10).forEach((keyword: string) => {
        keywordCounter[keyword] = (keywordCounter[keyword] || 0) + 1;
        if (!keywordEvents[keyword]) {
          keywordEvents[keyword] = [];
        }
        keywordEvents[keyword].push(event.event_id);
      });
    }
    let topKeywords = Object.keys(keywordCounter).sort((a: string, b: string) => keywordCounter[b] - keywordCounter[a]).slice(0, 3);
    let claims: RawProfileClaim[] = [];
    if (topKeywords.length > 0) {
      let ids: string[] = [];
      topKeywords.forEach((keyword: string) => {
        ids = ids.concat(keywordEvents[keyword] || []);
      });
      let claim: RawProfileClaim = {
        statement: `近期${topKeywords.join('、')}等话题反复出现。`,
        kind: 'observation',
        confidence: events.length >= 5 ? 'medium' : 'low',
        event_ids: stableUnique(ids).slice(0, 8),
        example: events[events.length - 1].summary
      };
      claims.push(claim);
    }
    let topSource = Object.keys(sourceCounter).sort((a: string, b: string) => sourceCounter[b] - sourceCounter[a])[0] || '';
    if (topSource.length > 0 && events.length >= 2) {
      let claim: RawProfileClaim = {
        statement: `该领域的数据主要来自${topSource}。`,
        kind: 'source',
        confidence: 'medium',
        event_ids: events.slice(-6).map((event: IndexedEvent) => event.event_id),
        example: events[events.length - 1].summary
      };
      claims.push(claim);
    }
    let payload: ProfileModelPayload = {
      short_summary: '',
      summary: claims.length > 0 ? claims.map((claim: RawProfileClaim) => normalizeFreeText(claim.statement)).join('；') + '。' : '',
      claims: claims
    };
    payload.short_summary = this.profileShortSummary(domain, '', payload.summary, claims, events);
    return payload;
  }

  private isEnabled(config: DataManagerModelConfig): boolean {
    return config.enabled && config.baseUrl.trim().length > 0;
  }

  private newDecision(reason: string): DedupDecision {
    let decision: DedupDecision = {
      decision: 'new',
      matched_record_ids: [],
      reason: reason,
      merged_summary: '',
      merged_fact: '',
      merged_tags: []
    };
    return decision;
  }

  private heuristicDedupDecision(fact: CandidateFact, records: AggregatedRecord[], reasonPrefix: string): DedupDecision {
    let factKey = normalizedSimilarityKey(fact.dedup_text);
    let factAmounts = extractAmountTokens(fact.dedup_text);
    let factSignature = normalizedTransactionSignature(fact.dedup_text);
    for (let index = records.length - 1; index >= 0; index--) {
      let record = records[index];
      let recordKey = normalizedSimilarityKey(record.dedup_text);
      if (factKey.length > 0 && factKey === recordKey) {
        let decision: DedupDecision = {
          decision: 'duplicate',
          matched_record_ids: [record.record_id],
          reason: reasonPrefix + '_exact_match',
          merged_summary: '',
          merged_fact: '',
          merged_tags: []
        };
        return decision;
      }
      let recordAmounts = extractAmountTokens(record.dedup_text);
      let recordSignature = normalizedTransactionSignature(record.dedup_text);
      if (factAmounts.length > 0 && this.sameStringSet(factAmounts, recordAmounts) && factSignature.length > 0 && factSignature === recordSignature) {
        let decision: DedupDecision = {
          decision: 'merge_with_existing',
          matched_record_ids: [record.record_id],
          reason: reasonPrefix + '_signature_match',
          merged_summary: '',
          merged_fact: '',
          merged_tags: []
        };
        return decision;
      }
    }
    return this.newDecision(reasonPrefix + '_no_match');
  }

  private sameStringSet(left: string[], right: string[]): boolean {
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
      tags: event.tags.slice(),
      source_refs: event.source_refs.slice(),
      sources: event.sources.slice(),
      workflow_scene_ids: (event.workflow_scene_ids || []).slice(),
      image_paths: event.image_paths.slice(),
      keywords: event.keywords.slice(),
      domains: event.domains.slice(),
      entity_mentions: event.entity_mentions.slice(),
      enrichment_method: event.enrichment_method,
      entities: event.entities.slice(),
      profile_domains: event.profile_domains.slice()
    };
    return copied;
  }

  private normalizeNumberArray(value: Object | string | number | boolean | null | undefined): number[] {
    if (!Array.isArray(value)) {
      return [];
    }
    let result: number[] = [];
    for (let item of value as Object[]) {
      let id = Number(item);
      if (!isNaN(id)) {
        result.push(id);
      }
    }
    return result;
  }

  private normalizeProfilePayload(payload: JsonMap): ProfileModelPayload {
    let claims: RawProfileClaim[] = [];
    let rawClaims = payload['claims'];
    if (Array.isArray(rawClaims)) {
      for (let raw of rawClaims as JsonMap[]) {
        let claim: RawProfileClaim = {
          statement: normalizeFreeText(raw['statement'] || raw['claim'] || raw['summary']),
          kind: normalizeFreeText(raw['kind']) || 'observation',
          confidence: normalizeFreeText(raw['confidence']) || 'low',
          event_ids: this.normalizeProfileEventIds(raw),
          example: normalizeFreeText(raw['example'])
        };
        if (claim.statement.length > 0) {
          claims.push(claim);
        }
      }
    }
    let result: ProfileModelPayload = {
      short_summary: normalizeProfileShortSummary(payload['short_summary']),
      summary: normalizeFreeText(payload['summary']),
      claims: claims
    };
    return result;
  }

  private async callJson(config: DataManagerModelConfig, systemPrompt: string, userPrompt: string): Promise<JsonMap> {
    let messages: CloudChatMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ];
    let startedAt = Date.now();
    dataManagerInfo(`Model request start: baseUrl=${config.baseUrl}, promptChars=${userPrompt.length}`);
    try {
      let content = await this.cloudClient.chatCompletionText({
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        messages: messages,
        temperature: 0,
        chatTemplateKwargs: {
          enable_thinking: false
        }
      });
      dataManagerInfo(`Model request response: ms=${Date.now() - startedAt}`);
      return this.parseJsonObject(content);
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Model request failed: baseUrl=${config.baseUrl}, ms=${Date.now() - startedAt}, error=${err.message}`);
      throw err;
    }
  }

  private parseJsonObject(rawText: string): JsonMap {
    let text = rawText.trim();
    let fenced = /```json\s*([\s\S]*?)\s*```/i.exec(text);
    if (fenced) {
      text = fenced[1].trim();
    }
    let objectStart = text.indexOf('{');
    if (objectStart >= 0) {
      let objectEnd = text.lastIndexOf('}');
      if (objectEnd > objectStart) {
        text = text.substring(objectStart, objectEnd + 1);
      }
    }
    let parsed = ArkJSON.parse(text) as JsonMap;
    if (!parsed || typeof parsed !== 'object') {
      throw new Error('JSON root is not object');
    }
    return parsed;
  }

  private normalizeStringArray(value: Object | string | number | boolean | null | undefined): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    return stableUnique((value as string[]).map((item: string) => normalizeFreeText(item)));
  }

  private normalizeProfileEventIds(raw: JsonMap): string[] {
    let ids = this.normalizeStringArray(raw['event_ids']);
    if (ids.length === 0) {
      ids = this.normalizeStringArray(raw['evidence_event_ids']);
    }
    if (ids.length === 0) {
      ids = this.normalizeStringArray(raw['evidence']);
    }
    return ids;
  }

  private normalizeEntityArray(value: Object | string | number | boolean | null | undefined): EntityMention[] {
    if (!Array.isArray(value)) {
      return [];
    }
    let result: EntityMention[] = [];
    for (let item of value as EntityMention[]) {
      if (!item || typeof item !== 'object') {
        continue;
      }
      result.push({
        type: normalizeFreeText(item.type),
        name: normalizeFreeText(item.name),
        aliases: Array.isArray(item.aliases) ? item.aliases : []
      });
    }
    return normalizeEntityMentions(result);
  }
}

