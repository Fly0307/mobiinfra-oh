import { intelligence } from '@kit.ArkData';
import { CloudModelClient, EmbeddingCloudConfig } from '../CloudModelClient';
import { GalleryAnalyzerConfig } from './GalleryTypes';

export class GalleryEmbeddingService {
  private cloudClient: CloudModelClient;

  constructor(cloudClient: CloudModelClient) {
    this.cloudClient = cloudClient;
  }

  async embedText(text: string, config: GalleryAnalyzerConfig, filesDir: string): Promise<number[]> {
    if (config.embeddingMode === 'huawei_local') {
      return this.embedTextOnDevice(text, filesDir);
    }
    let cloudConfig: EmbeddingCloudConfig = {
      baseUrl: config.embeddingBaseUrl,
      apiKey: config.embeddingApiKey,
      model: config.embeddingModel
    };
    return this.cloudClient.createEmbedding(text, cloudConfig);
  }

  private async embedTextOnDevice(text: string, filesDir: string): Promise<number[]> {
    let model = await intelligence.getTextEmbeddingModel({
      version: intelligence.ModelVersion.BASIC_MODEL,
      isNpuAvailable: false,
      cachePath: filesDir + '/gallery_embedding_cache'
    });
    try {
      await model.loadModel();
      let clipped = text.length > 512 ? text.substring(0, 512) : text;
      return await model.getEmbedding(clipped);
    } finally {
      try {
        await model.releaseModel();
      } catch (e) {
      }
    }
  }
}
