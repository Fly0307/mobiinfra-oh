import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
  DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
  DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES,
  DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED,
  DEFAULT_WECHAT_AUTO_SUMMARY_WAIT,
  normalizeWechatAutoSummaryDays,
  normalizeWechatAutoSummaryHistorySwipeRatio,
  normalizeWechatAutoSummaryMaxHistorySwipes,
  normalizeWechatAutoSummaryMaxContacts,
  normalizeWechatAutoSummaryMode,
  normalizeWechatAutoSummaryStableSwipes,
  normalizeWechatAutoSummarySwipeSpeed,
  normalizeWechatAutoSummaryWait,
  validateWechatAutoSummaryRequest,
  WECHAT_AUTO_SUMMARY_MODE_RECENT,
  WECHAT_AUTO_SUMMARY_MODE_TARGET,
  WechatAutoSummaryConversation,
  WechatAutoSummaryJsonMap,
  WechatAutoSummaryRequest,
  WechatAutoSummaryResponse,
  WechatAutoSummaryTimeRange
} from '../main/ets/utils/wechat/WechatAutoSummaryTypes';
import {
  renderWechatAutoSummaryDailyLog,
  wechatAutoSummaryRunDir
} from '../main/ets/utils/wechat/WechatAutoSummaryStorage';

function demoRequest(mode: string, targetContact: string): WechatAutoSummaryRequest {
  return {
    mode: mode,
    days: 7,
    max_contacts: 10,
    target_contact: targetContact,
    swipe_speed: 2500,
    history_swipe_ratio: 0.65,
    stable_swipes: 3,
    max_history_swipes: 80,
    wait: 1.0
  };
}

