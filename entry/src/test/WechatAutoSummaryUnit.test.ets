import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
  normalizeWechatAutoSummaryDays,
  normalizeWechatAutoSummaryMaxContacts,
  normalizeWechatAutoSummaryMode,
  validateWechatAutoSummaryRequest,
  WECHAT_AUTO_SUMMARY_MODE_RECENT,
  WECHAT_AUTO_SUMMARY_MODE_TARGET,
  WechatAutoSummaryRequest
} from '../main/ets/utils/wechat/WechatAutoSummaryTypes';

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
      expect(normalizeWechatAutoSummaryDays('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryDays('120')).assertEqual(90);
      expect(normalizeWechatAutoSummaryMaxContacts('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryMaxContacts('80')).assertEqual(50);
    });

    it('normalizesModes', 0, () => {
      expect(normalizeWechatAutoSummaryMode(WECHAT_AUTO_SUMMARY_MODE_TARGET))
        .assertEqual(WECHAT_AUTO_SUMMARY_MODE_TARGET);
      expect(normalizeWechatAutoSummaryMode('bad')).assertEqual(WECHAT_AUTO_SUMMARY_MODE_RECENT);
    });

    it('validatesTargetContactForTargetMode', 0, () => {
      expect(validateWechatAutoSummaryRequest(demoRequest(WECHAT_AUTO_SUMMARY_MODE_TARGET, ' ')).length > 0)
        .assertTrue();
      expect(validateWechatAutoSummaryRequest(demoRequest(WECHAT_AUTO_SUMMARY_MODE_TARGET, '小赵'))).assertEqual('');
    });
  });
}
