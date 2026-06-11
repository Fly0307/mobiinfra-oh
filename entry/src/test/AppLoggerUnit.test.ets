import { describe, it, expect } from '@ohos/hypium';
import {
  AppLogStructuredCause,
  appLogCauseTextForTest,
  appLogMessageForTest
} from '../main/ets/utils/AppLogger';

export default function appLoggerUnitTest() {
  describe('appLoggerUnitTest', () => {
    it('formatsModuleMessageWithStablePrefix', 0, () => {
      expect(appLogMessageForTest(' Chat ', 'hello')).assertEqual('[MobiInfra][Chat] hello');
      expect(appLogMessageForTest('', 'hello')).assertEqual('[MobiInfra][App] hello');
    });

    it('formatsErrorCauseForLogMessages', 0, () => {
      let err = new Error('network failed');
      let businessError: AppLogStructuredCause = {
        code: 16000050,
        message: 'ability unavailable'
      };

      expect(appLogCauseTextForTest('request failed', err)).assertEqual('request failed: Error: network failed');
      expect(appLogCauseTextForTest('request failed', 'timeout')).assertEqual('request failed: timeout');
      expect(appLogCauseTextForTest('open failed', businessError))
        .assertEqual('open failed: code=16000050, message=ability unavailable');
    });
  });
}
