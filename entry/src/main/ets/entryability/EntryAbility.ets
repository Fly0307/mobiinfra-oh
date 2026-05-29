import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { AgentExecutionController } from '../utils/AgentExecutionController';

const DOMAIN = 0x0000;

// 应用主 Ability：加载 Index 页面，并在 Agent 执行期间协调后台浮窗、
// 长时任务权限和“从浮窗回到主应用”的能力。
export default class EntryAbility extends UIAbility {
  private floatWindow: window.Window | null = null;

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

  private createFloatWindow() {
    // 后台浮窗只承载实时状态和终止按钮，不负责模型推理或任务调度。
    if (this.floatWindow) {
      this.floatWindow.showWindow();
      return;
    }
    let config: window.Configuration = {
      name: 'MnnLlmChatFloatWindow',
      windowType: window.WindowType.TYPE_FLOAT,
      ctx: this.context
    };

    window.createWindow(config).then((win: window.Window) => {
      this.floatWindow = win;
      win.resize(430, 96);
      win.moveWindowTo(620, 1570);
      win.setUIContent('pages/FloatWindow', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load float window content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        win.showWindow();
        hilog.info(DOMAIN, 'testTag', 'Float window created and shown');
      });
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to create float window. Cause: ' + JSON.stringify(err));
    });
  }

  private destroyFloatWindow() {
    // 回到前台或任务结束后销毁浮窗，防止遮挡主界面。
    if (this.floatWindow) {
      this.floatWindow.destroyWindow().then(() => {
        hilog.info(DOMAIN, 'testTag', 'Float window destroyed');
        this.floatWindow = null;
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to destroy float window. Cause: ' + JSON.stringify(err));
      });
    }
  }
}
