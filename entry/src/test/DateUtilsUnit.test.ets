import { describe, it, expect } from '@ohos/hypium';
import {
  formatLocalDateKey,
  localWeekdayLabel,
  weekRangeTextFromDate,
  weekdayLabelFromDate
} from '../main/ets/utils/DateUtils';
import { weekdayLabelFromDate as dataManagerWeekdayLabelFromDate } from '../main/ets/datamanager/DataManagerUtils';

export default function dateUtilsUnitTest() {
  describe('dateUtilsUnitTest', () => {
    it('formatsLocalDateAndWeekday', 0, () => {
      let date = new Date(2026, 5, 18);

      expect(formatLocalDateKey(date)).assertEqual('2026-06-18');
      expect(localWeekdayLabel(date)).assertEqual('星期四');
      expect(weekdayLabelFromDate('2026-06-18')).assertEqual('星期四');
      expect(weekdayLabelFromDate('2026-02-31')).assertEqual('');
      expect(dataManagerWeekdayLabelFromDate('2026-06-18')).assertEqual('星期四');
    });

    it('formatsMondayToSundayWeekRange', 0, () => {
      expect(weekRangeTextFromDate(new Date(2026, 5, 15))).assertEqual('2026-06-15 至 2026-06-21');
      expect(weekRangeTextFromDate(new Date(2026, 5, 18))).assertEqual('2026-06-15 至 2026-06-21');
      expect(weekRangeTextFromDate(new Date(2026, 5, 21))).assertEqual('2026-06-15 至 2026-06-21');
    });
  });
}
