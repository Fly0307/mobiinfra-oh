import { describe, it, expect } from '@ohos/hypium';
import {
  atomicizeCandidateFacts,
  findExactExistingMatch,
  eventSourceNames,
  indexTerms,
  normalizeProfileShortSummary,
  parseDailyLogDocument,
  parseNumberedEntries,
  profileShortSummaryFromText,
  sourceAppDisplayName,
  sourceDisplayName,
  weekdayLabelFromDate
} from '../main/ets/datamanager/DataManagerUtils';
import {
  heuristicCollectionGroups,
  normalizeCollectionGroups
} from '../main/ets/datamanager/CollectionGroupingService';
import { GalleryExifUtils } from '../main/ets/utils/gallery/GalleryExifUtils';
import {
  homeRecommendationSourceInputFingerprint,
  isHomeRecommendationSourceReusable,
  isCurrentOrFutureTodoDeadline,
  recommendationTodoDeadlineMeta
} from '../main/ets/datamanager/HomeRecommendationService';
import {
  eventEnrichInputFingerprint,
  isEventEnrichInputReusable,
  isHomeTodoIndexCandidate,
  isRecentNoDeadlineHomeTodoEvent,
  isQueryResultTruncated,
  resolveQueryLimit
} from '../main/ets/datamanager/IndexService';
import { shouldKeepTodoAgentTask } from '../main/ets/datamanager/DataPipelineModelClient';
import { setHomeRecommendationCompletedInDocument, shouldShowHomeRecommendationInView } from '../main/ets/datamanager/DataManagerFacade';
import {
  AggregatedRecord,
  CandidateFact,
  CollectionGroupState,
  HomeRecommendationsDocument,
  HomeRecommendationState,
  IndexedEvent,
  IndexedEventTodo,
  HomeRecommendationPlannerEvent,
  SourceEntry,
  createJsonMap
} from '../main/ets/datamanager/DataManagerTypes';

function demoIndexedEvent(id: string, summary: string, source: string, domain: string, keyword: string): IndexedEvent {
  return {
    event_id: id,
    source_state_file: '2026-05/demo.md.state.json',
    record_id: Number(id.replace('e', '')),
    event_date: '2026-05-29',
    last_seen_date: '2026-05-29',
    summary: summary,
    normalized_fact: summary,
    tags: [],
    source_refs: [],
    sources: [source],
    workflow_scene_ids: [3],
    image_paths: [],
    todo: {
      type: '',
      deadline: '',
      text: '',
      agent_task: ''
    },
    keywords: [keyword],
    domains: [domain],
    entity_mentions: [],
    enrichment_method: 'test',
    entities: [],
    profile_domains: [domain]
  };
}

function demoPlannerEvent(id: string, deadline: string, todoType: string = 'buy'): HomeRecommendationPlannerEvent {
  return {
    event_id: id,
    date: '2026-06-05',
    todo_type: todoType,
    todo_deadline: deadline,
    todo_text: '购买咖啡豆',
    summary: '微信里提到要买咖啡豆',
    normalized_fact: '用户想购买咖啡豆',
    sources: ['微信'],
    domains: ['eat'],
    keywords: ['咖啡豆'],
    image_paths: []
  };
}

function demoRecommendationState(id: string, completed: boolean): HomeRecommendationState {
  return {
    id: id,
    tag: '待购买',
    title: '购买咖啡豆',
    desc: '记得购买咖啡豆',
    meta: '',
    domain: 'eat',
    source_event_ids: ['e1'],
    source_input_hash: 'hash-' + id,
    completed: completed
  };
}

function demoHomeRecommendationEvent(id: string, eventDate: string, deadline: string): IndexedEvent {
  let event = demoIndexedEvent(id, '微信里提到一个待办事项', '微信', 'work', '待办');
  event.event_date = eventDate;
  event.todo = {
    type: deadline.length > 0 ? '' : 'buy',
    deadline: deadline,
    text: '处理待办事项',
    agent_task: ''
  };
  return event;
}

function demoEventMap(events: IndexedEvent[]): Record<string, IndexedEvent> {
  let map: Record<string, IndexedEvent> = new Object() as Record<string, IndexedEvent>;
  events.forEach((event: IndexedEvent) => {
    map[event.event_id] = event;
  });
  return map;
}

