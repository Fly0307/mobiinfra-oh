import { CloudContentPart } from '../../utils/CloudModelClient';

export const CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT: string = '请分析这张图片。';
export const CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA: string = 'camera';
export const CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM: string = 'album';
export const CHAT_ATTACHMENT_PREVIEW_HEIGHT_RATIO: number = 0.86;
export const CHAT_ATTACHMENT_PREVIEW_GAP_RATIO: number = 0.22;
export const CHAT_ATTACHMENT_PREVIEW_MIN_HEIGHT: number = 44;

// 聊天附件策略集中处理输入判定和云端多模态 content 组装，避免 UI 与发送链路各自散落判断。
export function hasChatImageAttachment(uri: string): boolean {
  return uri.trim().length > 0;
}

export function chatCanSendMessage(input: string, imageAttachmentUri: string): boolean {
  return input.trim().length > 0 || hasChatImageAttachment(imageAttachmentUri);
}

export function chatMessageTextForSend(input: string, imageAttachmentUri: string): string {
  let text = input.trim();
  if (text.length > 0) {
    return text;
  }
  return hasChatImageAttachment(imageAttachmentUri) ? CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT : '';
}

// 图片来源入口固定为拍照和相册，UI 只消费这里的来源列表，避免入口文案和回调顺序分散维护。
export function chatImageAttachmentSourceOptions(): string[] {
  return [CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA, CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM];
}

export function chatImageAttachmentSourceLabel(source: string): string {
  if (source === CHAT_IMAGE_ATTACHMENT_SOURCE_CAMERA) {
    return '拍照';
  }
  if (source === CHAT_IMAGE_ATTACHMENT_SOURCE_ALBUM) {
    return '相册';
  }
  return '';
}

// 附件预览高度跟随输入框高度按比例计算，避免不同屏幕上固定留白过大或过小。
export function chatAttachmentPreviewHeight(textAreaHeight: number): number {
  return Math.max(CHAT_ATTACHMENT_PREVIEW_MIN_HEIGHT, Math.round(textAreaHeight * CHAT_ATTACHMENT_PREVIEW_HEIGHT_RATIO));
}

export function chatAttachmentComposerExtraHeight(textAreaHeight: number, imageAttachmentUri: string): number {
  if (!hasChatImageAttachment(imageAttachmentUri)) {
    return 0;
  }
  return chatAttachmentPreviewHeight(textAreaHeight) + Math.round(textAreaHeight * CHAT_ATTACHMENT_PREVIEW_GAP_RATIO);
}

// OpenAI-compatible 多模态消息要求 text 和 image_url 作为 content part 一起发送。
export function chatCloudUserContentWithImage(text: string, imageDataUrl: string): string | CloudContentPart[] {
  let normalizedText = text.trim();
  let normalizedImage = imageDataUrl.trim();
  if (normalizedImage.length === 0) {
    return normalizedText;
  }
  let parts: CloudContentPart[] = [
    { type: 'text', text: normalizedText.length > 0 ? normalizedText : CHAT_IMAGE_ATTACHMENT_ONLY_PROMPT },
    { type: 'image_url', image_url: { url: normalizedImage } }
  ];
  return parts;
}
