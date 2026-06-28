import { Want } from '@kit.AbilityKit';
import { JSON as ArkJSON, util } from '@kit.ArkTS';
import { fileUri } from '@kit.CoreFileKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import fs from '@ohos.file.fs';
import { AppLogger } from './AppLogger';
import { decodeUtf8Compat, encodeUtf8Compat } from './TextEncodingCompat';
import { parseJsonCompat, stringifyJsonCompat } from './JsonCompat';
import { WorkflowStorage } from './WorkflowStorage';

export const PROFILE_KNOCK_SHARE_UTD: string = 'com.mobiinfra.profile-json';
export const PROFILE_KNOCK_SHARE_FILE_EXTENSION: string = '.mobi-profile.json';

const PROFILE_SHARE_DIR: string = 'profile-share';
const PROFILE_SHARE_OUTBOX_DIR: string = 'outbox';
const PROFILE_SHARE_INBOX_DIR: string = 'inbox';
const MAX_RECEIVED_PROFILE_BYTES: number = 512 * 1024;
const PROFILE_SHARE_SCHEMA_VERSION: number = 1;

type ShareWantListener = (want: Want) => void;

export interface ProfileShareEnvelope {
  schemaVersion: number;
  typeId: string;
  appId: string;
  appName: string;
  generatedAt: string;
  profileText: string;
  profile: Object;
}

export interface ProfileShareReceivedEvent {
  profileText: string;
  rawText: string;
  title: string;
  sourceUri: string;
  source: string;
  generatedAt: string;
  receivedAt: string;
}

export interface ProfileKnockShareOptions {
  filesDir: string;
  windowId: number;
  buildLocalProfile: () => ProfileShareEnvelope;
  onProfileReceived: (event: ProfileShareReceivedEvent) => Promise<void>;
  onLog?: (message: string) => void;
}

interface ParsedProfileShareEnvelope {
  schemaVersion?: number;
  typeId?: string;
  appId?: string;
  appName?: string;
  generatedAt?: string;
  profileText?: string;
  profile?: Object;
}

export class ProfileShareLaunchBridge {
  private static pendingWants: Want[] = [];
  private static listeners: ShareWantListener[] = [];

  static enqueueWant(want: Want): void {
    ProfileShareLaunchBridge.pendingWants.push(want);
    let listeners = ProfileShareLaunchBridge.listeners.slice();
    for (let i = 0; i < listeners.length; i++) {
      listeners[i](want);
    }
  }

  static drainWants(): Want[] {
    let wants = ProfileShareLaunchBridge.pendingWants.slice();
    ProfileShareLaunchBridge.pendingWants = [];
    return wants;
  }

  static addListener(listener: ShareWantListener): void {
    if (ProfileShareLaunchBridge.listeners.indexOf(listener) >= 0) {
      return;
    }
    ProfileShareLaunchBridge.listeners.push(listener);
  }

  static removeListener(listener: ShareWantListener): void {
    ProfileShareLaunchBridge.listeners = ProfileShareLaunchBridge.listeners.filter((item: ShareWantListener) =>
      item !== listener);
  }
}

export class ProfileKnockShareService {
  private options: ProfileKnockShareOptions | null = null;
  private sendCapability: harmonyShare.SendCapabilityRegistry | null = null;
  private recvCapability: harmonyShare.RecvCapabilityRegistry | null = null;
  private knockShareCallback: ((target: harmonyShare.SharableTarget) => void) | null = null;
  private dataReceiveCallback: ((target: harmonyShare.ReceivableTarget) => void) | null = null;
  private wantListener: ShareWantListener | null = null;

  configure(options: ProfileKnockShareOptions): void {
    this.dispose();
    this.options = options;
    this.registerKnockShare(options);
    this.registerDataReceive(options);
    this.registerLaunchWantConsumer();
    this.consumePendingLaunchWants();
  }

  dispose(): void {
    if (this.sendCapability !== null && this.knockShareCallback !== null) {
      try {
        harmonyShare.off('knockShare', this.sendCapability, this.knockShareCallback);
      } catch (e) {
        AppLogger.warnCause('ProfileKnockShare', 'unregister knockShare failed', e as Error);
      }
    }
    if (this.recvCapability !== null && this.dataReceiveCallback !== null) {
      try {
        harmonyShare.off('dataReceive', this.recvCapability, this.dataReceiveCallback);
      } catch (e) {
        AppLogger.warnCause('ProfileKnockShare', 'unregister dataReceive failed', e as Error);
      }
    }
    if (this.wantListener !== null) {
      ProfileShareLaunchBridge.removeListener(this.wantListener);
    }
    this.sendCapability = null;
    this.recvCapability = null;
    this.knockShareCallback = null;
    this.dataReceiveCallback = null;
    this.wantListener = null;
    this.options = null;
  }

