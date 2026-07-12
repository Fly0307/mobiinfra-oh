// MiMO V2.5 TTS 内置中文音色白名单，设置页和角色预设只能从这里暴露的音色中选择。
export type VoiceTtsVoicePreset = 'mimo_default' | '冰糖' | '茉莉' | '苏打' | '白桦';

export type VoiceTtsRolePresetId = 'data_home' | 'task_butler';

// 角色预设描述默认音色和给 TTS user message 使用的自然语言风格控制。
export interface VoiceTtsRolePreset {
  id: VoiceTtsRolePresetId;
  label: string;
  voice: VoiceTtsVoicePreset;
  stylePrompt: string;
}

// 设置页点击角色预设时使用完整快照，避免 role、voice、stylePrompt 分散赋值后出现状态漂移。
export interface VoiceTtsRoleSelection {
  rolePreset: VoiceTtsRolePresetId;
  voice: VoiceTtsVoicePreset;
  stylePrompt: string;
}

export const MIMO_CHINESE_VOICE_PRESETS: VoiceTtsVoicePreset[] = [
  'mimo_default',
  '冰糖',
  '茉莉',
  '苏打',
  '白桦'
];

export const VOICE_TTS_ROLE_PRESETS: VoiceTtsRolePreset[] = [
  {
    id: 'data_home',
    label: 'ClawMate',
    voice: '冰糖',
    stylePrompt: '用温和清晰的中文语气朗读，适合整理回顾信息。'
  },
  {
    id: 'task_butler',
    label: '任务管家',
    voice: '白桦',
    stylePrompt: '用干练明确的中文语气朗读，适合任务执行和步骤确认。'
  }
];

export function voiceTtsVoicePresetSupported(voice: string): boolean {
  let normalized = voice.trim();
  for (let i = 0; i < MIMO_CHINESE_VOICE_PRESETS.length; i++) {
    if (MIMO_CHINESE_VOICE_PRESETS[i] === normalized) {
      return true;
    }
  }
  return false;
}

export function normalizeVoiceTtsPreset(voice: string): VoiceTtsVoicePreset {
  let normalized = voice.trim();
  for (let i = 0; i < MIMO_CHINESE_VOICE_PRESETS.length; i++) {
    if (MIMO_CHINESE_VOICE_PRESETS[i] === normalized) {
      return MIMO_CHINESE_VOICE_PRESETS[i];
    }
  }
  return 'mimo_default';
}

export function voiceTtsRolePresetById(id: VoiceTtsRolePresetId): VoiceTtsRolePreset {
  for (let i = 0; i < VOICE_TTS_ROLE_PRESETS.length; i++) {
    if (VOICE_TTS_ROLE_PRESETS[i].id === id) {
      return VOICE_TTS_ROLE_PRESETS[i];
    }
  }
  return VOICE_TTS_ROLE_PRESETS[0];
}

export function voiceTtsSelectionFromRolePreset(preset: VoiceTtsRolePreset): VoiceTtsRoleSelection {
  return {
    rolePreset: preset.id,
    voice: preset.voice,
    stylePrompt: preset.stylePrompt
  };
}
