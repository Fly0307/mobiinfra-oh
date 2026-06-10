import { AppLogger } from '../utils/AppLogger';

const DATA_MANAGER_LOG_MODULE: string = 'DataManager';

export function dataManagerInfo(message: string): void {
  AppLogger.info(DATA_MANAGER_LOG_MODULE, message);
}

export function dataManagerWarn(message: string): void {
  AppLogger.warn(DATA_MANAGER_LOG_MODULE, message);
}

export function dataManagerError(message: string): void {
  AppLogger.error(DATA_MANAGER_LOG_MODULE, message);
}
