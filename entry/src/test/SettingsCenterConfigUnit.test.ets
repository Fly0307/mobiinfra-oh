import { describe, it, expect } from '@ohos/hypium';
import {
  isSettingsSectionSelected,
  normalizeSettingsSectionId,
  SETTINGS_SECTION_ITEMS,
  SETTINGS_SECTION_NONE,
  SettingsSectionId,
  settingsSectionSubtitle,
  settingsSectionTitle
} from '../main/ets/pages/settings/SettingsCenterTypes';

export default function settingsCenterConfigUnitTest() {
  describe('settingsCenterConfigUnitTest', () => {
    it('usesConfirmedSettingsSectionOrder', 0, () => {
      expect(SETTINGS_SECTION_ITEMS.length).assertEqual(5);
      expect(SETTINGS_SECTION_ITEMS[0].id).assertEqual(SettingsSectionId.PersonalPrivacy);
      expect(SETTINGS_SECTION_ITEMS[1].id).assertEqual(SettingsSectionId.DataCollection);
      expect(SETTINGS_SECTION_ITEMS[2].id).assertEqual(SettingsSectionId.ModelAgents);
      expect(SETTINGS_SECTION_ITEMS[3].id).assertEqual(SettingsSectionId.TaskAutomation);
      expect(SETTINGS_SECTION_ITEMS[4].id).assertEqual(SettingsSectionId.StorageAbout);
    });

    it('exposesChineseSectionTitles', 0, () => {
      expect(settingsSectionTitle(SettingsSectionId.PersonalPrivacy)).assertEqual('个人与隐私');
      expect(settingsSectionTitle(SettingsSectionId.DataCollection)).assertEqual('数据采集');
      expect(settingsSectionTitle(SettingsSectionId.ModelAgents)).assertEqual('模型与智能体');
      expect(settingsSectionTitle(SettingsSectionId.TaskAutomation)).assertEqual('任务与自动化');
      expect(settingsSectionTitle(SettingsSectionId.StorageAbout)).assertEqual('存储与关于');
      expect(settingsSectionSubtitle(SettingsSectionId.ModelAgents)).assertEqual('云端 Planner/Decider、本地模型与 HDC');
    });

    it('normalizesSettingsSectionSelection', 0, () => {
      expect(normalizeSettingsSectionId(SettingsSectionId.TaskAutomation)).assertEqual(SettingsSectionId.TaskAutomation);
      expect(isSettingsSectionSelected(SettingsSectionId.TaskAutomation)).assertTrue();
      expect(normalizeSettingsSectionId(SETTINGS_SECTION_NONE)).assertEqual(SETTINGS_SECTION_NONE);
      expect(normalizeSettingsSectionId(99)).assertEqual(SETTINGS_SECTION_NONE);
      expect(isSettingsSectionSelected(99)).assertFalse();
      expect(isSettingsSectionSelected(SETTINGS_SECTION_NONE)).assertFalse();
    });
  });
}
