import { SettingsActionKind } from './SettingsCenterTypes';

export const SETTINGS_PAGE_BACKGROUND_COLOR: string = '#F4F8FF';
export const SETTINGS_CARD_BACKGROUND_COLOR: string = '#FFFFFF';
export const SETTINGS_INPUT_BACKGROUND_COLOR: string = '#F2F5FC';
export const SETTINGS_INPUT_DISABLED_BACKGROUND_COLOR: string = '#E6EAF2';
export const SETTINGS_PANEL_BACKGROUND_COLOR: string = '#EEF4FF';
export const SETTINGS_TITLE_COLOR: string = '#11182F';
export const SETTINGS_SECONDARY_TEXT_COLOR: string = '#7B8290';
export const SETTINGS_MUTED_TEXT_COLOR: string = '#6F7684';
export const SETTINGS_BORDER_COLOR: string = '#E6EAF2';
export const SETTINGS_PANEL_BORDER_COLOR: string = '#D9E5FF';
export const SETTINGS_CARD_RADIUS: number = 18;
export const SETTINGS_CONTROL_RADIUS: number = 12;
export const SETTINGS_CARD_PADDING: number = 16;
export const SETTINGS_PAGE_HORIZONTAL_PADDING: string = '92%';
export const SETTINGS_FIELD_HEIGHT: number = 42;
export const SETTINGS_BUTTON_HEIGHT: number = 40;
export const SETTINGS_GROUP_GAP: number = 12;
export const SETTINGS_ACTION_GAP: number = 10;

export function settingsActionColor(kind: SettingsActionKind): string {
  if (kind === SettingsActionKind.Secondary) {
    return '#607D8B';
  }
  if (kind === SettingsActionKind.Success) {
    return '#38BE8B';
  }
  if (kind === SettingsActionKind.Warning) {
    return '#FF9800';
  }
  if (kind === SettingsActionKind.Danger) {
    return '#F44336';
  }
  if (kind === SettingsActionKind.Special) {
    return '#765BFF';
  }
  return '#4F68FF';
}
