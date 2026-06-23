export type AvatarStatus = 'empty' | 'current' | 'stale' | 'generating' | 'failed';
export type AvatarGenerationMode = 'text_to_image' | 'image_to_image';
export type AvatarStringMap = Record<string, string>;
export type AvatarErrorValue = Error | Object | string | number | boolean | null | undefined;

export interface AvatarHomeViewModel {
  avatarUri: string;
  avatarForegroundUri: string;
  avatarMessageForegroundUri: string;
  avatarReferencePhotoUri: string;
  avatarStatus: AvatarStatus;
  avatarUpdatedLabel: string;
  avatarActionLabel: string;
  avatarVersionId: string;
}

export interface AvatarDomainSnapshot {
  domain: string;
  display_name: string;
  short_summary: string;
  summary: string;
  claims: string[];
  event_count: number;
}

export interface AvatarProfileSnapshot {
  generated_at: string;
  event_count: number;
  completeness: number;
  gender: string;
  age: string;
  domains: AvatarDomainSnapshot[];
  prompt_profile_text: string;
}

export interface AvatarConsentSnapshot {
  mode: AvatarGenerationMode;
  photo_used: boolean;
  consented_at: string;
  photo_source: string;
}

export interface AvatarGenerationParams {
  size: string;
  response_format: string;
  output_format: string;
  sequential_image_generation: string;
  stream: boolean;
  watermark: boolean;
}

export interface AvatarVersionState {
  version_id: string;
  created_at: string;
  image_path: string;
  thumbnail_path: string;
  mode: AvatarGenerationMode;
  provider: string;
  model: string;
  generation_params: AvatarGenerationParams;
  prompt_snapshot: string;
  profile_snapshot: AvatarProfileSnapshot;
  profile_snapshot_hash: string;
  consent_snapshot: AvatarConsentSnapshot;
}

export interface AvatarVersionViewModel {
  versionId: string;
  createdAt: string;
  imageUri: string;
  imagePath: string;
  mode: AvatarGenerationMode;
  provider: string;
  model: string;
  generationParams: AvatarGenerationParams;
  promptSnapshot: string;
  profileSnapshot: AvatarProfileSnapshot;
  profileSnapshotHash: string;
  consentSnapshot: AvatarConsentSnapshot;
}

export interface AvatarState {
  current_version_id: string;
  profile_snapshot_hash: string;
  status: AvatarStatus;
  last_error_code: string;
  last_error_message: string;
  updated_at: string;
  reference_photo_path: string;
}

export interface AvatarProviderConfig {
  imageBaseUrl: string;
  apiKey: string;
  textToImageModel: string;
  imageToImageModel: string;
  size: string;
  responseFormat: string;
  outputFormat: string;
  sequentialImageGeneration: string;
  stream: boolean;
  watermark: boolean;
  timeoutMs: number;
}

export interface AvatarGenerateRequest {
  mode: AvatarGenerationMode;
  prompt: string;
  sourceImage: string;
  profileSnapshot: AvatarProfileSnapshot;
  profileSnapshotHash: string;
  consent: AvatarConsentSnapshot;
}

export interface AvatarProviderRequest {
  prompt: string;
  sourceImage: string;
  model: string;
  params: AvatarGenerationParams;
}

export interface AvatarProviderResult {
  imageBytesBase64: string;
  imageUrl: string;
  providerRequestId: string;
  rawMetadata: AvatarStringMap;
}

export function createEmptyAvatarHomeViewModel(): AvatarHomeViewModel {
  return {
    avatarUri: '',
    avatarForegroundUri: '',
    avatarMessageForegroundUri: '',
    avatarReferencePhotoUri: '',
    avatarStatus: 'empty',
    avatarUpdatedLabel: '',
    avatarActionLabel: '生成数字分身',
    avatarVersionId: ''
  };
}

export function createEmptyAvatarState(): AvatarState {
  return {
    current_version_id: '',
    profile_snapshot_hash: '',
    status: 'empty',
    last_error_code: '',
    last_error_message: '',
    updated_at: '',
    reference_photo_path: ''
  };
}

export function createDefaultAvatarGenerationParams(size: string, responseFormat: string, watermark: boolean,
  outputFormat: string = 'jpeg'): AvatarGenerationParams {
  return {
    size: size,
    response_format: responseFormat,
    output_format: outputFormat,
    sequential_image_generation: 'disabled',
    stream: false,
    watermark: watermark
  };
}

export function createEmptyRawMetadata(): AvatarStringMap {
  return new Object() as AvatarStringMap;
}

export function avatarErrorMessage(value: AvatarErrorValue, fallback: string): string {
  if (value === null || value === undefined) {
    return fallback;
  }
  if (value instanceof Error) {
    let message = value.message.trim();
    return message.length > 0 ? message : fallback;
  }
  let text = String(value).replace(/\s+/g, ' ').trim();
  return text.length > 0 ? text : fallback;
}
