import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';

export class GalleryOcrService {
  private initialized: boolean = false;

  async recognize(pixelMap: image.PixelMap): Promise<string> {
    try {
      await this.ensureInitialized();
      let result = await textRecognition.recognizeText({
        pixelMap: pixelMap
      }, {
        isDirectionDetectionSupported: true
      });
      if (!result || !result.value) {
        return '';
      }
      return result.value;
    } catch (e) {
      return '';
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
