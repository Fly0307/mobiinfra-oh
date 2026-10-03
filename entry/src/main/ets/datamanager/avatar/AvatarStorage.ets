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
  private referencePhotoSaveSequence: number = 0;

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
    return this.normalizeState(this.storage.readJson<AvatarState>(this.statePath(), createEmptyAvatarState()));
  }

  saveState(state: AvatarState): void {
    this.ensureReady();
    this.storage.writeJsonAtomic(this.statePath(), this.normalizeState(state) as Object);
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

  saveReferencePhotoBytes(bytes: Uint8Array, sourceUri: string): string {
    this.ensureReady();
    let extension = this.referencePhotoExtension(sourceUri);
    let relativePath = this.nextReferencePhotoPath(extension);
    this.storage.writeBytesAtomic(this.storage.join(this.paths.avatarRoot, relativePath), bytes);
    this.removeStaleReferencePhotoFiles(relativePath);
    return relativePath;
  }

  referencePhotoDisplayUri(relativePath: string): string {
    let normalized = relativePath.trim();
    if (normalized.length === 0) {
      return '';
    }
    let absolutePath = normalized.startsWith('/') || normalized.startsWith('file://') ?
      normalized.replace(/^file:\/\//, '') :
      this.storage.join(this.paths.avatarRoot, normalized);
    if (!this.storage.exists(absolutePath)) {
      return '';
    }
    return this.displayUri(normalized);
  }

  foregroundAssetPath(versionId: string): string {
    return this.storage.join(this.paths.avatarAssetsRoot, versionId + '-foreground.png');
  }

  relativeAvatarForegroundPath(versionId: string): string {
    return 'assets/' + versionId + '-foreground.png';
  }

  foregroundDisplayUri(versionId: string): string {
    return this.displayUri(this.relativeAvatarForegroundPath(versionId));
  }

  messageForegroundAssetPath(versionId: string): string {
    return this.storage.join(this.paths.avatarAssetsRoot, versionId + '-message-foreground.png');
  }

  relativeAvatarMessageForegroundPath(versionId: string): string {
    return 'assets/' + versionId + '-message-foreground.png';
  }

  messageForegroundDisplayUri(versionId: string): string {
    return this.displayUri(this.relativeAvatarMessageForegroundPath(versionId));
  }

  foregroundExists(versionId: string): boolean {
    if (versionId.length === 0) {
      return false;
    }
    return this.storage.exists(this.foregroundAssetPath(versionId));
  }

  messageForegroundExists(versionId: string): boolean {
    if (versionId.length === 0) {
      return false;
    }
    return this.storage.exists(this.messageForegroundAssetPath(versionId));
  }

  saveForegroundPng(versionId: string, bytes: Uint8Array): string {
    this.ensureReady();
    this.storage.writeBytesAtomic(this.foregroundAssetPath(versionId), bytes);
    return this.relativeAvatarForegroundPath(versionId);
  }

  saveMessageForegroundPng(versionId: string, bytes: Uint8Array): string {
    this.ensureReady();
    this.storage.writeBytesAtomic(this.messageForegroundAssetPath(versionId), bytes);
    return this.relativeAvatarMessageForegroundPath(versionId);
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
    view.avatarReferencePhotoUri = this.referencePhotoDisplayUri(state.reference_photo_path);
    if (currentVersion !== null && currentVersion.image_path.length > 0) {
      view.avatarUri = this.displayUri(currentVersion.image_path);
      if (this.foregroundExists(currentVersion.version_id)) {
        view.avatarForegroundUri = this.foregroundDisplayUri(currentVersion.version_id);
      }
      if (this.messageForegroundExists(currentVersion.version_id)) {
        view.avatarMessageForegroundUri = this.messageForegroundDisplayUri(currentVersion.version_id);
      }
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

  private nextReferencePhotoPath(extension: string): string {
    this.referencePhotoSaveSequence += 1;
    return 'assets/reference-photo-' + String(Date.now()) + '-' + String(this.referencePhotoSaveSequence) + extension;
  }

  private removeStaleReferencePhotoFiles(keepRelativePath: string): void {
    let keepName = this.storage.basename(keepRelativePath);
    this.storage.listDir(this.paths.avatarAssetsRoot).forEach((name: string) => {
      if (name.startsWith('reference-photo') && name !== keepName) {
        this.storage.removeFile(this.storage.join(this.paths.avatarAssetsRoot, name));
      }
    });
  }

  private referencePhotoExtension(sourceUri: string): string {
    let normalized = sourceUri.trim().toLowerCase();
    if (normalized.startsWith('data:image/png')) {
      return '.png';
    }
    if (normalized.startsWith('data:image/webp')) {
      return '.webp';
    }
    if (normalized.startsWith('data:image/heic')) {
      return '.heic';
    }
    if (normalized.startsWith('data:image/heif')) {
      return '.heif';
    }
    if (normalized.endsWith('.png')) {
      return '.png';
    }
    if (normalized.endsWith('.webp')) {
      return '.webp';
    }
    if (normalized.endsWith('.heic')) {
      return '.heic';
    }
    if (normalized.endsWith('.heif')) {
      return '.heif';
    }
    return '.jpg';
  }

  private normalizeState(state: AvatarState): AvatarState {
    return {
      current_version_id: this.safeString(state.current_version_id),
      profile_snapshot_hash: this.safeString(state.profile_snapshot_hash),
      status: this.safeStatus(state.status),
      last_error_code: this.safeString(state.last_error_code),
      last_error_message: this.safeString(state.last_error_message),
      updated_at: this.safeString(state.updated_at),
      reference_photo_path: this.safeString(state.reference_photo_path)
    };
  }

  private safeString(value: string): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  private safeStatus(value: AvatarStatus): AvatarStatus {
    if (value === 'current' || value === 'stale' || value === 'generating' || value === 'failed') {
      return value;
    }
    return 'empty';
  }
}
