import { JSON as ArkJSON } from '@kit.ArkTS';
import { ChatTool, ChatToolExecutionContext } from '../utils/ChatToolRegistry';
import {
  DOMAIN_KEYS,
  IndexedEvent,
  IndexedEventTodo,
  QueryOptions,
  QueryResult
} from './DataManagerTypes';
import {
  normalizeFreeText,
  stableUnique
} from './DataManagerUtils';

export const QUERY_EVENTS_TOOL_NAME: string = 'query_events';
const DEFAULT_QUERY_EVENTS_LIMIT: number = 20;
const QUERY_EVENTS_TOOL_DESCRIPTION: string =
  '如果根据用户请求，你需要根据关键词、实体、时间、领域等信息，查询数据归家App已收集并汇总整理的历史事件数据时（例如用户询问“帮我查一下我上周做了什么”时），调用该工具。未注明年份的日期必须根据系统消息中的当前日期补全年份后再调用。';
const ENTITY_TYPES: string[] = ['person', 'place', 'merchant'];

type QueryEventsJsonValue = Object | string | number | boolean | null;
type QueryEventsJsonMap = Record<string, QueryEventsJsonValue>;
type QueryEventsSchemaMap = Record<string, Object | string | number | boolean | null>;

export type QueryEventsIndexAvailabilityProvider = () => boolean;
export type QueryEventsQueryRunner = (options: QueryOptions) => QueryResult;

export interface QueryEventsEntityInput {
  type: string;
  name: string;
}

export interface QueryEventsPublicQuery {
  keywords: string[];
  domains: string[];
  entities: QueryEventsEntityInput[];
  date: string;
  month: string;
  start_date: string;
  end_date: string;
  limit: number;
}

export interface QueryEventsArgumentValidation {
  ok: boolean;
  options: QueryOptions;
  publicQuery: QueryEventsPublicQuery;
  error: string;
}

interface QueryEventsToolEvent {
  event_id: string;
  event_date: string;
  last_seen_date: string;
  summary: string;
  normalized_fact: string;
  domains: string[];
  keywords: string[];
  entities: string[];
  sources: string[];
  source_refs: string[];
  image_paths: string[];
  todo: IndexedEventTodo;
}

interface QueryEventsToolResponse {
  ok: boolean;
  query: QueryEventsPublicQuery;
  total_events: number;
  returned_events: number;
  events_truncated: boolean;
  events: QueryEventsToolEvent[];
}

interface QueryEventsToolErrorResponse {
  ok: boolean;
  error: string;
}

export function createQueryEventsTool(hasBuiltIndexes: QueryEventsIndexAvailabilityProvider,
  queryRunner: QueryEventsQueryRunner): ChatTool {
  return {
    name: QUERY_EVENTS_TOOL_NAME,
    description: QUERY_EVENTS_TOOL_DESCRIPTION,
    parameters: queryEventsToolParameters(),
    strict: false,
    execute: async (argsText: string, _context: ChatToolExecutionContext): Promise<string> => {
      let normalized = normalizeQueryEventsToolArguments(argsText);
      if (!normalized.ok) {
        return queryEventsToolErrorPayload(normalized.error);
      }
      if (!hasBuiltIndexes()) {
        return queryEventsToolErrorPayload('数据归家事件索引尚未构建，请先同步或刷新数据后再查询。');
      }
      let result = queryRunner(normalized.options);
      return ArkJSON.stringify(queryEventsToolResponse(normalized.publicQuery, result) as Object);
    }
  };
}

