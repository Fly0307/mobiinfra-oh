import { describe, it, expect } from '@ohos/hypium';
import {
  buildHarmonyAsrCreateEngineParams,
  buildHarmonyAsrStartParams,
  mergeHarmonyAsrFinalTranscript,
  mergeHarmonyAsrPartialTranscript,
  shouldSkipDuplicateHarmonyAsrFinalCallback
} from '../main/ets/utils/voice/HarmonySpeechRecognizerAsrProvider';

export default function harmonySpeechRecognizerAsrProviderUnitTest() {
  describe('harmonySpeechRecognizerAsrProviderUnitTest', () => {
    it('buildsStartParamsWithOfficialDemoRecordingOptions', 0, () => {
      let params = buildHarmonyAsrStartParams('voice-turn-1');
      let extraParams = params.extraParams as Record<string, Object>;

      expect(params.sessionId).assertEqual('voice-turn-1');
      expect(params.audioInfo.audioType).assertEqual('pcm');
      expect(params.audioInfo.sampleRate).assertEqual(16000);
      expect(params.audioInfo.soundChannel).assertEqual(1);
      expect(params.audioInfo.sampleBit).assertEqual(16);
      expect(extraParams['recognitionMode'] as number).assertEqual(0);
      expect(extraParams['vadBegin'] as number).assertEqual(500);
      expect(extraParams['vadEnd'] as number).assertEqual(10000);
      expect(extraParams['maxAudioDuration'] as number).assertEqual(60000);
    });

    it('buildsLongModeEngineForNaturalDictation', 0, () => {
      let params = buildHarmonyAsrCreateEngineParams('zh-CN');
      let extraParams = params.extraParams as Record<string, Object>;

      expect(params.language).assertEqual('zh-CN');
      expect(params.online).assertEqual(1);
      expect(extraParams['locate'] as string).assertEqual('CN');
      expect(extraParams['recognizerMode'] as string).assertEqual('long');
    });

    it('mergesFinalClausesWithoutDuplicatingDraftText', 0, () => {
      let firstClause = mergeHarmonyAsrFinalTranscript('', '已完成修复审核，', false);
      let partialSecondClause = mergeHarmonyAsrPartialTranscript(firstClause, '并且提交');
      let finalText = mergeHarmonyAsrFinalTranscript(firstClause, '并且提交。', true);
      let cumulativeFinalText = mergeHarmonyAsrFinalTranscript(firstClause, '已完成修复审核，并且提交。', true);
      let cumulativeWithPunctuationRewrite = mergeHarmonyAsrFinalTranscript('已完成修复审核，', '已完成修复审核并且提交。',
        true);
      let repeatedShortClause = mergeHarmonyAsrFinalTranscript('谢谢。', '谢谢。', true);

      expect(firstClause).assertEqual('已完成修复审核，');
      expect(partialSecondClause).assertEqual('已完成修复审核，并且提交');
      expect(finalText).assertEqual('已完成修复审核，并且提交。');
      expect(cumulativeFinalText).assertEqual('已完成修复审核，并且提交。');
      expect(cumulativeWithPunctuationRewrite).assertEqual('已完成修复审核并且提交。');
      expect(repeatedShortClause).assertEqual('谢谢。谢谢。');
    });

    it('skipsOnlyIdenticalFinalCallbackRepeats', 0, () => {
      expect(shouldSkipDuplicateHarmonyAsrFinalCallback('谢谢。', false, '谢谢。', false)).assertTrue();
      expect(shouldSkipDuplicateHarmonyAsrFinalCallback('谢谢。', false, '谢谢。', true)).assertFalse();
      expect(shouldSkipDuplicateHarmonyAsrFinalCallback('谢谢。', true, '再见。', true)).assertFalse();
    });
  });
}
