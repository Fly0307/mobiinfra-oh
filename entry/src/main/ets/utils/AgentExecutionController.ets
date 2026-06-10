import { AppLogger } from './AppLogger';

type CancelHandler = () => Promise<void> | void;
type VoidHandler = () => void;
type FloatPanelLayoutHandler = (expanded: boolean) => void;
type FloatPanelMoveHandler = (phase: string) => void;
type CaptureOverlayHandler = (hidden: boolean) => Promise<boolean>;

const PAUSE_POLL_INTERVAL_MS = 200;

export class AgentExecutionController {
  private static executionActive: boolean = false;
  private static cancelRequested: boolean = false;
  private static pauseRequested: boolean = false;
  private static floatPanelExpanded: boolean = false;
  private static localCancelHandler: CancelHandler | null = null;
  private static cloudCancelHandler: CancelHandler | null = null;
  private static floatWindowSyncHandler: VoidHandler | null = null;
  private static floatPanelLayoutHandler: FloatPanelLayoutHandler | null = null;
  private static floatPanelMoveHandler: FloatPanelMoveHandler | null = null;
  private static returnToAppHandler: VoidHandler | null = null;
  private static captureOverlayHandler: CaptureOverlayHandler | null = null;
  private static captureOverlayHideDepth: number = 0;
  private static captureOverlayHidden: boolean = false;

  private static warn(message: string, err: Object): void {
    AppLogger.warn('AgentExecution', message + ': ' + String(err));
  }

  static initialize(): void {
    AppStorage.setOrCreate('floatText', 'AI Agent 运行中...');
    AppStorage.setOrCreate('agentExecutionActive', false);
    AppStorage.setOrCreate('agentCancelRequested', false);
    AppStorage.setOrCreate('agentPauseRequested', false);
    AppStorage.setOrCreate('agentFloatPanelExpanded', false);
  }

  static isExecutionActive(): boolean {
    return AgentExecutionController.executionActive;
  }

  static isCancelRequested(): boolean {
    return AgentExecutionController.cancelRequested;
  }

  static isPauseRequested(): boolean {
    return AgentExecutionController.pauseRequested;
  }

  static isFloatPanelExpanded(): boolean {
    return AgentExecutionController.floatPanelExpanded;
  }

  static beginExecution(text: string = 'AI Agent running...'): void {
    AgentExecutionController.executionActive = true;
    AgentExecutionController.cancelRequested = false;
    AgentExecutionController.pauseRequested = false;
    AgentExecutionController.floatPanelExpanded = false;
    AppStorage.setOrCreate('agentExecutionActive', true);
    AppStorage.setOrCreate('agentCancelRequested', false);
    AppStorage.setOrCreate('agentPauseRequested', false);
    AppStorage.setOrCreate('agentFloatPanelExpanded', false);
    AppStorage.setOrCreate('floatText', text);
    AgentExecutionController.notifyFloatWindowSync();
  }

  static updateFloatText(text: string): void {
    AppStorage.setOrCreate('floatText', text);
  }

  static finishExecution(text: string = 'AI Agent running...'): void {
    AgentExecutionController.executionActive = false;
    AgentExecutionController.cancelRequested = false;
    AgentExecutionController.pauseRequested = false;
    AgentExecutionController.floatPanelExpanded = false;
    AgentExecutionController.captureOverlayHideDepth = 0;
    AgentExecutionController.captureOverlayHidden = false;
    AppStorage.setOrCreate('agentExecutionActive', false);
    AppStorage.setOrCreate('agentCancelRequested', false);
    AppStorage.setOrCreate('agentPauseRequested', false);
    AppStorage.setOrCreate('agentFloatPanelExpanded', false);
    AppStorage.setOrCreate('floatText', text);
    AgentExecutionController.notifyFloatWindowSync();
  }

  static requestCancellation(): void {
    AgentExecutionController.cancelRequested = true;
    AgentExecutionController.executionActive = false;
    AgentExecutionController.pauseRequested = false;
    AgentExecutionController.floatPanelExpanded = false;
    AgentExecutionController.captureOverlayHideDepth = 0;
    AgentExecutionController.captureOverlayHidden = false;
    AppStorage.setOrCreate('agentCancelRequested', true);
    AppStorage.setOrCreate('agentExecutionActive', false);
    AppStorage.setOrCreate('agentPauseRequested', false);
    AppStorage.setOrCreate('agentFloatPanelExpanded', false);
    AgentExecutionController.notifyFloatWindowSync();

    try {
      AgentExecutionController.localCancelHandler?.();
    } catch (e) {
      AgentExecutionController.warn('local cancel handler failed', e as Object);
    }

    try {
      AgentExecutionController.cloudCancelHandler?.();
    } catch (e) {
      AgentExecutionController.warn('cloud cancel handler failed', e as Object);
    }

    try {
      AgentExecutionController.returnToAppHandler?.();
    } catch (e) {
      AgentExecutionController.warn('return-to-app handler failed', e as Object);
    }
  }

