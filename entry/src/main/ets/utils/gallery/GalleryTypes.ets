export interface GalleryAnalyzerConfig {
  apiBaseUrl: string;
  apiKey: string;
  model: string;
  skipOcr: boolean;
  useOcrKeywordFilter: boolean;
  ocrConcurrency: number;
  modelConcurrency: number;
  embeddingConcurrency: number;
  embeddingMode: string;
  embeddingBaseUrl: string;
  embeddingApiKey: string;
  embeddingModel: string;
  imageScale: number;
}

export interface GalleryPhotoInput {
  uri: string;
  id?: string;
  date?: string;
  latitude?: number;
  longitude?: number;
}

export interface GalleryScanItem {
  uri: string;
  id: string;
  date: string;
  status: string;
  error: string;
}

export interface GalleryScanSession {
  id: string;
  status: string;
  createdAt: number;
  updatedAt: number;
  total: number;
  processed: number;
  skipped: number;
  failed: number;
  items: GalleryScanItem[];
}

export interface GalleryAnalysisResult {
  id: string;
  uri: string;
  thumbnailUri?: string;
  title: string;
  category: string;
  summary: string;
  details: string[];
  tags: string[];
  ocrText: string;
  rawModelText: string;
  keywords: string[];
  date: string;
  embeddingRef: string;
  embeddingStatus: string;
  embeddingDimension: number;
  error: string;
  latitude?: number;
  longitude?: number;
  createdAt: number;
}

export interface GalleryAnalyzeOutcome {
  result: GalleryAnalysisResult;
  cached: boolean;
  skippedByKeyword?: boolean;
}

export interface GalleryAnalyzeOptions {
  shouldPause?: () => boolean;
  onItemDone?: (input: GalleryPhotoInput, outcome: GalleryAnalyzeOutcome) => void;
}

export interface GalleryEmbeddingRecord {
  id: string;
  uri: string;
  date: string;
  category: string;
  text: string;
  vector: number[];
  model: string;
  mode: string;
  createdAt: number;
}

export interface GalleryProgress {
  selected: number;
  processed: number;
  skipped: number;
  pending: number;
  ocrDone: number;
  modelDone: number;
  embeddingDone: number;
  failed: number;
  current: string;
}

export type GalleryProgressHandler = (progress: GalleryProgress) => void;

export interface GalleryModelJson {
  title?: string;
  category?: string;
  summary?: string;
  details?: string[];
  tags?: string[];
  importance?: number;
}
