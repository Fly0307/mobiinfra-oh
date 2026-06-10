import { util } from '@kit.ArkTS';
import { DataManagerPaths } from '../DataManagerPaths';
import { DataManagerStorage } from '../DataManagerStorage';
import {
  AvatarHomeViewModel,
  AvatarState,
  AvatarStatus,
  AvatarVersionState,
  createEmptyAvatarHomeViewModel,
  createEmptyAvatarState
} from './AvatarTypes';

export class AvatarStorage {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage) {
    this.paths = paths;
    this.storage = storage;
  }

  ensureReady(): void {
    this.storage.ensureDir(this.paths.avatarRoot);
    this.storage.ensureDir(this.paths.avatarVersionsRoot);
    this.storage.ensureDir(this.paths.avatarAssetsRoot);
  }

  emptyState(): AvatarState {
    return createEmptyAvatarState();
  }

  statePath(): string {
    return this.storage.join(this.paths.avatarRoot, 'state.json');
  }

  loadState(): AvatarState {
    return this.storage.readJson<AvatarState>(this.statePath(), createEmptyAvatarState());
  }

  saveState(state: AvatarState): void {
    this.ensureReady();
    this.storage.writeJsonAtomic(this.statePath(), state as Object);
  }

  versionPath(versionId: string): string {
    return this.storage.join(this.paths.avatarVersionsRoot, versionId + '.json');
  }

  assetPath(versionId: string): string {
    return this.storage.join(this.paths.avatarAssetsRoot, versionId + '.png');
  }

  relativeAvatarAssetPath(versionId: string): string {
    return 'assets/' + versionId + '.png';
  }

  saveAssetBase64(versionId: string, base64Text: string): string {
    let helper = new util.Base64Helper();
    let bytes = helper.decodeSync(base64Text);
    let path = this.assetPath(versionId);
    this.storage.writeBytesAtomic(path, bytes);
    return this.relativeAvatarAssetPath(versionId);
  }

  saveVersion(version: AvatarVersionState): void {
    this.ensureReady();
    this.storage.writeJsonAtomic(this.versionPath(version.version_id), version as Object);
  }

  loadVersion(versionId: string): AvatarVersionState | null {
    if (versionId.length === 0) {
      return null;
    }
    let fallback = null as AvatarVersionState | null;
    return this.storage.readJson<AvatarVersionState | null>(this.versionPath(versionId), fallback);
  }

  listVersions(): AvatarVersionState[] {
    let result: AvatarVersionState[] = [];
    this.storage.listDir(this.paths.avatarVersionsRoot).forEach((name: string) => {
      if (!name.endsWith('.json')) {
        return;
      }
      let version = this.storage.readJson<AvatarVersionState | null>(this.storage.join(this.paths.avatarVersionsRoot, name), null);
      if (version !== null && version.version_id.length > 0) {
        result.push(version);
      }
    });
    return result.sort((a: AvatarVersionState, b: AvatarVersionState) => b.created_at.localeCompare(a.created_at));
  }

  homeViewFromState(state: AvatarState, currentVersion: AvatarVersionState | null): AvatarHomeViewModel {
    let view = createEmptyAvatarHomeViewModel();
    view.avatarStatus = state.status;
    view.avatarVersionId = state.current_version_id;
    view.avatarUpdatedLabel = state.updated_at;
    view.avatarActionLabel = this.actionLabel(state.status);
    if (currentVersion !== null && currentVersion.image_path.length > 0) {
      view.avatarUri = this.displayUri(currentVersion.image_path);
    }
    return view;
  }

  currentHomeView(): AvatarHomeViewModel {
    let state = this.loadState();
    return this.homeViewFromState(state, this.loadVersion(state.current_version_id));
  }

  displayUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('data:image/')) {
      return path;
    }
    if (path.startsWith('/')) {
      return 'file://' + path;
    }
    return 'file://' + this.storage.join(this.paths.avatarRoot, path);
  }

  private actionLabel(status: AvatarStatus): string {
    if (status === 'current') {
      return '数字分身已更新';
    }
    if (status === 'stale') {
      return '画像已更新，可生成新分身';
    }
    if (status === 'generating') {
      return '数字分身生成中';
    }
    if (status === 'failed') {
      return '生成失败，可重试';
    }
    return '生成数字分身';
  }
}
