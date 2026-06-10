import { JSON as ArkJSON } from '@kit.ArkTS';
import { CloudModelClient, CloudModelConfig } from './CloudModelClient';
import { AgentExecutionController } from './AgentExecutionController';
import { HdcWorkflowBridge } from './HdcWorkflowBridge';
import { WorkflowJsonRepair } from './WorkflowJsonRepair';
import { WorkflowDateContext } from './WorkflowDateContext';
import { WorkflowStorage } from './WorkflowStorage';
import {
  WorkflowCondition,
  WorkflowDefinition,
  WorkflowJsonMap,
  WorkflowJsonValue,
  WorkflowRunResult,
  WorkflowRunSummary,
  WorkflowStep,
  WorkflowStepResult,
  WorkflowTask
} from './WorkflowTypes';

const VARIABLE_PATTERN: RegExp = /\$\{([^}]+)\}/g;
const MAX_GUI_STEPS = 15;
const SUMMARY_JOB_RETRY_LIMIT: number = 1;

interface PlannerResult {
  appName: string;
  packageName: string;
  finalTaskDescription: string;
}

interface RuntimeScope {
  name: string;
  value: WorkflowJsonValue;
}

interface GuiPlannerOutput {
  step_dir: string;
  task_description: string;
  planner_task_description: string;
  app_name: string;
  package_name: string;
  device: string;
  mode: string;
}

interface GuiDeciderOutput {
  step_dir: string;
  task_description: string;
  device: string;
  app_name: string;
  package_name: string;
  mode: string;
  stop_reason: string;
}

interface GuiActionOutput {
  step_dir: string;
  action: string;
  device: string;
  image_path?: string;
  image_b64?: string;
  width?: number;
  height?: number;
  file_name?: string;
  result?: string;
}

interface GuiActionPayload {
  action: string;
  x?: number;
  y?: number;
  text?: string;
  direction?: string;
  start_x?: number;
  start_y?: number;
  end_x?: number;
  end_y?: number;
  key?: string;
  seconds?: number;
  package_name?: string;
  reset_first?: boolean;
}

interface ToolOutput {
  step_dir: string;
  tool_name: string;
  mode: string;
  question: string;
  response: string;
  daily_log_path?: string;
  structured_output?: WorkflowJsonMap;
  deferred?: boolean;
  deferred_error?: string;
}

interface SummaryJobResult {
  ok: boolean;
  actual_id: string;
  response: string;
  error: string;
}

interface PendingSummaryJob {
  actual_id: string;
  prompt: string;
  image: string;
  promise: Promise<SummaryJobResult>;
}

interface LoopRuntimeValue {
  index: number;
  index0: number;
  count: number;
  first: boolean;
  last: boolean;
}

interface LoopRuntimeMap {
  loop: Object;
}

interface LoopIterationOutput {
  iteration: number;
  prefix: string;
  break_triggered: boolean;
}

interface LoopOutput {
  times: number;
  max_times: number;
  broke_early: boolean;
  break_iteration: number;
  iterations: LoopIterationOutput[];
}

interface IfOutput {
  matched: boolean;
  branch: string;
  executed_step_count: number;
}

interface RunVariableMap {
  dir: string;
  workflow_file: string;
  workflow_dir: string;
}

interface StepResultMap {
  step_id: string;
  status: string;
  started_at: number;
  finished_at: number;
  duration_sec: number;
  output: WorkflowJsonMap;
  error?: string;
}

interface DailyLogMetadata {
  workflow_metadata: WorkflowJsonMap;
  latest_entry_index: number;
}

interface RawResponseMap {
  raw_response: string;
}

export class WorkflowRunner {
  private static readonly APP_BUNDLE_NAME: string = 'com.example.mnnllmchat';

  private filesDir: string;
  private cloudClient: CloudModelClient;
  private cloudConfigProvider: () => CloudModelConfig;
  private hdcBridge: HdcWorkflowBridge;
  private logHandler: (message: string) => void;
  private workflow: WorkflowDefinition | null = null;
  private contextValues: WorkflowJsonMap = {};
  private stepResults: Record<string, WorkflowStepResult> = {};
  private aliasStack: Record<string, string>[] = [];
  private runtimeStack: RuntimeScope[] = [];
  private runDir: string = '';
  private runStartedAt: Date = new Date(0);
  private dateContext: WorkflowDateContext = new WorkflowDateContext(new Date(0));
  private runDate: string = '';
  private workflowFile: string = '';
  private runningTask: WorkflowTask | null = null;
  private currentAppName: string = '';
  private currentPackageName: string = '';
  private latestDailyLogPath: string = '';
  private pendingSummaryJobs: PendingSummaryJob[] = [];

  constructor(filesDir: string, cloudClient: CloudModelClient, cloudConfigProvider: () => CloudModelConfig,
    hdcServerIp: string, logHandler: (message: string) => void) {
    this.filesDir = filesDir;
    this.cloudClient = cloudClient;
    this.cloudConfigProvider = cloudConfigProvider;
    this.hdcBridge = new HdcWorkflowBridge(hdcServerIp, logHandler);
    this.logHandler = logHandler;
  }

  private workflowJsonForRun(task: WorkflowTask): string {
    try {
      return WorkflowStorage.readTaskWorkflowJson(this.filesDir, task);
    } catch (e) {
      let err = e as Error;
      this.log('读取最新 Workflow 配置失败，使用任务索引中的缓存配置：' + (err.message || String(e)));
      return task.workflowJson;
    }
  }

