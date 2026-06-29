export interface MobileGuiTaskRequest {
  task: string;
  maxSteps: number;
}

export type MobileGuiTaskJsonValue = Object | string | number | boolean | null;

export interface MobileGuiTaskBusinessResult {
  outcome: string;
  summary: string;
  key_values: Record<string, MobileGuiTaskJsonValue>;
  items: Object[];
  extraction_error?: string;
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
  result?: MobileGuiTaskBusinessResult;
}

export type MobileGuiTaskConfirmCallback = (request: MobileGuiTaskRequest) => Promise<boolean>;
export type MobileGuiTaskRunCallback = (request: MobileGuiTaskRequest) => Promise<MobileGuiTaskRunResult>;

export interface MobileGuiTaskExecutionCallbacks {
  confirmMobileGuiTask?: MobileGuiTaskConfirmCallback;
  runMobileGuiTask?: MobileGuiTaskRunCallback;
}
