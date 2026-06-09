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

    it('workflowImageInputRecognizesBase64AndPath', 0, () => {
      let base64 = '/9j/4AAQSkZJRgABAQAAAQABAAD';
      expect(WorkflowStorage.workflowImageInputKind(base64)).assertEqual('base64');
      expect(WorkflowStorage.workflowImageInputKind('data:image/jpeg;base64,' + base64)).assertEqual('data_uri');
      expect(WorkflowStorage.workflowImageInputKind('/data/storage/el2/base/files/workflows/runs/demo/steps/1/screenshot.jpg'))
        .assertEqual('path');
      expect(WorkflowStorage.workflowImageInputKind('workflows/runs/demo/steps/1/screenshot.jpg')).assertEqual('path');
    });

    it('workflowScreenshotRelativePathUsesConcreteImageFile', 0, () => {
      let relative = WorkflowStorage.workflowRunRelativePath(
        '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files',
        '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files/workflows/runs/20260608-103333-basic-gui-task/steps/3/screenshot.jpg'
      );
      expect(relative).assertEqual('workflows/runs/20260608-103333-basic-gui-task/steps/3/screenshot.jpg');
      expect(relative.endsWith('/steps/3')).assertFalse();
    });

    it('runSummaryDeleteTargetUsesWholeRunDirectory', 0, () => {
      let filesDir = '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files';
      let file: WorkflowManagedFile = {
        name: '20260609-104256-basic-gui-task/run_summary.json',
        path: filesDir + '/workflows/runs/20260609-104256-basic-gui-task/run_summary.json',
        size: 128,
        modifiedTime: 0
      };

      expect(WorkflowStorage.managedFileDeleteTarget(filesDir, 'run', file))
        .assertEqual(filesDir + '/workflows/runs/20260609-104256-basic-gui-task');
    });

    it('rootConfigDeleteTargetKeepsSingleConfigFile', 0, () => {
      let filesDir = '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files';
      let file: WorkflowManagedFile = {
        name: 'default_ele_order.json',
        path: filesDir + '/workflows/configs/default_ele_order.json',
        size: 128,
        modifiedTime: 0
      };

      expect(WorkflowStorage.managedFileDeleteTarget(filesDir, 'config', file)).assertEqual(file.path);
    });
  });
}