  async runTask(task: WorkflowTask): Promise<WorkflowRunResult> {
    this.workflowFile = WorkflowStorage.configDir(this.filesDir) + '/' + task.configFileName;
    this.workflow = WorkflowStorage.validateWorkflowJson(this.workflowJsonForRun(task));
    this.runningTask = task;
    this.contextValues = this.workflow.context || {};
    this.stepResults = {};
    this.aliasStack = [];
    this.runtimeStack = [];
    this.currentAppName = '';
    this.currentPackageName = '';
    this.latestDailyLogPath = '';
    this.pendingSummaryJobs = [];
    this.runStartedAt = new Date();
    this.dateContext = new WorkflowDateContext(this.runStartedAt);
    this.runDate = this.dateContext.runDate();
    this.runDir = this.createRunDir(task);

    this.log('====== Workflow started ======');
    this.log('任务：' + task.title);
    this.log('run 目录已创建：' + this.runDir);
    AgentExecutionController.beginExecution('Workflow 启动：' + task.title);
    this.writeRunSummary('running');

    let status = 'success';
    let message = 'Workflow 执行完成';
    let returnedToApp = false;
    try {
      let steps = this.normalizeSteps(this.workflow.steps);
      await this.executeSteps(steps, '', {});
      if (AgentExecutionController.isCancelRequested()) {
        status = 'cancelled';
        message = '用户取消 workflow';
      }
    } catch (e) {
      let err = e as Error;
      status = AgentExecutionController.isCancelRequested() ? 'cancelled' : 'failed';
      message = err.message || String(e);
      this.log('Workflow 失败：' + message);
    }

    if (status !== 'cancelled' && !AgentExecutionController.isCancelRequested()) {
      try {
        await this.flushPendingSummaryJobs();
        if (AgentExecutionController.isCancelRequested()) {
          status = 'cancelled';
          message = '用户取消 workflow';
        }
      } catch (e) {
        let err = e as Error;
        let flushMessage = err.message || String(e);
        this.log('Workflow deferred summary flush failed: ' + flushMessage);
        if (AgentExecutionController.isCancelRequested()) {
          status = 'cancelled';
          message = '用户取消 workflow';
        } else if (status === 'success') {
          status = 'failed';
          message = flushMessage;
        }
      }
    }

    this.writeRunSummary(status);

    returnedToApp = await this.returnToHostApp();
    if (returnedToApp) {
      this.log('Workflow 收尾：已切回数据归家 App。');
    } else {
      this.log('Workflow 收尾：切回数据归家 App 失败，请手动确认前台界面。');
    }

    if (status === 'success') {
      AgentExecutionController.finishExecution('Workflow 完成');
    } else {
      AgentExecutionController.finishExecution('Workflow ' + status);
    }
    this.log('====== Workflow finished: ' + status + ' ======');
    return {
      status: status,
      message: message,
      runDir: this.runDir,
      dailyLogPath: this.latestDailyLogPath,
      returnedToApp: returnedToApp
    };
  }

  private writeRunSummary(status: string): void {
    if (this.runDir.length === 0) {
      return;
    }
    let summary: WorkflowRunSummary = {
      workflow_file: this.workflowFile,
      run_dir: this.runDir,
      context: this.contextValues,
      status: status,
      steps: this.stepResults
    };
    WorkflowStorage.writeText(this.runDir + '/run_summary.json', ArkJSON.stringify(summary, null, 2));
  }

  private async returnToHostApp(): Promise<boolean> {
    try {
      await this.hdcBridge.startApp(WorkflowRunner.APP_BUNDLE_NAME, WorkflowRunner.APP_BUNDLE_NAME, false);
      return true;
    } catch (e) {
      let err = e as Error;
      this.log('通过 HDC 拉起宿主 App 失败：' + (err.message || String(e)));
    }

    if (AgentExecutionController.returnToApp()) {
      return true;
    }
    this.log('通过浮窗返回宿主 App 失败：未注册返回处理器或处理器执行失败');
    return false;
  }

  private createRunDir(task: WorkflowTask): string {
    WorkflowStorage.ensureWorkspace(this.filesDir);
    let stamp = this.formatTimestamp(this.runStartedAt);
    let safeName = this.sanitizeFileName(task.source || task.id);
    let dir = WorkflowStorage.runsDir(this.filesDir) + '/' + stamp + '-' + safeName;
    WorkflowStorage.ensureDirectory(dir);
    WorkflowStorage.ensureDirectory(dir + '/steps');
    return dir;
  }

  private normalizeSteps(steps: WorkflowStep[]): WorkflowStep[] {
    let normalized: WorkflowStep[] = [];
    let seen: Record<string, boolean> = {};
    for (let i = 0; i < steps.length; i++) {
      let src = steps[i];
      let step: WorkflowStep = src;
      step.id = String(src.id);
      if (!step.name) {
        step.name = String(step.id);
      }
      if (step.type === 'loop') {
        step.steps = this.normalizeSteps(step.steps || []);
      }
      if (step.type === 'if') {
        step.then_steps = this.normalizeSteps(step.then_steps || []);
        step.else_steps = this.normalizeSteps(step.else_steps || []);
      }
      let id = String(step.id);
      if (seen[id]) {
        throw new Error('Duplicate workflow step id: ' + id);
      }
      seen[id] = true;
      normalized.push(step);
    }
    return normalized;
  }

  private async executeSteps(steps: WorkflowStep[], actualPrefix: string,
    runtimeValues: WorkflowJsonMap): Promise<void> {
    let aliases: Record<string, string> = {};
    this.aliasStack.push(aliases);
    this.pushRuntimeValues(runtimeValues);
    try {
      for (let i = 0; i < steps.length; i++) {
        if (AgentExecutionController.isCancelRequested()) {
          throw new Error('用户取消 workflow');
        }
        await AgentExecutionController.waitIfPaused();
        if (AgentExecutionController.isCancelRequested()) {
          throw new Error('用户取消 workflow');
        }
        let localId = String(steps[i].id);
        let actualId = actualPrefix.length === 0 ? localId : actualPrefix + '.' + localId;
        let stopped = await this.executeOneStep(steps[i], actualId, aliases);
        if (stopped) {
          throw new Error('workflow stopped at step ' + actualId);
        }
      }
    } finally {
      this.popRuntimeValues(runtimeValues);
      this.aliasStack.pop();
    }
  }

