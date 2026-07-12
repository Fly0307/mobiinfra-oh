export const HIDDEN_DEFAULT_SETTING_PLACEHOLDER: string = '默认（输入新值以覆盖）';

export function settingUsesDefaultValue(configuredValue: string, defaultValue: string): boolean {
  let value = configuredValue.trim();
  return value.length === 0 || value === defaultValue.trim();
}

export function hiddenDefaultSettingEditorValue(configuredValue: string, defaultValue: string): string {
  return settingUsesDefaultValue(configuredValue, defaultValue) ? '' : configuredValue;
}

export function hiddenDefaultSettingPlaceholder(configuredValue: string, defaultValue: string,
  customPlaceholder: string): string {
  return settingUsesDefaultValue(configuredValue, defaultValue) ? HIDDEN_DEFAULT_SETTING_PLACEHOLDER : customPlaceholder;
}

export function migrateDefaultSettingValue(currentValue: string, configuredDefault: string, legacyDefaults: string[],
  lastAppliedDefault: string): string {
  let shouldUseConfiguredDefault = legacyDefaults.includes(currentValue) ||
    (lastAppliedDefault.length > 0 && currentValue === lastAppliedDefault);
  return shouldUseConfiguredDefault ? configuredDefault : currentValue;
}
