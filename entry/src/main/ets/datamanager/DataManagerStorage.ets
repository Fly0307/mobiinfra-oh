import { JSON as ArkJSON, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import fs from '@ohos.file.fs';

const EMPTY_SHA256: string = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

export class DataManagerStorage {
  join(...parts: string[]): string {
    let filtered = parts
      .filter((part: string) => part.length > 0)
      .map((part: string, index: number) => {
        let value = part.replace(/\\/g, '/');
        if (index === 0) {
          return value.replace(/\/+$/g, '');
        }
        return value.replace(/^\/+/g, '').replace(/\/+$/g, '');
      });
    return filtered.join('/');
  }

  dirname(path: string): string {
    let normalized = path.replace(/\\/g, '/');
    let index = normalized.lastIndexOf('/');
    return index > 0 ? normalized.substring(0, index) : '';
  }

  basename(path: string): string {
    let normalized = path.replace(/\\/g, '/');
    let index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  isDirectory(path: string): boolean {
    try {
      if (!this.exists(path)) {
        return false;
      }
      return fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  ensureDir(path: string): void {
    if (path.length === 0 || this.exists(path)) {
      return;
    }
    let normalized = path.replace(/\\/g, '/');
    let parts = normalized.split('/').filter((part: string) => part.length > 0);
    let current = normalized.startsWith('/') ? '' : '';
    for (let part of parts) {
      current = current.length === 0 ? (normalized.startsWith('/') ? '/' + part : part) : current + '/' + part;
      if (!this.exists(current)) {
        try {
          fs.mkdirSync(current);
        } catch (e) {
        }
      }
    }
  }

  listDir(path: string): string[] {
    try {
      if (!this.isDirectory(path)) {
        return [];
      }
      return fs.listFileSync(path).sort();
    } catch (e) {
      return [];
    }
  }

  readText(path: string, fallback: string = ''): string {
    try {
      if (!this.exists(path)) {
        return fallback;
      }
      let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buf));
    } catch (e) {
      return fallback;
    }
  }

  writeText(path: string, content: string): void {
    let parent = this.dirname(path);
    if (parent.length > 0) {
      this.ensureDir(parent);
    }
    let encoded = util.TextEncoder.create('utf-8').encodeInto(content);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, encoded.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  writeBytes(path: string, bytes: Uint8Array): void {
    let parent = this.dirname(path);
    if (parent.length > 0) {
      this.ensureDir(parent);
    }
    let buffer = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength ? bytes.buffer : new Uint8Array(bytes).buffer;
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  writeBytesAtomic(path: string, bytes: Uint8Array): void {
    let temporary = path + '.tmp';
    this.writeBytes(temporary, bytes);
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
    try {
      fs.renameSync(temporary, path);
    } catch (e) {
      this.writeBytes(path, bytes);
      try {
        fs.unlinkSync(temporary);
      } catch (err) {
      }
    }
  }

  writeTextAtomic(path: string, content: string): void {
    let temporary = path + '.tmp';
    this.writeText(temporary, content);
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
    try {
      fs.renameSync(temporary, path);
    } catch (e) {
      this.writeText(path, content);
      try {
        fs.unlinkSync(temporary);
      } catch (err) {
      }
    }
  }

  readJson<T>(path: string, fallback: T): T {
    let content = this.readText(path, '');
    if (content.length === 0) {
      return fallback;
    }
    try {
      return ArkJSON.parse(content) as T;
    } catch (e) {
      return fallback;
    }
  }

  writeJsonAtomic(path: string, payload: Object): void {
    this.writeTextAtomic(path, ArkJSON.stringify(payload, null, 2) + '\n');
  }

  removeFile(path: string): void {
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
    }
  }

  removeTree(path: string): void {
    if (!this.exists(path)) {
      return;
    }
    if (!this.isDirectory(path)) {
      this.removeFile(path);
      return;
    }
    let children = this.listDir(path);
    for (let child of children) {
      this.removeTree(this.join(path, child));
    }
    try {
      fs.unlinkSync(path);
      return;
    } catch (e) {
    }
    try {
      fs.rmdirSync(path);
    } catch (e) {
    }
  }

  syncJsonDirectory(directory: string, desired: Record<string, Object>): void {
    this.ensureDir(directory);
    Object.keys(desired).forEach((name: string) => {
      this.writeJsonAtomic(this.join(directory, name), desired[name]);
    });
    this.listDir(directory).forEach((name: string) => {
      if (name.endsWith('.json') && desired[name] === undefined) {
        this.removeFile(this.join(directory, name));
      }
    });
  }

  findFiles(root: string, suffix: string): string[] {
    let result: string[] = [];
    this.findFilesInner(root, suffix, result);
    return result.sort();
  }

  private findFilesInner(path: string, suffix: string, out: string[]): void {
    if (!this.exists(path)) {
      return;
    }
    if (!this.isDirectory(path)) {
      if (path.endsWith(suffix)) {
        out.push(path);
      }
      return;
    }
    let children = this.listDir(path);
    for (let child of children) {
      let childPath = this.join(path, child);
      if (this.isDirectory(childPath)) {
        this.findFilesInner(childPath, suffix, out);
      } else if (child.endsWith(suffix)) {
        out.push(childPath);
      }
    }
  }

  relativePath(root: string, path: string): string {
    let normalizedRoot = root.replace(/\\/g, '/').replace(/\/+$/g, '');
    let normalizedPath = path.replace(/\\/g, '/');
    if (normalizedPath.startsWith(normalizedRoot + '/')) {
      return normalizedPath.substring(normalizedRoot.length + 1);
    }
    return normalizedPath;
  }

  sha256Text(value: string): string {
    if (value.length === 0) {
      return EMPTY_SHA256;
    }
    let bytes = util.TextEncoder.create('utf-8').encodeInto(value);
    let md = cryptoFramework.createMd('SHA256');
    let blob: cryptoFramework.DataBlob = { data: bytes };
    md.updateSync(blob);
    let digest = md.digestSync();
    return this.bytesToHex(digest.data);
  }

  private bytesToHex(bytes: Uint8Array): string {
    let parts: string[] = [];
    for (let index = 0; index < bytes.length; index++) {
      parts.push(bytes[index].toString(16).padStart(2, '0'));
    }
    return parts.join('');
  }
}