  private async executeOneStep(step: WorkflowStep, actualId: string, aliases: Record<string, string>): Promise<boolean> {
    let started = new Date().getTime() / 1000;
    let localId = String(step.id);
    this.log('Step ' + actualId + ' started: ' + step.type);
    AgentExecutionController.updateFloatText(this.buildStepFloatText(step, actualId));
    await AgentExecutionController.waitIfPaused();
    if (AgentExecutionController.isCancelRequested()) {
      throw new Error('用户取消 workflow');
    }
    try {
      let resolved = this.shouldDeferNestedResolution(step) ? step : this.resolveStep(step);
      let output = await this.executeStep(resolved, actualId);
      let result = this.buildStepResult(actualId, 'success', started, output, '');
      this.stepResults[actualId] = result;
      aliases[localId] = actualId;
      this.log('Step ' + actualId + ' success');
      return false;
    } catch (e) {
      let err = e as Error;
      let result = this.buildStepResult(actualId, 'failed', started, {}, err.message || String(e));
      this.stepResults[actualId] = result;
      aliases[localId] = actualId;
      this.log('Step ' + actualId + ' failed: ' + result.error);
      return step.on_error !== 'continue';
    }
  }

  private shouldDeferNestedResolution(step: WorkflowStep): boolean {
    return step.type === 'loop' || step.type === 'if';
  }

  private buildStepResult(stepId: string, status: string, started: number, output: WorkflowJsonMap,
    error: string): WorkflowStepResult {
    let finished = new Date().getTime() / 1000;
    let result: WorkflowStepResult = {
      step_id: stepId,
      status: status,
      started_at: started,
      finished_at: finished,
      duration_sec: Math.round((finished - started) * 1000) / 1000,
      output: output
    };
    if (error.length > 0) {
      result.error = error;
    }
    return result;
  }

  private async executeStep(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    if (step.type === 'gui_task') {
      return this.runGuiTask(step, actualId);
    }
    if (step.type === 'gui_action') {
      return this.runGuiAction(step, actualId);
    }
    if (step.type === 'tool') {
      return this.runTool(step, actualId);
    }
    if (step.type === 'loop') {
      return this.runLoop(step, actualId);
    }
    if (step.type === 'if') {
      return this.runIf(step, actualId);
    }
    throw new Error('Unsupported workflow step type: ' + step.type);
  }

  private async runGuiTask(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    let taskDescription = step.task_description || '';
    if (actualId === '1') {
      let planner = await this.runPlanner(taskDescription);
      this.currentAppName = planner.appName;
      this.currentPackageName = planner.packageName.length > 0 ? planner.packageName : planner.appName;
      this.log('Planner 选择 App：' + planner.appName + ' ' + planner.packageName);
      await this.hdcBridge.startApp(planner.appName, planner.packageName, true);
      let output: GuiPlannerOutput = {
        step_dir: this.stepDir(actualId),
        task_description: taskDescription,
        planner_task_description: planner.finalTaskDescription,
        app_name: planner.appName,
        package_name: planner.packageName,
        device: step.device || 'Harmony',
        mode: 'planner_only'
      };
      return output as Object as WorkflowJsonMap;
    }

    if (this.currentAppName.length === 0) {
      throw new Error('gui_task after step 1 requires active app context');
    }
    let stopReason = await this.runDeciderLoop(taskDescription);
    let output: GuiDeciderOutput = {
      step_dir: this.stepDir(actualId),
      task_description: taskDescription,
      device: step.device || 'Harmony',
      app_name: this.currentAppName,
      package_name: this.currentPackageName,
      mode: 'decider_only',
      stop_reason: stopReason
    };
    return output as Object as WorkflowJsonMap;
  }

  private async runPlanner(taskDescription: string): Promise<PlannerResult> {
    let prompt = await this.buildPlannerPrompt(taskDescription);
    let response = await this.cloudClient.chatPlanner(prompt, this.cloudConfigProvider());
    this.log('Planner response:\n' + response);
    let data = this.extractJsonMap(response, true);
    let appName = this.getMapString(data, 'app_name');
    if (appName.length === 0) {
      appName = this.getMapString(data, 'app');
    }
    let packageName = this.getMapString(data, 'package_name');
    if (appName.length === 0) {
      if (packageName.length > 0) {
        appName = packageName;
      } else {
        throw new Error('Planner 未返回 app_name/package_name，终止执行，不再进入 Decider');
      }
    }
    let finalTask = this.getMapString(data, 'final_task_description');
    if (finalTask.length === 0) {
      finalTask = taskDescription;
    }
    return {
      appName: appName,
      packageName: packageName,
      finalTaskDescription: finalTask
    };
  }