  private registerKnockShare(options: ProfileKnockShareOptions): void {
    this.sendCapability = {
      windowId: options.windowId
    };
    this.knockShareCallback = (target: harmonyShare.SharableTarget): void => {
      this.shareLocalProfile(target).catch((e: Error) => {
        AppLogger.errorCause('ProfileKnockShare', 'share local profile failed', e);
        this.log('一碰分享发送失败：' + e.message);
      });
    };
    harmonyShare.on('knockShare', this.sendCapability, this.knockShareCallback);
    this.log('已注册一碰发送能力，windowId=' + String(options.windowId));
  }

  private registerDataReceive(options: ProfileKnockShareOptions): void {
    this.recvCapability = {
      windowId: options.windowId,
      capabilities: [
        {
          utd: PROFILE_KNOCK_SHARE_UTD,
          maxSupportedCount: 1
        }
      ]
    };
    this.dataReceiveCallback = (target: harmonyShare.ReceivableTarget): void => {
      this.receiveProfileData(target).catch((e: Error) => {
        AppLogger.errorCause('ProfileKnockShare', 'receive profile data failed', e);
        this.log('一碰分享接收失败：' + e.message);
      });
    };
    harmonyShare.on('dataReceive', this.recvCapability, this.dataReceiveCallback);
    this.log('已注册一碰接收能力，UTD=' + PROFILE_KNOCK_SHARE_UTD);
  }

  private registerLaunchWantConsumer(): void {
    this.wantListener = (want: Want): void => {
      this.handleShareWant(want).catch((e: Error) => {
        AppLogger.warnCause('ProfileKnockShare', 'handle launch want failed', e);
      });
    };
    ProfileShareLaunchBridge.addListener(this.wantListener);
  }

  private consumePendingLaunchWants(): void {
    let pending = ProfileShareLaunchBridge.drainWants();
    for (let i = 0; i < pending.length; i++) {
      this.handleShareWant(pending[i]).catch((e: Error) => {
        AppLogger.warnCause('ProfileKnockShare', 'handle pending launch want failed', e);
      });
    }
  }

  private async shareLocalProfile(target: harmonyShare.SharableTarget): Promise<void> {
    let options = this.requireOptions();
    try {
      let data = this.createSharedData(options);
      await target.share(data);
      this.log('已通过一碰分享发送画像文件');
    } catch (e) {
      let err = e as Error;
      try {
        await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
      } catch (rejectErr) {
        AppLogger.warnCause('ProfileKnockShare', 'reject share target failed', rejectErr as Error);
      }
      throw err;
    }
  }

  private createSharedData(options: ProfileKnockShareOptions): systemShare.SharedData {
    let envelope = options.buildLocalProfile();
    let content = stringifyJsonCompat(envelope, 2);
    let path = this.nextOutboxFilePath(options.filesDir);
    this.writeText(path, content);
    let uri = fileUri.getUriFromPath(path);
    return new systemShare.SharedData({
      utd: PROFILE_KNOCK_SHARE_UTD,
      uri: uri,
      title: 'MobiInfer 用户画像',
      label: '用户画像',
      description: '用于生成同频报告的个人画像摘要',
      extraData: {
        schemaVersion: PROFILE_SHARE_SCHEMA_VERSION,
        typeId: PROFILE_KNOCK_SHARE_UTD,
        generatedAt: envelope.generatedAt
      }
    });
  }

