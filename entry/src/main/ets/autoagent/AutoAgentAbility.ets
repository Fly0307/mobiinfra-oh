import { AccessibilityExtensionAbility, AccessibilityEvent } from '@kit.AccessibilityKit';
import { AppLogger } from '../utils/AppLogger';

// 预留的无障碍扩展能力：当前 PC 侧主要通过 HDC/hmdriver2 执行动作，
// 这里保留 context 和事件日志，便于未来改为 App 内无障碍执行点击/滑动。
export default class AutoAgentAbility extends AccessibilityExtensionAbility {
  async onConnect() {
    AppLogger.info('AutoAgent', 'Accessibility Service Connected');
    // 在这里存储全局 context，便于主程序调用点击和滑动
    AppStorage.setOrCreate('agentContext', this.context);
  }

  onDisconnect() {
    AppLogger.info('AutoAgent', 'Accessibility Service Disconnected');
    AppStorage.delete('agentContext');
  }

  onAccessibilityEvent(accessibilityEvent: AccessibilityEvent) {
    // 监听页面发生变化，可用于等待新页面加载或者抓取最新树状结构
    AppLogger.info('AutoAgent', 'Received event: ' + JSON.stringify(accessibilityEvent));
  }
}
