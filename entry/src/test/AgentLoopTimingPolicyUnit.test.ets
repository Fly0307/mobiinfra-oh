import { describe, expect, it } from '@ohos/hypium';
import {
  agentPostActionDelayMs,
  DEFAULT_AGENT_POST_ACTION_DELAY_MS,
  ELEME_AGENT_POST_ACTION_DELAY_MS,
  isElemeAgentTarget
} from '../main/ets/utils/AgentLoopTimingPolicy';

export default function agentLoopTimingPolicyUnitTest(): void {
  describe('agentLoopTimingPolicyUnitTest', () => {
    it('usesExtendedDelayForElemeTargets', 0, () => {
      expect(isElemeAgentTarget('饿了么', '')).assertTrue();
      expect(isElemeAgentTarget('', 'me.ele.eleme')).assertTrue();
      expect(isElemeAgentTarget('me.ele', '')).assertTrue();
      expect(agentPostActionDelayMs('饿了么', 'me.ele.eleme')).assertEqual(ELEME_AGENT_POST_ACTION_DELAY_MS);
    });

    it('keepsDefaultDelayForOtherTargets', 0, () => {
      expect(isElemeAgentTarget('微信', 'com.tencent.wechat')).assertFalse();
      expect(agentPostActionDelayMs('微信', 'com.tencent.wechat')).assertEqual(DEFAULT_AGENT_POST_ACTION_DELAY_MS);
    });

    it('normalizesPlannerTargetValues', 0, () => {
      expect(agentPostActionDelayMs(' ELEME ', '')).assertEqual(ELEME_AGENT_POST_ACTION_DELAY_MS);
      expect(agentPostActionDelayMs('', ' ME.ELE.ELEME ')).assertEqual(ELEME_AGENT_POST_ACTION_DELAY_MS);
    });
  });
}
