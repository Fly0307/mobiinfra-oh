import { accessibility } from '@kit.AccessibilityKit';
import { AppLogger } from './AppLogger';

// 无障碍手势注入辅助类。部分 HarmonyOS SDK 对 GesturePath 的构造类型暴露不稳定，
// 所以这里通过 Reflect 动态访问，尽量绕开 ArkTS 严格类型校验带来的编译限制。
export class AccessibilityWrapper {
  static async injectGesture(accContext: Object, x1: number, y1: number, x2: number, y2: number, duration: number): Promise<boolean> {
    try {
      // 通过 Reflect 拿到构建方法和属性，避开 ArkTS 在新版由于系统安全隐藏部分对象字面量构造的限制
      let GesturePathClass = Reflect.get(globalThis as Object, 'accessibility_GesturePath') as Object;
      let path: Object;
      
      if (GesturePathClass) {
        // 如果系统顶层有暴露类
        path = Reflect.construct(GesturePathClass as Function, [x1, y1, x2, y2, duration]) as Object;
      } else {
        // 尝试用系统支持的反序列化或基础结构
        class FakeGesturePath {
          public startX: number = x1;
          public startY: number = y1;
          public endX: number = x2;
          public endY: number = y2;
          public duration: number = duration;
        }
        path = new FakeGesturePath();
      }
      
      let injectFunc = Reflect.get(accContext, 'injectGesture') as Function;
      if (injectFunc) {
        await Reflect.apply(injectFunc, accContext, [path]);
        return true;
      }
    } catch (e) {
      AppLogger.error('Accessibility', 'Dynamic gesture inject failed: ' + String(e));
    }
    return false;
  }
}
