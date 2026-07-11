import { describe, it, expect } from '@ohos/hypium';
import { AgentActionParser } from '../main/ets/utils/AgentActionParser';

interface SwipePayloadForTest {
  action?: string;
  start_x?: number;
  start_y?: number;
  end_x?: number;
  end_y?: number;
  direction?: string;
  width?: number;
  height?: number;
}

interface ClickPayloadForTest {
  action?: string;
  x?: number;
  y?: number;
}

export default function agentActionParserUnitTest() {
  describe('agentActionParserUnitTest', () => {
    it('repairsBareSwipeCoordinatePairFields', 0, () => {
      let raw = '{"reasoning":"scroll list","action":"swipe","parameters":{"direction":"UP",' +
        '"start_coords":500,788,"end_coords":500,180}}';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1000, 1000) as Object as SwipePayloadForTest;

      expect(parsed.action).assertEqual('swipe');
      expect(payload.action).assertEqual('swipe_with_coords');
      expect(payload.start_x).assertEqual(500);
      expect(payload.start_y).assertEqual(788);
      expect(payload.end_x).assertEqual(500);
      expect(payload.end_y).assertEqual(180);
    });

    it('fallsBackToDirectionalSwipeWhenExplicitSwipeStartsInUnsafeHeaderArea', 0, () => {
      let raw = '{"reasoning":"scroll to earlier month","action":"swipe","parameters":' +
        '{"direction":"DOWN","start_coords":[500,200],"end_coords":[500,800]}}';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1080, 2444) as Object as SwipePayloadForTest;

      expect(parsed.action).assertEqual('swipe');
      expect(payload.action).assertEqual('swipe');
      expect(payload.direction).assertEqual('DOWN');
      expect(payload.width).assertEqual(1080);
      expect(payload.height).assertEqual(2444);
      let diagnostic = AgentActionParser.getSwipeFallbackDiagnostic(parsed, 1080, 2444);
      expect(diagnostic).assertContain('start point is outside the safe vertical area');
      expect(diagnostic).assertContain('using direction-based swipe');
    });

    it('repairsBareClickBboxField', 0, () => {
      let raw = '{"action":"click","parameters":{"target_element":"confirm","bbox":100,200,300,400}}';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1000, 1000) as Object as ClickPayloadForTest;

      expect(parsed.action).assertEqual('click');
      expect(payload.action).assertEqual('click');
      expect(payload.x).assertEqual(200);
      expect(payload.y).assertEqual(300);
    });

    it('repairsCjkPunctuationBareBboxAndTruncatedJson', 0, () => {
      // 覆盖模型同时输出中文标点、裸 bbox 序列和截断 JSON 的组合容错。
      let raw = '{"action":"click"，"parameters":{"target_element":"confirm"，"bbox"：100，200，300，400';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1000, 1000) as Object as ClickPayloadForTest;

      expect(parsed.action).assertEqual('click');
      expect(payload.action).assertEqual('click');
      expect(payload.x).assertEqual(200);
      expect(payload.y).assertEqual(300);
    });

    it('repairsQuotedCjkTargetAndBareBboxWithExtraClosingBracket', 0, () => {
      let raw = '{"reasoning":"select province","action":"click","parameters":' +
        '{"target_element":"搜索结果中的"广东"选项","bbox":132,280,1000,319]}}';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1000, 1000) as Object as ClickPayloadForTest;

      expect(parsed.action).assertEqual('click');
      expect(payload.action).assertEqual('click');
      expect(payload.x).assertEqual(566);
      expect(payload.y).assertEqual(299);
    });

    it('repairsDuplicateColonBeforeStructuredBbox', 0, () => {
      let raw = '{"reasoning":"find Beijing","action":"click_input","parameters":' +
        '{"target_element":"顶部支持搜索城市／国家的输入框","text":"北京","bbox"::[26,209,975,262]}}';

      let parsed = AgentActionParser.parse(raw, true);
      let payload = AgentActionParser.buildHdcActionPayload(parsed, 1000, 1000) as Object as ClickPayloadForTest;

      expect(parsed.action).assertEqual('click_input');
      expect(payload.action).assertEqual('click_input');
      expect(payload.x).assertEqual(500);
      expect(payload.y).assertEqual(235);
    });
  });
}
