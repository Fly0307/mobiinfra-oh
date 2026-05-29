import localUnitTest from './LocalUnit.test';
import dataManagerUnitTest from './DataManagerUnit.test';

export default function testsuite() {
  localUnitTest();
  dataManagerUnitTest();
}