export function queryEventsToolParameters(): Object {
  let properties = createSchemaMap();
  properties['keywords'] = stringArraySchema('关键词过滤。传入用户想查找的词或短语，例如“咖啡”“酒店订单”，根据关键词匹配事件内容。' +
    '关键词召回基于精确匹配，所以尽量使用具体而非抽象的词汇作为关键词。多个关键词之间是 AND 关系，避免使用过多keyword，否则召回条目数可能过少。') as Object;
  properties['domains'] = enumArraySchema('领域过滤。可选值：eat 吃、wear 穿、live 住、travel 行、work 办公、other 其他。' +
    '多个领域之间是 OR 关系，并会与其他过滤条件取 AND。', DOMAIN_KEYS) as Object;
  properties['entities'] = entitiesArraySchema() as Object;
  properties['date'] = stringSchema('精确日期过滤，格式 YYYY-MM-DD，例如 2026-06-18。不能和 month、start_date、end_date 同时使用。用户未说明年份时，必须根据系统消息中的当前日期补全年份。') as Object;
  properties['month'] = stringSchema('月份过滤，格式 YYYY-MM，例如 2026-06。不能和 date、start_date、end_date 同时使用。用户未说明年份时，必须根据系统消息中的当前日期补全年份。') as Object;
  properties['start_date'] = stringSchema('日期范围开始日期，格式 YYYY-MM-DD，例如 2026-06-01。可与 end_date 搭配，也可单独表示从该日开始。用户未说明年份时，必须根据系统消息中的当前日期补全年份。') as Object;
  properties['end_date'] = stringSchema('日期范围结束日期，格式 YYYY-MM-DD，例如 2026-06-30。可与 start_date 搭配，也可单独表示截至该日。用户未说明年份时，必须根据系统消息中的当前日期补全年份。') as Object;
  properties['limit'] = numberSchema('最多返回多少条事件。省略时默认返回 20 条；传 0 表示返回全部匹配事件。') as Object;

  let parameters = createSchemaMap();
  parameters['type'] = 'object';
  parameters['description'] = '查询数据归家App已收集并汇总整理的事件索引。';
  parameters['properties'] = properties as Object;
  parameters['additionalProperties'] = false;
  return parameters as Object;
}

export function normalizeQueryEventsToolArguments(argsText: string): QueryEventsArgumentValidation {
  try {
    let parsed = ArkJSON.parse(argsText.trim().length === 0 ? '{}' : argsText.trim()) as QueryEventsJsonValue;
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('Tool arguments must be a JSON object.');
    }
    let args = parsed as QueryEventsJsonMap;
    assertAllowedFields(args);

    let keywords = readStringArray(args, 'keywords');
    let domains = readDomains(args);
    let entities = readEntities(args);
    let date = readDateField(args, 'date');
    let month = readMonthField(args, 'month');
    let startDate = readDateField(args, 'start_date');
    let endDate = readDateField(args, 'end_date');
    validateTimeMode(date, month, startDate, endDate);
    let limit = readLimit(args);

    let options: QueryOptions = {
      keywords: keywords,
      domains: domains,
      entities: entities.map((entity: QueryEventsEntityInput): string => entity.type + ':' + entity.name),
      date: date,
      month: month,
      startDate: startDate,
      endDate: endDate,
      workflowSceneIds: [],
      limit: limit
    };
    let publicQuery: QueryEventsPublicQuery = {
      keywords: keywords.slice(),
      domains: domains.slice(),
      entities: entities,
      date: date,
      month: month,
      start_date: startDate,
      end_date: endDate,
      limit: limit
    };
    return {
      ok: true,
      options: options,
      publicQuery: publicQuery,
      error: ''
    };
  } catch (e) {
    let err = e as Error;
    return {
      ok: false,
      options: emptyQueryOptions(),
      publicQuery: emptyPublicQuery(),
      error: err.message
    };
  }
}

function assertAllowedFields(args: QueryEventsJsonMap): void {
  let allowed: string[] = ['keywords', 'domains', 'entities', 'date', 'month', 'start_date', 'end_date', 'limit'];
  Object.keys(args).forEach((key: string) => {
    if (allowed.indexOf(key) < 0) {
      throw new Error('Unsupported query_events argument: ' + key);
    }
  });
}

function readStringArray(args: QueryEventsJsonMap, key: string): string[] {
  if (!hasField(args, key)) {
    return [];
  }
  let value = args[key];
  if (!Array.isArray(value)) {
    throw new Error(key + ' must be an array of strings.');
  }
  let items = value as QueryEventsJsonValue[];
  let result: string[] = [];
  for (let index = 0; index < items.length; index++) {
    let item = items[index];
    if (typeof item !== 'string') {
      throw new Error(key + '[' + String(index) + '] must be a string.');
    }
    let text = normalizeFreeText(item);
    if (text.length > 0) {
      result.push(text);
    }
  }
  return stableUnique(result);
}

function readDomains(args: QueryEventsJsonMap): string[] {
  let domains = readStringArray(args, 'domains').map((item: string): string => item.toLowerCase());
  for (let domain of domains) {
    if (DOMAIN_KEYS.indexOf(domain) < 0) {
      throw new Error('domains contains unsupported value: ' + domain);
    }
  }
  return stableUnique(domains);
}

