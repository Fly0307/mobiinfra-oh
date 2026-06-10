import { DataManagerPaths } from '../DataManagerPaths';
import { DataManagerStorage } from '../DataManagerStorage';
import { ProfileState } from '../DataManagerTypes';
import { nowIsoLocal } from '../DataManagerUtils';
import { AvatarPromptBuilder } from './AvatarPromptBuilder';
import { AvatarStorage } from './AvatarStorage';
import { SeedreamAvatarProvider } from './SeedreamAvatarProvider';
import {
  AvatarGenerateRequest,
  AvatarGenerationMode,
  AvatarGenerationParams,
  AvatarHomeViewModel,
  AvatarProviderConfig,
  AvatarProviderRequest,
  AvatarProviderResult,
  AvatarState,
  AvatarVersionState,
  AvatarVersionViewModel
} from './AvatarTypes';

export class AvatarService {
  private avatarStorage: AvatarStorage;
  private promptBuilder: AvatarPromptBuilder;
  private provider: SeedreamAvatarProvider;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage) {
    this.avatarStorage = new AvatarStorage(paths, storage);
    this.promptBuilder = new AvatarPromptBuilder(storage);
    this.provider = new SeedreamAvatarProvider();
  }

  ensureReady(): void {
    this.avatarStorage.ensureReady();
  }

  homeView(profile: ProfileState, completeness: number): AvatarHomeViewModel {
    this.ensureReady();
    let state = this.avatarStorage.loadState();
    if (profile.event_count > 0 && state.current_version_id.length > 0) {
      let latestHash = this.previewProfileSnapshotHash(profile, completeness);
      if (state.status === 'current' && latestHash !== state.profile_snapshot_hash) {
        state.status = 'stale';
        state.updated_at = nowIsoLocal();
        this.avatarStorage.saveState(state);
      }
    }
    let currentVersion = this.avatarStorage.loadVersion(state.current_version_id);
    return this.avatarStorage.homeViewFromState(state, currentVersion);
  }

  previewProfileSnapshotHash(profile: ProfileState, completeness: number): string {
    return this.promptBuilder.snapshotHash(this.promptBuilder.buildSnapshot(profile, completeness));
  }

  isCurrentProfileSnapshotUnchanged(profile: ProfileState, completeness: number): boolean {
    this.ensureReady();
    let state = this.avatarStorage.loadState();
    if (state.current_version_id.length === 0 || state.profile_snapshot_hash.length === 0) {
      return false;
    }
    return this.previewProfileSnapshotHash(profile, completeness) === state.profile_snapshot_hash;
  }

  listVersionViewModels(): AvatarVersionViewModel[] {
    this.ensureReady();
    return this.avatarStorage.listVersionViewModels();
  }

  buildGenerateRequest(profile: ProfileState, completeness: number, mode: AvatarGenerationMode,
    sourceImage: string, consentedAt: string, photoSource?: string): AvatarGenerateRequest {
    let snapshot = this.promptBuilder.buildSnapshot(profile, completeness);
    let consentPhotoSource = photoSource === undefined ? sourceImage : photoSource;
    return {
      mode: mode,
      prompt: this.promptBuilder.buildPrompt(snapshot, mode),
      sourceImage: sourceImage,
      profileSnapshot: snapshot,
      profileSnapshotHash: this.promptBuilder.snapshotHash(snapshot),
      consent: {
        mode: mode,
        photo_used: mode === 'image_to_image' && sourceImage.trim().length > 0,
        consented_at: consentedAt,
        photo_source: consentPhotoSource
      }
    };
  }

  async generate(config: AvatarProviderConfig, request: AvatarGenerateRequest): Promise<AvatarHomeViewModel> {
    this.ensureReady();
    let previousState = this.avatarStorage.loadState();
    let generatingState: AvatarState = {
      current_version_id: previousState.current_version_id,
      profile_snapshot_hash: previousState.profile_snapshot_hash,
      status: 'generating',
      last_error_code: '',
      last_error_message: '',
      updated_at: nowIsoLocal()
    };
    this.avatarStorage.saveState(generatingState);

    try {
      let params: AvatarGenerationParams = {
        size: config.size,
        response_format: config.responseFormat,
        output_format: config.outputFormat,
        sequential_image_generation: config.sequentialImageGeneration,
        stream: config.stream,
        watermark: config.watermark
      };
      let model = request.mode === 'image_to_image' ? config.imageToImageModel : config.textToImageModel;
      let providerRequest: AvatarProviderRequest = {
        prompt: request.prompt,
        sourceImage: request.sourceImage,
        model: model,
        params: params
      };
      let result: AvatarProviderResult = request.mode === 'image_to_image' ?
        await this.provider.generateImageToImage(config, providerRequest) :
        await this.provider.generateTextToImage(config, providerRequest);
      if (result.imageBytesBase64.trim().length === 0) {
        throw new Error('Avatar provider returned empty image data');
      }

      let versionId = this.nextVersionId();
      let createdAt = nowIsoLocal();
      let imagePath = this.avatarStorage.saveAssetBase64(versionId, result.imageBytesBase64, params.output_format);
      let version: AvatarVersionState = {
        version_id: versionId,
        created_at: createdAt,
        image_path: imagePath,
        thumbnail_path: '',
        mode: request.mode,
        provider: 'seedream',
        model: model,
        generation_params: params,
        prompt_snapshot: request.prompt,
        profile_snapshot: request.profileSnapshot,
        profile_snapshot_hash: request.profileSnapshotHash,
        consent_snapshot: request.consent
      };
      this.avatarStorage.saveVersion(version);
      let currentState: AvatarState = {
        current_version_id: versionId,
        profile_snapshot_hash: request.profileSnapshotHash,
        status: 'current',
        last_error_code: '',
        last_error_message: '',
        updated_at: createdAt
      };
      this.avatarStorage.saveState(currentState);
      return this.avatarStorage.homeViewFromState(currentState, version);
    } catch (e) {
      let err = e as Error;
      let failedState: AvatarState = {
        current_version_id: previousState.current_version_id,
        profile_snapshot_hash: previousState.profile_snapshot_hash,
        status: 'failed',
        last_error_code: 'AVATAR_GENERATE_FAILED',
        last_error_message: err.message,
        updated_at: nowIsoLocal()
      };
      this.avatarStorage.saveState(failedState);
      throw err;
    }
  }

  private nextVersionId(): string {
    return 'avatar-' + String(Date.now()) + '-' + String(Math.floor(Math.random() * 1000000));
  }
}
