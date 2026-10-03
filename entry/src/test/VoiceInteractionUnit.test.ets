import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_MESSAGE_KIND_CHAT,
  ChatMessage,
  chatMessageVoiceMetadata,
  createChatMessage
} from '../main/ets/pages/chat/ChatSessionTypes';
import {
  ChatVoiceMetadata,
  VoiceSessionController,
  appendVoiceTranscriptToInput,
  createAsrVoiceMetadata,
  createTtsVoiceMetadata,
  createTtsVoiceRuntimeMetadata,
  normalizeChatVoiceMetadata,
  voiceReplayAvailable,
  voiceReplayGlobalBlockNeeded,
  voiceStatusLabel
} from '../main/ets/pages/chat/VoiceInteractionTypes';
import { ChatMessageUiModel } from '../main/ets/pages/chat/ChatMessageUiModel';
import {
  nextVoiceInputStartGeneration,
  voiceInputStartCanProceed,
  voiceInputStopGeneration
} from '../main/ets/pages/chat/ChatVoiceOrchestrator';

export default function voiceInteractionUnitTest() {
  describe('voiceInteractionUnitTest', () => {
    it('tracksVoiceTurnLifecycle', 0, () => {
      let controller = new VoiceSessionController();

      expect(controller.snapshot().status).assertEqual('idle');

      controller.beginListening('turn-1');
      controller.updatePartialTranscript('今天');
      expect(controller.snapshot().status).assertEqual('listening');
      expect(controller.snapshot().turnId).assertEqual('turn-1');
      expect(controller.snapshot().partialTranscript).assertEqual('今天');
      expect(controller.isBusy()).assertTrue();

      controller.markTranscribing();
      expect(controller.snapshot().status).assertEqual('transcribing');
      expect(controller.snapshot().partialTranscript).assertEqual('今天');

      controller.completeTranscript('今天天气怎么样');
      expect(controller.snapshot().status).assertEqual('transcribing');
      expect(controller.snapshot().finalTranscript).assertEqual('今天天气怎么样');

      controller.markThinking();
      expect(controller.snapshot().status).assertEqual('thinking');

      controller.beginSynthesizing('assistant-1');
      expect(controller.snapshot().status).assertEqual('synthesizing');
      expect(controller.snapshot().activeMessageId).assertEqual('assistant-1');

      controller.beginSpeaking('assistant-1');
      expect(controller.snapshot().status).assertEqual('speaking');
      expect(controller.snapshot().activeMessageId).assertEqual('assistant-1');

      controller.pauseSpeaking('assistant-1');
      expect(controller.snapshot().status).assertEqual('paused');
      expect(controller.snapshot().activeMessageId).assertEqual('assistant-1');

      controller.beginSpeaking('assistant-1');
      expect(controller.snapshot().status).assertEqual('speaking');
      expect(controller.snapshot().activeMessageId).assertEqual('assistant-1');

      controller.finishSpeaking();
      expect(controller.snapshot().status).assertEqual('idle');
      expect(controller.isBusy()).assertFalse();
    });

    it('resetsEmptyVoiceInputWithoutErrorStatus', 0, () => {
      let controller = new VoiceSessionController();

      controller.beginListening('empty-turn');
      controller.completeWithoutTranscript();

      expect(controller.snapshot().status).assertEqual('idle');
      expect(controller.snapshot().error).assertEqual('');
      expect(voiceStatusLabel(controller.snapshot().status)).assertEqual('');
      expect(controller.isBusy()).assertFalse();
    });

    it('labelsVoiceStatusesForChatUi', 0, () => {
      expect(voiceStatusLabel('idle')).assertEqual('');
      expect(voiceStatusLabel('listening')).assertEqual('正在聆听...');
      expect(voiceStatusLabel('transcribing')).assertEqual('正在转写...');
      expect(voiceStatusLabel('thinking')).assertEqual('正在思考...');
      expect(voiceStatusLabel('synthesizing')).assertEqual('正在合成语音...');
      expect(voiceStatusLabel('speaking')).assertEqual('正在朗读...');
      expect(voiceStatusLabel('paused')).assertEqual('已暂停朗读');
      expect(voiceStatusLabel('error')).assertEqual('语音出错');
    });

    it('disablesReplayGloballyWhileSynthesizingVoice', 0, () => {
      expect(voiceReplayAvailable('file://assistant-tts.wav', 'idle', false)).assertTrue();
      expect(voiceReplayAvailable('file://assistant-tts.wav', 'speaking', false)).assertTrue();
      expect(voiceReplayAvailable('file://assistant-tts.wav', 'synthesizing', false)).assertFalse();
      expect(voiceReplayAvailable('file://assistant-tts.wav', 'idle', true)).assertFalse();
      expect(voiceReplayAvailable('file://assistant-tts.wav', 'speaking', false, true)).assertFalse();
      expect(voiceReplayAvailable('', 'idle', false)).assertFalse();
    });

    it('blocksReplayWhileActiveStreamingVoiceCacheIsPending', 0, () => {
      expect(voiceReplayGlobalBlockNeeded('synthesizing', 'assistant-1', true, 'synthesizing', '')).assertTrue();
      expect(voiceReplayGlobalBlockNeeded('speaking', 'assistant-1', true, 'playing', '')).assertTrue();
      expect(voiceReplayGlobalBlockNeeded('paused', 'assistant-1', true, 'paused', '')).assertTrue();
      expect(voiceReplayGlobalBlockNeeded('speaking', 'assistant-1', true, 'playing',
        'file://assistant-1-tts.wav')).assertFalse();

      // 活跃语音来自其他会话时，当前列表看不到消息元数据；保守禁用重播，避免打断流式请求。
      expect(voiceReplayGlobalBlockNeeded('speaking', 'assistant-1', false, 'none', '')).assertTrue();
      expect(voiceReplayGlobalBlockNeeded('paused', 'assistant-1', false, 'none', '')).assertTrue();
      expect(voiceReplayGlobalBlockNeeded('idle', '', false, 'none', '')).assertFalse();
    });

    it('appendsVoiceTranscriptToEditableDraft', 0, () => {
      expect(appendVoiceTranscriptToInput('', '  今天有什么安排  ')).assertEqual('今天有什么安排');
      expect(appendVoiceTranscriptToInput('帮我查一下', '今天的天气')).assertEqual('帮我查一下\n今天的天气');
      expect(appendVoiceTranscriptToInput('帮我查一下\n', '今天的天气')).assertEqual('帮我查一下\n今天的天气');
      expect(appendVoiceTranscriptToInput('保留原文', '  ')).assertEqual('保留原文');
    });

    it('keepsVoiceInputStopRequestsBoundToStartGeneration', 0, () => {
      let latestStart: number = nextVoiceInputStartGeneration(0);
      let stopped: number = voiceInputStopGeneration(latestStart, 0);

      expect(voiceInputStartCanProceed(latestStart, latestStart, stopped)).assertFalse();

      let secondStart: number = nextVoiceInputStartGeneration(latestStart);

      expect(voiceInputStartCanProceed(latestStart, secondStart, stopped)).assertFalse();
      expect(voiceInputStartCanProceed(secondStart, secondStart, stopped)).assertTrue();

      stopped = voiceInputStopGeneration(secondStart, stopped);
      expect(voiceInputStartCanProceed(secondStart, secondStart, stopped)).assertFalse();
    });

    it('normalizesVoiceMetadata', 0, () => {
      let raw: ChatVoiceMetadata = {
        input: 'asr',
        provider: ' harmony ',
        status: 'transcribed',
        transcript: '  你好  ',
        confidence: 1.4,
        audioUri: ' file://voice.wav ',
        voice: ' ',
        error: '  ',
        createdAt: 123
      };

      let metadata = normalizeChatVoiceMetadata(raw);

      expect(metadata.input).assertEqual('asr');
      expect(metadata.provider).assertEqual('harmony');
      expect(metadata.status).assertEqual('transcribed');
      expect(metadata.transcript).assertEqual('你好');
      expect(metadata.confidence).assertEqual(1);
      expect(metadata.audioUri).assertEqual('file://voice.wav');
      expect(metadata.error).assertEqual('');
      expect(metadata.createdAt).assertEqual(123);
    });

    it('preservesVoiceMetadataOnChatMessagesAndUiModels', 0, () => {
      let voice = createAsrVoiceMetadata('harmony', '今天有什么安排', 0.82, 100);
      let message: ChatMessage = createChatMessage('voice-user-1', 'user', CHAT_MESSAGE_KIND_CHAT,
        '今天有什么安排', 100, [], '', [], voice);

      expect(chatMessageVoiceMetadata(message).provider).assertEqual('harmony');
      expect(chatMessageVoiceMetadata(message).transcript).assertEqual('今天有什么安排');

      let model = new ChatMessageUiModel(message);
      expect(model.detail.voice.provider).assertEqual('harmony');
      expect(model.detail.voice.status).assertEqual('transcribed');

      let tts = createTtsVoiceMetadata('mimo', 'mimo_default', 'file://assistant.wav', 101);
      let assistant: ChatMessage = createChatMessage('voice-assistant-1', 'assistant', CHAT_MESSAGE_KIND_CHAT,
        '我来帮你看看。', 101, [], '', [], tts);
      model.apply(assistant);

      expect(model.detail.voice.provider).assertEqual('mimo');
      expect(model.detail.voice.status).assertEqual('ready');
      expect(model.detail.voice.audioUri).assertEqual('file://assistant.wav');

      let playing = createTtsVoiceRuntimeMetadata('mimo', 'mimo_default', 'file://assistant.wav', 'playing', 102);
      assistant = createChatMessage('voice-assistant-1', 'assistant', CHAT_MESSAGE_KIND_CHAT,
        '我来帮你看看。', 102, [], '', [], playing);
      model.apply(assistant);

      expect(model.detail.voice.status).assertEqual('playing');

      let paused = createTtsVoiceRuntimeMetadata('mimo', 'mimo_default', 'file://assistant.wav', 'paused', 103);
      assistant = createChatMessage('voice-assistant-1', 'assistant', CHAT_MESSAGE_KIND_CHAT,
        '我来帮你看看。', 103, [], '', [], paused);
      model.apply(assistant);

      expect(model.detail.voice.status).assertEqual('paused');
    });
  });
}