  static togglePause(): void {
    if (!AgentExecutionController.executionActive) {
      return;
    }
    AgentExecutionController.pauseRequested = !AgentExecutionController.pauseRequested;
    AppStorage.setOrCreate('agentPauseRequested', AgentExecutionController.pauseRequested);
  }

  static resumeExecution(): void {
    AgentExecutionController.pauseRequested = false;
    AppStorage.setOrCreate('agentPauseRequested', false);
  }

  static toggleFloatPanelExpanded(): void {
    AgentExecutionController.floatPanelExpanded = !AgentExecutionController.floatPanelExpanded;
    AppStorage.setOrCreate('agentFloatPanelExpanded', AgentExecutionController.floatPanelExpanded);
    AgentExecutionController.notifyFloatPanelLayout();
  }

  static setFloatPanelExpanded(expanded: boolean): void {
    AgentExecutionController.floatPanelExpanded = expanded;
    AppStorage.setOrCreate('agentFloatPanelExpanded', expanded);
    AgentExecutionController.notifyFloatPanelLayout();
  }

  static async waitIfPaused(): Promise<void> {
    while (AgentExecutionController.pauseRequested && AgentExecutionController.executionActive &&
      !AgentExecutionController.cancelRequested) {
      await AgentExecutionController.sleep(PAUSE_POLL_INTERVAL_MS);
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

  static setFloatPanelLayoutHandler(handler: FloatPanelLayoutHandler | null): void {
    AgentExecutionController.floatPanelLayoutHandler = handler;
  }

  static setFloatPanelMoveHandler(handler: FloatPanelMoveHandler | null): void {
    AgentExecutionController.floatPanelMoveHandler = handler;
  }

  static startFloatPanelMove(): void {
    AgentExecutionController.notifyFloatPanelMove('start');
  }

  static endFloatPanelMove(): void {
    AgentExecutionController.notifyFloatPanelMove('end');
  }

  static setReturnToAppHandler(handler: VoidHandler | null): void {
    AgentExecutionController.returnToAppHandler = handler;
  }

  static setCaptureOverlayHandler(handler: CaptureOverlayHandler | null): void {
    AgentExecutionController.captureOverlayHandler = handler;
  }

  static async hideCaptureOverlay(): Promise<boolean> {
    if (!AgentExecutionController.executionActive) {
      return false;
    }
    AgentExecutionController.captureOverlayHideDepth += 1;
    if (AgentExecutionController.captureOverlayHidden) {
      return false;
    }
    if (!AgentExecutionController.captureOverlayHandler) {
      return false;
    }
    try {
      let hidden = await AgentExecutionController.captureOverlayHandler(true);
      AgentExecutionController.captureOverlayHidden = hidden;
      return hidden;
    } catch (e) {
      AgentExecutionController.warn('capture overlay hide failed', e as Object);
      return false;
    }
  }

  static async restoreCaptureOverlay(token: boolean): Promise<void> {
    void token;
    if (AgentExecutionController.captureOverlayHideDepth > 0) {
      AgentExecutionController.captureOverlayHideDepth -= 1;
    }
    if (AgentExecutionController.captureOverlayHideDepth > 0) {
      return;
    }
    if (!AgentExecutionController.captureOverlayHidden) {
      return;
    }
    AgentExecutionController.captureOverlayHidden = false;
    if (!AgentExecutionController.captureOverlayHandler) {
      return;
    }
    try {
      await AgentExecutionController.captureOverlayHandler(false);
    } catch (e) {
      AgentExecutionController.warn('capture overlay restore failed', e as Object);
    }
  }

  static returnToApp(): boolean {
    if (!AgentExecutionController.returnToAppHandler) {
      return false;
    }
    try {
      AgentExecutionController.returnToAppHandler();
      return true;
    } catch (e) {
      AgentExecutionController.warn('return-to-app handler failed', e as Object);
      return false;
    }
  }

  private static notifyFloatWindowSync(): void {
    try {
      AgentExecutionController.floatWindowSyncHandler?.();
    } catch (e) {
      AgentExecutionController.warn('float window sync handler failed', e as Object);
    }
  }

  private static notifyFloatPanelLayout(): void {
    try {
      AgentExecutionController.floatPanelLayoutHandler?.(AgentExecutionController.floatPanelExpanded);
    } catch (e) {
      AgentExecutionController.warn('float panel layout handler failed', e as Object);
    }
  }

  private static notifyFloatPanelMove(phase: string): void {
    try {
      AgentExecutionController.floatPanelMoveHandler?.(phase);
    } catch (e) {
      AgentExecutionController.warn('float panel move handler failed', e as Object);
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
