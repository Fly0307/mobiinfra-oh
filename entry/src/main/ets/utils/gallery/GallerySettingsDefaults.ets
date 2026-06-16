export const DEFAULT_GALLERY_API_BASE_URL: string = 'https://api.modelbest.cn/v1';
export const DEFAULT_GALLERY_API_KEY: string = 'sk-pQ8L2zF3XmR5kY9wV4jB7hN1tC6vM0xG3aD5sH2bJ9lK4cZ8';
export const DEFAULT_GALLERY_MODEL: string = 'MiniCPM-V-4.6-Instruct';
export const DEFAULT_GALLERY_SKIP_OCR: string = 'false';
export const DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER: string = 'true';
export const DEFAULT_GALLERY_OCR_CONCURRENCY: string = '3';
export const DEFAULT_GALLERY_MODEL_CONCURRENCY: string = '2';
export const DEFAULT_GALLERY_EMBEDDING_CONCURRENCY: string = '2';
export const DEFAULT_GALLERY_PARALLEL_FIELD_REQUESTS: string = 'true';
export const DEFAULT_GALLERY_EMBEDDING_MODE: string = 'huawei_local';
export const DEFAULT_GALLERY_EMBEDDING_BASE_URL: string = 'https://api.siliconflow.cn/v1';
export const DEFAULT_GALLERY_EMBEDDING_API_KEY: string = '';
export const DEFAULT_GALLERY_EMBEDDING_MODEL: string = 'BAAI/bge-m3';
export const DEFAULT_GALLERY_IMAGE_SCALE: string = '0.9';
export const DEFAULT_GALLERY_AMAP_WEB_KEY: string = '';

export function registerGallerySettingsDefaults(): void {
  PersistentStorage.persistProp('galleryApiBaseUrl', DEFAULT_GALLERY_API_BASE_URL);
  PersistentStorage.persistProp('galleryApiKey', DEFAULT_GALLERY_API_KEY);
  PersistentStorage.persistProp('galleryModel', DEFAULT_GALLERY_MODEL);
  PersistentStorage.persistProp('gallerySkipOcr', DEFAULT_GALLERY_SKIP_OCR);
  PersistentStorage.persistProp('galleryUseOcrKeywordFilter', DEFAULT_GALLERY_USE_OCR_KEYWORD_FILTER);
  PersistentStorage.persistProp('galleryOcrConcurrency', DEFAULT_GALLERY_OCR_CONCURRENCY);
  PersistentStorage.persistProp('galleryModelConcurrency', DEFAULT_GALLERY_MODEL_CONCURRENCY);
  PersistentStorage.persistProp('galleryEmbeddingConcurrency', DEFAULT_GALLERY_EMBEDDING_CONCURRENCY);
  PersistentStorage.persistProp('galleryParallelFieldRequests', DEFAULT_GALLERY_PARALLEL_FIELD_REQUESTS);
  PersistentStorage.persistProp('galleryEmbeddingMode', DEFAULT_GALLERY_EMBEDDING_MODE);
  PersistentStorage.persistProp('galleryEmbeddingBaseUrl', DEFAULT_GALLERY_EMBEDDING_BASE_URL);
  PersistentStorage.persistProp('galleryEmbeddingApiKey', DEFAULT_GALLERY_EMBEDDING_API_KEY);
  PersistentStorage.persistProp('galleryEmbeddingModel', DEFAULT_GALLERY_EMBEDDING_MODEL);
  PersistentStorage.persistProp('galleryImageScale', DEFAULT_GALLERY_IMAGE_SCALE);
  PersistentStorage.persistProp('galleryAmapWebKey', DEFAULT_GALLERY_AMAP_WEB_KEY);
}
