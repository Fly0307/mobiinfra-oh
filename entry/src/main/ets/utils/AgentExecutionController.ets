type CancelHandler = () => Promise<void> | void;
type VoidHandler = () => void;

export class AgentExecutionController {
  private static executionActive: boolean = false;
  private static cancelRequested: boolean = false;
  private static localCancelHandler: CancelHandler | null = null;
  private static cloudCancelHandler: CancelHandler | null = null;
  private static floatWindowSyncHandler: VoidHandler | null = null;
  private static returnToAppHandler: VoidHandler | null = null;

  static initialize(): void {
    AppStorage.setOrCreate('floatText', 'AI Agent 运行中...');
    AppStorage.setOrCreate('agentExecutionActive', false);
    AppStorage.setOrCreate('agentCancelRequested', false);
  }

  static isExecutionActive(): boolean {
    return AgentExecutionController.executionActive;
  }

  static isCancelRequested(): boolean {
    return AgentExecutionController.cancelRequested;
  }

  static beginExecution(text: string = 'AI Agent running...'): void {
    AgentExecutionController.executionActive = true;
    AgentExecutionController.cancelRequested = false;
    AppStorage.setOrCreate('agentExecutionActive', true);
    AppStorage.setOrCreate('agentCancelRequested', false);
    AppStorage.setOrCreate('floatText', text);
    AgentExecutionController.notifyFloatWindowSync();
  }

  static updateFloatText(text: string): void {
    AppStorage.setOrCreate('floatText', text);
  }

  static finishExecution(text: string = 'AI Agent running...'): void {
    AgentExecutionController.executionActive = false;
    AgentExecutionController.cancelRequested = false;
    AppStorage.setOrCreate('agentExecutionActive', false);
    AppStorage.setOrCreate('agentCancelRequested', false);
    AppStorage.setOrCreate('floatText', text);
    AgentExecutionController.notifyFloatWindowSync();
  }

  static requestCancellation(): void {
    AgentExecutionController.cancelRequested = true;
    AgentExecutionController.executionActive = false;
    AppStorage.setOrCreate('agentCancelRequested', true);
    AppStorage.setOrCreate('agentExecutionActive', false);
    AgentExecutionController.notifyFloatWindowSync();

    try {
      AgentExecutionController.localCancelHandler?.();
    } catch (e) {
    }

    try {
      AgentExecutionController.cloudCancelHandler?.();
    } catch (e) {
    }

    try {
      AgentExecutionController.returnToAppHandler?.();
    } catch (e) {
    }
  }

  static registerLocalCancelHandler(handler: CancelHandler | null): void {
    AgentExecutionController.localCancelHandler = handler;
  }

  static registerCloudCancelHandler(handler: CancelHandler | null): void {
    AgentExecutionController.cloudCancelHandler = handler;
  }

  static setFloatWindowSyncHandler(handler: VoidHandler | null): void {
    AgentExecutionController.floatWindowSyncHandler = handler;
  }

  static setReturnToAppHandler(handler: VoidHandler | null): void {
    AgentExecutionController.returnToAppHandler = handler;
  }

  private static notifyFloatWindowSync(): void {
    try {
      AgentExecutionController.floatWindowSyncHandler?.();
    } catch (e) {
    }
  }
}