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
  HomeRecommendationPlannerEvent,
  HomeRecommendationState,
  IndexedEvent,
  IndexedEventTodo,
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
  summarizeText,
  weekdayLabelFromDate
} from './DataManagerUtils';
import { dataManagerError, dataManagerInfo } from './DataManagerLog';
import { workflowSceneLabel } from '../utils/WorkflowSceneConfig';

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

interface SummaryPromptPayload {
  level: string;
  event_count: number;
  items: string[];
}

interface BatchEventPromptPayload {
  event_id: string;
  event_date: string;
  event_weekday: string;
  workflow_scene_labels: string[];
  summary: string;
  normalized_fact: string;
}

interface BatchEnrichPromptPayload {
  events: BatchEventPromptPayload[];
}

export interface EnrichPromptPreview {
  systemPrompt: string;
  userPrompt: string;
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

interface HomeRecommendationEventPromptPayload {
  event_id: string;
  date: string;
  todo_type: string;
  todo_deadline: string;
  todo_text: string;
  summary: string;
  normalized_fact: string;
  sources: string[];
  domains: string[];
  keywords: string[];
  image_paths: string[];
}

interface HomeRecommendationPromptPayload {
  current_date: string;
  events: HomeRecommendationEventPromptPayload[];
}

export function shouldKeepTodoAgentTask(type: string, workflowSceneLabels: string[]): boolean {
  return normalizeFreeText(type) === 'buy' && workflowSceneLabels.length === 1 && workflowSceneLabels[0] === '聊天';
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

const BATCH_ENRICH_SYSTEM_PROMPT: string =
  '你是本地个人数据索引助手。请批量为输入事件提取关键词、领域、实体和可能的待办事项信号。' +
  '\n\n输入字段说明：' +
  '\nevent_id：事件唯一标识，只需要在输出中原样返回。' +
  '\nevent_date：事件发生日期，格式为 YYYY-MM-DD。' +
  '\nevent_weekday：event_date 对应的星期，用于把“这周六”“下周一”“周末”等相对日期换算为绝对日期。' +
  '\nworkflow_scene_labels：工作流采集场景提示，例如聊天、购物、外卖、娱乐、生活、社交、差旅；它只帮助判断待办动作类型，不是 domains 的领域标签。' +
  '\nsummary：事件短摘要，用于快速理解事件。' +
  '\nnormalized_fact：整理后的完整事实描述，通常比 summary 包含更多商户、商品、人物、地点、金额、状态或行动细节；抽取关键词、领域、实体和待办时优先参考它。' +
  '\n\n输出必须是严格 JSON，不要输出 markdown 或解释：' +
  '{"events":[{"event_id":"原样返回","keywords":["关键词"],"domains":["eat|wear|live|travel|work|other"],"entities":[{"type":"person|place|merchant","name":"名称","aliases":["别名"]}],"todo":{"type":"场景允许的 action tag 或空字符串","deadline":"YYYY-MM-DD 或空字符串","text":"触发待办的具体行动内容或空字符串","agent_task":"可直接交给 GUI Agent 执行的任务描述或空字符串"}}]}。' +
  '\n必须为每个输入 event_id 返回一个结果。' +
  '\n\nkeywords 规则：提取具体、可检索的商品、服务、商户、地点、人物、应用、动作、状态、主题词或金额词；优先保留输入原词；避免“当前页面”“截图”“记录”“信息”“详情”等泛词。' +
  '\n\ndomains 规则：只能从 eat|wear|live|travel|work|other 中多选。eat 表示餐饮、外卖、食品、饮料；wear 表示服装、鞋包、美妆；live 表示住房、家居、酒店；travel 表示交通、通勤、出行、旅行、票务、差旅；work 表示工作、会议、协作、办公事务；other 表示无法归入以上分类的事件。购物、聊天、外卖、娱乐、生活、社交、差旅是 workflow_scene_labels，不要直接当作 domains。请注意 eat/wear/live/travel/work 只能覆盖真实场景中 20% 的事件，如果你没有 90% 以上的把握明确归类，**必须仅输出 other**。如果已经输出 eat/wear/live/travel/work 中任一领域，不要再输出 other。' +
  '\n\nentities 规则：只抽取现实对象。person 只用于真实联系人、聊天对象或明确人物姓名；place 只用于实际地点、地址、场馆、目的地；merchant 只用于商户、店铺、平台、品牌门店或服务商。不要把商品、服务类别、金额、日期、订单号、抽象话题、页面元素、按钮、状态词或泛化类别抽成实体。name 和 aliases 必须来自输入文本，aliases 只放同一现实对象在输入中出现过的其他写法。' +
  '\n\ntodo 规则：todo 只在事件明确包含用户未来可能需要处理的行动、计划、到期、预约、购买、退款、售后、出行、参与或后续事项时填写；普通记录、偏好、已完成消费、纯浏览、信息分享、截图描述、无行动内容时必须把 todo 的四个字段都写空。' +
  '有明确相对日期时，必须以该事件 event_date 和 event_weekday 为基准换算为绝对 deadline；“这周六/本周六”表示 event_date 所在自然周的星期六，不要按模型运行当天换算。没有明确日期但有明确待办动作时 deadline 写空字符串。text 必须只描述触发 todo 的具体行动内容，不要把同一事件里的其他文件分享、技术讨论、页面状态混进去。agent_task 只在纯聊天场景且 type=buy 时填写，写成可直接执行的 GUI Agent 任务；其他情况必须为空。';

function enrichWorkflowSceneLabels(sceneIds: number[]): string[] {
  let labels: string[] = [];
  sceneIds.forEach((sceneId: number) => {
    if (!isNaN(sceneId) && sceneId >= 0) {
      labels.push(workflowSceneLabel(sceneId));
    }
  });
  return stableUnique(labels);
}

function buildBatchEnrichPromptPayload(events: IndexedEvent[]): BatchEnrichPromptPayload {
  let promptEvents: BatchEventPromptPayload[] = events.map((event: IndexedEvent): BatchEventPromptPayload => {
    let item: BatchEventPromptPayload = {
      event_id: event.event_id,
      event_date: event.event_date,
      event_weekday: weekdayLabelFromDate(event.event_date),
      workflow_scene_labels: enrichWorkflowSceneLabels(event.workflow_scene_ids || []),
      summary: event.summary,
      normalized_fact: event.normalized_fact
    };
    return item;
  });
  let promptPayload: BatchEnrichPromptPayload = {
    events: promptEvents
  };
  return promptPayload;
}

function enrichTodoGuideForEvents(events: IndexedEvent[]): string {
  let labels: string[] = [];
  events.forEach((event: IndexedEvent) => {
    labels = labels.concat(enrichWorkflowSceneLabels(event.workflow_scene_ids || []));
  });
  labels = stableUnique(labels);
  let guides: string[] = ['\n按 workflow_scene_labels 使用以下待办提取规则：'];
  if (labels.length === 0) {
    guides.push('未知场景：只在行动责任明确时使用 other；不要因为普通信息记录生成 todo。');
    return guides.join('');
  }
  if (labels.indexOf('聊天') >= 0) {
    guides.push('聊天：提取两类待办。第一类是有明确时间锚点的未来计划、约定、聚餐、出行、会议、到期或必须回复时间，此时 todo.type 写空字符串，只填写 deadline 和 text，没有可换算日期时写空 todo。第二类是用户明确表达要购买某商品或让对方帮忙购买某商品，此时允许 type=buy，deadline 可以为空，text 写购买行动，agent_task 写可直接执行的 GUI Agent 任务，例如“在淘宝中购买xxx商品”；如果聊天明确指定京东、淘宝、美团等平台则使用该平台，否则默认淘宝。遇到“周末”且未说明周几时，以 event_date 之后最近的周六作为 deadline。text 和 agent_task 只描述该待办本身，不要写同条事件里的文件或技术讨论。');
  }
  if (labels.indexOf('购物') >= 0) {
    guides.push('购物：允许 type=buy|pay|pickup|other，分别表示购买、付款、取货/收货、其他。');
  }
  if (labels.indexOf('外卖') >= 0) {
    guides.push('外卖：允许 type=order|pay|pickup|other，分别表示下单、付款、取餐、其他。');
  }
  if (labels.indexOf('娱乐') >= 0) {
    guides.push('娱乐：允许 type=renew|book|other，分别表示续费、预约/订票、其他。');
  }
  if (labels.indexOf('生活') >= 0) {
    guides.push('生活：允许 type=pay|repair|appointment|other，分别表示缴费、维修、预约、其他。');
  }
  if (labels.indexOf('社交') >= 0) {
    guides.push('社交：允许 type=attend|plan|book|other，分别表示赴约/参加、安排计划、预订、其他。');
  }
  if (labels.indexOf('差旅') >= 0) {
    guides.push('差旅：允许 type=book|depart|check_in|pay|reimburse|other，分别表示预订、出发、入住/值机、付款、其他。');
  }
  if (labels.length > 1) {
    guides.push('如果事件同时属于多个场景，优先使用最具体的非聊天场景规则；聊天规则只用于纯聊天场景。');
  }
  guides.push('不要输出规则外的 type。');
  return guides.join('');
}

export function buildEnrichPromptPreview(events: IndexedEvent[]): EnrichPromptPreview {
  let preview: EnrichPromptPreview = {
    systemPrompt: BATCH_ENRICH_SYSTEM_PROMPT + enrichTodoGuideForEvents(events),
    userPrompt: ArkJSON.stringify(buildBatchEnrichPromptPayload(events), null, 2)
  };
  return preview;
}

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
  'relation 类 insight 只适合 other 领域；吃、穿、住、行、办公领域不要输出联系人关系画像。只依据输入事件内容归纳。不要输出 markdown。';

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
  '你是一个事件语义分组助手。请把输入的事件组织成适合手机列表展示的少量分组。分组应来自事件本身的语义相近性、上下文连续性、联系人/商户/来源、用户意图或主题，而不是来自固定模板。' +
  '返回严格 JSON：{"groups":[{"title":"短标题，14字以内","source":"主要来源","domain":"eat|wear|live|travel|work|other","event_ids":["输入中的事件id"]}]}。' +
  '每个事件 id 只能出现一次；只能使用输入中存在的 event_id；不要逐条复述事件；尽量把同一联系人、商户、主题、通知来源或兴趣内容放在同一组；分组数量通常 3 到 8 个，最多 12 个。' +
  '标题必须有信息量，尽量表达“对象/来源 + 主题/意图/状态”。聊天 tab 必须按语义接近和上下文连贯性分组，输入事件顺序就是对话线索；不要按日期、单条截图、平台名或泛泛的“聊天记录/工作记录”切组。' +
  '避免低信息标题：平台名、纯数字、日期时间、单个技术词、单个截图/图片/贴图/表情包等界面元素、或“微信聊天记录”“工作相关聊天记录”“聊天记录”“通知记录”“视频记录”“订单记录”这类泛称。不要输出 markdown。';

const COLLECTION_GROUP_MERGE_SYSTEM_PROMPT: string =
  '你是一个事件语义分组合并助手。输入是已经分批生成的临时分组，请把相同主题、联系人、商户、来源或兴趣方向的分组合并成更少的列表分组。' +
  '返回严格 JSON：{"groups":[{"title":"短标题，14字以内","source":"主要来源","domain":"eat|wear|live|travel|work|other","group_ids":["输入中的临时分组id"]}]}。' +
  '每个 group_id 最多出现一次；只能使用输入中存在的 group_id；分组数量最多 12 个。合并后的标题必须保留具体对象/来源和主题/意图，避免平台名、日期、纯数字、单个技术词或界面元素等低信息标题。不要输出 markdown。';

const HOME_RECOMMENDATION_SYSTEM_PROMPT: string =
  '你是用户待办事项推荐助手。输入中的事件每条都有上游提取出的待办事项信号；todo_text 是具体待办行动内容；todo_deadline 为截止日期（可能为空）；' +
  'todo_type 是待办类型（可能为空），只会来自精简集合：buy购买、pay付款、pickup取货/收货/取餐、order下单、renew续费/权益恢复、book预订/订票、repair维修、appointment预约、attend参加/赴约、plan安排计划、depart出发、check_in入住/值机、reimburse报销、other其他待处理事项。' +
  '不要重新判断输入事件是不是 todo，也不要丢弃任何输入事件，你的任务只是在不丢事件的前提下，把同一事项、同一约定、同一截止目标的事件合并，并生成适合在应用首页展示给用户的推荐卡片文案。' +
  '返回严格 JSON：' +
  '{"recommendations":[{"tag":"4到6个中文字符的短标签","title":"8个字左右的精简标题","desc":"一句完整说明","domain":"eat|wear|live|travel|work|other","source_event_ids":["输入中的event_id"]}]}。' +
  'source_event_ids 必须来自输入事件，至少 1 个，每个输入 event_id 必须且只能出现在一张推荐卡片的 source_event_ids 中；每个推荐要能让用户知道接下来具体要做什么。不要编造输入里没有的人名、地点、商品、金额或行动。' +
  'tag 用于卡片左上角，只写状态或行动类型，例如“待续费”“待出发”“待购买”“待预约”“待付款”；title 精简在 8 个字左右，优先根据 todo_text 写行动对象和动作；desc 写一完整句，说明为什么需要跟进。' +
  'title 和 desc 不要使用省略号或“...”截断内容；请关注 todo_text 指向的核心待办事项，不要受同一事件里的各种其他背景信息干扰。' +
  '按截止日期临近程度和事件时间排序；输入为空时返回空数组，否则不要返回空数组。不要输出 markdown。';

export class DataPipelineModelClient {
  private cloudClient: CloudModelClient = new CloudModelClient();
  private requestSequence: number = 0;

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
    let chunks = this.chunkSourceEntries(entries, 24);
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
        let payload = await this.callJson(config, 'split.batch', BATCH_FACT_SPLIT_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
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
      let payload = await this.callJson(config, 'dedup', DEDUP_SYSTEM_PROMPT, prompt);
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

  async enrichEvents(events: IndexedEvent[], config: DataManagerModelConfig): Promise<IndexedEvent[]> {
    let result: Record<string, IndexedEvent> = {};
    events.forEach((event: IndexedEvent) => {
      result[event.event_id] = this.heuristicEnrichEvent(event, this.isEnabled(config) ? 'heuristic_batch_fallback' : 'heuristic');
    });
    if (!this.isEnabled(config) || events.length === 0) {
      return events.map((event: IndexedEvent) => result[event.event_id]);
    }
    let chunks = this.chunkEventsByTodoGuide(events, 32);
    for (let chunk of chunks) {
      let eventMap: Record<string, IndexedEvent> = {};
      chunk.forEach((event: IndexedEvent) => {
        eventMap[event.event_id] = event;
      });
      let preview = buildEnrichPromptPreview(chunk);
      try {
        dataManagerInfo(`Batch enrich request: events=${chunk.length}`);
        let payload = await this.callJson(config, 'enrich.batch', preview.systemPrompt, preview.userPrompt);
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
      let payload = await this.callJson(config, 'summary', SUMMARY_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload));
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
      let payload = await this.callJson(config, 'entity.resolve', ENTITY_RESOLUTION_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
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
        let payload = await this.callJson(config, 'profile.generate.' + domain, PROFILE_SYSTEM_PROMPT, this.profilePromptText(promptPayloads[0]));
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
        let payload = await this.callJson(config, 'profile.generate.' + domain, PROFILE_SYSTEM_PROMPT, this.profilePromptText(promptPayload));
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
    let payload = await this.callJson(config, 'collection.group.' + tabId, COLLECTION_GROUPING_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
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

  async planHomeRecommendations(events: HomeRecommendationPlannerEvent[], currentDate: string, config: DataManagerModelConfig): Promise<HomeRecommendationState[]> {
    if (!this.isEnabled(config) || events.length === 0) {
      return [];
    }
    let promptEvents: HomeRecommendationEventPromptPayload[] = events.map((event: HomeRecommendationPlannerEvent): HomeRecommendationEventPromptPayload => {
      let item: HomeRecommendationEventPromptPayload = {
        event_id: event.event_id,
        date: event.date,
        todo_type: event.todo_type,
        todo_deadline: event.todo_deadline,
        todo_text: summarizeText(event.todo_text, 120),
        summary: summarizeText(event.summary, 100),
        normalized_fact: summarizeText(event.normalized_fact, 180),
        sources: event.sources.slice(0, 4),
        domains: event.domains.slice(0, 4),
        keywords: event.keywords.slice(0, 8),
        image_paths: event.image_paths.slice(0, 3)
      };
      return item;
    });
    let promptPayload: HomeRecommendationPromptPayload = {
      current_date: currentDate,
      events: promptEvents
    };
    dataManagerInfo(`Home recommendation planner request: events=${events.length}, currentDate=${currentDate}`);
    let payload = await this.callJson(config, 'home.recommendation', HOME_RECOMMENDATION_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
    return this.normalizeHomeRecommendations(payload);
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
    let payload = await this.callJson(config, 'collection.merge.' + tabId, COLLECTION_GROUP_MERGE_SYSTEM_PROMPT, ArkJSON.stringify(promptPayload, null, 2));
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

  private normalizeHomeRecommendations(payload: JsonMap): HomeRecommendationState[] {
    let rawItems = Array.isArray(payload['recommendations']) ? payload['recommendations'] as JsonMap[] : [];
    let result: HomeRecommendationState[] = [];
    rawItems.forEach((raw: JsonMap, index: number) => {
      let title = normalizeFreeText(raw['title']);
      let sourceEventIds = this.normalizeStringArray(raw['source_event_ids']);
      if (title.length === 0 || sourceEventIds.length === 0) {
        return;
      }
      let domains = normalizeDomains([normalizeFreeText(raw['domain'])]);
      let item: HomeRecommendationState = {
        id: normalizeFreeText(raw['id']) || 'todo-' + String(index + 1),
        tag: this.normalizeRecommendationTag(raw['tag']),
        title: title,
        desc: normalizeFreeText(raw['desc']),
        meta: '',
        domain: domains.length > 0 ? domains[0] : 'other',
        source_event_ids: sourceEventIds,
        source_input_hash: '',
        completed: false
      };
      result.push(item);
    });
    return result;
  }

  private normalizeRecommendationTag(value: Object | string | number | boolean | null | undefined): string {
    let tag = normalizeFreeText(value);
    if (tag.length < 2) {
      return '';
    }
    if (tag.length > 6) {
      return '';
    }
    return tag;
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
    enriched.todo = this.emptyTodo();
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
    enriched.todo = this.normalizeTodo(payload['todo'], event);
    enriched.enrichment_method = method;
    return enriched;
  }

  private emptyTodo(): IndexedEventTodo {
    return {
      type: '',
      deadline: '',
      text: '',
      agent_task: ''
    };
  }

  private normalizeTodo(value: Object | string | number | boolean | null | undefined, event: IndexedEvent): IndexedEventTodo {
    if (!value || typeof value !== 'object') {
      return this.emptyTodo();
    }
    let raw = value as JsonMap;
    let type = this.normalizeTodoType(raw['type']);
    let deadline = normalizeFreeText(raw['deadline']);
    deadline = /^\d{4}-\d{2}-\d{2}$/.test(deadline) ? deadline : '';
    let text = normalizeFreeText(raw['text']);
    let agentTask = this.normalizeAgentTask(raw['agent_task'], type, event);
    if (type.length === 0 && deadline.length === 0) {
      return this.emptyTodo();
    }
    let todo: IndexedEventTodo = {
      type: type,
      deadline: deadline,
      text: text,
      agent_task: agentTask
    };
    return todo;
  }

  private normalizeAgentTask(value: Object | string | number | boolean | null | undefined, type: string, event: IndexedEvent): string {
    if (!shouldKeepTodoAgentTask(type, this.workflowSceneLabels(event.workflow_scene_ids || []))) {
      return '';
    }
    return normalizeFreeText(value);
  }

  private normalizeTodoType(value: Object | string | number | boolean | null | undefined): string {
    let type = normalizeFreeText(value);
    let allowed = [
      'buy', 'pay', 'pickup', 'order',
      'renew', 'book', 'repair', 'appointment',
      'attend', 'plan', 'depart', 'check_in', 'reimburse',
      'other'
    ];
    return allowed.indexOf(type) >= 0 ? type : '';
  }

  private workflowSceneLabels(sceneIds: number[]): string[] {
    return enrichWorkflowSceneLabels(sceneIds);
  }

  private todoGuideKey(event: IndexedEvent): string {
    let labels = this.workflowSceneLabels(event.workflow_scene_ids || []);
    if (labels.indexOf('聊天') >= 0 && labels.length === 1) {
      return 'chat';
    }
    if (labels.length > 0) {
      return labels[0];
    }
    return 'default';
  }

  private chunkEventsByTodoGuide(events: IndexedEvent[], size: number): IndexedEvent[][] {
    let grouped: Record<string, IndexedEvent[]> = new Object() as Record<string, IndexedEvent[]>;
    let keys: string[] = [];
    events.forEach((event: IndexedEvent) => {
      let key = this.todoGuideKey(event);
      if (!grouped[key]) {
        grouped[key] = [];
        keys.push(key);
      }
      grouped[key].push(event);
    });
    let chunks: IndexedEvent[][] = [];
    keys.forEach((key: string) => {
      chunks = chunks.concat(this.chunkEvents(grouped[key], size));
    });
    return chunks;
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
        let raw = await this.callJson(config, 'profile.merge.' + domain, PROFILE_MERGE_SYSTEM_PROMPT, this.profilePromptText(payload));
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
      todo: {
        type: event.todo.type,
        deadline: event.todo.deadline,
        text: event.todo.text,
        agent_task: event.todo.agent_task
      },
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

  private async callJson(config: DataManagerModelConfig, kind: string, systemPrompt: string, userPrompt: string): Promise<JsonMap> {
    let messages: CloudChatMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ];
    let startedAt = Date.now();
    this.requestSequence += 1;
    let requestId = this.requestSequence;
    dataManagerInfo(`Model request start: id=${requestId}, kind=${kind}, baseUrl=${config.baseUrl}, systemChars=${systemPrompt.length}, promptChars=${userPrompt.length}`);
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
      dataManagerInfo(`Model request response: id=${requestId}, kind=${kind}, ms=${Date.now() - startedAt}, responseChars=${content.length}`);
      return this.parseJsonObject(content);
    } catch (e) {
      let err = e as Error;
      dataManagerError(`Model request failed: id=${requestId}, kind=${kind}, baseUrl=${config.baseUrl}, ms=${Date.now() - startedAt}, error=${err.message}`);
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
