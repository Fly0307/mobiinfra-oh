export const DEFAULT_AGENT_POST_ACTION_DELAY_MS: number = 700;
export const ELEME_AGENT_POST_ACTION_DELAY_MS: number = 1500;

const ELEME_APP_NAME: string = '饿了么';
const ELEME_APP_ALIAS: string = 'eleme';
const ELEME_BUNDLE_NAME: string = 'me.ele.eleme';
const ELEME_LEGACY_BUNDLE_NAME: string = 'me.ele';

function normalizedTargetValue(value: string): string {
  return value.trim().toLowerCase();
}

function isElemeTargetValue(value: string): boolean {
  let normalized = normalizedTargetValue(value);
  return normalized === ELEME_APP_NAME || normalized === ELEME_APP_ALIAS ||
    normalized === ELEME_BUNDLE_NAME || normalized === ELEME_LEGACY_BUNDLE_NAME;
}

export function isElemeAgentTarget(appName: string, packageName: string): boolean {
  return isElemeTargetValue(appName) || isElemeTargetValue(packageName);
}

export function agentPostActionDelayMs(appName: string, packageName: string): number {
  return isElemeAgentTarget(appName, packageName) ? ELEME_AGENT_POST_ACTION_DELAY_MS :
    DEFAULT_AGENT_POST_ACTION_DELAY_MS;
}
