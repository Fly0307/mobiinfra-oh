import { describe, it, expect } from '@ohos/hypium';
import { DEFAULT_ENDPOINT_CONFIG } from '../main/ets/config/DefaultEndpointConfig';
import {
  MIMO_CHINESE_VOICE_PRESETS,
  VOICE_TTS_ROLE_PRESETS,
  VoiceTtsRolePresetId,
  VoiceTtsRoleSelection,
  voiceTtsSelectionFromRolePreset,
  voiceTtsRolePresetById,
  voiceTtsVoicePresetSupported
} from '../main/ets/utils/voice/VoiceTtsPresets';

export default function voiceTtsPresetsUnitTest() {
  describe('voiceTtsPresetsUnitTest', () => {
    it('limitsBuiltInMimoVoicesToChinesePresets', 0, () => {
      expect(MIMO_CHINESE_VOICE_PRESETS.length).assertEqual(5);
      expect(voiceTtsVoicePresetSupported('mimo_default')).assertTrue();
      expect(voiceTtsVoicePresetSupported('冰糖')).assertTrue();
      expect(voiceTtsVoicePresetSupported('茉莉')).assertTrue();
      expect(voiceTtsVoicePresetSupported('苏打')).assertTrue();
      expect(voiceTtsVoicePresetSupported('白桦')).assertTrue();
      expect(voiceTtsVoicePresetSupported('Chloe')).assertFalse();
    });

    it('mapsAssistantRolePresetsToDefaultVoiceAndStyle', 0, () => {
      let dataRole = voiceTtsRolePresetById('data_home');
      expect(dataRole.label).assertEqual('数据归家');
      expect(dataRole.voice).assertEqual('冰糖');
      expect(dataRole.stylePrompt.indexOf('温和')).assertLarger(-1);
      expect(dataRole.stylePrompt.indexOf('整理回顾')).assertLarger(-1);

      let taskRole = voiceTtsRolePresetById('task_butler');
      expect(taskRole.label).assertEqual('任务管家');
      expect(taskRole.voice).assertEqual('白桦');
      expect(taskRole.stylePrompt.indexOf('干练')).assertLarger(-1);
      expect(taskRole.stylePrompt.indexOf('任务执行')).assertLarger(-1);
    });

    it('fallsBackToDefaultRoleForUnknownPresetId', 0, () => {
      let role = voiceTtsRolePresetById('unknown' as VoiceTtsRolePresetId);

      expect(role.id).assertEqual(VOICE_TTS_ROLE_PRESETS[0].id);
    });

    it('returnsCompleteSelectionWhenAssistantRoleChanges', 0, () => {
      let taskRole = voiceTtsRolePresetById('task_butler');
      let selection: VoiceTtsRoleSelection = voiceTtsSelectionFromRolePreset(taskRole);

      expect(selection.rolePreset).assertEqual('task_butler');
      expect(selection.voice).assertEqual('白桦');
      expect(selection.stylePrompt).assertEqual(taskRole.stylePrompt);
      expect(selection.stylePrompt === voiceTtsRolePresetById('data_home').stylePrompt).assertFalse();
    });

    it('keepsDefaultTtsEndpointAndRolePresetAligned', 0, () => {
      let dataRole = voiceTtsRolePresetById('data_home');

      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsBaseUrl).assertEqual('https://token-plan-cn.xiaomimimo.com/v1');
      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsApiKey).assertEqual('');
      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsModel).assertEqual('mimo-v2.5-tts');
      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsRolePreset).assertEqual(dataRole.id);
      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsVoice).assertEqual(dataRole.voice);
      expect(DEFAULT_ENDPOINT_CONFIG.voiceTtsStylePrompt).assertEqual(dataRole.stylePrompt);
    });
  });
}
