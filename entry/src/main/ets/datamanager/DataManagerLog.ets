import { hilog } from '@kit.PerformanceAnalysisKit';

const DATA_MANAGER_LOG_DOMAIN: number = 0x0000;
const DATA_MANAGER_LOG_TAG: string = 'DataManager';

export function dataManagerInfo(message: string): void {
  hilog.info(DATA_MANAGER_LOG_DOMAIN, DATA_MANAGER_LOG_TAG, '%{public}s', message);
}

export function dataManagerWarn(message: string): void {
  hilog.warn(DATA_MANAGER_LOG_DOMAIN, DATA_MANAGER_LOG_TAG, '%{public}s', message);
}

export function dataManagerError(message: string): void {
  hilog.error(DATA_MANAGER_LOG_DOMAIN, DATA_MANAGER_LOG_TAG, '%{public}s', message);
}

