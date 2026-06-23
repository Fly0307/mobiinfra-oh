import { stringifyJsonCompat } from './JsonCompat';
import { MobileGuiTaskRequest, MobileGuiTaskRunResult } from './MobileGuiTaskTypes';
import { WorkflowStorage } from './WorkflowStorage';
import { WorkflowDefinition, WorkflowRunResult, WorkflowStep, WorkflowTask } from './WorkflowTypes';

const MOBILE_GUI_CHAT_TASK_ID: string = 'chat-mobile-gui-task';
const MOBILE_GUI_CHAT_TASK_SOURCE: string = 'chat_mobile_gui_task';
const MOBILE_GUI_CHAT_TASK_TITLE: string = '聊天手机 GUI 任务';
const MOBILE_GUI_CHAT_TASK_CONFIG_FILE_NAME: string = '__chat_mobile_gui_task.json';

function compactLine(value: string): string {
  return value.trim().replace(/\s+/g, ' ');
}

export function buildMobileGuiWorkflowTaskDescription(request: MobileGuiTaskRequest): string {
  let lines: string[] = ['手机 GUI 任务：' + compactLine(request.task)];
  if (request.appName.trim().length > 0) {
    lines.push('目标应用名称提示：' + compactLine(request.appName));
  }
  if (request.packageName.trim().length > 0) {
    lines.push('目标应用包名提示：' + compactLine(request.packageName));
  }
  lines.push('最大步骤建议：' + String(request.maxSteps));
  return lines.join('\n');
}

export function buildMobileGuiWorkflowDefinition(request: MobileGuiTaskRequest): WorkflowDefinition {
  let taskDescription = buildMobileGuiWorkflowTaskDescription(request);
  let plannerStep: WorkflowStep = {
    id: '1',
    name: 'plan_and_launch',
    type: 'gui_task',
    task_description: taskDescription,
    package_name: request.packageName.trim().length > 0 ? request.packageName.trim() : undefined
  };
  let deciderStep: WorkflowStep = {
    id: '2',
    name: 'execute_task',
    type: 'gui_task',
    task_description: taskDescription,
    package_name: request.packageName.trim().length > 0 ? request.packageName.trim() : undefined
  };
  return {
    metadata: {
      name: MOBILE_GUI_CHAT_TASK_TITLE,
      description: '由聊天 Agent 临时构造的手机 GUI workflow。'
    },
    steps: [plannerStep, deciderStep]
  };
}

export function buildMobileGuiWorkflowTask(request: MobileGuiTaskRequest): WorkflowTask {
  let workflow = buildMobileGuiWorkflowDefinition(request);
  return {
    id: MOBILE_GUI_CHAT_TASK_ID,
    sceneId: 0,
    icon: 'Sparkles',
    iconColor: '#3B82F6',
    title: MOBILE_GUI_CHAT_TASK_TITLE,
    source: MOBILE_GUI_CHAT_TASK_SOURCE,
    enabled: true,
    configFileName: MOBILE_GUI_CHAT_TASK_CONFIG_FILE_NAME,
    workflowJson: stringifyJsonCompat(workflow as Object),
    lastStatus: '',
    lastRun: '',
    lastMessage: '',
    isUserModified: false
  };
}

export function classifyMobileGuiWorkflowFailure(message: string): string {
  let normalized = message.trim().toLowerCase();
  if (normalized.indexOf('timeout') >= 0 || normalized.indexOf('timed out') >= 0 ||
    normalized.indexOf('超时') >= 0) {
    return 'timeout';
  }
  if (normalized.indexOf('mismatch') >= 0 || normalized.indexOf('identity') >= 0 ||
    normalized.indexOf('包名不匹配') >= 0 || normalized.indexOf('应用不匹配') >= 0 ||
    normalized.indexOf('当前应用') >= 0) {
    return 'app_identity_mismatch';
  }
  if (normalized.indexOf('app_start') >= 0 || normalized.indexOf('startapp') >= 0 ||
    normalized.indexOf('start app') >= 0 || normalized.indexOf('拉起') >= 0 ||
    normalized.indexOf('启动应用') >= 0 || normalized.indexOf('open_app') >= 0) {
    return 'app_start_failed';
  }
  if (normalized.indexOf('planner') >= 0 || normalized.indexOf('app_name/package_name') >= 0 ||
    normalized.indexOf('app_name') >= 0 || normalized.indexOf('package_name') >= 0) {
    return 'planner_unavailable';
  }
  if (normalized.indexOf('decider') >= 0 || normalized.indexOf('qwendecider') >= 0) {
    return 'decider_unavailable';
  }
  return 'workflow_failed';
}

export function mobileGuiTaskRunResultFromFailure(errorCode: string, error: string, recoverable: boolean,
  runDir: string = '', returnedToApp: boolean = false, status: string = 'failed'): MobileGuiTaskRunResult {
  return {
    ok: false,
    status: status,
    errorCode: errorCode,
    error: error,
    recoverable: recoverable,
    summary: '',
    runDir: runDir,
    returnedToApp: returnedToApp
  };
}

export function mobileGuiTaskRunResultFromWorkflowResult(filesDir: string,
  result: WorkflowRunResult): MobileGuiTaskRunResult {
  let relativeRunDir = result.runDir.trim().length > 0 ?
    WorkflowStorage.workflowRunRelativePath(filesDir, result.runDir) : '';
  if (result.status === 'success') {
    return {
      ok: true,
      status: 'completed',
      errorCode: '',
      error: '',
      recoverable: false,
      summary: result.message,
      runDir: relativeRunDir,
      returnedToApp: result.returnedToApp
    };
  }
  if (result.status === 'cancelled') {
    return {
      ok: false,
      status: 'cancelled',
      errorCode: 'user_cancelled',
      error: result.message,
      recoverable: true,
      summary: '',
      runDir: relativeRunDir,
      returnedToApp: result.returnedToApp
    };
  }
  return {
    ok: false,
    status: 'failed',
    errorCode: classifyMobileGuiWorkflowFailure(result.message),
    error: result.message,
    recoverable: true,
    summary: '',
    runDir: relativeRunDir,
    returnedToApp: result.returnedToApp
  };
}
