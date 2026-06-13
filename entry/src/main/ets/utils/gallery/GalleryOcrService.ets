import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';

export class GalleryOcrService {
  private initialized: boolean = false;

  async recognize(pixelMap: image.PixelMap): Promise<string> {
    await this.ensureInitialized();
    try {
      let result = await textRecognition.recognizeText({
        pixelMap: pixelMap
      }, {
        isDirectionDetectionSupported: true
      });
      return result.value ? result.value : '';
    } catch (e) {
      let err = e as Error;
      throw err;
    }
  }

  async release(): Promise<void> {
    if (!this.initialized) {
      return;
    }
    try {
      await textRecognition.release();
    } catch (e) {
    }
    this.initialized = false;
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) {
      return;
    }
    try {
      await textRecognition.init();
    } catch (e) {
    }
    this.initialized = true;
  }
}
