export const WECHAT_AUTO_SUMMARY_ENABLED_KEY: string = 'wechatAutoSummaryEnabled';
export const WECHAT_AUTO_SUMMARY_DEFAULT_DAYS_KEY: string = 'wechatAutoSummaryDefaultDays';
export const WECHAT_AUTO_SUMMARY_DEFAULT_MAX_CONTACTS_KEY: string = 'wechatAutoSummaryDefaultMaxContacts';
export const WECHAT_AUTO_SUMMARY_SWIPE_SPEED_KEY: string = 'wechatAutoSummarySwipeSpeed';
export const WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO_KEY: string = 'wechatAutoSummaryHistorySwipeRatio';
export const WECHAT_AUTO_SUMMARY_STABLE_SWIPES_KEY: string = 'wechatAutoSummaryStableSwipes';
export const WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES_KEY: string = 'wechatAutoSummaryMaxHistorySwipes';
export const WECHAT_AUTO_SUMMARY_WAIT_KEY: string = 'wechatAutoSummaryWait';

export const DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED: string = 'false';
export const DEFAULT_WECHAT_AUTO_SUMMARY_DAYS: string = '7';
export const DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS: string = '10';
export const DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED: string = '2500';
export const DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO: string = '0.65';
export const DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES: string = '3';
export const DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES: string = '80';
export const DEFAULT_WECHAT_AUTO_SUMMARY_WAIT: string = '1.0';

export const WECHAT_AUTO_SUMMARY_MODE_RECENT: string = 'recent_contacts';
export const WECHAT_AUTO_SUMMARY_MODE_TARGET: string = 'target_contact';

export type WechatAutoSummaryJsonValue = Object | string | number | boolean | null;
export type WechatAutoSummaryJsonMap = Record<string, WechatAutoSummaryJsonValue>;

// 微信自动汇总请求参数，对齐 PC 侧采集服务的 snake_case JSON 字段。
export interface WechatAutoSummaryRequest {
  mode: string;
  days: number;
  max_contacts: number;
  target_contact: string;
  swipe_speed: number;
  history_swipe_ratio: number;
  stable_swipes: number;
  max_history_swipes: number;
  wait: number;
}

// 单条聊天消息的结构，sender 仅在服务端能识别发言人时返回。
export interface WechatAutoSummaryMessage {
  kind: string;
  text: string;
  sender?: string;
}

export interface WechatAutoSummaryConversation {
  title: string;
  contact?: WechatAutoSummaryJsonMap;
  messages: WechatAutoSummaryMessage[];
}

export interface WechatAutoSummaryResponse {
  status: string;
  message?: string;
  run_id?: string;
  mode?: string;
  days?: number;
  contacts_requested?: number;
  contacts_collected?: number;
  conversations?: WechatAutoSummaryConversation[];
  daily_log_entries?: string[];
  artifacts?: WechatAutoSummaryJsonMap;
}

function isInvalidNumber(value: number): boolean {
  return isNaN(value) || !isFinite(value);
}

function clampRoundedSetting(value: string, fallback: number, min: number, max: number): number {
  let text = value.trim();
  if (text.length === 0) {
    return fallback;
  }
  let parsed = Number(text);
  if (isInvalidNumber(parsed)) {
    return fallback;
  }
  let rounded = Math.round(parsed);
  if (rounded < min) {
    return min;
  }
  if (rounded > max) {
    return max;
  }
  return rounded;
}

export function normalizeWechatAutoSummaryDays(value: string): number {
  return clampRoundedSetting(value, 7, 1, 90);
}

export function normalizeWechatAutoSummaryMaxContacts(value: string): number {
  return clampRoundedSetting(value, 10, 1, 50);
}

export function normalizeWechatAutoSummaryMode(value: string): string {
  if (value === WECHAT_AUTO_SUMMARY_MODE_TARGET) {
    return WECHAT_AUTO_SUMMARY_MODE_TARGET;
  }
  return WECHAT_AUTO_SUMMARY_MODE_RECENT;
}

// 返回空字符串表示校验通过；非空中文文案可直接展示给用户。
export function validateWechatAutoSummaryRequest(request: WechatAutoSummaryRequest): string {
  if (isInvalidNumber(request.days) || request.days < 1 || request.days > 90) {
    return '汇总天数需在 1 到 90 天之间';
  }
  if (isInvalidNumber(request.max_contacts) || request.max_contacts < 1 || request.max_contacts > 50) {
    return '联系人数量需在 1 到 50 个之间';
  }
  if (normalizeWechatAutoSummaryMode(request.mode) === WECHAT_AUTO_SUMMARY_MODE_TARGET &&
    request.target_contact.trim().length === 0) {
    return '指定联系人模式需要填写联系人名称';
  }
  return '';
}
