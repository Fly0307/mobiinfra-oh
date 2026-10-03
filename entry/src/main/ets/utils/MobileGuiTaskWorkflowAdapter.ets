import { stringifyJsonCompat } from './JsonCompat';
import {
  MobileGuiTaskBusinessResult,
  MobileGuiTaskJsonValue,
  MobileGuiTaskRequest,
  MobileGuiTaskRunResult
} from './MobileGuiTaskTypes';
import { WorkflowStorage } from './WorkflowStorage';
import { WorkflowDefinition, WorkflowJsonMap, WorkflowJsonValue, WorkflowRunResult, WorkflowStep, WorkflowTask } from './WorkflowTypes';

const MOBILE_GUI_CHAT_TASK_ID: string = 'chat-mobile-gui-task';
const MOBILE_GUI_CHAT_TASK_SOURCE: string = 'chat_mobile_gui_task';
const MOBILE_GUI_CHAT_TASK_TITLE: string = '聊天手机 GUI 任务';
const MOBILE_GUI_CHAT_TASK_CONFIG_FILE_NAME: string = '__chat_mobile_gui_task.json';

export function isMobileGuiTaskCloudConfigReady(plannerBaseUrl: string, deciderBaseUrl: string,
  plannerApiKey: string, deciderApiKey: string): boolean {
  return plannerBaseUrl.trim().length > 0 &&
    deciderBaseUrl.trim().length > 0 &&
    plannerApiKey.trim().length > 0 &&
    deciderApiKey.trim().length > 0;
}

export function mobileGuiTaskCloudConfigMissingMessage(): string {
  return '配置不完整：请先填写 Planner / Decider 的服务地址和各自 API Key。';
}

export function buildMobileGuiWorkflowTaskDescription(request: MobileGuiTaskRequest): string {
  // 聊天工具只传递用户原始目标；App 选择、包名判断和启动动作统一交给 step1 Planner。
  return request.task.trim();
}

export function buildMobileGuiWorkflowDefinition(request: MobileGuiTaskRequest): WorkflowDefinition {
  let taskDescription = buildMobileGuiWorkflowTaskDescription(request);
  let plannerStep: WorkflowStep = {
    id: '1',
    name: 'plan_and_launch',
    type: 'gui_task',
    task_description: taskDescription
  };
  let deciderStep: WorkflowStep = {
    id: '2',
    name: 'execute_task',
    type: 'gui_task',
    task_description: taskDescription,
    max_steps: request.maxSteps,
    fail_on_max_steps: true,
    extract_result: true
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
    isUserModified: false,
    useEmbeddedWorkflowJson: true
  };
}

export function classifyMobileGuiWorkflowFailure(message: string): string {
  let normalized = message.trim().toLowerCase();
  if (normalized.indexOf('timeout') >= 0 || normalized.indexOf('timed out') >= 0 ||
    normalized.indexOf('超时') >= 0 || normalized.indexOf('max_steps_reached') >= 0 ||
    normalized.indexOf('max steps reached') >= 0 || normalized.indexOf('步数上限') >= 0) {
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
    let businessResult = mobileGuiBusinessResultFromWorkflowResult(result);
    return {
      ok: true,
      status: 'completed',
      errorCode: '',
      error: '',
      recoverable: false,
      summary: mobileGuiSummaryFromWorkflowResult(result, businessResult),
      runDir: relativeRunDir,
      returnedToApp: result.returnedToApp,
      result: businessResult === null ? undefined : businessResult
    };
  }
  if (result.status === 'cancelled') {
    return {
      ok: false,
      status: 'cancelled',
      errorCode: 'user_cancelled',
      error: result.message,
      // 用户已在执行过程中终止任务，不应由聊天 Agent 自动再次发起同一 GUI 操作。
      recoverable: false,
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

function mobileGuiSummaryFromWorkflowResult(result: WorkflowRunResult,
  businessResult: MobileGuiTaskBusinessResult | null): string {
  if (result.resultSummary !== undefined && result.resultSummary.trim().length > 0) {
    return result.resultSummary;
  }
  if (businessResult !== null && businessResult.summary.trim().length > 0) {
    return businessResult.summary;
  }
  return result.message;
}

function mobileGuiBusinessResultFromWorkflowResult(result: WorkflowRunResult): MobileGuiTaskBusinessResult | null {
  if (result.result !== undefined) {
    return normalizeMobileGuiBusinessResult(result.result);
  }
  if (result.resultExtractionError !== undefined && result.resultExtractionError.trim().length > 0) {
    let keyValues: Record<string, MobileGuiTaskJsonValue> = {};
    let items: Object[] = [];
    let summary = result.resultSummary !== undefined && result.resultSummary.trim().length > 0 ?
      result.resultSummary : result.message;
    let fallback: MobileGuiTaskBusinessResult = {
      outcome: 'uncertain',
      summary: summary,
      key_values: keyValues,
      items: items,
      extraction_error: result.resultExtractionError
    };
    return fallback;
  }
  return null;
}

function normalizeMobileGuiBusinessResult(value: WorkflowJsonMap): MobileGuiTaskBusinessResult {
  let keyValues = normalizeMobileGuiKeyValues(value['key_values']);
  let items = normalizeMobileGuiItems(value['items']);
  let result: MobileGuiTaskBusinessResult = {
    outcome: readWorkflowString(value['outcome'], 'uncertain'),
    summary: readWorkflowString(value['summary'], ''),
    key_values: keyValues,
    items: items
  };
  let extractionError = readWorkflowString(value['extraction_error'], '');
  if (extractionError.length > 0) {
    result.extraction_error = extractionError;
  }
  return result;
}

function normalizeMobileGuiKeyValues(value: WorkflowJsonValue | undefined): Record<string, MobileGuiTaskJsonValue> {
  let normalized: Record<string, MobileGuiTaskJsonValue> = {};
  if (value === undefined || value === null || Array.isArray(value) || typeof value !== 'object') {
    return normalized;
  }
  let source = value as Record<string, MobileGuiTaskJsonValue>;
  let keys = Object.keys(source);
  for (let i = 0; i < keys.length; i++) {
    normalized[keys[i]] = source[keys[i]];
  }
  return normalized;
}

function normalizeMobileGuiItems(value: WorkflowJsonValue | undefined): Object[] {
  let normalized: Object[] = [];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return normalized;
  }
  let source = value as Object[];
  for (let i = 0; i < source.length; i++) {
    let item = source[i];
    if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
      normalized.push(item);
    }
  }
  return normalized;
}

function readWorkflowString(value: WorkflowJsonValue | undefined, fallback: string): string {
  if (value === undefined || value === null || typeof value !== 'string') {
    return fallback;
  }
  let text = value.trim();
  return text.length > 0 ? text : fallback;
}