  private async buildPlannerPrompt(taskDescription: string): Promise<string> {
    let fallbackPrompt = '你是 HarmonyOS 手机任务 Planner。请根据用户任务选择最合适的目标 App，并严格输出 JSON 对象，不要输出解释。' +
      '\nJSON 字段：reasoning, app_name, package_name, final_task_description。' +
      '\n如果不知道 package_name，可以留空，但 app_name 必须填写。' +
      '\n用户任务：' + taskDescription;
    try {
      let template = await this.hdcBridge.loadPromptTemplate('planner_oneshot_harmony.md');
      if (template.trim().length === 0) {
        return this.withExecutionDatePrompt(fallbackPrompt, 'Planner 用户任务');
      }
      let prompt = template.replace('{task_description}', taskDescription)
        .replace('<task_description>', taskDescription)
        .replace('{experience_content}', '')
        .replace('<experience_content>', '');
      if (prompt.indexOf(taskDescription) === -1) {
        prompt += '\n\n原始用户任务描述："' + taskDescription + '"';
      }
      return this.withExecutionDatePrompt(prompt, 'Planner 用户任务');
    } catch (e) {
      let err = e as Error;
      this.log('加载共享 planner prompt 失败，使用内置 fallback：' + (err.message || String(e)));
      return this.withExecutionDatePrompt(fallbackPrompt, 'Planner 用户任务');
    }
  }

  private withExecutionDatePrompt(prompt: string, sectionTitle: string): string {
    return this.dateContext.withDatePrompt(prompt, sectionTitle);
  }

  private async runDeciderLoop(taskDescription: string): Promise<string> {
    let deciderTask = this.dateContext.withDatePromptAsTask(taskDescription);
    let history: string[] = [];
    let stopReason = 'MAX_STEPS_REACHED';
    for (let i = 0; i < MAX_GUI_STEPS; i++) {
      if (AgentExecutionController.isCancelRequested()) {
        throw new Error('用户取消 workflow');
      }
      await AgentExecutionController.waitIfPaused();
      if (AgentExecutionController.isCancelRequested()) {
        throw new Error('用户取消 workflow');
      }
      AgentExecutionController.updateFloatText('Decider ' + (i + 1) + '/' + MAX_GUI_STEPS + ': 识别屏幕并决策');
      let shot = await this.hdcBridge.screenshot();
      let imageBase64 = shot.image_b64 || '';
      let width = shot.width || 0;
      let height = shot.height || 0;
      this.log('Decider 截图完成：' + width + 'x' + height);
      let response = await this.cloudClient.chatQwenDecider(deciderTask, history, imageBase64, this.cloudConfigProvider());
      this.log('Decider response:\n' + response);
      let parsed = this.extractJsonMap(response);
      let action = this.getMapString(parsed, 'action').toLowerCase();
      AgentExecutionController.updateFloatText(this.buildDeciderFloatText(parsed, i + 1));
      if (action === 'done' || action === 'stop' || action === 'terminate' || action === 'abort') {
        stopReason = 'TASK_COMPLETED_' + action;
        break;
      }
      await this.hdcBridge.executeModelAction(response, width * 2, height * 2);
      history.push(ArkJSON.stringify(parsed));
    }
    return stopReason;
  }

  private async runGuiAction(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    let action = step.action || '';
    let output: GuiActionOutput = {
      step_dir: this.stepDir(actualId),
      action: action,
      device: step.device || 'Harmony'
    };
    if (action === 'screenshot') {
      let shot = await this.hdcBridge.screenshot();
      let imageBase64 = shot.image_b64 || '';
      let imageFileName = this.screenshotFileName(step.file_name || 'screenshot.jpg');
      let imagePath = this.stepDir(actualId) + '/' + imageFileName;
      WorkflowStorage.writeBase64Image(imagePath, imageBase64);
      output.image_path = WorkflowStorage.workflowRunRelativePath(this.filesDir, imagePath);
      output.image_b64 = imageBase64;
      output.width = shot.width || 0;
      output.height = shot.height || 0;
      output.file_name = imageFileName;
      return output as Object as WorkflowJsonMap;
    }

    let payload: GuiActionPayload = {
      action: action
    };
    if (step.x !== undefined) {
      payload.x = step.x;
    }
    if (step.y !== undefined) {
      payload.y = step.y;
    }
    if (step.text !== undefined) {
      payload.text = step.text;
    }
    if (step.direction !== undefined) {
      payload.direction = step.direction;
    }
    if (step.start_x !== undefined) {
      payload.start_x = step.start_x;
    }
    if (step.start_y !== undefined) {
      payload.start_y = step.start_y;
    }
    if (step.end_x !== undefined) {
      payload.end_x = step.end_x;
    }
    if (step.end_y !== undefined) {
      payload.end_y = step.end_y;
    }
    if (step.key !== undefined) {
      payload.key = step.key;
    }
    if (step.seconds !== undefined) {
      payload.seconds = step.seconds;
    }
    if (step.package_name !== undefined) {
      payload.package_name = step.package_name;
    }
    if (action === 'app_start') {
      payload.reset_first = true;
    }
    let response = await this.hdcBridge.guiAction(payload as Object as WorkflowJsonMap);
    output.result = response.message || 'ok';
    return output as Object as WorkflowJsonMap;
  }

