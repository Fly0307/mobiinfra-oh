import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT,
  CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM,
  CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA,
  chatAttachmentComposerExtraHeight,
  chatAttachmentPreviewHeight,
  chatCanSendMessage,
  chatCanSendMessageWithImages,
  chatCanSubmitTaskWithImages,
  chatCloudUserContentWithImage,
  chatCloudUserContentWithImages,
  chatImageAttachmentSourceLabel,
  chatImageAttachmentSourceOptions,
  chatMessageTextForSend,
  chatMessageTextForSendWithImages,
  normalizeChatImageAttachments
} from '../main/ets/pages/chat/ChatAttachmentPolicy';
import { CloudContentPart, CloudImagePart } from '../main/ets/utils/CloudModelClient';

export default function chatAttachmentPolicyUnitTest() {
  describe('chatAttachmentPolicyUnitTest', () => {
    it('allowsSendWhenTextOrImageAttachmentExists', 0, () => {
      expect(chatCanSendMessage('', '')).assertFalse();
      expect(chatCanSendMessage('  你好  ', '')).assertTrue();
      expect(chatCanSendMessage('', 'photo://image/1')).assertTrue();
    });

    it('usesImageOnlyPromptOnlyWhenDraftIsEmpty', 0, () => {
      expect(chatMessageTextForSend('  请总结这张图  ', 'photo://image/1')).assertEqual('请总结这张图');
      expect(chatMessageTextForSend('', 'photo://image/1')).assertEqual(CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT);
      expect(chatMessageTextForSend('', '')).assertEqual('');
    });

    it('buildsCloudMultimodalContentForImageAttachment', 0, () => {
      let content = chatCloudUserContentWithImage('看看这张图', 'data:image/jpeg;base64,abc') as CloudContentPart[];

      expect(content.length).assertEqual(2);
      expect(content[0].type).assertEqual('text');
      expect(content[1].type).assertEqual('image_url');
      expect((content[1] as CloudImagePart).image_url.url).assertEqual('data:image/jpeg;base64,abc');
    });

    it('buildsCloudMultimodalContentForMultipleImageAttachments', 0, () => {
      let content = chatCloudUserContentWithImages('请比较这些图', [
        'data:image/jpeg;base64,first',
        'data:image/jpeg;base64,second'
      ]) as CloudContentPart[];

      expect(content.length).assertEqual(3);
      expect(content[0].type).assertEqual('text');
      expect(content[1].type).assertEqual('image_url');
      expect(content[2].type).assertEqual('image_url');
      expect((content[1] as CloudImagePart).image_url.url).assertEqual('data:image/jpeg;base64,first');
      expect((content[2] as CloudImagePart).image_url.url).assertEqual('data:image/jpeg;base64,second');
    });

    it('allowsSendAndPromptWhenMultipleImageAttachmentsExist', 0, () => {
      expect(chatCanSendMessageWithImages('', [])).assertFalse();
      expect(chatCanSendMessageWithImages('', ['photo://image/1', 'photo://image/2'])).assertTrue();
      expect(chatMessageTextForSendWithImages('', ['photo://image/1', 'photo://image/2']))
        .assertEqual(CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT);
      expect(chatMessageTextForSendWithImages('  总结这些图片  ', ['photo://image/1']))
        .assertEqual('总结这些图片');
    });

    it('blocksTaskSubmitWhenImageAttachmentsArePending', 0, () => {
      expect(chatCanSubmitTaskWithImages([])).assertTrue();
      expect(chatCanSubmitTaskWithImages(['photo://image/1'])).assertFalse();
      expect(chatCanSubmitTaskWithImages(['photo://image/1', 'photo://image/2'])).assertFalse();
    });

    it('normalizesMultipleImageAttachmentsByTrimmingEmptyAndLimitingCount', 0, () => {
      let sources: string[] = [
        '  photo://image/1  ', '', 'photo://image/2', 'photo://image/3', 'photo://image/4',
        'photo://image/5', 'photo://image/6', 'photo://image/7', 'photo://image/8',
        'photo://image/9', 'photo://image/10'
      ];
      let normalized: string[] = normalizeChatImageAttachments(sources);

      expect(normalized.length).assertEqual(9);
      expect(normalized[0]).assertEqual('photo://image/1');
      expect(normalized[8]).assertEqual('photo://image/9');
    });

    it('keepsComposerAttachmentSpaceRelativeToTextAreaHeight', 0, () => {
      expect(chatAttachmentPreviewHeight(46)).assertEqual(44);
      expect(chatAttachmentComposerExtraHeight(80, '')).assertEqual(0);
      expect(chatAttachmentComposerExtraHeight(80, 'photo://image/1') > chatAttachmentPreviewHeight(80)).assertTrue();
    });

    it('keepsAttachmentSourceMenuLimitedToCameraAndAlbum', 0, () => {
      let sources: string[] = chatImageAttachmentSourceOptions();

      expect(sources.length).assertEqual(2);
      expect(sources[0]).assertEqual(CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA);
      expect(sources[1]).assertEqual(CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM);
      expect(chatImageAttachmentSourceLabel(CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA)).assertEqual('拍照');
      expect(chatImageAttachmentSourceLabel(CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM)).assertEqual('相册');
    });
  });
}
