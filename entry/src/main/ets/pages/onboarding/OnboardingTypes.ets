/**
 * 首次安装引导页的稳定数据契约。
 *
 * 该文件只保存版本、持久化 key、页面文案和纯函数，不依赖 ArkUI 组件。
 * 这样 Index 只需要判断是否展示，引导页组件只负责渲染，单元测试也能直接覆盖
 * “以后不再出现”的版本化行为。
 */
export const FIRST_LAUNCH_ONBOARDING_STORAGE_KEY: string = 'firstLaunchOnboardingVersion';
export const FIRST_LAUNCH_ONBOARDING_VERSION: string = '2026-07-core-preview';

export const FIRST_LAUNCH_ONBOARDING_SLIDE_DATA_HOME: string = 'data_home';
export const FIRST_LAUNCH_ONBOARDING_SLIDE_AVATAR: string = 'avatar';
export const FIRST_LAUNCH_ONBOARDING_SLIDE_AGENT: string = 'agent';

export interface FirstLaunchOnboardingSlide {
  id: string;
  title: string;
  description: string;
  mediaResourceName: string;
  accentColor: string;
  softBackgroundColor: string;
}

export const FIRST_LAUNCH_ONBOARDING_SLIDES: FirstLaunchOnboardingSlide[] = [
  {
    id: FIRST_LAUNCH_ONBOARDING_SLIDE_DATA_HOME,
    title: '数据归家',
    description: '汇总聊天、图库、任务和位置线索，让分散在各个 App 里的信息回到你的个人数据中心。',
    mediaResourceName: 'onboarding_data_home',
    accentColor: '#4F68FF',
    softBackgroundColor: '#EAF1FF'
  },
  {
    id: FIRST_LAUNCH_ONBOARDING_SLIDE_AVATAR,
    title: '数字分身',
    description: '结合个人资料、头像和历史上下文，生成更懂你的助手，用于问答、朗读和任务协作。',
    mediaResourceName: 'onboarding_avatar',
    accentColor: '#8066FF',
    softBackgroundColor: '#F1EEFF'
  },
  {
    id: FIRST_LAUNCH_ONBOARDING_SLIDE_AGENT,
    title: '自动执行',
    description: '让 Agent 根据你的目标规划步骤、调用工具并执行任务，关键动作保留确认边界。',
    mediaResourceName: 'onboarding_agent',
    accentColor: '#18A886',
    softBackgroundColor: '#E9F8F3'
  }
];

export function shouldShowFirstLaunchOnboarding(storedVersion: string): boolean {
  return storedVersion !== FIRST_LAUNCH_ONBOARDING_VERSION;
}

export function isFirstLaunchOnboardingLastPage(index: number): boolean {
  return clampFirstLaunchOnboardingIndex(index) === FIRST_LAUNCH_ONBOARDING_SLIDES.length - 1;
}

export function firstLaunchOnboardingButtonText(index: number): string {
  return isFirstLaunchOnboardingLastPage(index) ? '开始使用' : '下一页';
}

export function clampFirstLaunchOnboardingIndex(index: number): number {
  if (index < 0) {
    return 0;
  }
  let maxIndex = FIRST_LAUNCH_ONBOARDING_SLIDES.length - 1;
  if (index > maxIndex) {
    return maxIndex;
  }
  return Math.floor(index);
}
