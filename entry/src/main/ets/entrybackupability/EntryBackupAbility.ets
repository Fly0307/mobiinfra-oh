import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { AppLogger } from '../utils/AppLogger';

// 系统备份/恢复扩展的占位实现。当前项目状态主要在本地沙箱和 PersistentStorage，
// 这里仅记录生命周期，避免误以为有完整云备份逻辑。
export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    AppLogger.info('BackupAbility', 'onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    AppLogger.info('BackupAbility', 'onRestore ok ' + JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