  private async runTool(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    let toolName = step.tool_name || '';
    if (toolName !== 'vlm_qa') {
      throw new Error('Unsupported workflow tool: ' + toolName);
    }
    let inputs = step.inputs;
    if (!inputs) {
      throw new Error('vlm_qa requires inputs');
    }
    let question = inputs.question || '';
    let mode = inputs.mode || 'answer';
    let image = inputs.image || '';
    if (question.length === 0 || image.length === 0) {
      throw new Error('vlm_qa requires question and image');
    }
    let imageBase64 = WorkflowStorage.resolveWorkflowImageInputAsBase64(this.filesDir, image);
    let requiresStructuredOutput = inputs.json_schema !== undefined && inputs.json_schema !== null;
    let promptBody = mode === 'summary' ? '请基于给定图片做总结：' + question : question;
    let prompt = this.withExecutionDatePrompt(promptBody, 'VLM 图片问答问题');
    if (requiresStructuredOutput) {
      prompt += '\n请严格输出一个 JSON 对象，不要输出 markdown 或额外解释。JSON Schema：' +
        ArkJSON.stringify(inputs.json_schema);
    }
    if (mode === 'summary' && inputs.blocking !== true && !requiresStructuredOutput) {
      this.log('VLM QA summary 已转为后台执行，先继续后续滑动步骤：' + actualId);
      this.pendingSummaryJobs.push(this.createSummaryJob(actualId, prompt, imageBase64));
      let deferredOutput: ToolOutput = {
        step_dir: this.stepDir(actualId),
        tool_name: toolName,
        mode: mode,
        question: question,
        response: 'summary_deferred',
        deferred: true
      };
      return deferredOutput as Object as WorkflowJsonMap;
    }
    this.log('VLM QA request started: ' + actualId);
    let response = await this.cloudClient.chatImageQuestion(prompt, imageBase64, this.cloudConfigProvider());
    this.log('VLM QA response:\n' + response);
    let output: ToolOutput = {
      step_dir: this.stepDir(actualId),
      tool_name: toolName,
      mode: mode,
      question: question,
      response: response
    };
    let structuredOutput: WorkflowJsonMap | undefined = undefined;
    if (requiresStructuredOutput) {
      structuredOutput = this.extractJsonMap(response);
      output.structured_output = structuredOutput;
    }
    if (mode === 'summary') {
      let dailyLogPath = this.appendDailySummaryLog(this.summaryLogText(response, structuredOutput));
      output.daily_log_path = dailyLogPath;
    }
    return output as Object as WorkflowJsonMap;
  }

  private createSummaryJob(actualId: string, prompt: string, imageBase64: string): PendingSummaryJob {
    return {
      actual_id: actualId,
      prompt: prompt,
      image: imageBase64,
      promise: this.startSummaryJob(actualId, prompt, imageBase64)
    };
  }

  private async startSummaryJob(actualId: string, prompt: string, imageBase64: string): Promise<SummaryJobResult> {
    try {
      let response = await this.cloudClient.chatImageQuestion(prompt, imageBase64, this.cloudConfigProvider());
      return this.normalizeSummaryJobResult({
        ok: true,
        actual_id: actualId,
        response: response,
        error: ''
      });
    } catch (e) {
      let err = e as Error;
      return {
        ok: false,
        actual_id: actualId,
        response: '',
        error: err.message || String(e)
      };
    }
  }

  private normalizeSummaryJobResult(result: SummaryJobResult): SummaryJobResult {
    if (result.ok && result.response.trim().length === 0) {
      return {
        ok: false,
        actual_id: result.actual_id,
        response: '',
        error: 'empty VLM summary response'
      };
    }
    return result;
  }

  private async resolveSummaryJob(job: PendingSummaryJob): Promise<SummaryJobResult> {
    let result = await job.promise;
    let retries = 0;
    while (!result.ok && retries < SUMMARY_JOB_RETRY_LIMIT && !AgentExecutionController.isCancelRequested()) {
      retries++;
      this.log('VLM QA deferred retry (' + job.actual_id + ') #' + String(retries) + ': ' + result.error);
      result = await this.startSummaryJob(job.actual_id, job.prompt, job.image);
    }
    return result;
  }

  private async flushPendingSummaryJobs(): Promise<void> {
    if (this.pendingSummaryJobs.length === 0) {
      return;
    }
    this.log('等待后台 summary 写入 daily-log：' + this.pendingSummaryJobs.length + ' 个');
    AgentExecutionController.updateFloatText('Workflow 写入 summary daily-log');
    let jobs = this.pendingSummaryJobs;
    this.pendingSummaryJobs = [];
    let failures: string[] = [];
    for (let i = 0; i < jobs.length; i++) {
      let result = await this.resolveSummaryJob(jobs[i]);
      if (AgentExecutionController.isCancelRequested()) {
        this.log('用户取消 workflow，停止等待后台 summary 写入');
        break;
      }
      if (result.ok) {
        this.log('VLM QA deferred response (' + result.actual_id + '):\n' + result.response);
        let dailyLogPath = this.appendDailySummaryLog(this.summaryLogText(result.response));
        if (dailyLogPath.length > 0) {
          this.updateDeferredSummaryOutput(result.actual_id, result.response, dailyLogPath);
          this.writeRunSummary('running');
        } else {
          let error = 'empty daily-log path after VLM summary';
          this.log('VLM QA deferred failed (' + result.actual_id + '): ' + error);
          this.markDeferredSummaryFailed(result.actual_id, error);
          this.writeRunSummary('running');
          failures.push(result.actual_id + ': ' + error);
        }
      } else {
        this.log('VLM QA deferred failed (' + result.actual_id + '): ' + result.error);
        this.markDeferredSummaryFailed(result.actual_id, result.error);
        this.writeRunSummary('running');
        failures.push(result.actual_id + ': ' + result.error);
      }
    }
    if (failures.length > 0) {
      throw new Error('VLM QA deferred summary failed: ' + failures.join('; '));
    }
  }

  private updateDeferredSummaryOutput(actualId: string, response: string, dailyLogPath: string): void {
    let result = this.stepResults[actualId];
    if (!result) {
      return;
    }
    let output = result.output as Object as ToolOutput;
    output.response = response;
    output.daily_log_path = dailyLogPath;
    output.deferred = false;
    output.deferred_error = '';
    result.output = output as Object as WorkflowJsonMap;
    this.refreshStepFinishedTime(result);
  }

