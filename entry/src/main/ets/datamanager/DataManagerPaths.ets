import {
  DAILY_LOG_DIR_NAME,
  COLLECTION_GROUPS_DIR_NAME,
  DATA_MANAGER_STORAGE_ROOT_NAME,
  INDEXES_DIR_NAME,
  OUTPUTS_DIR_NAME,
  PROFILE_CONSOLIDATION_DIR_NAME,
  HOME_RECOMMENDATIONS_FILE_NAME,
  WORKFLOW_RUNS_DIR_NAME
} from './DataManagerTypes';
import { DataManagerStorage } from './DataManagerStorage';

const AVATAR_DIR_NAME: string = 'avatar';
const AVATAR_VERSIONS_DIR_NAME: string = 'versions';
const AVATAR_ASSETS_DIR_NAME: string = 'assets';

export class DataManagerPaths {
  readonly filesDir: string;
  readonly rootDir: string;
  readonly dailyLogRoot: string;
  readonly consolidationRoot: string;
  readonly outputsRoot: string;
  readonly indexesRoot: string;
  readonly collectionGroupsRoot: string;
  readonly workflowRunsRoot: string;
  readonly avatarRoot: string;
  readonly avatarVersionsRoot: string;
  readonly avatarAssetsRoot: string;
  private storage: DataManagerStorage;

  constructor(filesDir: string, storage: DataManagerStorage) {
    this.filesDir = filesDir.replace(/\\/g, '/').replace(/\/+$/g, '');
    this.storage = storage;
    this.rootDir = this.storage.join(this.filesDir, DATA_MANAGER_STORAGE_ROOT_NAME);
    this.dailyLogRoot = this.storage.join(this.rootDir, DAILY_LOG_DIR_NAME);
    this.consolidationRoot = this.storage.join(this.rootDir, PROFILE_CONSOLIDATION_DIR_NAME);
    this.outputsRoot = this.storage.join(this.consolidationRoot, OUTPUTS_DIR_NAME);
    this.indexesRoot = this.storage.join(this.consolidationRoot, INDEXES_DIR_NAME);
    this.collectionGroupsRoot = this.storage.join(this.indexesRoot, COLLECTION_GROUPS_DIR_NAME);
    this.workflowRunsRoot = this.storage.join(this.rootDir, WORKFLOW_RUNS_DIR_NAME);
    this.avatarRoot = this.storage.join(this.rootDir, AVATAR_DIR_NAME);
    this.avatarVersionsRoot = this.storage.join(this.avatarRoot, AVATAR_VERSIONS_DIR_NAME);
    this.avatarAssetsRoot = this.storage.join(this.avatarRoot, AVATAR_ASSETS_DIR_NAME);
  }

  ensureBaseDirs(): void {
    [
      this.rootDir,
      this.dailyLogRoot,
      this.consolidationRoot,
      this.outputsRoot,
      this.indexesRoot,
      this.workflowRunsRoot,
      this.avatarRoot,
      this.avatarVersionsRoot,
      this.avatarAssetsRoot,
      this.storage.join(this.indexesRoot, 'events'),
      this.storage.join(this.indexesRoot, 'inverted'),
      this.storage.join(this.indexesRoot, 'source'),
      this.storage.join(this.indexesRoot, 'domain'),
      this.storage.join(this.indexesRoot, 'entity'),
      this.storage.join(this.indexesRoot, 'temporal'),
      this.storage.join(this.indexesRoot, 'profile'),
      this.storage.join(this.indexesRoot, 'workflow-scene'),
      this.collectionGroupsRoot
    ].forEach((path: string) => {
      this.storage.ensureDir(path);
    });
  }

  outputMarkdownPath(month: string, fileName: string): string {
    return this.storage.join(this.outputsRoot, month, fileName);
  }

  outputStatePath(month: string, fileName: string): string {
    return this.outputMarkdownPath(month, fileName) + '.state.json';
  }

  eventPartitionPath(month: string): string {
    return this.storage.join(this.indexesRoot, 'events', month + '.json');
  }

  temporalPath(month: string): string {
    return this.storage.join(this.indexesRoot, 'temporal', month + '.json');
  }

  collectionGroupsPath(tabId: string): string {
    return this.storage.join(this.collectionGroupsRoot, tabId + '.json');
  }

  homeRecommendationsPath(): string {
    return this.storage.join(this.indexesRoot, HOME_RECOMMENDATIONS_FILE_NAME);
  }

  relativeToDataManager(path: string): string {
    return this.storage.relativePath(this.rootDir, path);
  }

  fromDataManagerRelative(relativePath: string): string {
    return this.storage.join(this.rootDir, relativePath);
  }
}
