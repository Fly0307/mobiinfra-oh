import { AccessibilityExtensionAbility, AccessibilityEvent } from '@kit.AccessibilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export default class AutoAgentAbility extends AccessibilityExtensionAbility {
  async onConnect() {
    hilog.info(0x0000, 'AutoAgent', 'Accessibility Service Connected');
    // 在这里存储全局 context，便于主程序调用点击和滑动
    AppStorage.setOrCreate('agentContext', this.context);
  }

  onDisconnect() {
    hilog.info(0x0000, 'AutoAgent', 'Accessibility Service Disconnected');
    AppStorage.delete('agentContext');
  }

  onAccessibilityEvent(accessibilityEvent: AccessibilityEvent) {
    // 监听页面发生变化，可用于等待新页面加载或者抓取最新树状结构
    hilog.info(0x0000, 'AutoAgent', 'Received event: %{public}s', JSON.stringify(accessibilityEvent));
  }
}
