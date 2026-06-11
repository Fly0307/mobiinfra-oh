export type WorkflowJsonValue = Object | string | number | boolean | null;
export type WorkflowJsonMap = Record<string, WorkflowJsonValue>;

export interface WorkflowMetadata {
  name?: string;
  description?: string;
}

export interface WorkflowDefaults {
  device?: string;
  use_qwen3?: boolean;
  use_e2e?: boolean;
  use_experience?: boolean;
  accept_planner_changes?: boolean;
  decider_protocol?: string;
  output_dir?: string;
}

export interface WorkflowCondition {
  left?: WorkflowJsonValue;
  operator?: string;
  right?: WorkflowJsonValue;
}

export interface WorkflowToolInputs {
  mode?: string;
  image?: string;
  question?: string;
  json_schema?: Object;
  blocking?: boolean;
}

export interface WorkflowStep {
  id: string | number;
  type: string;
  name?: string;
  on_error?: string;
  task_description?: string;
  device?: string;
  use_qwen3?: boolean;
  use_e2e?: boolean;
  use_experience?: boolean;
  accept_planner_changes?: boolean;
  decider_protocol?: string;
  action?: string;
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
  file_name?: string;
  package_name?: string;
  tool_name?: string;
  inputs?: WorkflowToolInputs;
  times?: number | string;
  max_times?: number | string;
  break_if?: WorkflowCondition;
  condition?: WorkflowCondition | string | boolean;
  steps?: WorkflowStep[];
  then_steps?: WorkflowStep[];
  else_steps?: WorkflowStep[];
}

export interface WorkflowDefinition {
  metadata?: WorkflowMetadata;
  defaults?: WorkflowDefaults;
  context?: WorkflowJsonMap;
  steps: WorkflowStep[];
}

export interface WorkflowTask {
  id: string;
  sceneId: number;
  icon: string;
  iconColor: string;
  title: string;
  source: string;
  enabled: boolean;
  configFileName: string;
  workflowJson: string;
  lastStatus: string;
  lastRun: string;
  lastMessage: string;
  isUserModified?: boolean;
}

export interface WorkflowTaskIndex {
  version: number;
  tasks: WorkflowTask[];
}

export interface WorkflowFileStats {
  configCount: number;
  dailyLogCount: number;
  runCount: number;
  totalBytes: number;
}

export interface WorkflowManagedFile {
  name: string;
  path: string;
  size: number;
  modifiedTime: number;
}

export interface WorkflowStepResult {
  step_id: string;
  status: string;
  started_at: number;
  finished_at: number;
  duration_sec: number;
  output: WorkflowJsonMap;
  error?: string;
}

export interface WorkflowRunSummary {
  workflow_file: string;
  run_dir: string;
  context: WorkflowJsonMap;
  status: string;
  steps: Record<string, WorkflowStepResult>;
}

export interface WorkflowRunOptions {
  filesDir: string;
  hdcServerIp: string;
}

export interface WorkflowRunResult {
  status: string;
  message: string;
  runDir: string;
  dailyLogPath: string;
  returnedToApp: boolean;
}

export interface HdcBridgeResponse {
  status: string;
  message?: string;
  result?: string;
  image_b64?: string;
  width?: number;
  height?: number;
  action?: string;
  package_name?: string;
  no_reason?: boolean;
  max_steps?: number;
}
