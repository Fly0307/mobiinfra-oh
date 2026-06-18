import { JSON as ArkJSON } from '@kit.ArkTS';
import { describe, it, expect } from '@ohos/hypium';
import {
  createQueryEventsTool,
  normalizeQueryEventsToolArguments,
  queryEventsToolParameters
} from '../main/ets/datamanager/DataManagerQueryEventsTool';
import {
  IndexedEvent,
  QueryOptions,
  QueryResult
} from '../main/ets/datamanager/DataManagerTypes';
import { ChatToolExecutionContext } from '../main/ets/utils/ChatToolRegistry';

type TestJsonValue = Object | string | number | boolean | null;
type TestJsonMap = Record<string, TestJsonValue>;

function toolContext(): ChatToolExecutionContext {
  return {
    filesDir: '',
    sessionId: 'test-session',
    userMessage: '查询咖啡记录'
  };
}

function demoIndexedEvent(): IndexedEvent {
  return {
    event_id: 'e1',
    source_state_file: '2026-06/demo.md.state.json',
    record_id: 1,
    event_date: '2026-06-18',
    last_seen_date: '2026-06-18',
    summary: '微信里提到要买咖啡豆',
    normalized_fact: '用户想购买咖啡豆',
    tags: [],
    source_refs: ['workflows/daily-log/2026-06-18/demo.md#1'],
    sources: ['微信'],
    workflow_scene_ids: [3],
    image_paths: [],
    todo: {
      type: 'buy',
      deadline: '',
      text: '购买咖啡豆',
      agent_task: ''
    },
    keywords: ['咖啡豆'],
    domains: ['eat'],
    entity_mentions: [],
    enrichment_method: 'test',
    entities: ['merchant:星巴克'],
    profile_domains: ['eat']
  };
}

function emptyQueryResult(): QueryResult {
  return {
    total_events: 0,
    events: [],
    events_truncated: false
  };
}

function fieldHasDescription(properties: TestJsonMap, key: string): boolean {
  let field = properties[key] as TestJsonMap;
  let description = field['description'];
  return typeof description === 'string' && (description as string).length > 0;
}

