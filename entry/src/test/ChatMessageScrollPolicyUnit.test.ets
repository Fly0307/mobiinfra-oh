import { describe, it, expect } from '@ohos/hypium';
import {
  BOTTOM_SPACER_EXTRA_GAP_MAX,
  BOTTOM_SPACER_EXTRA_GAP_MIN,
  BOTTOM_SPACER_EXTRA_GAP_RATIO,
  chatBottomSpacerExtraGap,
  chatBottomOverlayKind,
  chatBottomSpacerIndex,
  chatLatestContentIndex,
  chatMessageListBottomSpacerHeight,
  chatStreamFollowTargetIndex,
  THINKING_OVERLAY_GAP,
  THINKING_OVERLAY_HEIGHT
} from '../main/ets/pages/chat/ChatMessageScrollPolicy';

export default function chatMessageScrollPolicyUnitTest() {
  describe('chatMessageScrollPolicyUnitTest', () => {
    it('keepsLatestContentIndexOnLastMessageWhenThinkingOverlayIsShown', 0, () => {
      expect(chatLatestContentIndex(0)).assertEqual(-1);
      expect(chatLatestContentIndex(1)).assertEqual(0);
      expect(chatLatestContentIndex(3)).assertEqual(2);
    });

    it('placesBottomSpacerAfterMessagesWithoutThinkingListItem', 0, () => {
      expect(chatBottomSpacerIndex(0)).assertEqual(0);
      expect(chatBottomSpacerIndex(1)).assertEqual(1);
      expect(chatBottomSpacerIndex(3)).assertEqual(3);
      expect(chatBottomSpacerIndex(-1)).assertEqual(0);
    });

    it('usesBottomSpacerAsStreamFollowTarget', 0, () => {
      expect(chatStreamFollowTargetIndex(0)).assertEqual(0);
      expect(chatStreamFollowTargetIndex(1)).assertEqual(1);
      expect(chatStreamFollowTargetIndex(3)).assertEqual(3);
    });

    it('prioritizesBackToBottomOverlayOverThinkingOverlay', 0, () => {
      expect(chatBottomOverlayKind(false, false)).assertEqual('none');
      expect(chatBottomOverlayKind(true, false)).assertEqual('thinking');
      expect(chatBottomOverlayKind(false, true)).assertEqual('back_to_bottom');
      expect(chatBottomOverlayKind(true, true)).assertEqual('back_to_bottom');
    });

    it('usesRelativeExtraBottomGapWithBounds', 0, () => {
      let normalInset = 122;
      let expectedNormal = Math.round(normalInset * BOTTOM_SPACER_EXTRA_GAP_RATIO);

      expect(chatBottomSpacerExtraGap(24)).assertEqual(BOTTOM_SPACER_EXTRA_GAP_MIN);
      expect(chatBottomSpacerExtraGap(normalInset)).assertEqual(expectedNormal);
      expect(chatBottomSpacerExtraGap(400)).assertEqual(BOTTOM_SPACER_EXTRA_GAP_MAX);
    });

    it('reservesCompactBottomSpaceWhenThinkingOverlayIsHidden', 0, () => {
      let bottomOverlayInset = 122;
      let expected = bottomOverlayInset + chatBottomSpacerExtraGap(bottomOverlayInset);

      expect(chatMessageListBottomSpacerHeight(bottomOverlayInset, false)).assertEqual(expected);
    });

    it('reservesThinkingOverlayOnlyWhenThinkingIsVisible', 0, () => {
      let bottomOverlayInset = 122;
      let expected = bottomOverlayInset + THINKING_OVERLAY_GAP + THINKING_OVERLAY_HEIGHT +
        chatBottomSpacerExtraGap(bottomOverlayInset);

      expect(chatMessageListBottomSpacerHeight(bottomOverlayInset, true)).assertEqual(expected);
    });

    it('clampsNegativeBottomInsetBeforeCalculatingSpacerHeight', 0, () => {
      let expectedIdle = chatBottomSpacerExtraGap(0);
      let expectedThinking = THINKING_OVERLAY_GAP + THINKING_OVERLAY_HEIGHT + chatBottomSpacerExtraGap(0);

      expect(chatMessageListBottomSpacerHeight(-24, false)).assertEqual(expectedIdle);
      expect(chatMessageListBottomSpacerHeight(-24, true)).assertEqual(expectedThinking);
    });
  });
}