  private markDeferredSummaryFailed(actualId: string, error: string): void {
    let result = this.stepResults[actualId];
    if (!result) {
      return;
    }
    let output = result.output as Object as ToolOutput;
    output.response = 'summary_failed';
    output.daily_log_path = '';
    output.deferred = false;
    output.deferred_error = error;
    result.output = output as Object as WorkflowJsonMap;
    result.status = 'failed';
    result.error = 'Deferred VLM summary failed: ' + error;
    this.refreshStepFinishedTime(result);
  }

  private refreshStepFinishedTime(result: WorkflowStepResult): void {
    let finished = new Date().getTime() / 1000;
    result.finished_at = finished;
    result.duration_sec = Math.round((finished - result.started_at) * 1000) / 1000;
  }

  private async runLoop(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    let maxValue = step.max_times !== undefined ? step.max_times : step.times;
    let maxTimes = this.toNumber(this.resolveValue(maxValue), 0);
    let iterations: LoopIterationOutput[] = [];
    let brokeEarly = false;
    let breakIteration = 0;
    for (let i = 0; i < maxTimes; i++) {
      let loopValue: LoopRuntimeValue = {
        index: i + 1,
        index0: i,
        count: maxTimes,
        first: i === 0,
        last: i === maxTimes - 1
      };
      let runtimeData: LoopRuntimeMap = {
        loop: loopValue as Object
      };
      let runtime = runtimeData as Object as WorkflowJsonMap;
      await this.executeSteps(step.steps || [], actualId + '.iter' + (i + 1), runtime);
      this.pushRuntimeValues(runtime);
      let shouldBreak = false;
      try {
        shouldBreak = step.break_if ? this.evaluateCondition(step.break_if) : false;
      } finally {
        this.popRuntimeValues(runtime);
      }
      let iterationOutput: LoopIterationOutput = {
        iteration: i + 1,
        prefix: actualId + '.iter' + (i + 1),
        break_triggered: shouldBreak
      };
      iterations.push(iterationOutput);
      if (shouldBreak) {
        brokeEarly = true;
        breakIteration = i + 1;
        break;
      }
    }
    let output: LoopOutput = {
      times: iterations.length,
      max_times: maxTimes,
      broke_early: brokeEarly,
      break_iteration: breakIteration,
      iterations: iterations
    };
    return output as Object as WorkflowJsonMap;
  }

  private async runIf(step: WorkflowStep, actualId: string): Promise<WorkflowJsonMap> {
    let matched = this.evaluateCondition(step.condition);
    let branch = matched ? 'then' : 'else';
    let branchSteps = matched ? (step.then_steps || []) : (step.else_steps || []);
    if (branchSteps.length > 0) {
      await this.executeSteps(branchSteps, actualId + '.' + branch, {});
    }
    let output: IfOutput = {
      matched: matched,
      branch: branch,
      executed_step_count: branchSteps.length
    };
    return output as Object as WorkflowJsonMap;
  }

  private resolveStep(step: WorkflowStep): WorkflowStep {
    let text = ArkJSON.stringify(step);
    let resolvedText = this.resolveString(text);
    return ArkJSON.parse(resolvedText) as WorkflowStep;
  }

  private resolveValue(value: WorkflowJsonValue | undefined): WorkflowJsonValue {
    if (value === undefined) {
      return null;
    }
    if (typeof value === 'string') {
      return this.resolveString(value);
    }
    return value;
  }

  private resolveString(raw: string): string {
    let matches = raw.match(VARIABLE_PATTERN);
    if (!matches) {
      return raw;
    }
    let resolved = raw;
    for (let i = 0; i < matches.length; i++) {
      let token = matches[i];
      let expression = token.substring(2, token.length - 1);
      let value = this.lookup(expression);
      let replacement = typeof value === 'string' ? value : ArkJSON.stringify(value);
      resolved = resolved.replace(token, replacement);
    }
    return resolved;
  }

  private lookup(expression: string): WorkflowJsonValue {
    let parts = expression.split('.');
    if (parts.length === 0) {
      throw new Error('Empty variable expression');
    }
    if (parts[0] === 'context') {
      return this.pickPath(this.contextValues, parts, 1);
    }
    if (parts[0] === 'run') {
      let runMap: RunVariableMap = {
        dir: this.runDir,
        workflow_file: this.workflowFile,
        workflow_dir: WorkflowStorage.configDir(this.filesDir)
      };
      return this.pickPath(runMap as Object as WorkflowJsonMap, parts, 1);
    }
    for (let i = this.runtimeStack.length - 1; i >= 0; i--) {
      if (this.runtimeStack[i].name === parts[0]) {
        return this.pickPath(this.runtimeStack[i].value, parts, 1);
      }
    }
    if (parts[0] === 'steps') {
      if (parts.length < 3) {
        throw new Error('Invalid steps variable: ' + expression);
      }
      let stepId = parts[1];
      for (let i = this.aliasStack.length - 1; i >= 0; i--) {
        let mapped = this.aliasStack[i][stepId];
        if (mapped) {
          stepId = mapped;
          break;
        }
      }
      let result = this.stepResults[stepId];
      if (!result) {
        throw new Error('Step result not found: ' + stepId);
      }
      let resultMap = this.stepResultToMap(result);
      return this.pickPath(resultMap, parts, 2);
    }
    throw new Error('Unsupported variable root: ' + parts[0]);
  }

  private pickPath(root: WorkflowJsonValue, parts: string[], start: number): WorkflowJsonValue {
    let current: WorkflowJsonValue = root;
    for (let i = start; i < parts.length; i++) {
      let map = current as WorkflowJsonMap;
      let key = parts[i];
      current = map[key];
      if ((current === undefined || current === null) && key === 'image_path') {
        current = this.legacyImagePathAlias(map);
      }
      if (current === undefined || current === null) {
        return null;
      }
    }
    return current;
  }

