import { hilog } from '@kit.PerformanceAnalysisKit';

const APP_LOG_DOMAIN: number = 0x0000;
const APP_LOG_TAG: string = 'MobiInfra';
const APP_LOG_PREFIX: string = 'MobiInfra';

function formatMessage(moduleName: string, message: string): string {
  let normalizedModule = moduleName.trim();
  if (normalizedModule.length === 0) {
    normalizedModule = 'App';
  }
  return '[' + APP_LOG_PREFIX + '][' + normalizedModule + '] ' + message;
}

export class AppLogger {
  static debug(moduleName: string, message: string): void {
    hilog.debug(APP_LOG_DOMAIN, APP_LOG_TAG, '%{public}s', formatMessage(moduleName, message));
  }

  static info(moduleName: string, message: string): void {
    hilog.info(APP_LOG_DOMAIN, APP_LOG_TAG, '%{public}s', formatMessage(moduleName, message));
  }

  static warn(moduleName: string, message: string): void {
    hilog.warn(APP_LOG_DOMAIN, APP_LOG_TAG, '%{public}s', formatMessage(moduleName, message));
  }

  static error(moduleName: string, message: string): void {
    hilog.error(APP_LOG_DOMAIN, APP_LOG_TAG, '%{public}s', formatMessage(moduleName, message));
  }
}

export function appLogDebug(moduleName: string, message: string): void {
  AppLogger.debug(moduleName, message);
}

export function appLogInfo(moduleName: string, message: string): void {
  AppLogger.info(moduleName, message);
}

export function appLogWarn(moduleName: string, message: string): void {
  AppLogger.warn(moduleName, message);
}

export function appLogError(moduleName: string, message: string): void {
  AppLogger.error(moduleName, message);
}
