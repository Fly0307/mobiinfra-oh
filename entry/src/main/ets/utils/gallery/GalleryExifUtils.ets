import { GalleryExifMetadata } from './GalleryTypes';

export class GalleryExifUtils {
  static cleanProperty(value: string | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    let text = String(value).replace(/\u0000/g, '').replace(/\s+/g, ' ').trim();
    if (text === 'undefined' || text === 'null' || text === '0' || text === '0/0') {
      return '';
    }
    return text;
  }

  static coordinateFromExif(value: string | undefined, ref: string | undefined): number | undefined {
    let text = GalleryExifUtils.cleanProperty(value);
    if (text.length === 0) {
      return undefined;
    }
    let parts = GalleryExifUtils.coordinateParts(text);
    if (parts.length === 0) {
      return undefined;
    }
    let decimal = parts[0];
    if (parts.length >= 3) {
      decimal = parts[0] + parts[1] / 60 + parts[2] / 3600;
    } else if (parts.length === 2) {
      decimal = parts[0] + parts[1] / 60;
    }
    let direction = GalleryExifUtils.cleanProperty(ref).toUpperCase();
    if (direction === 'S' || direction === 'W') {
      decimal = -Math.abs(decimal);
    }
    if (isNaN(decimal) || !isFinite(decimal)) {
      return undefined;
    }
    return decimal;
  }

  static rawGpsLocationText(metadata: GalleryExifMetadata | undefined): string {
    if (!metadata) {
      return '';
    }
    let latitude = GalleryExifUtils.cleanProperty(metadata.gpsLatitude);
    let longitude = GalleryExifUtils.cleanProperty(metadata.gpsLongitude);
    if (latitude.length === 0 || longitude.length === 0) {
      return '';
    }
    let latitudeRef = GalleryExifUtils.cleanProperty(metadata.gpsLatitudeRef);
    let longitudeRef = GalleryExifUtils.cleanProperty(metadata.gpsLongitudeRef);
    if (latitudeRef.length > 0) {
      latitude = latitude + ' ' + latitudeRef;
    }
    if (longitudeRef.length > 0) {
      longitude = longitude + ' ' + longitudeRef;
    }
    return latitude + ', ' + longitude;
  }

  static dateFromExifDateTime(value: string | undefined): string {
    let text = GalleryExifUtils.cleanProperty(value);
    if (text.length < 10) {
      return '';
    }
    let normalized = text.substring(0, 10).replace(/:/g, '-').replace(/\//g, '-');
    let parts = normalized.split('-');
    if (parts.length !== 3) {
      return '';
    }
    let year = Number(parts[0]);
    let month = Number(parts[1]);
    let day = Number(parts[2]);
    if (isNaN(year) || isNaN(month) || isNaN(day) || year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return '';
    }
    return year.toString().padStart(4, '0') + '-' +
      month.toString().padStart(2, '0') + '-' +
      day.toString().padStart(2, '0');
  }

  static displayDateTime(value: string | undefined): string {
    let text = GalleryExifUtils.cleanProperty(value);
    if (text.length < 10) {
      return '';
    }
    let date = GalleryExifUtils.dateFromExifDateTime(text);
    if (date.length === 0) {
      return text;
    }
    if (text.length <= 10) {
      return date;
    }
    return date + ' ' + text.substring(11).trim();
  }

  static deviceText(metadata: GalleryExifMetadata | undefined): string {
    if (!metadata) {
      return '';
    }
    let make = GalleryExifUtils.cleanProperty(metadata.deviceMake);
    let model = GalleryExifUtils.cleanProperty(metadata.deviceModel);
    if (make.length > 0 && model.length > 0) {
      if (model.toLowerCase().indexOf(make.toLowerCase()) >= 0) {
        return model;
      }
      return make + ' ' + model;
    }
    return model.length > 0 ? model : make;
  }

  static locationText(latitude: number | undefined, longitude: number | undefined): string {
    if (latitude === undefined || longitude === undefined) {
      return '';
    }
    let lat = Number(latitude);
    let lon = Number(longitude);
    if (!GalleryExifUtils.isValidLocation(lat, lon)) {
      return '';
    }
    return lat.toFixed(6) + ', ' + lon.toFixed(6);
  }

  static directedLocationText(latitude: number | undefined, longitude: number | undefined): string {
    if (latitude === undefined || longitude === undefined) {
      return '';
    }
    let lat = Number(latitude);
    let lon = Number(longitude);
    if (!GalleryExifUtils.isValidLocation(lat, lon)) {
      return '';
    }
    let latLabel = lat >= 0 ? '北纬' : '南纬';
    let lonLabel = lon >= 0 ? '东经' : '西经';
    return latLabel + ' ' + Math.abs(lat).toFixed(6) + '，' + lonLabel + ' ' + Math.abs(lon).toFixed(6);
  }

  static mapUrl(latitude: number | undefined, longitude: number | undefined): string {
    if (latitude === undefined || longitude === undefined) {
      return '';
    }
    let lat = Number(latitude);
    let lon = Number(longitude);
    if (!GalleryExifUtils.isValidLocation(lat, lon)) {
      return '';
    }
    return 'https://uri.amap.com/marker?position=' + lon.toFixed(6) + ',' + lat.toFixed(6) +
      '&name=' + encodeURIComponent('拍摄位置');
  }

  static isValidLocation(latitude: number, longitude: number): boolean {
    if (isNaN(latitude) || isNaN(longitude)) {
      return false;
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return false;
    }
    return latitude !== 0 || longitude !== 0;
  }

  private static coordinateParts(text: string): number[] {
    let normalized = text
      .replace(/\[/g, '')
      .replace(/\]/g, '')
      .replace(/;/g, ',')
      .replace(/，/g, ',')
      .replace(/；/g, ',')
      .replace(/°/g, ',')
      .replace(/º/g, ',')
      .replace(/度/g, ',')
      .replace(/′/g, ',')
      .replace(/’/g, ',')
      .replace(/'/g, ',')
      .replace(/分/g, ',')
      .replace(/″/g, ',')
      .replace(/”/g, ',')
      .replace(/"/g, ',')
      .replace(/秒/g, ',')
      .replace(/\(/g, ' ')
      .replace(/\)/g, ' ')
      .replace(/N/g, ' ')
      .replace(/S/g, ' ')
      .replace(/E/g, ' ')
      .replace(/W/g, ' ')
      .replace(/n/g, ' ')
      .replace(/s/g, ' ')
      .replace(/e/g, ' ')
      .replace(/w/g, ' ');
    let rawParts = normalized.indexOf(',') >= 0 ? normalized.split(',') : normalized.split(' ');
    let parts: number[] = [];
    for (let i = 0; i < rawParts.length; i++) {
      let value = GalleryExifUtils.rationalToNumber(rawParts[i].trim());
      if (value !== undefined) {
        parts.push(value);
      }
    }
    return parts;
  }

  private static rationalToNumber(text: string): number | undefined {
    if (text.length === 0) {
      return undefined;
    }
    let slash = text.indexOf('/');
    if (slash > 0) {
      let numerator = Number(text.substring(0, slash));
      let denominator = Number(text.substring(slash + 1));
      if (!isNaN(numerator) && !isNaN(denominator) && denominator !== 0) {
        return numerator / denominator;
      }
      return undefined;
    }
    let value = Number(text);
    if (isNaN(value) || !isFinite(value)) {
      return undefined;
    }
    return value;
  }
}
