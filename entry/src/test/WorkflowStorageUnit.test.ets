import { describe, it, expect } from '@ohos/hypium';
import { WorkflowStorage } from '../main/ets/utils/WorkflowStorage';
import { WorkflowManagedFile } from '../main/ets/utils/WorkflowTypes';

export default function workflowStorageUnitTest() {
  describe('workflowStorageUnitTest', () => {
    it('sortManagedFilesForDisplayUsesLatestFilesFirst', 0, () => {
      let files: WorkflowManagedFile[] = [
        { name: 'b.md', path: '/tmp/b.md', size: 20, modifiedTime: 200 },
        { name: 'a.md', path: '/tmp/a.md', size: 10, modifiedTime: 200 },
        { name: 'c.md', path: '/tmp/c.md', size: 30, modifiedTime: 100 }
      ];

      let sorted = WorkflowStorage.sortManagedFilesForDisplay(files);

      expect(sorted[0].name).assertEqual('a.md');
      expect(sorted[1].name).assertEqual('b.md');
      expect(sorted[2].name).assertEqual('c.md');
    });
  });
}
