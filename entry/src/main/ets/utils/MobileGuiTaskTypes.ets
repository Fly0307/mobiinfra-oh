export interface MobileGuiTaskRequest {
  task: string;
  appName: string;
  packageName: string;
  maxSteps: number;
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

export type MobileGuiTaskConfirmCallback = (request: MobileGuiTaskRequest) => Promise<boolean>;
export type MobileGuiTaskRunCallback = (request: MobileGuiTaskRequest) => Promise<MobileGuiTaskRunResult>;

export interface MobileGuiTaskExecutionCallbacks {
  confirmMobileGuiTask?: MobileGuiTaskConfirmCallback;
  runMobileGuiTask?: MobileGuiTaskRunCallback;
}
