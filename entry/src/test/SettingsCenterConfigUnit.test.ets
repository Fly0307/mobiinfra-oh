import { describe, it, expect } from '@ohos/hypium';
import {
  SettingsActionKind,
  isSettingsSectionSelected,
  maskSensitiveSettingValue,
  normalizeSettingsSectionId,
  restoreMaskedSensitiveSettingDefault,
  SETTINGS_SECTION_ITEMS,
  SETTINGS_SECTION_NONE,
  SettingsSectionId,
  settingsSectionSubtitle,
  settingsSectionTitle
} from '../main/ets/pages/settings/SettingsCenterTypes';
import { settingsActionColor } from '../main/ets/pages/settings/SettingsCenterTheme';
import {
  DEFAULT_ENDPOINT_CONFIG,
  configuredEndpointValueOrDefault
} from '../main/ets/config/DefaultEndpointConfig';

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

    it('mapsSettingsActionKindsToStableColors', 0, () => {
      expect(settingsActionColor(SettingsActionKind.Primary)).assertEqual('#4F68FF');
      expect(settingsActionColor(SettingsActionKind.Secondary)).assertEqual('#607D8B');
      expect(settingsActionColor(SettingsActionKind.Success)).assertEqual('#38BE8B');
      expect(settingsActionColor(SettingsActionKind.Warning)).assertEqual('#FF9800');
      expect(settingsActionColor(SettingsActionKind.Danger)).assertEqual('#F44336');
      expect(settingsActionColor(SettingsActionKind.Special)).assertEqual('#765BFF');
    });

    it('masksSensitiveSettingValuesByDefault', 0, () => {
      expect(maskSensitiveSettingValue('')).assertEqual('');
      expect(maskSensitiveSettingValue('abc')).assertEqual('•••');
      expect(maskSensitiveSettingValue('sk-1234567890abcdef')).assertEqual('sk-1••••••••cdef');
    });

    it('restoresMaskedDefaultSensitiveValues', 0, () => {
      expect(restoreMaskedSensitiveSettingDefault('sk-1••••••••cdef', 'sk-1234567890abcdef'))
        .assertEqual('sk-1234567890abcdef');
      expect(restoreMaskedSensitiveSettingDefault('sk-other••••••••abcd', 'sk-1234567890abcdef'))
        .assertEqual('sk-other••••••••abcd');
    });

    it('resolvesConfiguredEndpointValuesWithDefaultFallback', 0, () => {
      expect(configuredEndpointValueOrDefault('', 'default-model')).assertEqual('default-model');
      expect(configuredEndpointValueOrDefault('   ', 'default-model')).assertEqual('default-model');
      expect(configuredEndpointValueOrDefault(' custom-model ', 'default-model')).assertEqual('custom-model');
    });

    it('exposesModelAndApiDefaultsForFreshInstall', 0, () => {
      expect(DEFAULT_ENDPOINT_CONFIG.cloudPlannerBaseUrl).assertEqual('http://123.60.91.241:9003');
      expect(DEFAULT_ENDPOINT_CONFIG.cloudPlannerModel).assertEqual('');
      expect(DEFAULT_ENDPOINT_CONFIG.cloudDeciderBaseUrl).assertEqual('http://166.111.53.96:7003');
      expect(DEFAULT_ENDPOINT_CONFIG.avatarImageModel).assertEqual('doubao-seedream-4-5-251128');
      expect(DEFAULT_ENDPOINT_CONFIG.avatarImageResponseFormat).assertEqual('url');
    });
  });
}
