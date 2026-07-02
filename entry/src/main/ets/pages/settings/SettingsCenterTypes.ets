export enum SettingsSectionId {
  PersonalPrivacy = 0,
  DataCollection = 1,
  ModelAgents = 2,
  TaskAutomation = 3,
  StorageAbout = 4
}

export interface SettingsSectionItem {
  id: SettingsSectionId;
  title: string;
  subtitle: string;
}

export enum SettingsActionKind {
  Primary = 0,
  Secondary = 1,
  Success = 2,
  Warning = 3,
  Danger = 4,
  Special = 5
}

export interface SettingsConfirmConfig {
  title: string;
  message: string;
  confirmText: string;
}

export interface DownloadedModelItem {
  id: string;
  label: string;
  path: string;
  repo: string;
  sizeText: string;
  statusText: string;
  ready: boolean;
}

export const SETTINGS_SECTION_NONE: number = -1;

export const SETTINGS_SECTION_ITEMS: SettingsSectionItem[] = [
  {
    id: SettingsSectionId.PersonalPrivacy,
    title: '个人与隐私',
    subtitle: '隐私守护、确认策略与数字分身'
  },
  {
    id: SettingsSectionId.DataCollection,
    title: '数据采集',
    subtitle: '图库、OCR、Embedding 与地图服务'
  },
  {
    id: SettingsSectionId.ModelAgents,
    title: '模型与智能体',
    subtitle: '云端 Planner/Decider、本地模型与 HDC'
  },
  {
    id: SettingsSectionId.TaskAutomation,
    title: '任务与自动化',
    subtitle: 'Agent 执行、Workflow 与运行日志'
  },
  {
    id: SettingsSectionId.StorageAbout,
    title: '存储与关于',
    subtitle: '模型文件、调试产物、版本与说明'
  }
];

export function settingsSectionTitle(id: SettingsSectionId): string {
  for (let i = 0; i < SETTINGS_SECTION_ITEMS.length; i++) {
    if (SETTINGS_SECTION_ITEMS[i].id === id) {
      return SETTINGS_SECTION_ITEMS[i].title;
    }
  }
  return '';
}

export function settingsSectionSubtitle(id: SettingsSectionId): string {
  for (let i = 0; i < SETTINGS_SECTION_ITEMS.length; i++) {
    if (SETTINGS_SECTION_ITEMS[i].id === id) {
      return SETTINGS_SECTION_ITEMS[i].subtitle;
    }
  }
  return '';
}

export function normalizeSettingsSectionId(id: number): number {
  for (let i = 0; i < SETTINGS_SECTION_ITEMS.length; i++) {
    if (SETTINGS_SECTION_ITEMS[i].id === id) {
      return id;
    }
  }
  return SETTINGS_SECTION_NONE;
}

export function isSettingsSectionSelected(id: number): boolean {
  return normalizeSettingsSectionId(id) !== SETTINGS_SECTION_NONE;
}

export function maskSensitiveSettingValue(value: string): string {
  if (value.length === 0) {
    return '';
  }
  if (value.length <= 4) {
    return '••••'.substring(0, value.length);
  }
  return value.substring(0, 4) + '••••••••' + value.substring(value.length - 4);
}

export function restoreMaskedSensitiveSettingDefault(value: string, defaultValue: string): string {
  if (defaultValue.length === 0) {
    return value;
  }
  if (value === maskSensitiveSettingValue(defaultValue)) {
    return defaultValue;
  }
  return value;
}