export default function wechatAutoSummaryUnitTest() {
  describe('wechatAutoSummaryUnitTest', () => {
    it('normalizesDefaultsAndRanges', 0, () => {
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_DAYS).assertEqual('7');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS).assertEqual('10');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED).assertEqual('2500');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO).assertEqual('0.65');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES).assertEqual('3');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES).assertEqual('80');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_WAIT).assertEqual('1.0');
      expect(normalizeWechatAutoSummaryDays('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryDays('120')).assertEqual(90);
      expect(normalizeWechatAutoSummaryDays('')).assertEqual(7);
      expect(normalizeWechatAutoSummaryDays('bad')).assertEqual(7);
      expect(normalizeWechatAutoSummaryDays('7.6')).assertEqual(7);
      expect(normalizeWechatAutoSummaryMaxContacts('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryMaxContacts('80')).assertEqual(50);
      expect(normalizeWechatAutoSummaryMaxContacts('')).assertEqual(10);
      expect(normalizeWechatAutoSummaryMaxContacts('bad')).assertEqual(10);
      expect(normalizeWechatAutoSummaryMaxContacts('10.4')).assertEqual(10);
    });

    it('normalizesModes', 0, () => {
      expect(normalizeWechatAutoSummaryMode(WECHAT_AUTO_SUMMARY_MODE_TARGET))
        .assertEqual(WECHAT_AUTO_SUMMARY_MODE_TARGET);
      expect(normalizeWechatAutoSummaryMode('bad')).assertEqual(WECHAT_AUTO_SUMMARY_MODE_RECENT);
    });

    it('normalizesCollectionParameters', 0, () => {
      expect(normalizeWechatAutoSummarySwipeSpeed('-1')).assertEqual(0);
      expect(normalizeWechatAutoSummarySwipeSpeed('25001')).assertEqual(20000);
      expect(normalizeWechatAutoSummarySwipeSpeed('bad')).assertEqual(2500);
      expect(normalizeWechatAutoSummaryHistorySwipeRatio('0')).assertEqual(0.1);
      expect(normalizeWechatAutoSummaryHistorySwipeRatio('2')).assertEqual(0.95);
      expect(normalizeWechatAutoSummaryHistorySwipeRatio('bad')).assertEqual(0.65);
      expect(normalizeWechatAutoSummaryStableSwipes('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryStableSwipes('11')).assertEqual(10);
      expect(normalizeWechatAutoSummaryMaxHistorySwipes('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryMaxHistorySwipes('400')).assertEqual(300);
      expect(normalizeWechatAutoSummaryWait('-1')).assertEqual(0);
      expect(normalizeWechatAutoSummaryWait('11')).assertEqual(10);
      expect(normalizeWechatAutoSummaryWait('bad')).assertEqual(1.0);
    });

    it('validatesTargetContactForTargetMode', 0, () => {
      expect(validateWechatAutoSummaryRequest(demoRequest(WECHAT_AUTO_SUMMARY_MODE_TARGET, ' ')).length > 0)
        .assertTrue();
      expect(validateWechatAutoSummaryRequest(demoRequest(WECHAT_AUTO_SUMMARY_MODE_TARGET, '小赵'))).assertEqual('');
      expect(validateWechatAutoSummaryRequest(demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, ''))).assertEqual('');
      expect(validateWechatAutoSummaryRequest(demoRequest('bad', '')).length > 0).assertTrue();
    });

    it('validatesCollectionParameterRanges', 0, () => {
      let request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.days = 0;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.max_contacts = 80;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.swipe_speed = -1;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.history_swipe_ratio = 1.2;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.stable_swipes = 0;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.max_history_swipes = 301;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.wait = 11;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();

      request = demoRequest(WECHAT_AUTO_SUMMARY_MODE_RECENT, '');
      request.max_list_swipes = 101;
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();
    });

    it('acceptsPythonServiceResponseShape', 0, () => {
      let timeRange: WechatAutoSummaryTimeRange = { mode: 'visible_page_only' };
      let conversations: WechatAutoSummaryConversation[] = [
        {
          title: '小赵',
          contact: { title: '小赵' },
          dump: '<chat></chat>',
          snapshots: ['page-1'],
          messages: [
            { kind: 'text', sender: '小赵', text: '今天开会时间调整到下午三点' }
          ],
          time_range: timeRange,
          history_mode: 'visible_page_only'
        }
      ];
      let artifacts: WechatAutoSummaryJsonMap = { daily_log: '/tmp/daily-log.md' };
      let response: WechatAutoSummaryResponse = {
        status: 'ok',
        run_id: 'wechat-20260611-063600',
        started_at: '2026-06-11T06:36:00+08:00',
        finished_at: '2026-06-11T06:36:20+08:00',
        mode: WECHAT_AUTO_SUMMARY_MODE_RECENT,
        days: 7,
        target_contact: '',
        contacts_requested: 10,
        contacts_collected: 1,
        home_dump: '<root></root>',
        conversations: conversations,
        daily_log_entries: ['## 小赵'],
        artifacts: artifacts
      };

      expect(response.started_at).assertEqual('2026-06-11T06:36:00+08:00');
      expect(timeRange.mode).assertEqual('visible_page_only');
      expect(artifacts['daily_log']).assertEqual('/tmp/daily-log.md');
    });

    it('rendersWechatAutoSummaryDailyLogMetadata', 0, () => {
      let content = renderWechatAutoSummaryDailyLog('run-1', 'recent_contacts', 7, [
        '小赵提醒下午三点开会',
        '小李确认周五前提交材料'
      ]);

      expect(content.indexOf('DAILY_LOG_METADATA') >= 0).assertTrue();
      expect(content.indexOf('"workflow_metadata"') >= 0).assertTrue();
      expect(content.indexOf('"task_scene_id": 3') >= 0).assertTrue();
      expect(content.indexOf('"latest_entry_index": 2') >= 0).assertTrue();
      expect(content.indexOf('1. 小赵提醒下午三点开会') >= 0).assertTrue();
    });

    it('buildsWechatAutoSummaryRunDir', 0, () => {
      expect(wechatAutoSummaryRunDir('/tmp/files', 'run-1'))
        .assertEqual('/tmp/files/workflows/wechat-collection/runs/run-1');
    });
  });
}
