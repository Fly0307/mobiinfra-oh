import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import dataSharePredicates from '@ohos.data.dataSharePredicates';
import { GalleryPhotoInput } from './GalleryTypes';
import { GalleryStorage } from './GalleryStorage';

interface GalleryAssetLocation {
  latitude: number;
  longitude: number;
}

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
    let fetchColumns = this.buildFetchColumns();
    let fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: fetchColumns,
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
        let location = this.readAssetLocation(asset);
        inputs.push({
          uri: uri,
          id: this.stableId(uri),
          date: GalleryStorage.formatDate(dateMs),
          latitude: location?.latitude,
          longitude: location?.longitude
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

  private buildFetchColumns(): string[] {
    let columns: string[] = [
      photoAccessHelper.PhotoKeys.DATE_ADDED,
      photoAccessHelper.PhotoKeys.DATE_MODIFIED
    ];
    this.appendPhotoKey(columns, 'LATITUDE');
    this.appendPhotoKey(columns, 'LONGITUDE');
    this.appendPhotoKey(columns, 'GPS_LATITUDE');
    this.appendPhotoKey(columns, 'GPS_LONGITUDE');
    this.appendPhotoKey(columns, 'PHOTO_LATITUDE');
    this.appendPhotoKey(columns, 'PHOTO_LONGITUDE');
    this.appendPhotoKey(columns, 'LOCATION_LATITUDE');
    this.appendPhotoKey(columns, 'LOCATION_LONGITUDE');
    this.appendPhotoKey(columns, 'latitude');
    this.appendPhotoKey(columns, 'longitude');
    return columns;
  }

  private appendPhotoKey(columns: string[], name: string): void {
    let keys = photoAccessHelper.PhotoKeys as Record<string, string>;
    let key = keys[name];
    if (key && key.length > 0 && columns.indexOf(key) < 0) {
      columns.push(key);
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

  private readAssetLocation(asset: photoAccessHelper.PhotoAsset): GalleryAssetLocation | undefined {
    let latitude = this.readAssetNumber(asset,
      ['LATITUDE', 'GPS_LATITUDE', 'PHOTO_LATITUDE', 'LOCATION_LATITUDE', 'latitude'],
      ['latitude', 'Latitude', 'gpsLatitude', 'GPSLatitude']);
    let longitude = this.readAssetNumber(asset,
      ['LONGITUDE', 'GPS_LONGITUDE', 'PHOTO_LONGITUDE', 'LOCATION_LONGITUDE', 'longitude'],
      ['longitude', 'Longitude', 'gpsLongitude', 'GPSLongitude']);
    if (latitude === undefined || longitude === undefined) {
      return undefined;
    }
    if (!this.isValidLocation(latitude, longitude)) {
      return undefined;
    }
    return {
      latitude: latitude,
      longitude: longitude
    };
  }

  private readAssetNumber(asset: photoAccessHelper.PhotoAsset, photoKeyNames: string[], literalKeys: string[]): number | undefined {
    let keys = photoAccessHelper.PhotoKeys as Record<string, string>;
    for (let i = 0; i < photoKeyNames.length; i++) {
      let key = keys[photoKeyNames[i]];
      let value = this.toNumberValue(key ? this.safeAssetGet(asset, key) : undefined);
      if (value !== undefined) {
        return value;
      }
    }
    for (let j = 0; j < literalKeys.length; j++) {
      let value = this.toNumberValue(this.safeAssetGet(asset, literalKeys[j]));
      if (value !== undefined) {
        return value;
      }
    }
    return undefined;
  }

  private safeAssetGet(asset: photoAccessHelper.PhotoAsset, key: string): Object | undefined {
    try {
      return asset.get(key);
    } catch (e) {
      return undefined;
    }
  }

  private toNumberValue(value: Object | undefined): number | undefined {
    if (value === undefined || value === null) {
      return undefined;
    }
    let parsed = Number(String(value));
    if (isNaN(parsed) || !isFinite(parsed)) {
      return undefined;
    }
    return parsed;
  }

  private isValidLocation(latitude: number, longitude: number): boolean {
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return false;
    }
    return latitude !== 0 || longitude !== 0;
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
