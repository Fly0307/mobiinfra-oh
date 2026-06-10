import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { AgentExecutionController } from '../utils/AgentExecutionController';

const DOMAIN = 0x0000;
const FLOAT_PANEL_COLLAPSED_WIDTH_VP = 88;
const FLOAT_PANEL_HEIGHT_VP = 72;
const FLOAT_PANEL_EXPANDED_WIDTH_RATIO = 0.84;
const FLOAT_PANEL_EXPANDED_MIN_WIDTH_VP = 300;
const FLOAT_PANEL_EXPANDED_SAFE_MARGIN_VP = 16;
const FLOAT_PANEL_RIGHT_MARGIN_VP = 12;
const FLOAT_PANEL_BOTTOM_MARGIN_VP = 100;
const DEFAULT_DISPLAY_WIDTH = 1080;
const DEFAULT_DISPLAY_HEIGHT = 2340;
const DEFAULT_DISPLAY_DENSITY = 3;
const FLOAT_PANEL_MOVE_THRESHOLD_PX = 8;

interface DisplaySize {
  width: number;
  height: number;
  density: number;
}

// 应用主 Ability：加载 Index 页面，并在 Agent 执行期间协调后台浮窗、
// 长时任务权限和“从浮窗回到主应用”的能力。
export default class EntryAbility extends UIAbility {
  private edgeFlowWindow: window.Window | null = null;
  private floatWindow: window.Window | null = null;
  private floatPanelX: number = 0;
  private floatPanelY: number = 0;
  private floatPanelWidth: number = 0;
  private floatPanelHeight: number = 0;
  private floatPanelHasCustomPosition: boolean = false;
  private floatPanelAnchorCenterX: number = 0;
  private floatPanelAnchorCenterY: number = 0;
  private floatPanelMoveStartX: number = 0;
  private floatPanelMoveStartY: number = 0;
  private floatPanelMoveStartWidth: number = 0;
  private floatPanelMoveStartHeight: number = 0;
  private floatPanelRectChangeCallback: ((options: window.RectChangeOptions) => void) | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // AgentExecutionController 统一管理本地/云端 Agent 的执行态、取消态和浮窗同步。
    AgentExecutionController.initialize();
    AgentExecutionController.setFloatWindowSyncHandler(() => {
      this.syncFloatWindow();
    });
    AgentExecutionController.setFloatPanelLayoutHandler((expanded: boolean) => {
      this.layoutFloatPanelWindow(expanded);
    });
    AgentExecutionController.setFloatPanelMoveHandler((phase: string) => {
      this.handleFloatPanelMove(phase);
    });
    AgentExecutionController.setCaptureOverlayHandler(async (hidden: boolean): Promise<boolean> => {
      return await this.handleCaptureOverlayVisibility(hidden);
    });
    AgentExecutionController.setReturnToAppHandler(() => {
      let wantInfo: Want = {
        bundleName: 'com.example.mnnllmchat',
        abilityName: 'EntryAbility'
      };
      this.context.startAbility(wantInfo).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to bring app to foreground. Cause: %{public}s', JSON.stringify(err));
      });
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    AgentExecutionController.setFloatWindowSyncHandler(null);
    AgentExecutionController.setFloatPanelLayoutHandler(null);
    AgentExecutionController.setFloatPanelMoveHandler(null);
    AgentExecutionController.setCaptureOverlayHandler(null);
    AgentExecutionController.setReturnToAppHandler(null);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.destroyFloatWindow();
    try {
      // 当应用回到前台，停止后台长时任务，省电
      backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
        hilog.info(DOMAIN, 'testTag', 'stopBackgroundRunning succeeded');
      }).catch((err: Error) => {
        hilog.info(DOMAIN, 'testTag', 'stopBackgroundRunning failed Cause: ' + JSON.stringify(err));
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'stopBackgroundRunning error');
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    this.syncFloatWindow();
    if (!AgentExecutionController.isExecutionActive()) {
      return;
    }
    try {
      // 配置 WantAgent，用于在通知栏显示后台任务并能点击回到应用
      let wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: "com.example.mnnllmchat",
            abilityName: "EntryAbility"
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj) => {
        // 当应用退到后台时，立刻向系统申请数据传输类的长时运行权限
        backgroundTaskManager.startBackgroundRunning(this.context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgentObj).then(() => {
          hilog.info(DOMAIN, 'testTag', 'startBackgroundRunning succeeded');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'startBackgroundRunning failed Cause: ' + JSON.stringify(err));
        });
      });
    } catch (error) {
      hilog.error(DOMAIN, 'testTag', 'startBackgroundRunning error Cause: ' + JSON.stringify(error));
    }
  }

  private syncFloatWindow(): void {
    // 只有 Agent 正在执行时才保留浮窗；普通后台状态不额外占用屏幕空间。
    if (AgentExecutionController.isExecutionActive()) {
      this.createFloatWindow();
      return;
    }
    this.destroyFloatWindow();
  }

  private async handleCaptureOverlayVisibility(hidden: boolean): Promise<boolean> {
    if (hidden) {
      if (!this.floatWindow) {
        return false;
      }
      try {
        // HarmonyOS Window 没有 hideWindow 接口。截图前只销毁可点击的执行状态面板，
        // 保留不可触摸的边缘流光层，避免面板内容进入截图并影响视觉识别。
        let win = this.floatWindow;
        this.syncFloatPanelWindowRect();
        this.unregisterFloatPanelRectChange();
        await win.destroyWindow();
        if (this.floatWindow === win) {
          this.floatWindow = null;
        }
        return true;
      } catch (err) {
        if (this.floatWindow) {
          this.registerFloatPanelRectChange(this.floatWindow);
        }
        hilog.error(DOMAIN, 'testTag', 'Failed to hide float window for capture. Cause: %{public}s',
          JSON.stringify(err));
        return false;
      }
    }

    if (!AgentExecutionController.isExecutionActive()) {
      return false;
    }
    if (!this.floatWindow) {
      // 截图后按原执行态重建状态面板，位置与展开态由已缓存的布局状态恢复。
      this.createFloatPanelWindow();
      return true;
    }
    try {
      this.layoutFloatPanelWindow(AgentExecutionController.isFloatPanelExpanded());
      await this.floatWindow.showWindow();
      return true;
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to restore float window after capture. Cause: %{public}s',
        JSON.stringify(err));
      return false;
    }
  }

  private getDisplaySize(): DisplaySize {
    try {
      let defaultDisplay = display.getDefaultDisplaySync();
      let density = defaultDisplay.densityPixels > 0 ? defaultDisplay.densityPixels : DEFAULT_DISPLAY_DENSITY;
      return {
        width: defaultDisplay.width,
        height: defaultDisplay.height,
        density: density
      };
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to get display size. Cause: %{public}s', JSON.stringify(err));
    }
    return {
      width: DEFAULT_DISPLAY_WIDTH,
      height: DEFAULT_DISPLAY_HEIGHT,
      density: DEFAULT_DISPLAY_DENSITY
    };
  }

  private createFloatWindow(): void {
    // 后台任务由两层悬浮窗组成：全屏不可触透明流光层 + 可点击的小型状态面板。
    this.createEdgeFlowWindow(() => {
      this.createFloatPanelWindow();
    });
  }

  private createEdgeFlowWindow(onReady: () => void): void {
    if (this.edgeFlowWindow) {
      try {
        this.edgeFlowWindow.showWindow();
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to show edge flow window. Cause: %{public}s', JSON.stringify(err));
      }
      onReady();
      return;
    }
    let config: window.Configuration = {
      name: 'MnnLlmChatEdgeFlowWindow',
      windowType: window.WindowType.TYPE_FLOAT,
      ctx: this.context
    };

    window.createWindow(config).then((win: window.Window) => {
      this.edgeFlowWindow = win;
      let displaySize = this.getDisplaySize();
      // 浮窗保持真实屏幕大小，流光的贴边压缩由 EdgeFlowWindow 内部的效果层完成。
      win.resize(displaySize.width, displaySize.height);
      win.moveWindowTo(0, 0);
      try {
        win.setWindowBackgroundColor('#00000000');
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to configure edge flow window. Cause: %{public}s', JSON.stringify(err));
      }
      win.setWindowTouchable(false).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to disable edge flow window touch. Cause: %{public}s',
          JSON.stringify(err));
      });
      win.setUIContent('pages/EdgeFlowWindow', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load edge flow window content. Cause: %{public}s',
            JSON.stringify(err));
          onReady();
          return;
        }
        win.showWindow();
        try {
          win.setWindowBackgroundColor('#00000000');
        } catch (error) {
          hilog.error(DOMAIN, 'testTag', 'Failed to keep edge flow window transparent. Cause: %{public}s',
            JSON.stringify(error));
        }
        onReady();
        hilog.info(DOMAIN, 'testTag', 'Transparent edge flow window created and shown');
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to create edge flow window. Cause: ' + JSON.stringify(err));
      onReady();
    });
  }

  private createFloatPanelWindow(): void {
    // 小型浮窗只承载实时状态和终止按钮，不负责模型推理或任务调度。
    if (this.floatWindow) {
      this.layoutFloatPanelWindow(AgentExecutionController.isFloatPanelExpanded());
      try {
        this.floatWindow.showWindow();
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to show float window. Cause: %{public}s', JSON.stringify(err));
      }
      return;
    }
    let config: window.Configuration = {
      name: 'MnnLlmChatFloatWindow',
      windowType: window.WindowType.TYPE_FLOAT,
      ctx: this.context
    };

    window.createWindow(config).then((win: window.Window) => {
      this.floatWindow = win;
      this.registerFloatPanelRectChange(win);
      this.layoutFloatPanelWindow(AgentExecutionController.isFloatPanelExpanded());
      try {
        win.setWindowBackgroundColor('#00000000');
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to configure float window background. Cause: %{public}s',
          JSON.stringify(err));
      }
      win.setUIContent('pages/FloatWindow', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load float window content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        win.showWindow();
        try {
          win.setWindowBackgroundColor('#00000000');
        } catch (error) {
          hilog.error(DOMAIN, 'testTag', 'Failed to keep float window transparent. Cause: %{public}s',
            JSON.stringify(error));
        }
        hilog.info(DOMAIN, 'testTag', 'Float window created and shown');
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to create float window. Cause: ' + JSON.stringify(err));
    });
  }

  private layoutFloatPanelWindow(expanded: boolean): void {
    if (!this.floatWindow) {
      return;
    }
    let displaySize = this.getDisplaySize();
    let panelWidth = expanded ? this.getExpandedFloatPanelWidth(displaySize) :
      this.vpToPx(FLOAT_PANEL_COLLAPSED_WIDTH_VP, displaySize.density);
    let panelHeight = this.vpToPx(FLOAT_PANEL_HEIGHT_VP, displaySize.density);
    this.floatPanelWidth = panelWidth;
    this.floatPanelHeight = panelHeight;
    if (this.floatPanelHasCustomPosition) {
      this.floatPanelX = this.clamp(Math.round(this.floatPanelAnchorCenterX - panelWidth / 2), 0,
        Math.max(0, displaySize.width - panelWidth));
      this.floatPanelY = this.clamp(Math.round(this.floatPanelAnchorCenterY - panelHeight / 2), 0,
        Math.max(0, displaySize.height - panelHeight));
    } else {
      this.floatPanelX = Math.max(0,
        displaySize.width - panelWidth - this.vpToPx(FLOAT_PANEL_RIGHT_MARGIN_VP, displaySize.density));
      this.floatPanelY = Math.max(0,
        displaySize.height - panelHeight - this.vpToPx(FLOAT_PANEL_BOTTOM_MARGIN_VP, displaySize.density));
    }
    try {
      this.floatWindow.resize(panelWidth, panelHeight);
      this.floatWindow.moveWindowTo(this.floatPanelX, this.floatPanelY);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to layout float window. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private getExpandedFloatPanelWidth(displaySize: DisplaySize): number {
    // window.resize 使用物理像素，ArkUI 内部使用 vp。展开态按屏幕比例计算，
    // 同时保留左右安全边距，避免全屏覆盖和固定宽度在不同设备上裁切。
    let collapsedWidth = this.vpToPx(FLOAT_PANEL_COLLAPSED_WIDTH_VP, displaySize.density);
    let safeMargin = this.vpToPx(FLOAT_PANEL_EXPANDED_SAFE_MARGIN_VP, displaySize.density);
    let availableWidth = Math.max(collapsedWidth, displaySize.width - safeMargin * 2);
    let minWidth = Math.min(this.vpToPx(FLOAT_PANEL_EXPANDED_MIN_WIDTH_VP, displaySize.density), availableWidth);
    let preferredWidth = Math.round(displaySize.width * FLOAT_PANEL_EXPANDED_WIDTH_RATIO);
    return Math.min(Math.max(preferredWidth, minWidth), availableWidth);
  }

  private handleFloatPanelMove(phase: string): void {
    if (!this.floatWindow) {
      return;
    }
    if (phase === 'start') {
      this.captureFloatPanelMoveStart();
      // 系统浮窗移动必须在触摸按下回调链路中调用 startMoving，组件 PanGesture 只会移动内部内容。
      this.floatWindow.startMoving().catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to start moving float window. Cause: %{public}s',
          JSON.stringify(err));
      });
      return;
    }
    this.syncFloatPanelWindowRect();
    if (this.hasFloatPanelMoved()) {
      this.floatPanelHasCustomPosition = true;
      this.updateFloatPanelAnchorFromCurrentRect();
    }
  }

  private syncFloatPanelWindowRect(): void {
    if (!this.floatWindow) {
      return;
    }
    try {
      let rect = this.floatWindow.getWindowProperties().windowRect;
      this.floatPanelX = rect.left;
      this.floatPanelY = rect.top;
      this.floatPanelWidth = rect.width;
      this.floatPanelHeight = rect.height;
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to sync float window rect. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private registerFloatPanelRectChange(win: window.Window): void {
    if (this.floatPanelRectChangeCallback) {
      return;
    }
    this.floatPanelRectChangeCallback = (options: window.RectChangeOptions) => {
      this.floatPanelX = options.rect.left;
      this.floatPanelY = options.rect.top;
      this.floatPanelWidth = options.rect.width;
      this.floatPanelHeight = options.rect.height;
    };
    try {
      win.on('windowRectChange', this.floatPanelRectChangeCallback);
    } catch (err) {
      this.floatPanelRectChangeCallback = null;
      hilog.error(DOMAIN, 'testTag', 'Failed to watch float window rect. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private unregisterFloatPanelRectChange(): void {
    if (!this.floatWindow || !this.floatPanelRectChangeCallback) {
      return;
    }
    try {
      this.floatWindow.off('windowRectChange', this.floatPanelRectChangeCallback);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to unwatch float window rect. Cause: %{public}s', JSON.stringify(err));
    }
    this.floatPanelRectChangeCallback = null;
  }

  private captureFloatPanelMoveStart(): void {
    this.syncFloatPanelWindowRect();
    this.floatPanelMoveStartX = this.floatPanelX;
    this.floatPanelMoveStartY = this.floatPanelY;
    this.floatPanelMoveStartWidth = this.floatPanelWidth;
    this.floatPanelMoveStartHeight = this.floatPanelHeight;
  }

  private hasFloatPanelMoved(): boolean {
    let sizeChanged = Math.abs(this.floatPanelWidth - this.floatPanelMoveStartWidth) > FLOAT_PANEL_MOVE_THRESHOLD_PX ||
      Math.abs(this.floatPanelHeight - this.floatPanelMoveStartHeight) > FLOAT_PANEL_MOVE_THRESHOLD_PX;
    if (sizeChanged) {
      return false;
    }
    let offsetX = Math.abs(this.floatPanelX - this.floatPanelMoveStartX);
    let offsetY = Math.abs(this.floatPanelY - this.floatPanelMoveStartY);
    return offsetX > FLOAT_PANEL_MOVE_THRESHOLD_PX || offsetY > FLOAT_PANEL_MOVE_THRESHOLD_PX;
  }

  private updateFloatPanelAnchorFromCurrentRect(): void {
    this.floatPanelAnchorCenterX = this.floatPanelX + this.floatPanelWidth / 2;
    this.floatPanelAnchorCenterY = this.floatPanelY + this.floatPanelHeight / 2;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private vpToPx(value: number, density: number): number {
    return Math.round(value * density);
  }

  private destroyFloatWindow() {
    // 回到前台或任务结束后销毁浮窗，防止遮挡主界面。
    if (this.floatWindow) {
      this.unregisterFloatPanelRectChange();
      this.floatWindow.destroyWindow().then(() => {
        hilog.info(DOMAIN, 'testTag', 'Float window destroyed');
        this.floatWindow = null;
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to destroy float window. Cause: ' + JSON.stringify(err));
      });
    }
    if (this.edgeFlowWindow) {
      this.edgeFlowWindow.destroyWindow().then(() => {
        hilog.info(DOMAIN, 'testTag', 'Edge flow window destroyed');
        this.edgeFlowWindow = null;
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to destroy edge flow window. Cause: ' + JSON.stringify(err));
      });
    }
  }
}