function readEntities(args: QueryEventsJsonMap): QueryEventsEntityInput[] {
  if (!hasField(args, 'entities')) {
    return [];
  }
  let value = args['entities'];
  if (!Array.isArray(value)) {
    throw new Error('entities must be an array of objects.');
  }
  let items = value as QueryEventsJsonValue[];
  let result: QueryEventsEntityInput[] = [];
  let seen: Record<string, boolean> = {};
  for (let index = 0; index < items.length; index++) {
    let item = items[index];
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('entities[' + String(index) + '] must be an object.');
    }
    let entity = readEntity(item as QueryEventsJsonMap, index);
    let key = entity.type + ':' + entity.name;
    if (!seen[key]) {
      seen[key] = true;
      result.push(entity);
    }
  }
  return result;
}

function readEntity(entity: QueryEventsJsonMap, index: number): QueryEventsEntityInput {
  let allowed: string[] = ['type', 'name'];
  Object.keys(entity).forEach((key: string) => {
    if (allowed.indexOf(key) < 0) {
      throw new Error('entities[' + String(index) + '] has unsupported field: ' + key);
    }
  });
  let type = readRequiredString(entity, 'type', 'entities[' + String(index) + '].type').toLowerCase();
  let name = readRequiredString(entity, 'name', 'entities[' + String(index) + '].name');
  if (ENTITY_TYPES.indexOf(type) < 0) {
    throw new Error('entities[' + String(index) + '].type must be person, place, or merchant.');
  }
  return {
    type: type,
    name: name
  };
}

function readRequiredString(args: QueryEventsJsonMap, key: string, label: string): string {
  if (!hasField(args, key)) {
    throw new Error(label + ' is required.');
  }
  let value = args[key];
  if (typeof value !== 'string') {
    throw new Error(label + ' must be a string.');
  }
  let text = normalizeFreeText(value);
  if (text.length === 0) {
    throw new Error(label + ' must not be empty.');
  }
  return text;
}

function readOptionalString(args: QueryEventsJsonMap, key: string): string {
  if (!hasField(args, key)) {
    return '';
  }
  let value = args[key];
  if (typeof value !== 'string') {
    throw new Error(key + ' must be a string.');
  }
  return normalizeFreeText(value);
}

function readDateField(args: QueryEventsJsonMap, key: string): string {
  let value = readOptionalString(args, key);
  if (value.length === 0) {
    return '';
  }
  if (!isCalendarDate(value)) {
    throw new Error(key + ' must use YYYY-MM-DD and be a valid calendar date.');
  }
  return value;
}

function readMonthField(args: QueryEventsJsonMap, key: string): string {
  let value = readOptionalString(args, key);
  if (value.length === 0) {
    return '';
  }
  if (!/^\d{4}-\d{2}$/.test(value)) {
    throw new Error(key + ' must use YYYY-MM.');
  }
  let month = Number(value.substring(5, 7));
  if (month < 1 || month > 12) {
    throw new Error(key + ' must contain a month from 01 to 12.');
  }
  return value;
}

function validateTimeMode(date: string, month: string, startDate: string, endDate: string): void {
  let rangeUsed = startDate.length > 0 || endDate.length > 0;
  if (date.length > 0 && (month.length > 0 || rangeUsed)) {
    throw new Error('Use only one time filter mode: date, month, or start_date/end_date.');
  }
  if (month.length > 0 && rangeUsed) {
    throw new Error('Use only one time filter mode: date, month, or start_date/end_date.');
  }
  if (startDate.length > 0 && endDate.length > 0 && startDate > endDate) {
    throw new Error('start_date must be earlier than or equal to end_date.');
  }
}

function readLimit(args: QueryEventsJsonMap): number {
  if (!hasField(args, 'limit')) {
    return DEFAULT_QUERY_EVENTS_LIMIT;
  }
  let value = args['limit'];
  if (typeof value !== 'number' || isNaN(value) || Math.floor(value) !== value || value < 0) {
    throw new Error('limit must be a non-negative integer.');
  }
  return value;
}

