import { describe, it, expect } from '@ohos/hypium';
import { AgentActionParser } from '../main/ets/utils/AgentActionParser';

interface SwipePayloadForTest {
  action?: string;
  start_x?: number;
  start_y?: number;
  end_x?: number;
  end_y?: number;
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
  });
}
