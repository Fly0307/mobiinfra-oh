import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { subjectSegmentation } from '@kit.CoreVisionKit';
import { DataManagerPaths } from '../DataManagerPaths';
import { DataManagerStorage } from '../DataManagerStorage';
import { dataManagerWarn } from '../DataManagerLog';
import { AvatarStorage } from './AvatarStorage';
import { avatarErrorMessage } from './AvatarTypes';

const AVATAR_FOREGROUND_SEGMENT_MAX_COUNT: number = 1;

export class AvatarForegroundService {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;
  private avatarStorage: AvatarStorage;
  private initialized: boolean = false;
  private foregroundQueue: Promise<string> = Promise.resolve('');

  constructor(paths: DataManagerPaths, storage: DataManagerStorage, avatarStorage: AvatarStorage) {
    this.paths = paths;
    this.storage = storage;
    this.avatarStorage = avatarStorage;
  }

  async ensureForegroundForVersion(versionId: string, imagePath: string): Promise<string> {
    if (versionId.length === 0 || imagePath.trim().length === 0) {
      return '';
    }
    if (this.avatarStorage.foregroundExists(versionId)) {
      return this.avatarStorage.foregroundDisplayUri(versionId);
    }
    let sourcePath = this.sourceImagePath(imagePath);
    if (sourcePath.length === 0) {
      dataManagerWarn('Avatar foreground skipped: source image is not a local file.');
      return '';
    }
    // subjectSegmentation 是模块级视觉服务；串行化可避免多个头像前景任务交错 init/release。
    let task = this.foregroundQueue.then(async (): Promise<string> => {
      if (this.avatarStorage.foregroundExists(versionId)) {
        return this.avatarStorage.foregroundDisplayUri(versionId);
      }
      return await this.createForeground(versionId, sourcePath);
    });
    this.foregroundQueue = task.then((_value: string): string => {
      return '';
    }).catch((): string => {
      return '';
    });
    return await task;
  }

  private async createForeground(versionId: string, sourcePath: string): Promise<string> {
    let imageFile: fileIo.File | null = null;
    let imageSource: image.ImageSource | null = null;
    let sourcePixelMap: image.PixelMap | null = null;
    let foregroundPixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      imageFile = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(imageFile.fd);
      sourcePixelMap = await imageSource.createPixelMap();
      await this.ensureInitialized();
      let config: subjectSegmentation.SegmentationConfig = {
        maxCount: AVATAR_FOREGROUND_SEGMENT_MAX_COUNT,
        enableSubjectDetails: false,
        enableSubjectForegroundImage: true
      };
      let result = await subjectSegmentation.doSegmentation({ pixelMap: sourcePixelMap }, config);
      if (result === null || result === undefined || result.subjectCount <= 0 ||
        result.fullSubject === null || result.fullSubject === undefined ||
        result.fullSubject.foregroundImage === null || result.fullSubject.foregroundImage === undefined) {
        dataManagerWarn('Avatar foreground skipped: segmentation returned empty foreground image.');
        return '';
      }
      foregroundPixelMap = result.fullSubject.foregroundImage;
      if (foregroundPixelMap === null) {
        dataManagerWarn('Avatar foreground skipped: segmentation returned empty foreground image.');
        return '';
      }

      // 前景图是用于 UI 叠放的透明缓存，必须保存为 PNG，避免 JPEG 丢失 alpha 通道。
      packer = image.createImagePacker();
      let data = await packer.packToData(foregroundPixelMap, {
        format: 'image/png',
        quality: 100
      });
      this.avatarStorage.saveForegroundPng(versionId, new Uint8Array(data));
      return this.avatarStorage.foregroundDisplayUri(versionId);
    } catch (e) {
      dataManagerWarn('Avatar foreground failed: ' +
        avatarErrorMessage(e as Error | Object | string | number | boolean | null | undefined,
          'unknown foreground error'));
      return '';
    } finally {
      if (packer !== null) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
      if (foregroundPixelMap !== null && foregroundPixelMap !== sourcePixelMap) {
        try {
          await foregroundPixelMap.release();
        } catch (e) {
        }
      }
      if (sourcePixelMap !== null) {
        try {
          await sourcePixelMap.release();
        } catch (e) {
        }
      }
      if (imageSource !== null) {
        try {
          await imageSource.release();
        } catch (e) {
        }
      }
      if (imageFile !== null) {
        try {
          await fileIo.close(imageFile);
        } catch (e) {
        }
      }
      await this.release();
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) {
      return;
    }
    let ready = await subjectSegmentation.init();
    if (!ready) {
      throw new Error('Subject segmentation init failed');
    }
    this.initialized = true;
  }

  async release(): Promise<void> {
    if (!this.initialized) {
      return;
    }
    try {
      await subjectSegmentation.release();
    } catch (e) {
    }
    this.initialized = false;
  }

  private sourceImagePath(imagePath: string): string {
    let normalized = imagePath.trim();
    if (normalized.startsWith('data:image/') || normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return '';
    }
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    if (normalized.startsWith('/')) {
      return normalized;
    }
    return this.storage.join(this.paths.avatarRoot, normalized);
  }
}
