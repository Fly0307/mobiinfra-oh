import { hdsEffect } from '@kit.UIDesignKit';

export function createEdgeFlowShaderController(): hdsEffect.ShaderEffectController {
  return new hdsEffect.ShaderEffectController();
}

export function buildTransparentEdgeFlowEffect(controller: hdsEffect.ShaderEffectController): VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .shaderEffect({
      effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
      animation: {
        duration: 4000,
        iterations: -1,
        autoPlay: true
      },
      controller: controller,
      params: {
        firstEdgeFlowLight: {
          startPos: 0,
          endPos: 0.55,
          color: '#1AD0F1'
        },
        secondEdgeFlowLight: {
          startPos: 0.5,
          endPos: -0.05,
          color: '#FFA4E5'
        }
      }
    })
    .buildEffect();
}
