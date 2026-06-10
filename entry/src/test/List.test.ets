import localUnitTest from './LocalUnit.test';
import dataManagerUnitTest from './DataManagerUnit.test';
import workflowStorageUnitTest from './WorkflowStorageUnit.test';
import workflowDateContextUnitTest from './WorkflowDateContextUnit.test';
import mainTabConfigUnitTest from './MainTabConfigUnit.test';

export default function testsuite() {
  localUnitTest();
  dataManagerUnitTest();
  workflowStorageUnitTest();
  workflowDateContextUnitTest();
  mainTabConfigUnitTest();
}
