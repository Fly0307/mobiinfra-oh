import { JSON as ArkJSON, util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import {
  WorkflowCondition,
  WorkflowDefaults,
  WorkflowDefinition,
  WorkflowFileStats,
  WorkflowJsonMap,
  WorkflowJsonValue,
  WorkflowManagedFile,
  WorkflowStep,
  WorkflowTask,
  WorkflowTaskIndex
} from './WorkflowTypes';

const WORKFLOW_DIR = 'workflows';
const CONFIG_DIR = 'configs';
const RUN_DIR = 'runs';
const DAILY_LOG_DIR = 'daily-log';
const TASK_INDEX_FILE = 'task-index.json';
const DELETED_DEFAULT_TASKS_FILE = 'deleted-default-tasks.json';

interface VlmJsonSchemaField {
  type: string;
  description: string;
}

interface WeixinTodayJsonSchema {
  summary: VlmJsonSchemaField;
  contains_today_chat: VlmJsonSchemaField;
}

interface DeletedDefaultTaskIndex {
  ids: string[];
}

function nowText(): string {
  return new Date().toLocaleString();
}

export class WorkflowStorage {
  static rootDir(filesDir: string): string {
    return filesDir + '/' + WORKFLOW_DIR;
  }

  static configDir(filesDir: string): string {
    return WorkflowStorage.rootDir(filesDir) + '/' + CONFIG_DIR;
  }

  static runsDir(filesDir: string): string {
    return WorkflowStorage.rootDir(filesDir) + '/' + RUN_DIR;
  }

  static dailyLogDir(filesDir: string): string {
    return WorkflowStorage.rootDir(filesDir) + '/' + DAILY_LOG_DIR;
  }

  static indexPath(filesDir: string): string {
    return WorkflowStorage.rootDir(filesDir) + '/' + TASK_INDEX_FILE;
  }

  static configPath(filesDir: string, configFileName: string): string {
    return WorkflowStorage.configDir(filesDir) + '/' + configFileName;
  }

  static deletedDefaultsPath(filesDir: string): string {
    return WorkflowStorage.rootDir(filesDir) + '/' + DELETED_DEFAULT_TASKS_FILE;
  }

  static ensureDirectory(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path);
      }
    } catch (e) {
      try {
        fs.mkdirSync(path);
      } catch (err) {
      }
    }
  }

  static ensureWorkspace(filesDir: string): void {
    WorkflowStorage.ensureDirectory(WorkflowStorage.rootDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.configDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.runsDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.dailyLogDir(filesDir));
  }

  static readText(path: string): string {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      let textDecoder = util.TextDecoder.create('utf-8');
      return textDecoder.decodeWithStream(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  static writeText(path: string, content: string): void {
    let byteStr = util.TextEncoder.create('utf-8').encodeInto(content);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, byteStr.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  private static fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static readBytes(path: string): ArrayBuffer {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return buf;
    } finally {
      fs.closeSync(file);
    }
  }

  static writeBytes(path: string, data: ArrayBuffer): void {
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
  }

  static writeBase64Image(path: string, imageBase64: string): void {
    let helper = new util.Base64Helper();
    let imageBytes = helper.decodeSync(WorkflowStorage.stripImageDataUri(imageBase64));
    WorkflowStorage.writeBytes(path, imageBytes.buffer as ArrayBuffer);
  }

  static readImageAsBase64(path: string): string {
    let helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(WorkflowStorage.readBytes(path)));
  }

  static workflowRunRelativePath(filesDir: string, path: string): string {
    let root = filesDir.replace(/\\/g, '/').replace(/\/+$/g, '');
    let normalized = path.replace(/\\/g, '/');
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    if (normalized.startsWith('workflows/')) {
      return normalized;
    }
    let workflowRoot = root + '/' + WORKFLOW_DIR + '/';
    if (normalized.startsWith(workflowRoot)) {
      return WORKFLOW_DIR + '/' + normalized.substring(workflowRoot.length);
    }
    let marker = '/' + WORKFLOW_DIR + '/';
    let markerIndex = normalized.indexOf(marker);
    if (markerIndex >= 0) {
      return WORKFLOW_DIR + '/' + normalized.substring(markerIndex + marker.length);
    }
    return normalized;
  }

  static workflowImageInputKind(value: string): string {
    let text = value.trim();
    if (text.length === 0) {
      return 'empty';
    }
    if (text.startsWith('data:image/') && text.indexOf('base64,') >= 0) {
      return 'data_uri';
    }
    if (WorkflowStorage.looksLikeBase64Image(text)) {
      return 'base64';
    }
    let normalized = text.replace(/\\/g, '/');
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    if (normalized.startsWith('/') || normalized.startsWith('workflows/') || normalized.startsWith('runs/') ||
      /\.(jpg|jpeg|png|webp|gif)$/i.test(normalized)) {
      return 'path';
    }
    return 'text';
  }

  static resolveWorkflowImageInputAsBase64(filesDir: string, value: string): string {
    let kind = WorkflowStorage.workflowImageInputKind(value);
    if (kind === 'empty') {
      return '';
    }
    if (kind === 'data_uri') {
      return WorkflowStorage.stripImageDataUri(value);
    }
    if (kind === 'base64') {
      return value.replace(/\s+/g, '');
    }
    if (kind === 'path') {
      return WorkflowStorage.readImageAsBase64(WorkflowStorage.workflowAbsolutePath(filesDir, value));
    }
    return value;
  }

  private static workflowAbsolutePath(filesDir: string, path: string): string {
    let root = filesDir.replace(/\\/g, '/').replace(/\/+$/g, '');
    let normalized = path.trim().replace(/\\/g, '/');
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    if (normalized.startsWith('/')) {
      return normalized;
    }
    if (normalized.startsWith('workflows/')) {
      return root + '/' + normalized;
    }
    if (normalized.startsWith('runs/')) {
      return WorkflowStorage.rootDir(root) + '/' + normalized;
    }
    return root + '/' + normalized;
  }

  private static stripImageDataUri(value: string): string {
    let text = value.trim();
    let marker = 'base64,';
    let markerIndex = text.indexOf(marker);
    if (text.startsWith('data:image/') && markerIndex >= 0) {
      return text.substring(markerIndex + marker.length).replace(/\s+/g, '');
    }
    return text.replace(/\s+/g, '');
  }

  private static looksLikeBase64Image(value: string): boolean {
    let text = value.replace(/\s+/g, '');
    return text.startsWith('/9j/') || text.startsWith('iVBORw0KGgo') ||
      text.startsWith('R0lGOD') || text.startsWith('UklGR');
  }

  static validateWorkflowJson(rawJson: string, requireSteps: boolean = true): WorkflowDefinition {
    let parsed = ArkJSON.parse(rawJson) as WorkflowDefinition;
    if (!parsed.steps) {
      throw new Error('workflow.steps 不能为空');
    }
    if (requireSteps && parsed.steps.length === 0) {
      throw new Error('workflow.steps 不能为空');
    }
    let seen: Record<string, boolean> = {};
    for (let i = 0; i < parsed.steps.length; i++) {
      let step = parsed.steps[i];
      if (step.id === undefined || step.id === null) {
        throw new Error('workflow step 缺少 id');
      }
      if (!step.type || step.type.length === 0) {
        throw new Error('workflow step 缺少 type');
      }
      let id = String(step.id);
      if (seen[id]) {
        throw new Error('重复的 workflow step id: ' + id);
      }
      seen[id] = true;
      if (!WorkflowStorage.isSupportedStepType(step.type)) {
        throw new Error('暂不支持的 step type: ' + step.type);
      }
    }
    return parsed;
  }

  static isSupportedStepType(stepType: string): boolean {
    return stepType === 'gui_task' || stepType === 'gui_action' || stepType === 'tool' ||
      stepType === 'loop' || stepType === 'if';
  }

  static loadTasks(filesDir: string): WorkflowTask[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    let path = WorkflowStorage.indexPath(filesDir);
    try {
      if (!fs.accessSync(path)) {
        let recovered = WorkflowStorage.recoverTasksFromConfigFiles(filesDir);
        if (recovered.length > 0) {
          let syncedRecovered = WorkflowStorage.syncCodeDefinedDefaultTasks(filesDir, recovered);
          WorkflowStorage.saveTasks(filesDir, syncedRecovered);
          return syncedRecovered;
        }
        let defaults = WorkflowStorage.createDefaultTasks(filesDir);
        WorkflowStorage.saveTasks(filesDir, defaults);
        return defaults;
      }
      let parsed = ArkJSON.parse(WorkflowStorage.readText(path)) as WorkflowTaskIndex;
      let tasks = parsed.tasks || [];
      let syncedTasks = WorkflowStorage.syncTasksFromConfigFiles(filesDir,
        WorkflowStorage.syncCodeDefinedDefaultTasks(filesDir, tasks));
      if (!WorkflowStorage.areTaskListsEqual(tasks, syncedTasks)) {
        WorkflowStorage.saveTasks(filesDir, syncedTasks);
      }
      return syncedTasks;
    } catch (e) {
      WorkflowStorage.backupBrokenTaskIndex(filesDir);
      let recovered = WorkflowStorage.recoverTasksFromConfigFiles(filesDir);
      if (recovered.length > 0) {
        let syncedRecovered = WorkflowStorage.syncCodeDefinedDefaultTasks(filesDir, recovered);
        WorkflowStorage.saveTasks(filesDir, syncedRecovered);
        return syncedRecovered;
      }
      return WorkflowStorage.createDefaultTasks(filesDir);
    }
  }

  private static syncCodeDefinedDefaultTasks(filesDir: string, tasks: WorkflowTask[]): WorkflowTask[] {
    let defaults = WorkflowStorage.createDefaultTasks(filesDir);
    let deletedDefaults = WorkflowStorage.readDeletedDefaultTaskSet(filesDir);
    let defaultById: Record<string, WorkflowTask> = {};
    for (let i = 0; i < defaults.length; i++) {
      defaultById[defaults[i].id] = defaults[i];
    }

    let nextTasks: WorkflowTask[] = [];
    let storedDefaultIds: Record<string, boolean> = {};
    for (let i = 0; i < tasks.length; i++) {
      let task = tasks[i];
      let defaultTask = defaultById[task.id];
      if (defaultTask) {
        storedDefaultIds[task.id] = true;
        nextTasks.push(WorkflowStorage.mergeStoredStateIntoDefaultTask(defaultTask, task));
      } else if (WorkflowStorage.isCodeDefinedDefaultTaskId(task.id)) {
        continue;
      } else {
        nextTasks.push(task);
      }
    }
    for (let i = 0; i < defaults.length; i++) {
      let defaultId = defaults[i].id;
      if (!storedDefaultIds[defaultId] && !deletedDefaults[defaultId]) {
        nextTasks.push(defaults[i]);
      }
    }
    return nextTasks;
  }

  private static syncTasksFromConfigFiles(filesDir: string, tasks: WorkflowTask[]): WorkflowTask[] {
    let synced: WorkflowTask[] = [];
    for (let i = 0; i < tasks.length; i++) {
      synced.push(WorkflowStorage.taskWithLatestValidConfig(filesDir, tasks[i]));
    }
    return synced;
  }

  private static taskWithLatestValidConfig(filesDir: string, task: WorkflowTask): WorkflowTask {
    if (WorkflowStorage.isCodeDefinedDefaultTaskId(task.id) && task.isUserModified !== true) {
      return task;
    }
    if (task.configFileName.length === 0) {
      return task;
    }
    try {
      let rawJson = WorkflowStorage.readText(WorkflowStorage.configPath(filesDir, task.configFileName));
      let workflow = WorkflowStorage.validateWorkflowJson(rawJson, false);
      let title = WorkflowStorage.titleForWorkflow(workflow);
      let source = WorkflowStorage.sourceForWorkflow(workflow);
      if (rawJson === task.workflowJson && title === task.title && source === task.source) {
        return task;
      }
      return {
        id: task.id,
        sceneId: task.sceneId,
        icon: task.icon,
        iconColor: task.iconColor,
        title: title,
        source: source,
        enabled: task.enabled,
        configFileName: task.configFileName,
        workflowJson: rawJson,
        lastStatus: task.lastStatus,
        lastRun: task.lastRun,
        lastMessage: task.lastMessage,
        isUserModified: task.isUserModified
      };
    } catch (e) {
      return task;
    }
  }

  static readTaskWorkflowJson(filesDir: string, task: WorkflowTask): string {
    if (WorkflowStorage.isCodeDefinedDefaultTaskId(task.id) && task.isUserModified !== true) {
      return task.workflowJson;
    }
    if (task.configFileName.length > 0) {
      try {
        return WorkflowStorage.readText(WorkflowStorage.configPath(filesDir, task.configFileName));
      } catch (e) {
      }
    }
    return task.workflowJson;
  }

  private static backupBrokenTaskIndex(filesDir: string): void {
    let path = WorkflowStorage.indexPath(filesDir);
    try {
      if (fs.accessSync(path)) {
        WorkflowStorage.writeText(path + '.broken.' + String(new Date().getTime()), WorkflowStorage.readText(path));
      }
    } catch (e) {
    }
  }

  private static recoverTasksFromConfigFiles(filesDir: string): WorkflowTask[] {
    let files = WorkflowStorage.listConfigFiles(filesDir);
    let recovered: WorkflowTask[] = [];
    for (let i = 0; i < files.length; i++) {
      try {
        let rawJson = WorkflowStorage.readText(files[i].path);
        let taskId = WorkflowStorage.taskIdFromConfigName(files[i].name);
        let defaultTask = WorkflowStorage.findDefaultTask(filesDir, taskId);
        let sceneId = defaultTask ? defaultTask.sceneId : 0;
        let task = WorkflowStorage.createTaskFromJson(filesDir, sceneId, rawJson, taskId);
        task.configFileName = files[i].name;
        if (defaultTask) {
          task = WorkflowStorage.mergeStoredStateIntoDefaultTask(defaultTask, task);
        }
        recovered.push(task);
      } catch (e) {
      }
    }
    return recovered;
  }

  private static taskIdFromConfigName(configName: string): string {
    let name = configName;
    let slash = name.lastIndexOf('/');
    if (slash >= 0 && slash < name.length - 1) {
      name = name.substring(slash + 1);
    }
    if (name.endsWith('.json')) {
      return name.substring(0, name.length - 5);
    }
    return name;
  }

  private static readDeletedDefaultTaskSet(filesDir: string): Record<string, boolean> {
    let deleted: Record<string, boolean> = {};
    try {
      let parsed = ArkJSON.parse(WorkflowStorage.readText(WorkflowStorage.deletedDefaultsPath(filesDir))) as DeletedDefaultTaskIndex;
      let ids = parsed.ids || [];
      for (let i = 0; i < ids.length; i++) {
        deleted[ids[i]] = true;
      }
    } catch (e) {
    }
    return deleted;
  }

  private static writeDeletedDefaultTaskSet(filesDir: string, deleted: Record<string, boolean>): void {
    let ids = Object.keys(deleted);
    let index: DeletedDefaultTaskIndex = {
      ids: ids
    };
    WorkflowStorage.writeText(WorkflowStorage.deletedDefaultsPath(filesDir), ArkJSON.stringify(index, null, 2));
  }

  private static markDefaultTaskDeleted(filesDir: string, taskId: string): void {
    if (!WorkflowStorage.isCodeDefinedDefaultTaskId(taskId)) {
      return;
    }
    let deleted = WorkflowStorage.readDeletedDefaultTaskSet(filesDir);
    deleted[taskId] = true;
    WorkflowStorage.writeDeletedDefaultTaskSet(filesDir, deleted);
  }

  private static unmarkDefaultTaskDeleted(filesDir: string, taskId: string): void {
    if (!WorkflowStorage.isCodeDefinedDefaultTaskId(taskId)) {
      return;
    }
    let deleted = WorkflowStorage.readDeletedDefaultTaskSet(filesDir);
    if (!deleted[taskId]) {
      return;
    }
    let nextDeleted: Record<string, boolean> = {};
    let ids = Object.keys(deleted);
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== taskId) {
        nextDeleted[ids[i]] = true;
      }
    }
    WorkflowStorage.writeDeletedDefaultTaskSet(filesDir, nextDeleted);
  }

  private static clearDeletedDefaultTaskSet(filesDir: string): void {
    try {
      fs.unlinkSync(WorkflowStorage.deletedDefaultsPath(filesDir));
    } catch (e) {
    }
  }

  private static mergeStoredStateIntoDefaultTask(defaultTask: WorkflowTask, storedTask: WorkflowTask): WorkflowTask {
    let sceneId = storedTask.sceneId >= 0 ? storedTask.sceneId : defaultTask.sceneId;
    let userModified = storedTask.isUserModified === true;
    return {
      id: defaultTask.id,
      sceneId: sceneId,
      icon: WorkflowStorage.nonEmptyOrDefault(storedTask.icon, WorkflowStorage.iconForScene(sceneId)),
      iconColor: WorkflowStorage.nonEmptyOrDefault(storedTask.iconColor, WorkflowStorage.colorForScene(sceneId)),
      title: WorkflowStorage.nonEmptyOrDefault(storedTask.title, defaultTask.title),
      source: WorkflowStorage.nonEmptyOrDefault(storedTask.source, defaultTask.source),
      enabled: storedTask.enabled === false ? false : storedTask.enabled === true ? true : defaultTask.enabled,
      configFileName: WorkflowStorage.nonEmptyOrDefault(storedTask.configFileName, defaultTask.configFileName),
      workflowJson: userModified ? WorkflowStorage.nonEmptyOrDefault(storedTask.workflowJson, defaultTask.workflowJson) :
        defaultTask.workflowJson,
      lastStatus: WorkflowStorage.nonEmptyOrDefault(storedTask.lastStatus, defaultTask.lastStatus),
      lastRun: WorkflowStorage.nonEmptyOrDefault(storedTask.lastRun, defaultTask.lastRun),
      lastMessage: WorkflowStorage.nonEmptyOrDefault(storedTask.lastMessage, defaultTask.lastMessage),
      isUserModified: userModified
    };
  }

  static mergeCodeDefinedDefaultTaskForTest(defaultTask: WorkflowTask, storedTask: WorkflowTask): WorkflowTask {
    return WorkflowStorage.mergeStoredStateIntoDefaultTask(defaultTask, storedTask);
  }

  private static findDefaultTask(filesDir: string, taskId: string): WorkflowTask | null {
    let defaults = WorkflowStorage.createDefaultTasks(filesDir);
    for (let i = 0; i < defaults.length; i++) {
      if (defaults[i].id === taskId) {
        return defaults[i];
      }
    }
    return null;
  }

  private static areTaskListsEqual(left: WorkflowTask[], right: WorkflowTask[]): boolean {
    return ArkJSON.stringify(left) === ArkJSON.stringify(right);
  }

  private static isCodeDefinedDefaultTaskId(taskId: string): boolean {
    return taskId.startsWith('default_');
  }

  private static nonEmptyOrDefault(value: string, fallback: string): string {
    if (value && value.length > 0) {
      return value;
    }
    return fallback;
  }

  static saveTasks(filesDir: string, tasks: WorkflowTask[]): void {
    WorkflowStorage.ensureWorkspace(filesDir);
    for (let i = 0; i < tasks.length; i++) {
      WorkflowStorage.writeConfig(filesDir, tasks[i]);
    }
    let index: WorkflowTaskIndex = {
      version: 1,
      tasks: tasks
    };
    WorkflowStorage.writeText(WorkflowStorage.indexPath(filesDir), ArkJSON.stringify(index, null, 2));
  }

  static writeConfig(filesDir: string, task: WorkflowTask): void {
    WorkflowStorage.ensureWorkspace(filesDir);
    WorkflowStorage.writeText(WorkflowStorage.configPath(filesDir, task.configFileName), task.workflowJson);
  }

  static upsertTask(filesDir: string, task: WorkflowTask): WorkflowTask[] {
    let tasks = WorkflowStorage.loadTasks(filesDir);
    let defaultTask = WorkflowStorage.findDefaultTask(filesDir, task.id);
    if (defaultTask) {
      WorkflowStorage.unmarkDefaultTaskDeleted(filesDir, task.id);
      if (task.isUserModified !== true && task.workflowJson !== defaultTask.workflowJson) {
        task.isUserModified = true;
      }
      task = WorkflowStorage.mergeStoredStateIntoDefaultTask(defaultTask, task);
    }
    let found = false;
    for (let i = 0; i < tasks.length; i++) {
      if (tasks[i].id === task.id) {
        tasks[i] = task;
        found = true;
        break;
      }
    }
    if (!found) {
      tasks.push(task);
    }
    WorkflowStorage.saveTasks(filesDir, tasks);
    return WorkflowStorage.loadTasks(filesDir);
  }

  static deleteTask(filesDir: string, taskId: string): WorkflowTask[] {
    let tasks = WorkflowStorage.loadTasks(filesDir);
    let nextTasks: WorkflowTask[] = [];
    let configFileName = '';
    for (let i = 0; i < tasks.length; i++) {
      if (tasks[i].id === taskId) {
        configFileName = tasks[i].configFileName;
      } else {
        nextTasks.push(tasks[i]);
      }
    }
    WorkflowStorage.markDefaultTaskDeleted(filesDir, taskId);
    WorkflowStorage.saveTasks(filesDir, nextTasks);
    if (configFileName.length > 0) {
      try {
        fs.unlinkSync(WorkflowStorage.configPath(filesDir, configFileName));
      } catch (e) {
      }
    }
    return nextTasks;
  }

  static updateTaskRun(filesDir: string, taskId: string, status: string, message: string): void {
    let tasks = WorkflowStorage.loadTasks(filesDir);
    for (let i = 0; i < tasks.length; i++) {
      if (tasks[i].id === taskId) {
        tasks[i].lastStatus = status;
        tasks[i].lastRun = nowText();
        tasks[i].lastMessage = message;
        break;
      }
    }
    WorkflowStorage.saveTasks(filesDir, tasks);
  }

  private static titleForWorkflow(workflow: WorkflowDefinition): string {
    let metadata = workflow.metadata;
    return metadata && metadata.description ? metadata.description : '自定义 Workflow';
  }

  private static sourceForWorkflow(workflow: WorkflowDefinition): string {
    let metadata = workflow.metadata;
    return metadata && metadata.name ? metadata.name : 'workflow';
  }

  private static copyTitleBase(title: string): string {
    let current = title;
    while (true) {
      let stripped = WorkflowStorage.stripCopySuffix(current);
      if (stripped === current) {
        break;
      }
      current = stripped;
    }
    return current.length > 0 ? current : '自定义 Workflow';
  }

  private static stripCopySuffix(title: string): string {
    let marker = ' 复制';
    let markerIndex = title.lastIndexOf(marker);
    if (markerIndex < 0) {
      return title;
    }
    let suffix = title.substring(markerIndex + marker.length);
    if (suffix.length === 0) {
      return title.substring(0, markerIndex);
    }
    if (!suffix.startsWith(' ')) {
      return title;
    }
    let numberText = suffix.substring(1);
    if (numberText.length === 0) {
      return title;
    }
    for (let i = 0; i < numberText.length; i++) {
      let code = numberText.charCodeAt(i);
      if (code < 48 || code > 57) {
        return title;
      }
    }
    return title.substring(0, markerIndex);
  }

  private static uniqueCopyTitle(tasks: WorkflowTask[], title: string): string {
    let existing: Record<string, boolean> = {};
    for (let i = 0; i < tasks.length; i++) {
      existing[tasks[i].title] = true;
    }
    let base = WorkflowStorage.copyTitleBase(title);
    let candidate = base + ' 复制';
    if (!existing[candidate]) {
      return candidate;
    }
    let index = 2;
    while (existing[base + ' 复制 ' + index]) {
      index++;
    }
    return base + ' 复制 ' + index;
  }

  private static uniqueTaskId(filesDir: string, tasks: WorkflowTask[]): string {
    let existing: Record<string, boolean> = {};
    for (let i = 0; i < tasks.length; i++) {
      existing[tasks[i].id] = true;
    }
    let base = 'task_' + new Date().getTime();
    let candidate = base;
    let index = 1;
    while (existing[candidate] || WorkflowStorage.fileExists(WorkflowStorage.configPath(filesDir, candidate + '.json'))) {
      candidate = base + '_' + index;
      index++;
    }
    return candidate;
  }

  private static workflowJsonWithDescription(rawJson: string, title: string): string {
    let workflow = WorkflowStorage.validateWorkflowJson(rawJson, false);
    if (!workflow.metadata) {
      workflow.metadata = {};
    }
    workflow.metadata.description = title;
    return ArkJSON.stringify(workflow, null, 2);
  }

  static duplicateTask(filesDir: string, taskId: string): WorkflowTask {
    let tasks = WorkflowStorage.loadTasks(filesDir);
    let sourceTask: WorkflowTask | null = null;
    for (let i = 0; i < tasks.length; i++) {
      if (tasks[i].id === taskId) {
        sourceTask = tasks[i];
        break;
      }
    }
    if (!sourceTask) {
      throw new Error('Workflow 已不存在');
    }

    let copyTitle = WorkflowStorage.uniqueCopyTitle(tasks, sourceTask.title);
    let copyJson = WorkflowStorage.workflowJsonWithDescription(
      WorkflowStorage.readTaskWorkflowJson(filesDir, sourceTask),
      copyTitle
    );
    let copyId = WorkflowStorage.uniqueTaskId(filesDir, tasks);
    let copyTask = WorkflowStorage.createTaskFromJson(filesDir, sourceTask.sceneId, copyJson, copyId);
    copyTask.enabled = sourceTask.enabled;
    copyTask.lastStatus = '未运行';
    copyTask.lastRun = '尚未执行';
    copyTask.lastMessage = '复制自“' + sourceTask.title + '”';
    tasks.push(copyTask);
    WorkflowStorage.saveTasks(filesDir, tasks);
    return copyTask;
  }

  static createTaskFromJson(filesDir: string, sceneId: number, rawJson: string, existingId?: string): WorkflowTask {
    let workflow = WorkflowStorage.validateWorkflowJson(rawJson, false);
    let title = WorkflowStorage.titleForWorkflow(workflow);
    let source = WorkflowStorage.sourceForWorkflow(workflow);
    let taskId = existingId && existingId.length > 0 ? existingId : 'task_' + new Date().getTime();
    let configName = taskId + '.json';
    return {
      id: taskId,
      sceneId: sceneId,
      icon: WorkflowStorage.iconForScene(sceneId),
      iconColor: WorkflowStorage.colorForScene(sceneId),
      title: title,
      source: source,
      enabled: true,
      configFileName: configName,
      workflowJson: rawJson,
      lastStatus: '未运行',
      lastRun: '尚未执行',
      lastMessage: '点击运行后开始执行 workflow'
    };
  }

  static iconForScene(sceneId: number): string {
    if (sceneId === 0) {
      return 'Buy';
    }
    if (sceneId === 1) {
      return 'Food';
    }
    if (sceneId === 2) {
      return 'Play';
    }
    if (sceneId === 3) {
      return 'Chat';
    }
    if (sceneId === 4) {
      return 'Life';
    }
    if (sceneId === 6) {
      return 'Trip';
    }
    return 'Social';
  }

  static colorForScene(sceneId: number): string {
    if (sceneId === 0) {
      return '#4B8BFF';
    }
    if (sceneId === 1) {
      return '#39BFA3';
    }
    if (sceneId === 2) {
      return '#8066FF';
    }
    if (sceneId === 3) {
      return '#FF9347';
    }
    if (sceneId === 4) {
      return '#F59E0B';
    }
    if (sceneId === 6) {
      return '#0EA5E9';
    }
    return '#E85D8E';
  }

  static createDefaultTasks(filesDir: string): WorkflowTask[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return [
      WorkflowStorage.createTaskFromJson(filesDir, 0, WorkflowStorage.defaultAlipayWorkflow(), 'default_alipay_bill'),
      WorkflowStorage.createTaskFromJson(filesDir, 1, WorkflowStorage.defaultEleWorkflow(), 'default_ele_order'),
      WorkflowStorage.createTaskFromJson(filesDir, 2, WorkflowStorage.defaultBilibiliWorkflow(), 'default_bilibili_history'),
      WorkflowStorage.createTaskFromJson(filesDir, 2, WorkflowStorage.defaultTencentVideoWorkflow(), 'default_tencent_video_history'),
      WorkflowStorage.createTaskFromJson(filesDir, 3, WorkflowStorage.defaultWeixinWorkflow(), 'default_weixin_chat'),
      WorkflowStorage.createTaskFromJson(filesDir, 3, WorkflowStorage.defaultWeixinTodayWorkflow(), 'default_weixin_today_chat'),
      WorkflowStorage.createTaskFromJson(filesDir, 4, WorkflowStorage.defaultDianpingWorkflow(), 'default_dianping_order'),
      WorkflowStorage.createTaskFromJson(filesDir, 4, WorkflowStorage.defaultMeituanWorkflow(), 'default_meituan_order'),
      WorkflowStorage.createTaskFromJson(filesDir, 5, WorkflowStorage.defaultWeiboWorkflow(), 'default_weibo_hot_search'),
      WorkflowStorage.createTaskFromJson(filesDir, 5, WorkflowStorage.defaultXiaohongshuWorkflow(), 'default_xiaohongshu_history'),
      WorkflowStorage.createTaskFromJson(filesDir, 6, WorkflowStorage.defaultCtripWorkflow(), 'default_ctrip_order')
    ];
  }

  static defaultWorkflowForScene(sceneId: number): string {
    if (sceneId === 1) {
      return WorkflowStorage.defaultEleWorkflow();
    }
    if (sceneId === 2) {
      return WorkflowStorage.defaultBilibiliWorkflow();
    }
    if (sceneId === 3) {
      return WorkflowStorage.defaultWeixinWorkflow();
    }
    if (sceneId === 4) {
      return WorkflowStorage.defaultMeituanWorkflow();
    }
    if (sceneId === 5) {
      return WorkflowStorage.defaultWeiboWorkflow();
    }
    if (sceneId === 6) {
      return WorkflowStorage.defaultCtripWorkflow();
    }
    return WorkflowStorage.defaultAlipayWorkflow();
  }

  private static defaultWorkflowDefaults(): WorkflowDefaults {
    return {
      device: 'Harmony',
      use_qwen3: true,
      use_e2e: true,
      use_experience: false,
      accept_planner_changes: false
    };
  }

  private static basicGuiWorkflow(description: string, steps: WorkflowStep[], context?: WorkflowJsonMap): string {
    let workflow: WorkflowDefinition = {
      metadata: {
        name: 'basic-gui-task',
        description: description
      },
      defaults: WorkflowStorage.defaultWorkflowDefaults(),
      steps: steps
    };
    if (context) {
      workflow.context = context;
    }
    return ArkJSON.stringify(workflow, null, 2);
  }

  private static openAppStep(appName: string): WorkflowStep {
    return { id: 1, type: 'gui_task', task_description: '打开' + appName, on_error: 'stop' };
  }

  private static guiTaskStep(id: number, taskDescription: string): WorkflowStep {
    return { id: id, type: 'gui_task', task_description: taskDescription, on_error: 'stop' };
  }

  private static screenshotStep(id: number, fileName: string): WorkflowStep {
    return { id: id, type: 'gui_action', action: 'screenshot', file_name: fileName };
  }

  private static summaryToolStep(id: number, imageVariable: string, question: string): WorkflowStep {
    return {
      id: id,
      type: 'tool',
      tool_name: 'vlm_qa',
      inputs: {
        mode: 'summary',
        image: imageVariable,
        question: question
      }
    };
  }

  private static condition(left: WorkflowJsonValue, operator: string, right: WorkflowJsonValue): WorkflowCondition {
    return {
      left: left,
      operator: operator,
      right: right
    };
  }

  private static swipeWithCoordsStep(id: number, startX: number, startY: number, endX: number, endY: number): WorkflowStep {
    return {
      id: id,
      type: 'gui_action',
      action: 'swipe_with_coords',
      start_x: startX,
      start_y: startY,
      end_x: endX,
      end_y: endY
    };
  }

  private static sleepStep(id: number, seconds: number): WorkflowStep {
    return {
      id: id,
      type: 'gui_action',
      action: 'sleep',
      seconds: seconds
    };
  }

  private static ifStep(id: number, condition: WorkflowCondition, thenSteps: WorkflowStep[]): WorkflowStep {
    let elseSteps: WorkflowStep[] = [];
    return {
      id: id,
      type: 'if',
      condition: condition,
      then_steps: thenSteps,
      else_steps: elseSteps
    };
  }

  private static loopStep(id: number, steps: WorkflowStep[], times: number): WorkflowStep {
    return {
      id: id,
      type: 'loop',
      times: times,
      steps: steps
    };
  }

  private static loopUntilStep(id: number, steps: WorkflowStep[], maxTimes: number,
    breakIf: WorkflowCondition): WorkflowStep {
    return {
      id: id,
      type: 'loop',
      max_times: maxTimes,
      break_if: breakIf,
      steps: steps
    };
  }

  private static contactNameContext(name: string): WorkflowJsonMap {
    let context: WorkflowJsonMap = {};
    context['contact_name'] = name;
    return context;
  }

  private static weixinTodayJsonSchema(): WeixinTodayJsonSchema {
    let summary: VlmJsonSchemaField = {
      type: 'string',
      description: '对当前截图中可见聊天内容的简要总结'
    };
    let containsTodayChat: VlmJsonSchemaField = {
      type: 'boolean',
      description: '如果当前截图中的聊天记录属于任务执行日期对应的今天则为 true；如果截图中已经出现早于任务执行日期的聊天日期分隔符、明确更早日期内容，或当前可见聊天记录已经不属于任务执行日期，则为 false'
    };
    return {
      summary: summary,
      contains_today_chat: containsTodayChat
    };
  }

  private static weixinTodaySummaryToolStep(): WorkflowStep {
    return {
      id: 2,
      type: 'tool',
      tool_name: 'vlm_qa',
      inputs: {
        mode: 'summary',
        image: '${steps.1.output.image_b64}',
        question: '请分析当前微信聊天界面，这是第${loop.index}次截图。忽略手机状态栏/页面顶部系统时间，不要将其作为聊天消息时间。\n' +
          '请总结当前截图中可见聊天内容，并尽量识别：聊天对象、消息发送人、消息发送绝对时间、消息原文，以及原文中相对时间对应的事件绝对时间。\n' +
          '输出格式：\n' +
          '聊天对象：xxx\n' +
          '- 发送人｜消息发送绝对时间：消息原文（如含相对时间，在原文对应位置补充[事件绝对时间]）\n' +
          '规则：\n' +
          '1. 聊天对象能识别则输出名称；无法识别用“当前聊天对象”，不要编造。\n' +
          '2. 右侧绿色气泡通常为“我”；左侧白色气泡通常为“对方”。若顶部“联系人”名可识别，左侧消息发送人用该名称；不确定用“未知发送人”。\n' +
          '3. 消息发送绝对时间优先依据截图中的聊天日期分隔符和消息时间解析，如“昨天 下午 09:15”“上午 00:00”；结合【任务执行时间】解析“昨天/今天/周几”等日期。\n' +
          '4. 同一时间锚点下方、下一个时间锚点之前的消息，默认继承最近的上方时间锚点。\n' +
          '5. 只有截图中完全没有聊天时间锚点时，才使用【任务执行时间】兜底，并标注“不确定时间”，不要强行编造具体时分。\n' +
          '6. 原文中的“明天、后天、今晚、明早、下午两点、下周一”等事件相对时间，必须以该消息的发送绝对时间为基准解析，并用[]补充；原文无事件时间则不补充。\n' +
          '7. 不输出复杂 JSON；不编造不可见消息；看不清内容用“[无法识别]”。\n' +
          '示例：\n' +
          '任务执行时间：2026年06月09日 星期二 04:42\n' +
          '截图时间锚点：昨天 下午 09:15\n' +
          '消息：明天下午两点前修复新的 bug\n' +
          '最终输出：\n' +
          '- 我｜2026年06月08日 21:15：明天下午两点[2026年06月09日14:00]前修复新的 bug',
        json_schema: WorkflowStorage.weixinTodayJsonSchema() as Object
      }
    };
  }

  static defaultAlipayWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看支付宝上的用户账单信息', [
      WorkflowStorage.openAppStep('支付宝'),
      WorkflowStorage.guiTaskStep(2, '点击我的，进入账单页面，查看当前界面账单信息'),
      WorkflowStorage.screenshotStep(3, 'alipay_bill.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的支付宝账单信息（不要使用markdown格式，也不要分点，尽量按照账单出现顺序描述每一条记录的类型、对象、金额和时间）')
    ]);
  }

  static defaultCtripWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看携程上的用户全部订单', [
      WorkflowStorage.openAppStep('携程旅行'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”，进入待付款界面，切换到“全部”标签，查看当前界面的订单'),
      WorkflowStorage.screenshotStep(3, 'ctrip_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的携程全部订单内容（不要使用markdown格式，也不要分点，尽量按照订单出现顺序描述每一单的出行类型、目的地或酒店/车次/航班、时间、金额和订单状态）')
    ]);
  }

  static defaultBilibiliWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看哔哩哔哩上的用户浏览记录', [
      WorkflowStorage.openAppStep('哔哩哔哩'),
      WorkflowStorage.guiTaskStep(2, '进入个人中心，打开历史记录页面，查看浏览记录'),
      WorkflowStorage.screenshotStep(3, 'bilibili_history.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的哔哩哔哩浏览记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每个视频的标题、分区或观看进度等信息）')
    ]);
  }

  static defaultDianpingWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看大众点评上的用户订单记录', [
      WorkflowStorage.openAppStep('大众点评'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，进入我的订单页面，查看订单记录'),
      WorkflowStorage.screenshotStep(3, 'dianping_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的大众点评订单记录（不要使用markdown格式，也不要分点，尽量按照订单出现顺序描述每一单的店铺、消费内容、金额和订单状态）')
    ]);
  }

  static defaultEleWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看饿了么上的用户订单信息', [
      WorkflowStorage.openAppStep('饿了么'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，点击我的订单，结束任务'),
      WorkflowStorage.screenshotStep(3, 'ele_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的外卖订单信息（不要使用markdown格式，按照第一单，第二单，第三单的顺序描述，包括点了什么，花了多少钱）')
    ]);
  }

  static defaultMeituanWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看美团上的用户订单记录', [
      WorkflowStorage.openAppStep('美团'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，进入全部订单页面，查看订单记录'),
      WorkflowStorage.screenshotStep(3, 'meituan_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的美团订单记录（不要使用markdown格式，也不要分点，尽量按照订单出现顺序描述每一单的商家、下单内容、金额和订单状态）')
    ]);
  }

  static defaultTencentVideoWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看腾讯视频上的用户观看记录', [
      WorkflowStorage.openAppStep('腾讯视频'),
      WorkflowStorage.guiTaskStep(2, '进入个人中心，点击观看历史，查看观看记录'),
      WorkflowStorage.screenshotStep(3, 'tencent_video_history.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的腾讯视频观看记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每个视频的名称、观看进度或更新时间等关键信息）')
    ]);
  }

  static defaultWeiboWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看微博热搜中排名第一的新闻。', [
      WorkflowStorage.openAppStep('微博'),
      WorkflowStorage.guiTaskStep(2, '点击底部的发现按钮，点击更多微博文字即可'),
      WorkflowStorage.guiTaskStep(3, '查看第一条微博热搜，注意不是置顶的那条微博热搜，而是左侧数字是1的那条微博热搜'),
      WorkflowStorage.screenshotStep(4, 'vlm_input.jpg'),
      WorkflowStorage.summaryToolStep(5, '${steps.4.output.image_b64}', '帮我总结当前界面上新闻的内容。')
    ]);
  }

  static defaultWeixinWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('收集指定微信用户近3页的聊天记录', [
      WorkflowStorage.openAppStep('微信'),
      WorkflowStorage.guiTaskStep(2, '搜索${context.contact_name}，进入聊天界面'),
      WorkflowStorage.loopStep(3, [
        WorkflowStorage.screenshotStep(1, 'chat_${loop.index}.jpg'),
        WorkflowStorage.summaryToolStep(2, '${steps.1.output.image_b64}',
          '请分析当前微信聊天界面，这是第${loop.index}次截图。忽略手机状态栏/页面顶部系统时间，不要将其作为聊天消息时间。\n' +
            '请总结当前截图中可见聊天内容，并尽量识别：聊天对象、消息发送人、消息发送绝对时间、消息原文，以及原文中相对时间对应的事件绝对时间。\n' +
            '输出格式：\n' +
            '聊天对象：xxx\n' +
            '- 发送人｜消息发送绝对时间：消息原文（如含相对时间，在原文对应位置补充[事件绝对时间]）\n' +
            '规则：\n' +
            '1. 聊天对象能识别则输出名称；无法识别用“当前聊天对象”，不要编造。\n' +
            '2. 右侧绿色气泡通常为“我”；左侧白色气泡通常为“对方”。若顶部联系人名可识别，左侧消息发送人用该名称；不确定用“未知发送人”。\n' +
            '3. 消息发送绝对时间优先依据截图中的聊天日期分隔符和消息时间解析，如“昨天 下午 09:15”“上午 00:00”；结合【任务执行时间】解析“昨天/今天/周几”等日期。\n' +
            '4. 同一时间锚点下方、下一个时间锚点之前的消息，默认继承最近的上方时间锚点。\n' +
            '5. 只有截图中完全没有聊天时间锚点时，才使用【任务执行时间】兜底，并标注“不确定时间”，不要强行编造具体时分。\n' +
            '6. 原文中的“明天、后天、今晚、明早、下午两点、下周一”等事件相对时间，必须以该消息的发送绝对时间为基准解析，并用[]补充；原文无事件时间则不补充。\n' +
            '7. 不输出复杂 JSON；不编造不可见消息；看不清内容用“[无法识别]”。\n' +
            '示例：\n' +
            '任务执行时间：2026年06月09日 星期二 04:42\n' +
            '截图时间锚点：昨天 下午 09:15\n' +
            '消息：明天下午两点前修复新的 bug\n' +
            '最终输出：\n' +
            '- 我｜2026年06月08日 21:15：明天下午两点[2026年06月09日14:00]前修复新的 bug'),
        WorkflowStorage.ifStep(3, WorkflowStorage.condition('${loop.last}', '==', false), [
          WorkflowStorage.swipeWithCoordsStep(1, 540, 800, 540, 2100),
          WorkflowStorage.sleepStep(2, 1.0)
        ])
      ], 3)
    ], WorkflowStorage.contactNameContext('小赵'));
  }

  static defaultWeixinTodayWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('收集指定微信用户的今天聊天记录', [
      WorkflowStorage.openAppStep('微信'),
      WorkflowStorage.guiTaskStep(2, '搜索${context.contact_name}，进入聊天界面'),
      WorkflowStorage.loopUntilStep(3, [
        WorkflowStorage.screenshotStep(1, 'chat_${loop.index}.jpg'),
        WorkflowStorage.weixinTodaySummaryToolStep(),
        WorkflowStorage.ifStep(3,
          WorkflowStorage.condition('${steps.2.output.structured_output.contains_today_chat}', '!=', false), [
            WorkflowStorage.swipeWithCoordsStep(1, 540, 800, 540, 2100),
            WorkflowStorage.sleepStep(2, 1.0)
          ])
      ], 10, WorkflowStorage.condition('${steps.2.output.structured_output.contains_today_chat}', '==', false))
    ], WorkflowStorage.contactNameContext('小赵'));
  }

  static defaultXiaohongshuWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看小红书上的用户浏览记录', [
      WorkflowStorage.openAppStep('小红书'),
      WorkflowStorage.guiTaskStep(2, '进入个人中心，打开浏览记录页面，查看浏览记录'),
      WorkflowStorage.screenshotStep(3, 'xiaohongshu_history.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_b64}',
        '帮我用一段话简要总结当前页面上的小红书浏览记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每条内容的主题、标题或账号信息）')
    ]);
  }

  static listConfigFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.sortManagedFilesForDisplay(WorkflowStorage.listManagedFiles(WorkflowStorage.configDir(filesDir), ''));
  }

  static listDailyLogFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.sortManagedFilesForDisplay(WorkflowStorage.listManagedFiles(WorkflowStorage.dailyLogDir(filesDir), ''));
  }

  static listRunFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.sortManagedFilesForDisplay(WorkflowStorage.listManagedFiles(WorkflowStorage.runsDir(filesDir), '')
      .filter((file: WorkflowManagedFile): boolean => WorkflowStorage.isRunSummaryFile(file)));
  }

  static sortManagedFilesForDisplay(files: WorkflowManagedFile[]): WorkflowManagedFile[] {
    let sorted: WorkflowManagedFile[] = files.slice();
    sorted.sort((left: WorkflowManagedFile, right: WorkflowManagedFile) => {
      if (left.modifiedTime !== right.modifiedTime) {
        return right.modifiedTime - left.modifiedTime;
      }
      if (left.name === right.name) {
        return 0;
      }
      return left.name > right.name ? 1 : -1;
    });
    return sorted;
  }

  private static listManagedFiles(path: string, relativeName: string): WorkflowManagedFile[] {
    try {
      let children = fs.listFileSync(path);
      let all: WorkflowManagedFile[] = [];
      for (let i = 0; i < children.length; i++) {
        let childName = relativeName.length > 0 ? relativeName + '/' + children[i] : children[i];
        all = all.concat(WorkflowStorage.listManagedFiles(path + '/' + children[i], childName));
      }
      return all;
    } catch (e) {
      try {
        if (fs.accessSync(path)) {
          let stat = fs.statSync(path);
          let fileItem: WorkflowManagedFile = {
            name: relativeName.length > 0 ? relativeName : path,
            path: path,
            size: stat.size,
            modifiedTime: stat.mtime
          };
          return [fileItem];
        }
      } catch (err) {
      }
    }
    return [];
  }

  private static isRunSummaryFile(file: WorkflowManagedFile): boolean {
    return file.name.endsWith('/run_summary.json') || file.name === 'run_summary.json';
  }

  static countFiles(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let total = 0;
      for (let i = 0; i < children.length; i++) {
        total += WorkflowStorage.countFiles(path + '/' + children[i]);
      }
      return total;
    } catch (e) {
      try {
        if (fs.accessSync(path)) {
          return 1;
        }
      } catch (err) {
      }
      return 0;
    }
  }

  static calcPathSize(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let sum = 0;
      for (let i = 0; i < children.length; i++) {
        sum += WorkflowStorage.calcPathSize(path + '/' + children[i]);
      }
      return sum;
    } catch (e) {
      try {
        return fs.statSync(path).size;
      } catch (err) {
      }
      return 0;
    }
  }

  static getStats(filesDir: string): WorkflowFileStats {
    WorkflowStorage.ensureWorkspace(filesDir);
    return {
      configCount: WorkflowStorage.countFiles(WorkflowStorage.configDir(filesDir)),
      dailyLogCount: WorkflowStorage.countFiles(WorkflowStorage.dailyLogDir(filesDir)),
      runCount: WorkflowStorage.listRunFiles(filesDir).length,
      totalBytes: WorkflowStorage.calcPathSize(WorkflowStorage.rootDir(filesDir))
    };
  }

  static deletePathRecursively(path: string): number {
    try {
      let children = fs.listFileSync(path);
      let deleted = 0;
      for (let i = 0; i < children.length; i++) {
        deleted += WorkflowStorage.deletePathRecursively(path + '/' + children[i]);
      }
      fs.rmdirSync(path);
      return deleted + 1;
    } catch (e) {
      try {
        fs.unlinkSync(path);
        return 1;
      } catch (err) {
      }
      return 0;
    }
  }

  static deleteManagedFile(file: WorkflowManagedFile): number {
    return WorkflowStorage.deletePathRecursively(file.path);
  }

  static deleteManagedFiles(files: WorkflowManagedFile[]): number {
    let deleted = 0;
    for (let i = 0; i < files.length; i++) {
      deleted += WorkflowStorage.deleteManagedFile(files[i]);
    }
    return deleted;
  }

  static managedFileDeleteTarget(filesDir: string, category: string, file: WorkflowManagedFile): string {
    if (category === 'run') {
      return WorkflowStorage.runManagedFileDeleteTarget(filesDir, file);
    }
    return file.path;
  }

  static deleteManagedFileForCategory(filesDir: string, category: string, file: WorkflowManagedFile): number {
    if (category === 'config') {
      return WorkflowStorage.deleteConfigManagedFile(filesDir, file);
    }
    let deleteTarget = WorkflowStorage.managedFileDeleteTarget(filesDir, category, file);
    let deleted = WorkflowStorage.deletePathRecursively(deleteTarget);
    if (category === 'daily') {
      deleted += WorkflowStorage.deleteEmptyParentDirectory(WorkflowStorage.dailyLogDir(filesDir), file.path);
    }
    return deleted;
  }

  static deleteManagedFilesForCategory(filesDir: string, category: string, files: WorkflowManagedFile[]): number {
    let deleted = 0;
    for (let i = 0; i < files.length; i++) {
      deleted += WorkflowStorage.deleteManagedFileForCategory(filesDir, category, files[i]);
    }
    return deleted;
  }

  private static runManagedFileDeleteTarget(filesDir: string, file: WorkflowManagedFile): string {
    let runsRoot = WorkflowStorage.normalizePath(WorkflowStorage.runsDir(filesDir));
    let filePath = WorkflowStorage.normalizePath(file.path);
    let parent = WorkflowStorage.parentPath(filePath);
    if (WorkflowStorage.isRunSummaryFile(file) && WorkflowStorage.isNestedPath(parent, runsRoot)) {
      return parent;
    }
    return file.path;
  }

  private static deleteEmptyParentDirectory(categoryRoot: string, filePath: string): number {
    let root = WorkflowStorage.normalizePath(categoryRoot);
    let parent = WorkflowStorage.parentPath(WorkflowStorage.normalizePath(filePath));
    if (!WorkflowStorage.isNestedPath(parent, root)) {
      return 0;
    }
    try {
      let children = fs.listFileSync(parent);
      if (children.length === 0) {
        fs.rmdirSync(parent);
        return 1;
      }
    } catch (e) {
    }
    return 0;
  }

  private static normalizePath(path: string): string {
    let normalized = path.replace(/\\/g, '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private static parentPath(path: string): string {
    let normalized = WorkflowStorage.normalizePath(path);
    let index = normalized.lastIndexOf('/');
    if (index <= 0) {
      return '';
    }
    return normalized.substring(0, index);
  }

  private static isNestedPath(path: string, root: string): boolean {
    let normalizedPath = WorkflowStorage.normalizePath(path);
    let normalizedRoot = WorkflowStorage.normalizePath(root);
    return normalizedPath.length > normalizedRoot.length && normalizedPath.startsWith(normalizedRoot + '/');
  }

  private static taskMatchesConfigFile(filesDir: string, task: WorkflowTask, file: WorkflowManagedFile): boolean {
    return task.configFileName === file.name || WorkflowStorage.configPath(filesDir, task.configFileName) === file.path;
  }

  static deleteConfigManagedFile(filesDir: string, file: WorkflowManagedFile): number {
    let tasks = WorkflowStorage.loadTasks(filesDir);
    for (let i = 0; i < tasks.length; i++) {
      if (WorkflowStorage.taskMatchesConfigFile(filesDir, tasks[i], file)) {
        WorkflowStorage.deleteTask(filesDir, tasks[i].id);
        return 1;
      }
    }
    return WorkflowStorage.deleteManagedFile(file);
  }

  static deleteConfigManagedFiles(filesDir: string, files: WorkflowManagedFile[]): number {
    let deleted = 0;
    for (let i = 0; i < files.length; i++) {
      deleted += WorkflowStorage.deleteConfigManagedFile(filesDir, files[i]);
    }
    return deleted;
  }

  static deleteConfigs(filesDir: string): number {
    let deleted = WorkflowStorage.deletePathRecursively(WorkflowStorage.configDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.configDir(filesDir));
    WorkflowStorage.clearDeletedDefaultTaskSet(filesDir);
    let tasks = WorkflowStorage.createDefaultTasks(filesDir);
    WorkflowStorage.saveTasks(filesDir, tasks);
    return deleted;
  }

  static deleteDailyLogs(filesDir: string): number {
    let deleted = WorkflowStorage.deletePathRecursively(WorkflowStorage.dailyLogDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.dailyLogDir(filesDir));
    return deleted;
  }

  static deleteRunFiles(filesDir: string): number {
    let deleted = WorkflowStorage.deletePathRecursively(WorkflowStorage.runsDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.runsDir(filesDir));
    return deleted;
  }

  static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return bytes + 'B';
    }
    if (bytes < 1048576) {
      return (bytes / 1024).toFixed(1) + 'KB';
    }
    if (bytes < 1073741824) {
      return (bytes / 1048576).toFixed(1) + 'MB';
    }
    return (bytes / 1073741824).toFixed(2) + 'GB';
  }
}
