import { describe, it, expect } from '@ohos/hypium';
import {
  MimoAsrRequest,
  MimoTtsRequest,
  MimoVoiceClient
} from '../main/ets/utils/voice/MimoVoiceClient';

export default function mimoVoiceClientUnitTest() {
  describe('mimoVoiceClientUnitTest', () => {
    it('buildsNonStreamingTtsRequestWithAssistantText', 0, () => {
      let request: MimoTtsRequest = MimoVoiceClient.buildTtsRequest('你好，我是数字分身。', {
        model: 'mimo-v2.5-tts',
        voice: 'mimo_default',
        format: 'wav',
        stylePrompt: '用温和自然的中文女声朗读'
      });

      expect(request.model).assertEqual('mimo-v2.5-tts');
      expect(request.audio.format).assertEqual('wav');
      expect(request.audio.voice).assertEqual('mimo_default');
      expect(request.messages.length).assertEqual(2);
      expect(request.messages[0].role).assertEqual('user');
      expect(request.messages[1].role).assertEqual('assistant');
      expect(request.messages[1].content).assertEqual('你好，我是数字分身。');
      expect(request.stream).assertFalse();
    });

    it('parsesTtsAudioDataFromChatCompletion', 0, () => {
      let payload = '{"choices":[{"message":{"role":"assistant","content":"","audio":{"data":"UklGRg=="}}}]}';

      expect(MimoVoiceClient.parseTtsAudioBase64(payload)).assertEqual('UklGRg==');
    });

    it('buildsAsrRequestWithDataUrlAudio', 0, () => {
      let request: MimoAsrRequest = MimoVoiceClient.buildAsrRequest('QUJD', 'wav', 'zh', true);

      expect(request.model).assertEqual('mimo-v2.5-asr');
      expect(request.asr_options.language).assertEqual('zh');
      expect(request.stream).assertTrue();
      expect(request.messages[0].role).assertEqual('user');
      expect(request.messages[0].content[0].type).assertEqual('input_audio');
      expect(request.messages[0].content[0].input_audio.data).assertEqual('data:audio/wav;base64,QUJD');
    });

    it('parsesAsrTranscriptFromNonStreamingResponse', 0, () => {
      let openAiPayload = '{"choices":[{"message":{"role":"assistant","content":"今天天气不错。"}}]}';
      let contentPayload = '{"content":[{"type":"text","text":"明天提醒我开会。"}],"role":"assistant"}';

      expect(MimoVoiceClient.parseAsrTranscript(openAiPayload)).assertEqual('今天天气不错。');
      expect(MimoVoiceClient.parseAsrTranscript(contentPayload)).assertEqual('明天提醒我开会。');
    });
  });
}
