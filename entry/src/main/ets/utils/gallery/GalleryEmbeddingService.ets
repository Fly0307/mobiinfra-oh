import { intelligence } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { CloudModelClient, EmbeddingCloudConfig } from '../CloudModelClient';
import { GalleryAnalyzerConfig } from './GalleryTypes';

export interface GalleryEmbeddingResult {
  vector: number[];
  mode: string;
  model: string;
}

type GalleryEmbeddingLogHandler = (level: string, message: string) => void;

export class GalleryEmbeddingService {
  private cloudClient: CloudModelClient;

  constructor(cloudClient: CloudModelClient) {
    this.cloudClient = cloudClient;
  }

  async embedText(text: string, config: GalleryAnalyzerConfig, filesDir: string,
    onLog?: GalleryEmbeddingLogHandler): Promise<GalleryEmbeddingResult> {
    if (config.embeddingMode === 'huawei_local') {
      try {
        let vector = await this.embedTextOnDevice(text, filesDir);
        return {
          vector: vector,
          mode: 'huawei_local',
          model: 'huawei_local_basic'
        };
      } catch (e) {
        let message = this.errorMessage(e as Object);
        this.emitLog(onLog, 'ERROR', 'huawei local embedding failed, fallback to remote: ' + message);
      }
    }
    this.emitLog(onLog, 'INFO', 'remote embedding start model=' + config.embeddingModel);
    let vector = await this.embedTextRemote(text, config);
    this.emitLog(onLog, 'INFO', 'remote embedding done dimension=' + vector.length);
    return {
      vector: vector,
      mode: 'remote',
      model: config.embeddingModel
    };
  }

  private async embedTextRemote(text: string, config: GalleryAnalyzerConfig): Promise<number[]> {
    let cloudConfig: EmbeddingCloudConfig = {
      baseUrl: config.embeddingBaseUrl,
      apiKey: config.embeddingApiKey,
      model: config.embeddingModel
    };
    return this.cloudClient.createEmbedding(text, cloudConfig);
  }

  private async embedTextOnDevice(text: string, filesDir: string): Promise<number[]> {
    try {
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
    } catch (e) {
      let err = e as Error;
      throw err;
    }
  }

  private emitLog(onLog: GalleryEmbeddingLogHandler | undefined, level: string, message: string): void {
    if (onLog) {
      onLog(level, message);
    }
  }

  private errorMessage(e: Object): string {
    let err = e as BusinessError;
    let codeText = err.code !== undefined ? 'code=' + err.code.toString() + ' ' : '';
    if (e instanceof Error) {
      return codeText + e.message;
    }
    return codeText + String(e);
  }
}
