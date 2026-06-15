import { AppLogger } from '../utils/AppLogger';

const DATA_MANAGER_LOG_MODULE: string = 'DataManager';
const DATA_MANAGER_LOGGER = AppLogger.forModule(DATA_MANAGER_LOG_MODULE);

export function dataManagerInfo(message: string): void {
  DATA_MANAGER_LOGGER.info(message);
}

export function dataManagerWarn(message: string): void {
  DATA_MANAGER_LOGGER.warn(message);
}

export function dataManagerError(message: string): void {
  DATA_MANAGER_LOGGER.error(message);
}
