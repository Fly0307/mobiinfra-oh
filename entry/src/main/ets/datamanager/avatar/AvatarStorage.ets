import { util } from '@kit.ArkTS';
import { DataManagerPaths } from '../DataManagerPaths';
import { DataManagerStorage } from '../DataManagerStorage';
import {
  AvatarHomeViewModel,
  AvatarState,
  AvatarStatus,
  AvatarVersionState,
  AvatarVersionViewModel,
  createEmptyAvatarHomeViewModel,
  createEmptyAvatarState
} from './AvatarTypes';

interface AvatarVersionIndex {
  version_ids: string[];
}

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

  versionIndexPath(): string {
    return this.storage.join(this.paths.avatarRoot, 'version-index.json');
  }

  assetPath(versionId: string, outputFormat?: string): string {
    return this.storage.join(this.paths.avatarAssetsRoot, versionId + this.avatarAssetExtension(outputFormat));
  }

  relativeAvatarAssetPath(versionId: string, outputFormat?: string): string {
    return 'assets/' + versionId + this.avatarAssetExtension(outputFormat);
  }

  saveAssetBase64(versionId: string, base64Text: string, outputFormat?: string): string {
    let helper = new util.Base64Helper();
    let bytes = helper.decodeSync(base64Text);
    let path = this.assetPath(versionId, outputFormat);
    this.storage.writeBytesAtomic(path, bytes);
    return this.relativeAvatarAssetPath(versionId, outputFormat);
  }

  saveVersion(version: AvatarVersionState): void {
    this.ensureReady();
    this.storage.writeJsonAtomic(this.versionPath(version.version_id), version as Object);
    this.saveVersionId(version.version_id);
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
    let seen: Record<string, boolean> = new Object() as Record<string, boolean>;
    this.loadVersionIds().forEach((versionId: string) => {
      let version = this.loadVersion(versionId);
      if (version !== null && version.version_id.length > 0) {
        seen[version.version_id] = true;
        result.push(version);
      }
    });
    this.storage.listDir(this.paths.avatarVersionsRoot).forEach((name: string) => {
      if (!name.endsWith('.json')) {
        return;
      }
      let version = this.storage.readJson<AvatarVersionState | null>(this.storage.join(this.paths.avatarVersionsRoot, name), null);
      if (version !== null && version.version_id.length > 0 && seen[version.version_id] !== true) {
        seen[version.version_id] = true;
        result.push(version);
      }
    });
    return result.sort((a: AvatarVersionState, b: AvatarVersionState) => b.created_at.localeCompare(a.created_at));
  }

  listVersionViewModels(): AvatarVersionViewModel[] {
    return this.listVersions().map((version: AvatarVersionState): AvatarVersionViewModel => {
      return this.versionViewModel(version);
    });
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

  private versionViewModel(version: AvatarVersionState): AvatarVersionViewModel {
    return {
      versionId: version.version_id,
      createdAt: version.created_at,
      imageUri: this.displayUri(version.image_path),
      imagePath: version.image_path,
      mode: version.mode,
      provider: version.provider,
      model: version.model,
      generationParams: version.generation_params,
      promptSnapshot: version.prompt_snapshot,
      profileSnapshot: version.profile_snapshot,
      profileSnapshotHash: version.profile_snapshot_hash,
      consentSnapshot: version.consent_snapshot
    };
  }

  private loadVersionIds(): string[] {
    let index = this.storage.readJson<AvatarVersionIndex>(this.versionIndexPath(), { version_ids: [] });
    let result: string[] = [];
    let seen: Record<string, boolean> = new Object() as Record<string, boolean>;
    for (let versionId of index.version_ids || []) {
      if (versionId.length > 0 && seen[versionId] !== true) {
        seen[versionId] = true;
        result.push(versionId);
      }
    }
    return result;
  }

  private saveVersionId(versionId: string): void {
    if (versionId.length === 0) {
      return;
    }
    let ids = this.loadVersionIds();
    if (ids.indexOf(versionId) < 0) {
      ids.push(versionId);
    }
    let index: AvatarVersionIndex = {
      version_ids: ids
    };
    this.storage.writeJsonAtomic(this.versionIndexPath(), index as Object);
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

  private avatarAssetExtension(outputFormat?: string): string {
    if (outputFormat === undefined) {
      return '.png';
    }
    let normalized = outputFormat.trim().toLowerCase();
    if (normalized === 'jpg' || normalized === 'jpeg') {
      return '.jpg';
    }
    if (normalized === 'png') {
      return '.png';
    }
    if (normalized === 'webp') {
      return '.webp';
    }
    return '.jpg';
  }
}
