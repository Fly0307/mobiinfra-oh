import localUnitTest from './LocalUnit.test';
import dataManagerUnitTest from './DataManagerUnit.test';
import workflowStorageUnitTest from './WorkflowStorageUnit.test';
import workflowDateContextUnitTest from './WorkflowDateContextUnit.test';
import mainTabConfigUnitTest from './MainTabConfigUnit.test';
import chatPageTypesUnitTest from './ChatPageTypesUnit.test';
import settingsCenterConfigUnitTest from './SettingsCenterConfigUnit.test';
import chatSessionStorageUnitTest from './ChatSessionStorageUnit.test';
import chatContextBudgetUnitTest from './ChatContextBudgetUnit.test';
import chatReactAgentUnitTest from './ChatReactAgentUnit.test';
import dataManagerQueryEventsToolUnitTest from './DataManagerQueryEventsToolUnit.test';
import appLoggerUnitTest from './AppLoggerUnit.test';
import wechatAutoSummaryUnitTest from './WechatAutoSummaryUnit.test';
import avatarForegroundCropUnitTest from './AvatarForegroundCropUnit.test';
import markdownParserUnitTest from './MarkdownParserUnit.test';
import dateUtilsUnitTest from './DateUtilsUnit.test';

export default function testsuite() {
  localUnitTest();
  dataManagerUnitTest();
  workflowStorageUnitTest();
  workflowDateContextUnitTest();
  mainTabConfigUnitTest();
  chatPageTypesUnitTest();
  settingsCenterConfigUnitTest();
  chatSessionStorageUnitTest();
  chatContextBudgetUnitTest();
  chatReactAgentUnitTest();
  dataManagerQueryEventsToolUnitTest();
  appLoggerUnitTest();
  wechatAutoSummaryUnitTest();
  avatarForegroundCropUnitTest();
  markdownParserUnitTest();
  dateUtilsUnitTest();
}
