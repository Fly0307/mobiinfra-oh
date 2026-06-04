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
  sourceDisplayName
} from '../main/ets/datamanager/DataManagerUtils';
import {
  heuristicCollectionGroups,
  normalizeCollectionGroups
} from '../main/ets/datamanager/CollectionGroupingService';
import {
  isQueryResultTruncated,
  resolveQueryLimit
} from '../main/ets/datamanager/IndexService';
import {
  AggregatedRecord,
  CandidateFact,
  CollectionGroupState,
  IndexedEvent,
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
    keywords: [keyword],
    domains: [domain],
    entity_mentions: [],
    enrichment_method: 'test',
    entities: [],
    profile_domains: [domain]
  };
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
  });
}

