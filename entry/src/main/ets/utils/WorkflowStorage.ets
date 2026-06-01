import { JSON as ArkJSON, util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { WorkflowDefinition, WorkflowFileStats, WorkflowManagedFile, WorkflowTask, WorkflowTaskIndex } from './WorkflowTypes';

const WORKFLOW_DIR = 'workflows';
const CONFIG_DIR = 'configs';
const RUN_DIR = 'runs';
const DAILY_LOG_DIR = 'daily-log';
const TASK_INDEX_FILE = 'task-index.json';

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

  static validateWorkflowJson(rawJson: string): WorkflowDefinition {
    let parsed = ArkJSON.parse(rawJson) as WorkflowDefinition;
    if (!parsed.steps || parsed.steps.length === 0) {
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
        let defaults = WorkflowStorage.createDefaultTasks(filesDir);
        WorkflowStorage.saveTasks(filesDir, defaults);
        return defaults;
      }
      let parsed = ArkJSON.parse(WorkflowStorage.readText(path)) as WorkflowTaskIndex;
      return parsed.tasks || [];
    } catch (e) {
      let defaults = WorkflowStorage.createDefaultTasks(filesDir);
      WorkflowStorage.saveTasks(filesDir, defaults);
      return defaults;
    }
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
    WorkflowStorage.writeText(WorkflowStorage.configDir(filesDir) + '/' + task.configFileName, task.workflowJson);
  }

  static upsertTask(filesDir: string, task: WorkflowTask): WorkflowTask[] {
    let tasks = WorkflowStorage.loadTasks(filesDir);
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
    return tasks;
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

  static createTaskFromJson(filesDir: string, sceneId: number, rawJson: string, existingId?: string): WorkflowTask {
    let workflow = WorkflowStorage.validateWorkflowJson(rawJson);
    let metadata = workflow.metadata;
    let title = metadata && metadata.description ? metadata.description : '自定义 Workflow';
    let source = metadata && metadata.name ? metadata.name : 'workflow';
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
    return 'Chat';
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
    return '#FF9347';
  }

  static createDefaultTasks(filesDir: string): WorkflowTask[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return [
      WorkflowStorage.createTaskFromJson(filesDir, 0, WorkflowStorage.defaultAlipayWorkflow(), 'default_alipay_bill'),
      WorkflowStorage.createTaskFromJson(filesDir, 3, WorkflowStorage.defaultWeixinWorkflow(), 'default_weixin_chat')
    ];
  }

  static defaultWorkflowForScene(sceneId: number): string {
    if (sceneId === 3) {
      return WorkflowStorage.defaultWeixinWorkflow();
    }
    return WorkflowStorage.defaultAlipayWorkflow();
  }

  static defaultAlipayWorkflow(): string {
    return '{\n' +
      '  "metadata": {\n' +
      '    "name": "basic-gui-task",\n' +
      '    "description": "查看支付宝上的用户账单信息"\n' +
      '  },\n' +
      '  "defaults": {\n' +
      '    "device": "Harmony",\n' +
      '    "use_qwen3": true,\n' +
      '    "use_e2e": true,\n' +
      '    "use_experience": false,\n' +
      '    "accept_planner_changes": false\n' +
      '  },\n' +
      '  "steps": [\n' +
      '    { "id": 1, "type": "gui_task", "task_description": "打开支付宝", "on_error": "stop" },\n' +
      '    { "id": 2, "type": "gui_task", "task_description": "点击我的，进入账单页面，查看账单信息", "on_error": "stop" },\n' +
      '    { "id": 3, "type": "gui_action", "action": "screenshot", "file_name": "alipay_bill.jpg" },\n' +
      '    {\n' +
      '      "id": 4,\n' +
      '      "type": "tool",\n' +
      '      "tool_name": "vlm_qa",\n' +
      '      "inputs": {\n' +
      '        "mode": "summary",\n' +
      '        "image": "${steps.3.output.image_path}",\n' +
      '        "question": "帮我用一段话简要总结当前页面上的支付宝账单信息（不要使用markdown格式，也不要分点，尽量按照账单出现顺序描述每一条记录的类型、对象、金额和时间）"\n' +
      '      }\n' +
      '    }\n' +
      '  ]\n' +
      '}';
  }

  static defaultWeixinWorkflow(): string {
    return '{\n' +
      '  "metadata": {\n' +
      '    "name": "basic-gui-task",\n' +
      '    "description": "收集指定微信用户近3页的聊天记录"\n' +
      '  },\n' +
      '  "defaults": {\n' +
      '    "device": "Harmony",\n' +
      '    "use_qwen3": true,\n' +
      '    "use_e2e": true,\n' +
      '    "use_experience": false,\n' +
      '    "accept_planner_changes": false\n' +
      '  },\n' +
      '  "context": { "contact_name": "小赵" },\n' +
      '  "steps": [\n' +
      '    { "id": 1, "type": "gui_task", "task_description": "打开微信", "on_error": "stop" },\n' +
      '    { "id": 2, "type": "gui_task", "task_description": "搜索${context.contact_name}，进入聊天界面", "on_error": "stop" },\n' +
      '    {\n' +
      '      "id": 3,\n' +
      '      "type": "loop",\n' +
      '      "times": 3,\n' +
      '      "steps": [\n' +
      '        { "id": 1, "type": "gui_action", "action": "screenshot", "file_name": "chat_${loop.index}.jpg" },\n' +
      '        {\n' +
      '          "id": 2,\n' +
      '          "type": "tool",\n' +
      '          "tool_name": "vlm_qa",\n' +
      '          "inputs": {\n' +
      '            "mode": "summary",\n' +
      '            "image": "${steps.1.output.image_path}",\n' +
      '            "question": "帮我用一段话简要总结当前界面聊天记录的内容（不要使用markdown格式，也不要分点），这是第${loop.index}次截图。"\n' +
      '          }\n' +
      '        },\n' +
      '        {\n' +
      '          "id": 3,\n' +
      '          "type": "if",\n' +
      '          "condition": { "left": "${loop.last}", "operator": "==", "right": false },\n' +
      '          "then_steps": [\n' +
      '            { "id": 1, "type": "gui_action", "action": "swipe_with_coords", "start_x": 540, "start_y": 800, "end_x": 540, "end_y": 2100 },\n' +
      '            { "id": 2, "type": "gui_action", "action": "sleep", "seconds": 1.0 }\n' +
      '          ],\n' +
      '          "else_steps": []\n' +
      '        }\n' +
      '      ]\n' +
      '    }\n' +
      '  ]\n' +
      '}';
  }

  static listConfigFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.listManagedFiles(WorkflowStorage.configDir(filesDir), '');
  }

  static listDailyLogFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.listManagedFiles(WorkflowStorage.dailyLogDir(filesDir), '');
  }

  static listRunFiles(filesDir: string): WorkflowManagedFile[] {
    WorkflowStorage.ensureWorkspace(filesDir);
    return WorkflowStorage.listManagedFiles(WorkflowStorage.runsDir(filesDir), '');
  }

  private static listManagedFiles(path: string, relativeName: string): WorkflowManagedFile[] {
    try {
      let children = fs.listFileSync(path);
      let all: WorkflowManagedFile[] = [];
      for (let i = 0; i < children.length; i++) {
        let childName = relativeName.length > 0 ? relativeName + '/' + children[i] : children[i];
        all = all.concat(WorkflowStorage.listManagedFiles(path + '/' + children[i], childName));
      }
      all.sort((left: WorkflowManagedFile, right: WorkflowManagedFile) => left.name > right.name ? 1 : -1);
      return all;
    } catch (e) {
      try {
        if (fs.accessSync(path)) {
          let stat = fs.statSync(path);
          let fileItem: WorkflowManagedFile = {
            name: relativeName.length > 0 ? relativeName : path,
            path: path,
            size: stat.size
          };
          return [fileItem];
        }
      } catch (err) {
      }
    }
    return [];
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
      runCount: WorkflowStorage.countFiles(WorkflowStorage.runsDir(filesDir)),
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

  static deleteConfigs(filesDir: string): number {
    let deleted = WorkflowStorage.deletePathRecursively(WorkflowStorage.configDir(filesDir));
    WorkflowStorage.ensureDirectory(WorkflowStorage.configDir(filesDir));
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
