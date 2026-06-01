import { hdsEffect } from '@kit.UIDesignKit';
import {
  buildTransparentEdgeFlowEffect,
  createEdgeFlowShaderController
} from '../components/HdsVisualComponent';

const EDGE_FLOW_OUTSET_SCALE = 1.10;

// Agent 执行期间的全屏透明流光浮窗。
// 使用不带背景蒙版的 DUAL_EDGE_FLOW_LIGHT，只绘制边缘光效，中心区域保持透明。
@Entry
@Component
struct EdgeFlowWindow {
  @State shaderController: hdsEffect.ShaderEffectController = createEdgeFlowShaderController()

  build() {
    Stack() {
      // 添加Column作为中间层，因为Blank只能作为Row/Column/Flex的子组件
      Column() {
        // 空内容承载 visualEffect，避免 HdsVisualComponent 的背景蒙版遮挡前台应用。
        Blank()
          .width('100%')
          .height('100%')
          // 将光效边界略微推出屏幕外，减少屏幕内可见光带宽度。
          .scale({ x: EDGE_FLOW_OUTSET_SCALE, y: EDGE_FLOW_OUTSET_SCALE, centerX: '50%', centerY: '50%' })
          .visualEffect(buildTransparentEdgeFlowEffect(this.shaderController))
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00000000')
    .hitTestBehavior(HitTestMode.None)
  }
}