export default function dataManagerQueryEventsToolUnitTest() {
  describe('dataManagerQueryEventsToolUnitTest', () => {
    it('schemaDescribesAllExposedFieldsAndHidesWorkflowSceneIds', 0, () => {
      let parameters = queryEventsToolParameters() as TestJsonMap;
      let properties = parameters['properties'] as TestJsonMap;
      let fields = ['keywords', 'keyword_operator', 'domains', 'entities', 'date', 'month', 'start_date',
        'end_date', 'limit'];
      for (let field of fields) {
        expect(fieldHasDescription(properties, field)).assertTrue();
      }
      expect(properties['workflow_scene_ids'] === undefined).assertTrue();

      let entities = properties['entities'] as TestJsonMap;
      let entityItems = entities['items'] as TestJsonMap;
      expect(typeof entityItems['description']).assertEqual('string');
      let entityProperties = entityItems['properties'] as TestJsonMap;
      expect(fieldHasDescription(entityProperties, 'type')).assertTrue();
      expect(fieldHasDescription(entityProperties, 'name')).assertTrue();
    });

    it('normalizesKeywordsDomainsEntitiesAndDate', 0, () => {
      let validation = normalizeQueryEventsToolArguments('{"keywords":["咖啡","咖啡"],"domains":["eat"],' +
        '"entities":[{"type":"merchant","name":"星巴克"}],"date":"2026-06-18"}');

      expect(validation.ok).assertTrue();
      expect(validation.options.keywords.length).assertEqual(1);
      expect(validation.options.keywords[0]).assertEqual('咖啡');
      expect(validation.options.keywordOperator).assertEqual('and');
      expect(validation.options.domains[0]).assertEqual('eat');
      expect(validation.options.entities[0]).assertEqual('merchant:星巴克');
      expect(validation.options.date).assertEqual('2026-06-18');
      expect(validation.options.workflowSceneIds.length).assertEqual(0);
      expect(validation.options.limit).assertEqual(20);
    });

    it('normalizesKeywordOperator', 0, () => {
      let defaultValidation = normalizeQueryEventsToolArguments('{"keywords":["咖啡","奶茶"]}');
      expect(defaultValidation.ok).assertTrue();
      expect(defaultValidation.options.keywordOperator).assertEqual('and');
      expect(defaultValidation.publicQuery.keyword_operator).assertEqual('and');

      let orValidation = normalizeQueryEventsToolArguments('{"keywords":["咖啡","奶茶"],"keyword_operator":"OR"}');
      expect(orValidation.ok).assertTrue();
      expect(orValidation.options.keywordOperator).assertEqual('or');
      expect(orValidation.publicQuery.keyword_operator).assertEqual('or');
    });

    it('normalizesMonthRangeDefaultLimitAndUnlimitedLimit', 0, () => {
      let monthValidation = normalizeQueryEventsToolArguments('{"month":"2026-06"}');
      expect(monthValidation.ok).assertTrue();
      expect(monthValidation.options.month).assertEqual('2026-06');
      expect(monthValidation.options.limit).assertEqual(20);

      let rangeValidation = normalizeQueryEventsToolArguments('{"start_date":"2026-06-01","end_date":"2026-06-30"}');
      expect(rangeValidation.ok).assertTrue();
      expect(rangeValidation.options.startDate).assertEqual('2026-06-01');
      expect(rangeValidation.options.endDate).assertEqual('2026-06-30');

      let unlimitedValidation = normalizeQueryEventsToolArguments('{"limit":0}');
      expect(unlimitedValidation.ok).assertTrue();
      expect(unlimitedValidation.options.limit).assertEqual(0);
    });

    it('rejectsInvalidArguments', 0, () => {
      let invalidArgs = [
        '{"workflow_scene_ids":[3]}',
        '{"keyword_operator":"xor"}',
        '{"domains":["unknown"]}',
        '{"entities":[{"type":"app","name":"微信"}]}',
        '{"date":"2026-02-30"}',
        '{"date":"2026-06-18","month":"2026-06"}',
        '{"start_date":"2026-06-30","end_date":"2026-06-01"}',
        '{"limit":-1}'
      ];
      for (let args of invalidArgs) {
        let validation = normalizeQueryEventsToolArguments(args);
        expect(validation.ok).assertFalse();
        expect(validation.error.length > 0).assertTrue();
      }
    });

    it('returnsStructuredErrorWhenIndexesAreMissing', 0, async () => {
      let called = false;
      let tool = createQueryEventsTool((): boolean => false, (_options: QueryOptions): QueryResult => {
        called = true;
        return emptyQueryResult();
      });

      let output = await tool.execute('{"keywords":["咖啡"]}', toolContext());
      let payload = ArkJSON.parse(output) as TestJsonMap;

      expect(called).assertFalse();
      expect(payload['ok'] as boolean).assertFalse();
      expect(typeof payload['error']).assertEqual('string');
    });

    it('executesQueryAndReturnsCompactEvents', 0, async () => {
      let captured: QueryOptions = {
        keywords: [],
        keywordOperator: 'and',
        domains: [],
        entities: [],
        date: '',
        month: '',
        startDate: '',
        endDate: '',
        workflowSceneIds: [],
        limit: 20
      };
      let called = false;
      let queryResult: QueryResult = {
        total_events: 1,
        events: [demoIndexedEvent()],
        events_truncated: false
      };
      let tool = createQueryEventsTool((): boolean => true, (options: QueryOptions): QueryResult => {
        captured = options;
        called = true;
        return queryResult;
      });

      let output = await tool.execute('{"keywords":["咖啡"],"keyword_operator":"or","limit":1}', toolContext());
      let payload = ArkJSON.parse(output) as TestJsonMap;
      let query = payload['query'] as TestJsonMap;
      let events = payload['events'] as TestJsonValue[];

      expect(called).assertTrue();
      expect(captured.keywords[0]).assertEqual('咖啡');
      expect(captured.keywordOperator).assertEqual('or');
      expect(captured.workflowSceneIds.length).assertEqual(0);
      expect(captured.limit).assertEqual(1);
      expect(payload['ok'] as boolean).assertTrue();
      expect(query['keyword_operator'] as string).assertEqual('or');
      expect(payload['total_events'] as number).assertEqual(1);
      expect(payload['returned_events'] as number).assertEqual(1);
      expect(events.length).assertEqual(1);
      let event = events[0] as TestJsonMap;
      expect(event['summary'] as string).assertEqual('微信里提到要买咖啡豆');
      expect(event['workflow_scene_ids'] === undefined).assertTrue();
    });
  });
}
