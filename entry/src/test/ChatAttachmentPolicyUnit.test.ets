import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT,
  chatAttachmentComposerExtraHeight,
  chatAttachmentPreviewHeight,
  chatCanSendMessage,
  chatCloudUserContentWithImage,
  chatMessageTextForSend
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

    it('keepsComposerAttachmentSpaceRelativeToTextAreaHeight', 0, () => {
      expect(chatAttachmentPreviewHeight(46)).assertEqual(44);
      expect(chatAttachmentComposerExtraHeight(80, '')).assertEqual(0);
      expect(chatAttachmentComposerExtraHeight(80, 'photo://image/1') > chatAttachmentPreviewHeight(80)).assertTrue();
    });
  });
}
