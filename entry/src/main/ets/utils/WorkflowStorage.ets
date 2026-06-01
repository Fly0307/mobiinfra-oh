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

interface VlmJsonSchemaField {
  type: string;
  description: string;
}

interface WeixinTodayJsonSchema {
  summary: VlmJsonSchemaField;
  contains_today_chat: VlmJsonSchemaField;
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
      let tasks = parsed.tasks || [];
      let mergedTasks = WorkflowStorage.mergeMissingDefaultTasks(filesDir, tasks);
      if (mergedTasks.length !== tasks.length) {
        WorkflowStorage.saveTasks(filesDir, mergedTasks);
      }
      return mergedTasks;
    } catch (e) {
      let defaults = WorkflowStorage.createDefaultTasks(filesDir);
      WorkflowStorage.saveTasks(filesDir, defaults);
      return defaults;
    }
  }

  private static mergeMissingDefaultTasks(filesDir: string, tasks: WorkflowTask[]): WorkflowTask[] {
    let nextTasks = tasks.slice();
    let knownIds: Record<string, boolean> = {};
    for (let i = 0; i < nextTasks.length; i++) {
      knownIds[nextTasks[i].id] = true;
    }

    let defaults = WorkflowStorage.createDefaultTasks(filesDir);
    for (let i = 0; i < defaults.length; i++) {
      if (!knownIds[defaults[i].id]) {
        nextTasks.push(defaults[i]);
      }
    }
    return nextTasks;
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
    if (sceneId === 3) {
      return 'Chat';
    }
    if (sceneId === 4) {
      return 'Life';
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
      WorkflowStorage.createTaskFromJson(filesDir, 5, WorkflowStorage.defaultXiaohongshuWorkflow(), 'default_xiaohongshu_history')
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
      description: '如果当前截图中的聊天记录仍然属于今天则为 true；如果已经出现更早日期的聊天记录则为 false'
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
        image: '${steps.1.output.image_path}',
        question: '请分析当前微信聊天界面。这是第${loop.index}次截图。请总结当前截图中可见的聊天内容，并判断当前截图中的聊天记录是否仍然属于今天；如果已经出现更早日期的聊天记录，则应判定为 false。',
        json_schema: WorkflowStorage.weixinTodayJsonSchema() as Object
      }
    };
  }

  static defaultAlipayWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看支付宝上的用户账单信息', [
      WorkflowStorage.openAppStep('支付宝'),
      WorkflowStorage.guiTaskStep(2, '点击我的，进入账单页面，查看账单信息'),
      WorkflowStorage.screenshotStep(3, 'alipay_bill.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的支付宝账单信息（不要使用markdown格式，也不要分点，尽量按照账单出现顺序描述每一条记录的类型、对象、金额和时间）')
    ]);
  }

  static defaultBilibiliWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看哔哩哔哩上的用户浏览记录', [
      WorkflowStorage.openAppStep('哔哩哔哩'),
      WorkflowStorage.guiTaskStep(2, '进入个人中心，打开历史记录页面，查看浏览记录'),
      WorkflowStorage.screenshotStep(3, 'bilibili_history.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的哔哩哔哩浏览记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每个视频的标题、分区或观看进度等信息）')
    ]);
  }

  static defaultDianpingWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看大众点评上的用户订单记录', [
      WorkflowStorage.openAppStep('大众点评'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，进入我的订单页面，查看订单记录'),
      WorkflowStorage.screenshotStep(3, 'dianping_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的大众点评订单记录（不要使用markdown格式，也不要分点，尽量按照订单出现顺序描述每一单的店铺、消费内容、金额和订单状态）')
    ]);
  }

  static defaultEleWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看饿了么上的用户订单信息', [
      WorkflowStorage.openAppStep('饿了么'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，点击我的订单，查看外卖订单'),
      WorkflowStorage.screenshotStep(3, 'ele_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的外卖订单信息（不要使用markdown格式，按照第一单，第二单，第三单的顺序描述，包括点了什么，花了多少钱）')
    ]);
  }

  static defaultMeituanWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看美团上的用户订单记录', [
      WorkflowStorage.openAppStep('美团'),
      WorkflowStorage.guiTaskStep(2, '点击“我的”图标，进入全部订单页面，查看订单记录'),
      WorkflowStorage.screenshotStep(3, 'meituan_order.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的美团订单记录（不要使用markdown格式，也不要分点，尽量按照订单出现顺序描述每一单的商家、下单内容、金额和订单状态）')
    ]);
  }

  static defaultTencentVideoWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看腾讯视频上的用户观看记录', [
      WorkflowStorage.openAppStep('腾讯视频'),
      WorkflowStorage.guiTaskStep(2, '进入个人中心，点击观看历史，查看观看记录'),
      WorkflowStorage.screenshotStep(3, 'tencent_video_history.jpg'),
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的腾讯视频观看记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每个视频的名称、观看进度或更新时间等关键信息）')
    ]);
  }

  static defaultWeiboWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('查看微博热搜中排名第一的新闻。', [
      WorkflowStorage.openAppStep('微博'),
      WorkflowStorage.guiTaskStep(2, '点击底部的发现按钮，点击更多微博文字即可'),
      WorkflowStorage.guiTaskStep(3, '查看第一条微博热搜，注意不是置顶的那条微博热搜，而是左侧数字是1的那条微博热搜'),
      WorkflowStorage.screenshotStep(4, 'vlm_input.jpg'),
      WorkflowStorage.summaryToolStep(5, '${steps.4.output.image_path}', '帮我总结当前界面上新闻的内容。')
    ]);
  }

  static defaultWeixinWorkflow(): string {
    return WorkflowStorage.basicGuiWorkflow('收集指定微信用户近3页的聊天记录', [
      WorkflowStorage.openAppStep('微信'),
      WorkflowStorage.guiTaskStep(2, '搜索${context.contact_name}，进入聊天界面'),
      WorkflowStorage.loopStep(3, [
        WorkflowStorage.screenshotStep(1, 'chat_${loop.index}.jpg'),
        WorkflowStorage.summaryToolStep(2, '${steps.1.output.image_path}',
          '帮我用一段话简要总结当前界面聊天记录的内容（不要使用markdown格式，也不要分点），这是第${loop.index}次截图。'),
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
          WorkflowStorage.condition('${steps.2.output.structured_output.contains_today_chat}', '==', true), [
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
      WorkflowStorage.summaryToolStep(4, '${steps.3.output.image_path}',
        '帮我用一段话简要总结当前页面上的小红书浏览记录（不要使用markdown格式，也不要分点，尽量按照记录出现顺序描述每条内容的主题、标题或账号信息）')
    ]);
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