  private legacyImagePathAlias(map: WorkflowJsonMap): WorkflowJsonValue {
    if (map['action'] !== 'screenshot') {
      return null;
    }
    let imageBase64 = map['image_b64'];
    if (typeof imageBase64 === 'string' && imageBase64.length > 0) {
      return imageBase64;
    }
    return null;
  }

  private stepResultToMap(result: WorkflowStepResult): WorkflowJsonMap {
    let map: StepResultMap = {
      step_id: result.step_id,
      status: result.status,
      started_at: result.started_at,
      finished_at: result.finished_at,
      duration_sec: result.duration_sec,
      output: result.output
    };
    if (result.error) {
      map.error = result.error;
    }
    return map as Object as WorkflowJsonMap;
  }

  private pushRuntimeValues(values: WorkflowJsonMap): void {
    let keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      this.runtimeStack.push({ name: keys[i], value: values[keys[i]] });
    }
  }

  private popRuntimeValues(values: WorkflowJsonMap): void {
    let keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      this.runtimeStack.pop();
    }
  }

  private evaluateCondition(condition: WorkflowCondition | string | boolean | undefined): boolean {
    if (condition === undefined || condition === null) {
      return false;
    }
    if (typeof condition === 'boolean') {
      return condition;
    }
    if (typeof condition === 'string') {
      let resolved = this.resolveString(condition);
      let lowered = resolved.trim().toLowerCase();
      return !(lowered === '' || lowered === '0' || lowered === 'false' || lowered === 'no' || lowered === 'null');
    }
    let left = this.resolveValue(condition.left);
    let right = this.resolveValue(condition.right);
    let operator = condition.operator || '==';
    left = this.normalizeConditionValue(left, right);
    right = this.normalizeConditionValue(right, left);
    if (operator === '==') {
      return ArkJSON.stringify(left) === ArkJSON.stringify(right);
    }
    if (operator === '!=') {
      return ArkJSON.stringify(left) !== ArkJSON.stringify(right);
    }
    if (operator === 'contains') {
      return String(left).indexOf(String(right)) >= 0;
    }
    if (operator === 'not_contains') {
      return String(left).indexOf(String(right)) < 0;
    }
    if (operator === '>') {
      return this.toNumber(left, 0) > this.toNumber(right, 0);
    }
    if (operator === '>=') {
      return this.toNumber(left, 0) >= this.toNumber(right, 0);
    }
    if (operator === '<') {
      return this.toNumber(left, 0) < this.toNumber(right, 0);
    }
    if (operator === '<=') {
      return this.toNumber(left, 0) <= this.toNumber(right, 0);
    }
    throw new Error('Unsupported condition operator: ' + operator);
  }

  private normalizeConditionValue(value: WorkflowJsonValue, peer: WorkflowJsonValue): WorkflowJsonValue {
    if (typeof value === 'string' && typeof peer === 'boolean') {
      let lowered = value.trim().toLowerCase();
      if (lowered === 'true') {
        return true;
      }
      if (lowered === 'false') {
        return false;
      }
    }
    if (typeof value === 'string' && typeof peer === 'number') {
      let parsed = Number(value);
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
    return value;
  }

  private appendDailySummaryLog(summaryText: string): string {
    let text = this.dateContext.normalizeDailyLogText(summaryText.trim());
    if (text.length === 0) {
      return '';
    }
    let dailyDir = WorkflowStorage.dailyLogDir(this.filesDir) + '/' + this.runDate;
    WorkflowStorage.ensureDirectory(dailyDir);
    let fileName = this.buildDailyLogFileName();
    let path = dailyDir + '/' + fileName;
    let latest = 0;
    let body = '';
    try {
      if (WorkflowStorage.countFiles(path) > 0) {
        let existing = WorkflowStorage.readText(path);
        let metadataEnd = existing.indexOf('-->');
        if (metadataEnd >= 0) {
          body = existing.substring(metadataEnd + 3).trim();
        } else {
          body = existing.trim();
        }
        latest = this.lastEntryNumber(body);
      }
    } catch (e) {
    }
    let next = latest + 1;
    let newBody = body.length > 0 ? body + '\n\n' + next + '. ' + text + '\n' : next + '. ' + text + '\n';
    let workflowMetadata: WorkflowJsonMap = {};
    if (this.workflow && this.workflow.metadata) {
      if (this.workflow.metadata.name) {
        workflowMetadata['name'] = this.workflow.metadata.name;
      }
      if (this.workflow.metadata.description) {
        workflowMetadata['description'] = this.workflow.metadata.description;
      }
    }
    if (this.runningTask !== null) {
      workflowMetadata['task_scene_id'] = this.runningTask.sceneId;
    }
    let metadata: DailyLogMetadata = {
      workflow_metadata: workflowMetadata,
      latest_entry_index: next
    };
    let content = '<!-- DAILY_LOG_METADATA\n' + ArkJSON.stringify(metadata, null, 2) + '\n-->\n\n' + newBody;
    WorkflowStorage.writeText(path, content);
    this.latestDailyLogPath = path;
    this.log('daily-log 已写入：' + path);
    return path;
  }

  private summaryLogText(response: string, structuredOutput?: WorkflowJsonMap): string {
    let structuredSummary = this.structuredSummaryText(structuredOutput);
    if (structuredSummary.length > 0) {
      return structuredSummary;
    }
    let jsonSummary = this.summaryFromJsonText(response);
    if (jsonSummary.length > 0) {
      return jsonSummary;
    }
    return response.trim();
  }

  private structuredSummaryText(output?: WorkflowJsonMap): string {
    if (!output) {
      return '';
    }
    let summary = output['summary'];
    return typeof summary === 'string' ? summary.trim() : '';
  }

  private summaryFromJsonText(raw: string): string {
    let text = WorkflowJsonRepair.normalizeJsonText(raw);
    try {
      let parsed = ArkJSON.parse(text) as WorkflowJsonMap;
      return this.structuredSummaryText(parsed);
    } catch (e) {
      let candidates = WorkflowJsonRepair.repairCandidates(text);
      for (let i = 0; i < candidates.length; i++) {
        try {
          let parsed = ArkJSON.parse(candidates[i]) as WorkflowJsonMap;
          return this.structuredSummaryText(parsed);
        } catch {
        }
      }
      return '';
    }
  }

  private buildDailyLogFileName(): string {
    let workflowName = 'workflow';
    if (this.workflow && this.workflow.metadata && this.workflow.metadata.name) {
      workflowName = this.workflow.metadata.name;
    }
    let parts: string[] = [
      this.sanitizeFileName(this.currentPackageName.length > 0 ? this.currentPackageName : 'unknown-package'),
      this.sanitizeFileName(workflowName)
    ];
    let keys = Object.keys(this.contextValues);
    for (let i = 0; i < keys.length; i++) {
      let value = this.contextValues[keys[i]];
      if (value !== null && value !== undefined) {
        parts.push(this.sanitizeFileName(String(value)));
      }
    }
    return parts.join('__') + '.md';
  }

  private lastEntryNumber(body: string): number {
    let lines = body.split('\n');
    let last = 0;
    for (let i = 0; i < lines.length; i++) {
      let dot = lines[i].indexOf('. ');
      if (dot > 0) {
        let value = Number(lines[i].substring(0, dot));
        if (!isNaN(value)) {
          last = value;
        }
      }
    }
    return last;
  }

  private extractJsonMap(raw: string, failOnParseError: boolean = false): WorkflowJsonMap {
    let text = WorkflowJsonRepair.normalizeJsonText(raw);
    try {
      return ArkJSON.parse(text) as WorkflowJsonMap;
    } catch (e) {
      let err = e as Error;
      let candidates = WorkflowJsonRepair.repairCandidates(text);
      let repairMessage = '';
      for (let i = 0; i < candidates.length; i++) {
        try {
          let parsed = ArkJSON.parse(candidates[i]) as WorkflowJsonMap;
          this.log('JSON parse repaired after model returned non-strict JSON');
          return parsed;
        } catch (repairError) {
          let repairErr = repairError as Error;
          repairMessage = repairErr.message || String(repairError);
        }
      }
      let message = 'JSON parse failed, raw response preserved: ' + (err.message || String(e));
      if (repairMessage.length > 0) {
        message += '; repair failed: ' + repairMessage;
      }
      this.log(message);
      if (failOnParseError) {
        throw new Error('Planner JSON 解析失败，终止执行，不再进入 Decider：' + (err.message || String(e)));
      }
      let fallback: RawResponseMap = { raw_response: raw };
      return fallback as Object as WorkflowJsonMap;
    }
  }

  private getMapString(map: WorkflowJsonMap, key: string): string {
    let value = map[key];
    return typeof value === 'string' ? value : '';
  }

  private buildStepFloatText(step: WorkflowStep, actualId: string): string {
    if (step.task_description && step.task_description.length > 0) {
      return 'Step ' + actualId + ': ' + step.task_description;
    }
    if (step.action && step.action.length > 0) {
      return 'Step ' + actualId + ': ' + step.action;
    }
    if (step.name && step.name.length > 0) {
      return 'Step ' + actualId + ': ' + step.name;
    }
    return 'Step ' + actualId + ': ' + step.type;
  }

  private buildDeciderFloatText(parsed: WorkflowJsonMap, index: number): string {
    let action = this.getMapString(parsed, 'action');
    if (action.length === 0) {
      return 'Decider ' + index + '/' + MAX_GUI_STEPS + ': 等待动作';
    }
    let text = this.getMapString(parsed, 'text');
    if (text.length > 0) {
      return 'Decider ' + index + '/' + MAX_GUI_STEPS + ': ' + action + ' ' + text;
    }
    return 'Decider ' + index + '/' + MAX_GUI_STEPS + ': ' + action;
  }

  private toNumber(value: WorkflowJsonValue | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      let parsed = Number(value);
      return isNaN(parsed) ? fallback : parsed;
    }
    return fallback;
  }

  private stepDir(actualId: string): string {
    let dir = this.runDir + '/steps/' + actualId;
    WorkflowStorage.ensureDirectory(dir);
    return dir;
  }

  private screenshotFileName(value: string): string {
    let safeName = this.sanitizeFileName(value);
    let lower = safeName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
      lower.endsWith('.webp') || lower.endsWith('.gif')) {
      return safeName;
    }
    return safeName + '.jpg';
  }

  private sanitizeFileName(value: string): string {
    let sanitized = value.trim();
    sanitized = sanitized.replace(/[\\/:*?"<>|]+/g, '_');
    sanitized = sanitized.replace(/\s+/g, '-');
    if (sanitized.length === 0) {
      return 'workflow';
    }
    return sanitized;
  }

  private formatTimestamp(date: Date): string {
    let y = date.getFullYear();
    let m = (date.getMonth() + 1).toString().padStart(2, '0');
    let d = date.getDate().toString().padStart(2, '0');
    let h = date.getHours().toString().padStart(2, '0');
    let mi = date.getMinutes().toString().padStart(2, '0');
    let s = date.getSeconds().toString().padStart(2, '0');
    return y + m + d + '-' + h + mi + s;
  }

  private log(message: string): void {
    this.logHandler('[Workflow] ' + message);
  }
}
