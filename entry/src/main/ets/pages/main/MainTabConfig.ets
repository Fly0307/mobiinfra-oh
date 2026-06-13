export enum MainTabIndex {
  Home = 0,
  Summary = 1,
  Chat = 2,
  Task = 3,
  Settings = 4
}

export interface MainTabItem {
  index: MainTabIndex;
  icon: string;
  label: string;
}

export const MAIN_TAB_ITEMS: MainTabItem[] = [
  { index: MainTabIndex.Home, icon: 'H', label: '首页' },
  { index: MainTabIndex.Summary, icon: 'S', label: '汇总' },
  { index: MainTabIndex.Chat, icon: 'A', label: '聊天' },
  { index: MainTabIndex.Task, icon: 'T', label: '任务' },
  { index: MainTabIndex.Settings, icon: 'C', label: '设置' }
];

export function centerTabIndex(): MainTabIndex {
  return MainTabIndex.Chat;
}

export function mainTabLabel(index: MainTabIndex): string {
  for (let i = 0; i < MAIN_TAB_ITEMS.length; i++) {
    if (MAIN_TAB_ITEMS[i].index === index) {
      return MAIN_TAB_ITEMS[i].label;
    }
  }
  return '';
}

export function mainTabIcon(index: MainTabIndex): string {
  for (let i = 0; i < MAIN_TAB_ITEMS.length; i++) {
    if (MAIN_TAB_ITEMS[i].index === index) {
      return MAIN_TAB_ITEMS[i].icon;
    }
  }
  return '';
}
