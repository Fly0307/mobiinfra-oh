import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import dataSharePredicates from '@ohos.data.dataSharePredicates';
import { GalleryPhotoInput } from './GalleryTypes';
import { GalleryStorage } from './GalleryStorage';

export class GalleryAutoScanner {
  async scanAllImages(context: common.UIAbilityContext): Promise<GalleryPhotoInput[]> {
    return this.scanImages(context, 0);
  }

  async scanRecentImages(context: common.UIAbilityContext, limit: number): Promise<GalleryPhotoInput[]> {
    return this.scanImages(context, limit);
  }

  private async scanImages(context: common.UIAbilityContext, limit: number): Promise<GalleryPhotoInput[]> {
    let helper = photoAccessHelper.getPhotoAccessHelper(context);
    let predicates = new dataSharePredicates.DataSharePredicates();
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_ADDED);
    let fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.DATE_ADDED,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED
      ],
      predicates: predicates
    };
    let fetchResult = await helper.getAssets(fetchOptions);
    try {
      let total = fetchResult.getCount();
      let count = limit > 0 ? Math.min(limit, total) : total;
      let inputs: GalleryPhotoInput[] = [];
      for (let i = 0; i < count; i++) {
        let asset = await fetchResult.getObjectByPosition(i);
        if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) {
          continue;
        }
        let uri = asset.uri;
        if (!uri || uri.length === 0) {
          continue;
        }
        let dateMs = this.readAssetDateMs(asset);
        inputs.push({
          uri: uri,
          id: this.stableId(uri),
          date: GalleryStorage.formatDate(dateMs)
        });
      }
      return inputs;
    } finally {
      try {
        fetchResult.close();
      } catch (e) {
      }
    }
  }

  private readAssetDateMs(asset: photoAccessHelper.PhotoAsset): number {
    let dateAdded = this.toTimestampMs(String(asset.get(photoAccessHelper.PhotoKeys.DATE_ADDED)));
    if (dateAdded > 0) {
      return dateAdded;
    }
    let dateModified = this.toTimestampMs(String(asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED)));
    if (dateModified > 0) {
      return dateModified;
    }
    return new Date().getTime();
  }

  private toTimestampMs(text: string): number {
    let parsed = Number(text);
    if (isNaN(parsed) || parsed <= 0) {
      return 0;
    }
    if (parsed < 10000000000) {
      return parsed * 1000;
    }
    return parsed;
  }

  private stableId(uri: string): string {
    let hash = 0;
    for (let i = 0; i < uri.length; i++) {
      hash = ((hash << 5) - hash) + uri.charCodeAt(i);
      hash = hash & hash;
    }
    return 'gallery_' + Math.abs(hash).toString();
  }
}