  private async receiveProfileData(target: harmonyShare.ReceivableTarget): Promise<void> {
    let options = this.requireOptions();
    let receiveUri = this.inboxDirUri(options.filesDir);
    try {
      await target.receive(receiveUri, {
        onDataReceived: (data: systemShare.SharedData): void => {
          this.handleSharedData(data, 'dataReceive').catch((e: Error) => {
            AppLogger.errorCause('ProfileKnockShare', 'process received SharedData failed', e);
            this.log('解析一碰分享数据失败：' + e.message);
          });
        },
        onResult: (code: harmonyShare.ShareResultCode): void => {
          this.log('一碰分享接收结果：' + String(code));
        }
      });
    } catch (e) {
      let err = e as Error;
      try {
        await target.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR);
      } catch (rejectErr) {
        AppLogger.warnCause('ProfileKnockShare', 'reject receive target failed', rejectErr as Error);
      }
      throw err;
    }
  }

  private async handleShareWant(want: Want): Promise<void> {
    try {
      let data = await systemShare.getSharedData(want);
      await this.handleSharedData(data, 'want');
    } catch (e) {
      let errorText = ArkJSON.stringify(e);
      if (errorText.indexOf('1003703001') >= 0 || errorText.indexOf('Parse data failed') >= 0) {
        return;
      }
      AppLogger.warnCause('ProfileKnockShare', 'systemShare.getSharedData failed', e as Error);
    }
  }

  private async handleSharedData(data: systemShare.SharedData, source: string): Promise<void> {
    let options = this.requireOptions();
    let records = data.getRecords();
    for (let i = 0; i < records.length; i++) {
      let event = this.profileEventFromRecord(records[i], source);
      if (event !== null) {
        this.log('收到画像分享：' + event.title);
        await options.onProfileReceived(event);
        return;
      }
    }
    this.log('收到分享数据，但没有找到可解析的画像文件');
  }

  private profileEventFromRecord(record: systemShare.SharedRecord, source: string): ProfileShareReceivedEvent | null {
    let rawText = '';
    if (record.content !== undefined && record.content.trim().length > 0) {
      rawText = record.content;
    }
    if (rawText.length === 0 && record.uri !== undefined && record.uri.length > 0) {
      rawText = this.readText(record.uri);
    }
    if (rawText.length === 0 && record.extraData !== undefined) {
      let profileText = record.extraData['profileText'];
      if (typeof profileText === 'string') {
        rawText = profileText;
      }
    }
    if (rawText.trim().length === 0) {
      return null;
    }
    return this.profileEventFromText(rawText, record.title === undefined ? '' : record.title,
      record.uri === undefined ? '' : record.uri, source);
  }

  private profileEventFromText(rawText: string, title: string, sourceUri: string,
    source: string): ProfileShareReceivedEvent {
    let profileText = rawText;
    let generatedAt = '';
    try {
      let envelope = parseJsonCompat<ParsedProfileShareEnvelope>(rawText);
      if (envelope.profileText !== undefined && envelope.profileText.trim().length > 0) {
        profileText = envelope.profileText;
      }
      if (envelope.generatedAt !== undefined) {
        generatedAt = envelope.generatedAt;
      }
      if (title.length === 0 && envelope.appName !== undefined) {
        title = envelope.appName + ' 用户画像';
      }
    } catch (e) {
    }
    return {
      profileText: profileText,
      rawText: rawText,
      title: title.length > 0 ? title : '用户画像',
      sourceUri: sourceUri,
      source: source,
      generatedAt: generatedAt,
      receivedAt: new Date().toISOString()
    };
  }

  private requireOptions(): ProfileKnockShareOptions {
    if (this.options === null) {
      throw new Error('Profile knock share service is not configured.');
    }
    return this.options;
  }

  private nextOutboxFilePath(filesDir: string): string {
    let outboxDir = this.outboxDir(filesDir);
    WorkflowStorage.ensureDirectoryTree(outboxDir);
    let suffix = util.generateRandomUUID().substring(0, 8);
    return outboxDir + '/profile-' + String(new Date().getTime()) + '-' + suffix + PROFILE_KNOCK_SHARE_FILE_EXTENSION;
  }

  private outboxDir(filesDir: string): string {
    return filesDir.replace(/\\/g, '/').replace(/\/+$/g, '') + '/' + PROFILE_SHARE_DIR + '/' +
      PROFILE_SHARE_OUTBOX_DIR;
  }

  private inboxDir(filesDir: string): string {
    return filesDir.replace(/\\/g, '/').replace(/\/+$/g, '') + '/' + PROFILE_SHARE_DIR + '/' +
      PROFILE_SHARE_INBOX_DIR;
  }

  private inboxDirUri(filesDir: string): string {
    let dir = this.inboxDir(filesDir);
    WorkflowStorage.ensureDirectoryTree(dir);
    return fileUri.getUriFromPath(dir);
  }

  private writeText(path: string, content: string): void {
    let encoded = encodeUtf8Compat(content);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, encoded.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  private readText(pathOrUri: string): string {
    let file: fs.File | null = null;
    let chunks: Uint8Array[] = [];
    let total = 0;
    try {
      file = fs.openSync(pathOrUri, fs.OpenMode.READ_ONLY);
      while (total < MAX_RECEIVED_PROFILE_BYTES) {
        let buffer = new ArrayBuffer(16 * 1024);
        let readSize = fs.readSync(file.fd, buffer);
        if (readSize <= 0) {
          break;
        }
        let allowed = Math.min(readSize, MAX_RECEIVED_PROFILE_BYTES - total);
        chunks.push(new Uint8Array(buffer.slice(0, allowed)));
        total += allowed;
        if (allowed < readSize) {
          break;
        }
      }
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
    let merged = new Uint8Array(total);
    let offset = 0;
    for (let i = 0; i < chunks.length; i++) {
      merged.set(chunks[i], offset);
      offset += chunks[i].byteLength;
    }
    return decodeUtf8Compat(merged);
  }

  private log(message: string): void {
    AppLogger.info('ProfileKnockShare', message);
    if (this.options !== null && this.options.onLog !== undefined) {
      this.options.onLog(message);
    }
  }
}
