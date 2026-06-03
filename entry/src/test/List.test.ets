import localUnitTest from './LocalUnit.test';
import dataManagerUnitTest from './DataManagerUnit.test';
import workflowStorageUnitTest from './WorkflowStorageUnit.test';

export default function testsuite() {
  localUnitTest();
  dataManagerUnitTest();
  workflowStorageUnitTest();
}
