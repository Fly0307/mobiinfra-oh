import { ChatTool, ChatToolExecutionContext } from './ChatToolRegistry';
import { parseJsonCompat, stringifyJsonCompat } from './JsonCompat';

export const MOBILE_GUI_TASK_TOOL_NAME: string = 'run_mobile_gui_task';
const DEFAULT_MAX_STEPS: number = 20;
const MAX_MAX_STEPS: number = 50;

type MobileGuiTaskJsonValue = Object | string | number | boolean | null;
interface MobileGuiTaskArguments {
  task?: string;
  app_name?: string;
  package_name?: string;
  max_steps?: number;
}
interface MobileGuiTaskToolProperties {
  task: MobileGuiTaskSchemaField;
  app_name: MobileGuiTaskSchemaField;
  package_name: MobileGuiTaskSchemaField;
  max_steps: MobileGuiTaskSchemaField;
}

export interface MobileGuiTaskToolResponse {
  ok: boolean;
  status: string;
  summary?: string;
  run_dir?: string;
  returned_to_app?: boolean;
  error_code?: string;
  error?: string;
  recoverable?: boolean;
}

interface MobileGuiTaskToolParameters {
  type: string;
  description: string;
  properties: MobileGuiTaskToolProperties;
  required: string[];
  additionalProperties: boolean;
}

interface MobileGuiTaskSchemaField {
  type: string;
  description: string;
}

export interface MobileGuiTaskRequest {
  task: string;
  appName: string;
  packageName: string;
  maxSteps: number;
}

export interface MobileGuiTaskArgumentValidation {
  ok: boolean;
  request: MobileGuiTaskRequest;
  errorCode: string;
  error: string;
}

export interface MobileGuiTaskRunResult {
  ok: boolean;
  status: string;
  errorCode: string;
  error: string;
  recoverable: boolean;
  summary: string;
  runDir: string;
  returnedToApp: boolean;
}

export function createMobileGuiTaskTool(): ChatTool {
  return {
    name: MOBILE_GUI_TASK_TOOL_NAME,
    description: '执行需要手机 GUI 操作的高层任务。',
    parameters: mobileGuiTaskToolParameters(),
    strict: false,
    execute: async (argsText: string, _context: ChatToolExecutionContext): Promise<string> => {
      let validation = normalizeMobileGuiTaskArguments(argsText);
      if (!validation.ok) {
        return stringifyMobileGuiTaskToolResponse(
          mobileGuiTaskToolErrorResponse('failed', 'invalid_arguments', validation.error, false)
        );
      }
      return stringifyMobileGuiTaskToolResponse(
        mobileGuiTaskToolErrorResponse('unavailable', 'unavailable',
          '当前版本尚未接入手机 GUI 任务执行回调。', true)
      );
    }
  };
}

export function mobileGuiTaskToolParameters(): Object {
  let properties: MobileGuiTaskToolProperties = createToolProperties();
  let schema: MobileGuiTaskToolParameters = {
    type: 'object',
    description: '执行一个需要手机 GUI 操作的高层任务。未指定 max_steps 或传入非正数时回退默认值 20；超过 50 时会截断到 50。',
    properties: properties,
    required: ['task'],
    additionalProperties: false
  };
  return schema as Object;
}

export function normalizeMobileGuiTaskArguments(argsText: string): MobileGuiTaskArgumentValidation {
  try {
    let text = argsText.trim().length === 0 ? '{}' : argsText.trim();
    let parsed = parseJsonCompat<MobileGuiTaskJsonValue>(text);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('Tool arguments must be a JSON object.');
    }
    let args = parsed as MobileGuiTaskArguments;
    assertAllowedFields(parsed);

    let task = readRequiredStringField(args.task, 'task');
    if (task.length === 0) {
      throw new Error('task 不能为空。');
    }

    return {
      ok: true,
      request: {
        task: task,
        appName: readOptionalStringField(args.app_name),
        packageName: readOptionalStringField(args.package_name),
        maxSteps: readMaxSteps(args.max_steps)
      },
      errorCode: '',
      error: ''
    };
  } catch (e) {
    let err = e as Error;
    return {
      ok: false,
      request: emptyRequest(),
      errorCode: 'invalid_arguments',
      error: err.message
    };
  }
}

export function mobileGuiTaskToolResponseFromRunResult(result: MobileGuiTaskRunResult): MobileGuiTaskToolResponse {
  let response: MobileGuiTaskToolResponse = {
    ok: result.ok,
    status: result.status,
    summary: result.summary.length > 0 ? result.summary : undefined,
    run_dir: result.runDir.length > 0 ? result.runDir : undefined,
    returned_to_app: result.returnedToApp
  };
  if (!result.ok) {
    response.error_code = result.errorCode;
    response.error = result.error;
    response.recoverable = result.recoverable;
  }
  return response;
}

export function stringifyMobileGuiTaskToolResponse(response: MobileGuiTaskToolResponse): string {
  return stringifyJsonCompat(response as Object);
}

function mobileGuiTaskToolErrorResponse(status: string, errorCode: string, error: string, recoverable: boolean):
  MobileGuiTaskToolResponse {
  let response: MobileGuiTaskToolResponse = {
    ok: false,
    status: status,
    error_code: errorCode,
    error: error,
    recoverable: recoverable
  };
  return response;
}

function assertAllowedFields(args: Object): void {
  let allowed: string[] = ['task', 'app_name', 'package_name', 'max_steps'];
  let keys = Object.keys(args);
  for (let i = 0; i < keys.length; i++) {
    let key = keys[i];
    if (allowed.indexOf(key) < 0) {
      throw new Error('Unsupported run_mobile_gui_task argument: ' + key);
    }
  }
}

function readRequiredStringField(value: string | undefined, key: string): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value !== 'string') {
    throw new Error(key + ' must be a string.');
  }
  return value.trim();
}

function readOptionalStringField(value: string | undefined): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value !== 'string') {
    throw new Error('Optional string field must be a string.');
  }
  return value.trim();
}

function readMaxSteps(value: number | undefined): number {
  // 非正数回退默认值；过大值截断到上限，避免后续执行器被异常步数拖慢。
  if (value === undefined) {
    return DEFAULT_MAX_STEPS;
  }
  if (typeof value !== 'number' || !isFinite(value)) {
    throw new Error('max_steps must be a number.');
  }
  let normalized = Math.floor(value);
  if (normalized <= 0) {
    return DEFAULT_MAX_STEPS;
  }
  if (normalized > MAX_MAX_STEPS) {
    return MAX_MAX_STEPS;
  }
  return normalized;
}

function emptyRequest(): MobileGuiTaskRequest {
  return {
    task: '',
    appName: '',
    packageName: '',
    maxSteps: DEFAULT_MAX_STEPS
  };
}

function stringSchema(description: string): MobileGuiTaskSchemaField {
  let schema: MobileGuiTaskSchemaField = {
    type: 'string',
    description: description
  };
  return schema;
}

function numberSchema(description: string): MobileGuiTaskSchemaField {
  let schema: MobileGuiTaskSchemaField = {
    type: 'number',
    description: description
  };
  return schema;
}

function createToolProperties(): MobileGuiTaskToolProperties {
  let properties: MobileGuiTaskToolProperties = {
    task: stringSchema('需要执行的手机 GUI 任务。'),
    app_name: stringSchema('可选的目标应用名称。'),
    package_name: stringSchema('可选的目标应用包名。'),
    max_steps: numberSchema('可选的最大执行步数。非正数回退默认值 20，超过 50 时截断为 50。')
  };
  return properties;
}
