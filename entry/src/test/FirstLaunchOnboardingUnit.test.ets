import { describe, it, expect } from '@ohos/hypium';
import {
  FIRST_LAUNCH_ONBOARDING_SLIDE_AGENT,
  FIRST_LAUNCH_ONBOARDING_SLIDE_AVATAR,
  FIRST_LAUNCH_ONBOARDING_SLIDE_DATA_HOME,
  FIRST_LAUNCH_ONBOARDING_SLIDES,
  FIRST_LAUNCH_ONBOARDING_STORAGE_KEY,
  FIRST_LAUNCH_ONBOARDING_VERSION,
  clampFirstLaunchOnboardingIndex,
  firstLaunchOnboardingButtonText,
  isFirstLaunchOnboardingLastPage,
  shouldShowFirstLaunchOnboarding
} from '../main/ets/pages/onboarding/OnboardingTypes';

export default function firstLaunchOnboardingUnitTest() {
  describe('firstLaunchOnboardingUnitTest', () => {
    it('keepsVersionedStorageContractStable', 0, () => {
      expect(FIRST_LAUNCH_ONBOARDING_STORAGE_KEY).assertEqual('firstLaunchOnboardingVersion');
      expect(FIRST_LAUNCH_ONBOARDING_VERSION).assertEqual('2026-07-core-preview');
      expect(shouldShowFirstLaunchOnboarding('')).assertTrue();
      expect(shouldShowFirstLaunchOnboarding('old-version')).assertTrue();
      expect(shouldShowFirstLaunchOnboarding(FIRST_LAUNCH_ONBOARDING_VERSION)).assertFalse();
    });

    it('usesConfirmedSlideOrderAndCopy', 0, () => {
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES.length).assertEqual(3);
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[0].id).assertEqual(FIRST_LAUNCH_ONBOARDING_SLIDE_DATA_HOME);
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[0].title).assertEqual('数据归家');
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[0].mediaResourceName).assertEqual('onboarding_data_home');
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[1].id).assertEqual(FIRST_LAUNCH_ONBOARDING_SLIDE_AVATAR);
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[1].title).assertEqual('数字分身');
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[1].mediaResourceName).assertEqual('onboarding_avatar');
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[2].id).assertEqual(FIRST_LAUNCH_ONBOARDING_SLIDE_AGENT);
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[2].title).assertEqual('自动执行');
      expect(FIRST_LAUNCH_ONBOARDING_SLIDES[2].mediaResourceName).assertEqual('onboarding_agent');
    });

    it('usesNextUntilTheFinalStartButton', 0, () => {
      expect(firstLaunchOnboardingButtonText(0)).assertEqual('下一页');
      expect(firstLaunchOnboardingButtonText(1)).assertEqual('下一页');
      expect(firstLaunchOnboardingButtonText(2)).assertEqual('开始使用');
      expect(isFirstLaunchOnboardingLastPage(0)).assertFalse();
      expect(isFirstLaunchOnboardingLastPage(1)).assertFalse();
      expect(isFirstLaunchOnboardingLastPage(2)).assertTrue();
    });

    it('clampsInvalidPageIndexes', 0, () => {
      expect(clampFirstLaunchOnboardingIndex(-1)).assertEqual(0);
      expect(clampFirstLaunchOnboardingIndex(0)).assertEqual(0);
      expect(clampFirstLaunchOnboardingIndex(1)).assertEqual(1);
      expect(clampFirstLaunchOnboardingIndex(2)).assertEqual(2);
      expect(clampFirstLaunchOnboardingIndex(3)).assertEqual(2);
    });
  });
}
