import localUnitTest from './LocalUnit.test';
import dataManagerUnitTest from './DataManagerUnit.test';
import workflowStorageUnitTest from './WorkflowStorageUnit.test';
import workflowDateContextUnitTest from './WorkflowDateContextUnit.test';
import mainTabConfigUnitTest from './MainTabConfigUnit.test';
import chatPageTypesUnitTest from './ChatPageTypesUnit.test';
import settingsCenterConfigUnitTest from './SettingsCenterConfigUnit.test';
import chatSessionStorageUnitTest from './ChatSessionStorageUnit.test';
import chatReactAgentUnitTest from './ChatReactAgentUnit.test';
import dataManagerQueryEventsToolUnitTest from './DataManagerQueryEventsToolUnit.test';
import appLoggerUnitTest from './AppLoggerUnit.test';
import avatarForegroundCropUnitTest from './AvatarForegroundCropUnit.test';

export default function testsuite() {
  localUnitTest();
  dataManagerUnitTest();
  workflowStorageUnitTest();
  workflowDateContextUnitTest();
  mainTabConfigUnitTest();
  chatPageTypesUnitTest();
  settingsCenterConfigUnitTest();
  chatSessionStorageUnitTest();
  chatReactAgentUnitTest();
  dataManagerQueryEventsToolUnitTest();
  appLoggerUnitTest();
  avatarForegroundCropUnitTest();
}
