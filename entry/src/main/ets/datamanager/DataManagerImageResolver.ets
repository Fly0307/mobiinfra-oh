import {
  CollectionImageViewModel,
  JsonMap
} from './DataManagerTypes';
import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { normalizeFreeText } from './DataManagerUtils';

export class DataManagerImageResolver {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage) {
    this.paths = paths;
    this.storage = storage;
  }

  resolveAll(refs: string[]): CollectionImageViewModel[] {
    let result: CollectionImageViewModel[] = [];
    for (let index = 0; index < refs.length; index++) {
      let ref = normalizeFreeText(refs[index]);
      if (ref.length === 0) {
        continue;
      }
      result.push(this.resolve(ref, index));
    }
    return result;
  }

  private resolve(ref: string, index: number): CollectionImageViewModel {
    let uri = this.displayUri(ref);
    let image: CollectionImageViewModel = {
      ref: ref,
      uri: uri,
      available: uri.length > 0,
      label: '图片 ' + (index + 1).toString()
    };
    return image;
  }

  private displayUri(ref: string): string {
    if (ref.startsWith('data:image/')) {
      return ref;
    }
    let hashIndex = ref.indexOf('#');
    if (hashIndex >= 0) {
      return this.displayUriFromJsonPointer(ref.substring(0, hashIndex), ref.substring(hashIndex + 1));
    }
    let imageText = normalizeFreeText(ref);
    if (this.looksLikeBase64Image(imageText)) {
      return this.base64DataUri(imageText);
    }
    let absolutePath = this.absoluteImagePath(imageText);
    return absolutePath.length > 0 ? 'file://' + absolutePath : '';
  }

  private displayUriFromJsonPointer(fileRef: string, pointer: string): string {
    let filePath = this.absoluteJsonPath(fileRef);
    if (filePath.length === 0) {
      return '';
    }
    let payload = this.storage.readJson<JsonMap>(filePath, new Object() as JsonMap);
    let value = this.pointerString(payload, pointer);
    if (value.length === 0) {
      return '';
    }
    if (value.startsWith('data:image/')) {
      return value;
    }
    if (this.looksLikeBase64Image(value)) {
      return this.base64DataUri(value);
    }
    let absolutePath = this.absoluteImagePath(value);
    return absolutePath.length > 0 ? 'file://' + absolutePath : '';
  }

  private pointerString(payload: JsonMap, pointer: string): string {
    let segments = pointer.split('/').filter((segment: string) => segment.length > 0);
    let current: Object | string | number | boolean | null | undefined = payload;
    for (let segment of segments) {
      if (!current || typeof current !== 'object' || Array.isArray(current)) {
        return '';
      }
      let currentMap = current as JsonMap;
      current = currentMap[segment];
    }
    return normalizeFreeText(current);
  }

  private absoluteJsonPath(fileRef: string): string {
    let filePath = normalizeFreeText(fileRef).replace(/\\/g, '/');
    if (filePath.startsWith('file://')) {
      filePath = filePath.substring('file://'.length);
    }
    if (this.isAbsolutePath(filePath)) {
      return this.storage.exists(filePath) ? filePath : '';
    }
    if (filePath.startsWith('workflows/')) {
      let absolute = this.storage.join(this.paths.filesDir, filePath);
      return this.storage.exists(absolute) ? absolute : '';
    }
    let relative = this.paths.fromDataManagerRelative(filePath);
    return this.storage.exists(relative) ? relative : '';
  }

  private absoluteImagePath(value: string): string {
    let pathText = normalizeFreeText(value).replace(/\\/g, '/');
    if (pathText.startsWith('file://')) {
      pathText = pathText.substring('file://'.length);
    }
    if (this.isAbsolutePath(pathText)) {
      return this.storage.exists(pathText) ? pathText : '';
    }
    if (pathText.startsWith('workflows/')) {
      let absolute = this.storage.join(this.paths.filesDir, pathText);
      return this.storage.exists(absolute) ? absolute : '';
    }
    let relative = this.paths.fromDataManagerRelative(pathText);
    return this.storage.exists(relative) ? relative : '';
  }

  private isAbsolutePath(pathText: string): boolean {
    return pathText.startsWith('/') || /^[A-Za-z]:\//.test(pathText);
  }

  private looksLikeBase64Image(value: string): boolean {
    let text = value.replace(/\s+/g, '');
    return text.startsWith('/9j/') || text.startsWith('iVBORw0KGgo') ||
      text.startsWith('R0lGOD') || text.startsWith('UklGR');
  }

  private base64DataUri(value: string): string {
    let text = value.replace(/\s+/g, '');
    if (text.startsWith('iVBORw0KGgo')) {
      return 'data:image/png;base64,' + text;
    }
    if (text.startsWith('R0lGOD')) {
      return 'data:image/gif;base64,' + text;
    }
    if (text.startsWith('UklGR')) {
      return 'data:image/webp;base64,' + text;
    }
    return 'data:image/jpeg;base64,' + text;
  }
}