export default function dataManagerUnitTest() {
  describe('dataManagerUnitTest', () => {
    it('parseDailyLogDocument', 0, () => {
      let content = '<!-- DAILY_LOG_METADATA\n{"workflow_metadata":{"name":"demo"},"latest_entry_index":2}\n-->\n\n1. 第一条\n\n2. 第二条';
      let doc = parseDailyLogDocument(content);
      expect(doc.latest_entry_index).assertEqual(2);
      let entries = parseNumberedEntries(doc.body);
      expect(entries.length).assertEqual(2);
      expect(entries[0].index).assertEqual(1);
    });

    it('parseNumberedEntriesIgnoresNestedLists', 0, () => {
      let body = '1. 这段聊天记录主要围绕手机刷机故障处理展开，具体内容如下：\n' +
        '1. **故障描述**：手机出现 Magisk 图标异常。\n' +
        '2. **处理方案**：预约线下重新刷机。\n' +
        '3. **回应**：建议先暂停折腾。\n\n' +
        '2. 第二条顶层记录，讨论 workflow 替代 cli 的可行性。';
      let entries = parseNumberedEntries(body);
      expect(entries.length).assertEqual(2);
      expect(entries[0].index).assertEqual(1);
      expect(entries[0].text.indexOf('故障描述') >= 0).assertTrue();
      expect(entries[1].index).assertEqual(2);
    });

    it('sourceDisplayName', 0, () => {
      let source = sourceDisplayName('2026-05/com.tencent.wechat__01_basic_gui_task_weixin__WAIC-数据归家.md.state.json#1');
      expect(source).assertEqual('WAIC-数据归家');
      expect(sourceDisplayName('2026-05/com.tencent.wechat__01_basic_gui_task_weixin_v2__小赵.md.state.json#1')).assertEqual('小赵');
      expect(sourceAppDisplayName('2026-05/com.tencent.wechat__01_basic_gui_task_weixin_v2__小赵.md.state.json#1')).assertEqual('微信');
      expect(sourceDisplayName('2026-05/com.alipay.mobile.client__01_basic_gui_task_alipay.md.state.json#1')).assertEqual('支付宝');
      let wechatNames = eventSourceNames(
        ['2026-05/com.tencent.wechat__01_basic_gui_task_weixin_v2__小赵.md.state.json#1'],
        '2026-05/com.tencent.wechat__01_basic_gui_task_weixin_v2__小赵.md.state.json'
      );
      expect(wechatNames.length).assertEqual(2);
      expect(wechatNames[0]).assertEqual('微信');
      expect(wechatNames[1]).assertEqual('小赵');
      let xhsNames = eventSourceNames(
        ['2026-05/com.xingin.xhs_hos__01_basic_gui_task_xiaohongshu.md.state.json#1'],
        '2026-05/com.xingin.xhs_hos__01_basic_gui_task_xiaohongshu.md.state.json'
      );
      expect(xhsNames.length).assertEqual(1);
      expect(xhsNames[0]).assertEqual('小红书');
    });

    it('indexTerms', 0, () => {
      let terms = indexTerms('高德顺风车订单');
      expect(terms.indexOf('顺风') >= 0).assertTrue();
    });

    it('weekdayLabelFromDate', 0, () => {
      expect(weekdayLabelFromDate('2026-06-05')).assertEqual('星期五');
      expect(weekdayLabelFromDate('2026-06-06')).assertEqual('星期六');
      expect(weekdayLabelFromDate('bad-date')).assertEqual('');
      expect(weekdayLabelFromDate('2026-02-31')).assertEqual('');
    });

    it('profileShortSummaryNormalization', 0, () => {
      expect(normalizeProfileShortSummary('清淡轻食')).assertEqual('清淡轻食');
      expect(normalizeProfileShortSummary('清淡轻食。')).assertEqual('清淡轻食');
      expect(normalizeProfileShortSummary('健康轻食餐')).assertEqual('');
      expect(profileShortSummaryFromText('eat', '近期咖啡、奶茶等话题反复出现。', '')).assertEqual('咖啡奶茶');
      expect(profileShortSummaryFromText('travel', '', '近期记录')).assertEqual('近期记录');
    });

    it('atomicizeCandidateFacts', 0, () => {
      let entry: SourceEntry = {
        source_date: '2026-05-21',
        file_name: 'demo.md',
        entry_index: 1,
        entry_text: '当前页面显示了订单记录，其中最近一单是潮汕牛肉火锅实付25.8元，第二单是大米先生实付23.9元。',
        workflow_metadata: createJsonMap(),
        workflow_scene_id: 1,
        source_ref: '2026-05-21/demo.md#1'
      };
      let fact: CandidateFact = {
        summary: entry.entry_text,
        normalized_fact: entry.entry_text,
        event_date: '2026-05-21',
        tags: [],
        model_notes: 'test',
        raw_excerpt: entry.entry_text,
        source_ref: entry.source_ref,
        source_date: entry.source_date,
        workflow_scene_id: entry.workflow_scene_id,
        dedup_text: entry.entry_text
      };
      let facts = atomicizeCandidateFacts(entry, [fact]);
      expect(facts.length).assertEqual(2);
      expect(facts[0].normalized_fact.indexOf('25.8元') >= 0).assertTrue();
      expect(facts[1].normalized_fact.indexOf('23.9元') >= 0).assertTrue();
    });

    it('findExactExistingMatchSameSourceNeedsSameFact', 0, () => {
      let record: AggregatedRecord = {
        record_id: 1,
        first_seen_date: '2026-05-21',
        last_seen_date: '2026-05-21',
        source_refs: ['2026-05-21/demo.md#1'],
        source_dates: ['2026-05-21'],
        workflow_scene_ids: [1],
        summary: '潮汕牛肉火锅实付25.8元',
        normalized_fact: '潮汕牛肉火锅实付25.8元',
        raw_excerpts: [],
        tags: [],
        dedup_status: 'new',
        model_notes: [],
        dedup_text: '潮汕牛肉火锅实付25.8元'
      };
      let fact: CandidateFact = {
        summary: '大米先生实付23.9元',
        normalized_fact: '大米先生实付23.9元',
        event_date: '2026-05-21',
        tags: [],
        model_notes: 'test',
        raw_excerpt: '',
        source_ref: '2026-05-21/demo.md#1',
        source_date: '2026-05-21',
        workflow_scene_id: 1,
        dedup_text: '大米先生实付23.9元'
      };
      let match = findExactExistingMatch([record], fact);
      expect(match === null).assertTrue();
    });

    it('normalizeCollectionGroupsValidatesIdsAndBackfills', 0, () => {
      let events = [
        demoIndexedEvent('e1', '微信里讨论晚餐计划', '微信聊天', 'eat', '晚餐'),
        demoIndexedEvent('e2', '微信里讨论周末晚餐', '微信聊天', 'eat', '晚餐'),
        demoIndexedEvent('e3', '微信里讨论出游路线', '微信聊天', 'travel', '出游')
      ];
      let candidate: CollectionGroupState = {
        group_id: 'raw-1',
        title: '晚餐计划',
        source: '微信聊天',
        time: '',
        meta: '',
        status: '',
        domain: 'eat',
        event_ids: ['e1', 'missing', 'e1', 'e2']
      };
      let groups = normalizeCollectionGroups('chat', '最近聊天', events, [candidate]);
      let ids: string[] = [];
      groups.forEach((group: CollectionGroupState) => ids = ids.concat(group.event_ids));
      expect(groups.length >= 2).assertTrue();
      expect(ids.indexOf('missing') < 0).assertTrue();
      expect(ids.length).assertEqual(3);
    });

    it('heuristicCollectionGroupsByChatTopic', 0, () => {
      let events = [
        demoIndexedEvent('e1', '微信里讨论晚餐计划', '微信聊天', 'eat', '晚餐'),
        demoIndexedEvent('e2', '微信里继续讨论晚餐安排', '微信聊天', 'eat', '晚餐')
      ];
      let groups = heuristicCollectionGroups('chat', '最近聊天', events);
      expect(groups.length).assertEqual(1);
      expect(groups[0].event_ids.length).assertEqual(2);
    });

    it('normalizeChatGroupsUsesGenericFallbackForLowInformationTitles', 0, () => {
      let events = [
        demoIndexedEvent('e1', '联系人甲讨论一个待处理事项，后续需要继续确认。', '联系人甲', 'work', '12'),
        demoIndexedEvent('e2', '联系人乙发来一张截图，并围绕截图里的信息继续沟通。', '联系人乙', 'work', '截图'),
        demoIndexedEvent('e3', '联系人丙围绕一个技术配置项和用户继续沟通。', '联系人丙', 'work', 'API')
      ];
      let candidates: CollectionGroupState[] = [
        { group_id: 'raw-1', title: '12讨论', source: '联系人甲', time: '', meta: '', status: '', domain: 'work', event_ids: ['e1'] },
        { group_id: 'raw-2', title: '截图讨论', source: '联系人乙', time: '', meta: '', status: '', domain: 'work', event_ids: ['e2'] },
        { group_id: 'raw-3', title: 'API讨论', source: '联系人丙', time: '', meta: '', status: '', domain: 'work', event_ids: ['e3'] }
      ];
      let groups = normalizeCollectionGroups('chat', '最近聊天', events, candidates);
      let titles = groups.map((group: CollectionGroupState) => group.title).join('|');
      expect(titles.indexOf('12讨论') < 0).assertTrue();
      expect(titles.indexOf('截图讨论') < 0).assertTrue();
      expect(titles.indexOf('API讨论') < 0).assertTrue();
      expect(titles.indexOf('与联系人甲的对话') >= 0).assertTrue();
      expect(titles.indexOf('与联系人乙的对话') >= 0).assertTrue();
      expect(titles.indexOf('与联系人丙的对话') >= 0).assertTrue();
    });

    it('indexQueryLimitZeroReturnsAll', 0, () => {
      expect(resolveQueryLimit(2, 0)).assertEqual(2);
      expect(isQueryResultTruncated(2, 0)).assertFalse();
      expect(resolveQueryLimit(2, 1)).assertEqual(1);
      expect(isQueryResultTruncated(2, 1)).assertTrue();
    });

    it('galleryExifCoordinateParsesDmsAndRef', 0, () => {
      let latitude = GalleryExifUtils.coordinateFromExif('31/1, 12/1, 3000/100', 'N');
      let longitude = GalleryExifUtils.coordinateFromExif('121, 30, 0', 'E');
      expect(latitude !== undefined).assertTrue();
      expect(longitude !== undefined).assertTrue();
      expect(Math.abs((latitude as number) - 31.208333) < 0.00001).assertTrue();
      expect(Math.abs((longitude as number) - 121.5) < 0.00001).assertTrue();

      let west = GalleryExifUtils.coordinateFromExif('73/1, 59/1, 0/1', 'W');
      expect(west !== undefined).assertTrue();
      expect((west as number) < 0).assertTrue();

      let symbolLatitude = GalleryExifUtils.coordinateFromExif('31°12′30″', 'N');
      expect(symbolLatitude !== undefined).assertTrue();
      expect(Math.abs((symbolLatitude as number) - 31.208333) < 0.00001).assertTrue();
    });

    it('galleryExifRawGpsLocationFallback', 0, () => {
      let text = GalleryExifUtils.rawGpsLocationText({
        gpsLatitude: '31/1, 12/1, 3000/100',
        gpsLongitude: '121/1, 30/1, 0/1',
        gpsLatitudeRef: 'N',
        gpsLongitudeRef: 'E'
      });
      expect(text).assertEqual('31/1, 12/1, 3000/100 N, 121/1, 30/1, 0/1 E');
    });

    it('galleryExifLocationDirectionAndMapUrl', 0, () => {
      expect(GalleryExifUtils.directedLocationText(31.024267, 121.437828))
        .assertEqual('北纬 31.024267，东经 121.437828');
      expect(GalleryExifUtils.directedLocationText(-31.024267, -121.437828))
        .assertEqual('南纬 31.024267，西经 121.437828');
      let url = GalleryExifUtils.mapUrl(31.024267, 121.437828);
      expect(url.indexOf('position=121.437828,31.024267') >= 0).assertTrue();
    });

    it('galleryExifDateNormalizesOriginalTime', 0, () => {
      expect(GalleryExifUtils.dateFromExifDateTime('2024:06:17 14:03:02')).assertEqual('2024-06-17');
      expect(GalleryExifUtils.displayDateTime('2024:06:17 14:03:02')).assertEqual('2024-06-17 14:03:02');
      expect(GalleryExifUtils.dateFromExifDateTime('')).assertEqual('');
    });

    it('homeRecommendationTodoDeadlineFilter', 0, () => {
      expect(isCurrentOrFutureTodoDeadline('2026-06-06', '2026-06-05')).assertTrue();
      expect(isCurrentOrFutureTodoDeadline('2026-06-05', '2026-06-05')).assertTrue();
      expect(isCurrentOrFutureTodoDeadline('2026-06-04', '2026-06-05')).assertFalse();
      expect(isCurrentOrFutureTodoDeadline('', '2026-06-05')).assertFalse();
      expect(recommendationTodoDeadlineMeta('2026-06-06')).assertEqual('6月6日截止');
    });

    it('homeRecommendationSourceFingerprintTracksPlannerInputs', 0, () => {
      let event = demoPlannerEvent('e1', '2026-06-06');
      let fingerprint = homeRecommendationSourceInputFingerprint([event]);
      let changedTodo = demoPlannerEvent('e1', '2026-06-06');
      changedTodo.todo_text = '购买咖啡豆和滤纸';
      expect(homeRecommendationSourceInputFingerprint([changedTodo]) !== fingerprint).assertTrue();
      let changedSummary = demoPlannerEvent('e1', '2026-06-06');
      changedSummary.summary = '微信里提到要买咖啡豆和滤纸';
      expect(homeRecommendationSourceInputFingerprint([changedSummary]) !== fingerprint).assertTrue();
      let sameContent = demoPlannerEvent('e1', '2026-06-06');
      expect(homeRecommendationSourceInputFingerprint([sameContent])).assertEqual(fingerprint);
    });

    it('homeRecommendationSourceReuseRequiresCandidateHashAndNoOverlap', 0, () => {
      expect(isHomeRecommendationSourceReusable('hash-1', 'hash-1', ['e1'], ['e1', 'e2'], [])).assertTrue();
      expect(isHomeRecommendationSourceReusable('hash-1', 'hash-2', ['e1'], ['e1', 'e2'], [])).assertFalse();
      expect(isHomeRecommendationSourceReusable('hash-1', 'hash-1', ['e1'], ['e2'], [])).assertFalse();
      expect(isHomeRecommendationSourceReusable('hash-1', 'hash-1', ['e1'], ['e1', 'e2'], ['e1'])).assertFalse();
      expect(isHomeRecommendationSourceReusable('', 'hash-1', ['e1'], ['e1'], [])).assertFalse();
    });

    it('homeRecommendationCompletionDocumentToggle', 0, () => {
      let document: HomeRecommendationsDocument = {
        generated_at: '2026-06-05T00:00:00',
        input_hash: 'input',
        total_events: 1,
        recommendations: [demoRecommendationState('todo-1', false)]
      };
      expect(setHomeRecommendationCompletedInDocument(document, 'todo-1', true)).assertTrue();
      expect(document.recommendations[0].completed).assertTrue();
      expect(setHomeRecommendationCompletedInDocument(document, 'todo-1', false)).assertTrue();
      expect(document.recommendations[0].completed).assertFalse();
      expect(setHomeRecommendationCompletedInDocument(document, 'missing', true)).assertFalse();
      expect(document.recommendations[0].completed).assertFalse();
    });

    it('homeRecommendationViewFilterKeepsFutureDeadlineEvenWhenEventOld', 0, () => {
      let event = demoHomeRecommendationEvent('e1', '2026-05-01', '2026-06-10');
      let map = demoEventMap([event]);
      expect(shouldShowHomeRecommendationInView(['e1'], map, '2026-06-09')).assertTrue();
    });

    it('homeRecommendationViewFilterKeepsTodayDeadlineAndRejectsPastDeadline', 0, () => {
      let todayEvent = demoHomeRecommendationEvent('e1', '2026-06-09', '2026-06-09');
      let pastEvent = demoHomeRecommendationEvent('e2', '2026-06-08', '2026-06-08');
      expect(shouldShowHomeRecommendationInView(['e1'], demoEventMap([todayEvent]), '2026-06-09')).assertTrue();
      expect(shouldShowHomeRecommendationInView(['e2'], demoEventMap([pastEvent]), '2026-06-09')).assertFalse();
    });

    it('homeRecommendationViewFilterKeepsRecentNoDeadlineEvent', 0, () => {
      let event = demoHomeRecommendationEvent('e1', '2026-06-02', '');
      let map = demoEventMap([event]);
      expect(shouldShowHomeRecommendationInView(['e1'], map, '2026-06-09')).assertTrue();
    });

    it('homeRecommendationViewFilterRejectsOldNoDeadlineEvent', 0, () => {
      let event = demoHomeRecommendationEvent('e1', '2026-06-01', '');
      let map = demoEventMap([event]);
      expect(shouldShowHomeRecommendationInView(['e1'], map, '2026-06-09')).assertFalse();
    });

    it('homeRecommendationViewFilterRejectsMissingOrPartiallyExpiredSources', 0, () => {
      let recent = demoHomeRecommendationEvent('e1', '2026-06-08', '');
      let old = demoHomeRecommendationEvent('e2', '2026-06-01', '');
      expect(shouldShowHomeRecommendationInView(['missing'], demoEventMap([recent]), '2026-06-09')).assertFalse();
      expect(shouldShowHomeRecommendationInView(['e1', 'e2'], demoEventMap([recent, old]), '2026-06-09')).assertFalse();
    });

    it('homeRecommendationGenerationFilterUsesRecentNoDeadlineWindow', 0, () => {
      expect(isRecentNoDeadlineHomeTodoEvent('2026-06-02', '2026-06-09', 7)).assertTrue();
      expect(isRecentNoDeadlineHomeTodoEvent('2026-06-01', '2026-06-09', 7)).assertFalse();
      expect(isRecentNoDeadlineHomeTodoEvent('2026-06-08', '2026-06-09', 7)).assertTrue();
      expect(isRecentNoDeadlineHomeTodoEvent('', '2026-06-09', 7)).assertFalse();
    });

    it('homeTodoIndexAllowsChatBuyWithoutDeadline', 0, () => {
      let todo: IndexedEventTodo = { type: 'buy', deadline: '', text: '购买咖啡豆', agent_task: '在淘宝中购买咖啡豆' };
      expect(isHomeTodoIndexCandidate(todo, [3], [3])).assertTrue();
    });

    it('homeTodoIndexRejectsNonBuyChatWithoutDeadline', 0, () => {
      let todo: IndexedEventTodo = { type: 'plan', deadline: '', text: '安排周末聚餐', agent_task: '' };
      expect(isHomeTodoIndexCandidate(todo, [3], [3])).assertFalse();
    });

    it('agentTaskOnlyKeptForPureChatBuyTodo', 0, () => {
      expect(shouldKeepTodoAgentTask('buy', ['聊天'])).assertTrue();
      expect(shouldKeepTodoAgentTask('buy', ['聊天', '购物'])).assertFalse();
      expect(shouldKeepTodoAgentTask('buy', ['购物'])).assertFalse();
      expect(shouldKeepTodoAgentTask('plan', ['聊天'])).assertFalse();
    });

    it('eventEnrichInputFingerprintIgnoresGeneratedTodo', 0, () => {
      let event = demoIndexedEvent('e1', '微信里提到要买咖啡豆', '微信', 'eat', '咖啡豆');
      event.source_refs = ['2026-06-05/demo.md#1'];
      event.workflow_scene_ids = [3];
      let fingerprint = eventEnrichInputFingerprint(event);
      event.todo = { type: 'buy', deadline: '', text: '购买咖啡豆', agent_task: '在淘宝中购买咖啡豆' };
      expect(eventEnrichInputFingerprint(event)).assertEqual(fingerprint);
    });

    it('eventEnrichInputFingerprintChangesWhenEnrichInputsChange', 0, () => {
      let event = demoIndexedEvent('e1', '微信里提到要买咖啡豆', '微信', 'eat', '咖啡豆');
      event.source_refs = ['2026-06-05/demo.md#1'];
      event.workflow_scene_ids = [3];
      event.image_paths = ['workflows/runs/demo/a.png'];
      let fingerprint = eventEnrichInputFingerprint(event);
      event.summary = '微信里提到要买咖啡豆和滤纸';
      expect(eventEnrichInputFingerprint(event) !== fingerprint).assertTrue();
      event.summary = '微信里提到要买咖啡豆';
      event.source_refs = ['2026-06-05/demo.md#1', '2026-06-05/demo.md#2'];
      expect(eventEnrichInputFingerprint(event) !== fingerprint).assertTrue();
      event.source_refs = ['2026-06-05/demo.md#1'];
      event.workflow_scene_ids = [3, 4];
      expect(eventEnrichInputFingerprint(event) !== fingerprint).assertTrue();
      event.workflow_scene_ids = [3];
      event.image_paths = ['workflows/runs/demo/b.png'];
      expect(eventEnrichInputFingerprint(event) !== fingerprint).assertTrue();
    });

    it('eventEnrichInputReuseRequiresMatchingHashAndPreviousEvent', 0, () => {
      expect(isEventEnrichInputReusable('hash-1', 'hash-1', true)).assertTrue();
      expect(isEventEnrichInputReusable('hash-1', 'hash-2', true)).assertFalse();
      expect(isEventEnrichInputReusable('hash-1', 'hash-1', false)).assertFalse();
      expect(isEventEnrichInputReusable('', 'hash-1', true)).assertFalse();
    });
  });
}