function queryEventsToolResponse(query: QueryEventsPublicQuery, result: QueryResult): QueryEventsToolResponse {
  let events = result.events.map((event: IndexedEvent): QueryEventsToolEvent => publicToolEvent(event));
  return {
    ok: true,
    query: query,
    total_events: result.total_events,
    returned_events: events.length,
    events_truncated: result.events_truncated,
    events: events
  };
}

function publicToolEvent(event: IndexedEvent): QueryEventsToolEvent {
  return {
    event_id: event.event_id,
    event_date: event.event_date,
    last_seen_date: event.last_seen_date,
    summary: event.summary,
    normalized_fact: event.normalized_fact,
    domains: (event.domains || []).slice(),
    keywords: (event.keywords || []).slice(),
    entities: (event.entities || []).slice(),
    sources: (event.sources || []).slice(),
    source_refs: (event.source_refs || []).slice(),
    image_paths: (event.image_paths || []).slice(),
    todo: event.todo
  };
}

function queryEventsToolErrorPayload(error: string): string {
  let response: QueryEventsToolErrorResponse = {
    ok: false,
    error: error
  };
  return ArkJSON.stringify(response as Object);
}

function emptyQueryOptions(): QueryOptions {
  return {
    keywords: [],
    domains: [],
    entities: [],
    date: '',
    month: '',
    startDate: '',
    endDate: '',
    workflowSceneIds: [],
    limit: DEFAULT_QUERY_EVENTS_LIMIT
  };
}

function emptyPublicQuery(): QueryEventsPublicQuery {
  return {
    keywords: [],
    domains: [],
    entities: [],
    date: '',
    month: '',
    start_date: '',
    end_date: '',
    limit: DEFAULT_QUERY_EVENTS_LIMIT
  };
}

function hasField(args: QueryEventsJsonMap, key: string): boolean {
  return Object.keys(args).indexOf(key) >= 0;
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  let year = Number(value.substring(0, 4));
  let month = Number(value.substring(5, 7));
  let day = Number(value.substring(8, 10));
  let date = new Date(year, month - 1, day);
  return !isNaN(date.getTime()) && date.getFullYear() === year && date.getMonth() === month - 1 &&
    date.getDate() === day;
}

function createSchemaMap(): QueryEventsSchemaMap {
  return new Object() as QueryEventsSchemaMap;
}

function stringSchema(description: string): QueryEventsSchemaMap {
  let schema = createSchemaMap();
  schema['type'] = 'string';
  schema['description'] = description;
  return schema;
}

function numberSchema(description: string): QueryEventsSchemaMap {
  let schema = createSchemaMap();
  schema['type'] = 'integer';
  schema['description'] = description;
  schema['minimum'] = 0;
  return schema;
}

function stringArraySchema(description: string): QueryEventsSchemaMap {
  let schema = createSchemaMap();
  schema['type'] = 'array';
  schema['description'] = description;
  schema['items'] = stringSchema('单个查询词。') as Object;
  return schema;
}

function enumArraySchema(description: string, values: string[]): QueryEventsSchemaMap {
  let schema = createSchemaMap();
  schema['type'] = 'array';
  schema['description'] = description;
  let item = stringSchema('单个领域枚举值。');
  item['enum'] = values as Object;
  schema['items'] = item as Object;
  return schema;
}

function entitiesArraySchema(): QueryEventsSchemaMap {
  let typeSchema = stringSchema('实体类型。person 表示人，place 表示地点，merchant 表示商户或服务方。');
  typeSchema['enum'] = ENTITY_TYPES as Object;
  let nameSchema = stringSchema('实体名称，例如“张三”“上海虹桥站”“星巴克”。');
  let entityProperties = createSchemaMap();
  entityProperties['type'] = typeSchema as Object;
  entityProperties['name'] = nameSchema as Object;
  let entityItem = createSchemaMap();
  entityItem['type'] = 'object';
  entityItem['description'] = '实体过滤条件。多个实体之间是 OR 关系，并会与关键词、领域、时间等其他过滤条件取 AND。';
  entityItem['properties'] = entityProperties as Object;
  entityItem['required'] = ['type', 'name'] as Object;
  entityItem['additionalProperties'] = false;
  let schema = createSchemaMap();
  schema['type'] = 'array';
  schema['description'] = '实体过滤列表，用于按人物、地点、商户/服务方查询事件。';
  schema['items'] = entityItem as Object;
  return schema;
}
