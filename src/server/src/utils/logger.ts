import { getConfig } from "../config";

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4,
}

export function createLogger(
  namespace: string,
  minLevel: LogLevel = LogLevel.INFO,
) {
  const shouldLog = (level: LogLevel) => level >= minLevel;

  return {
    debug: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.DEBUG) && getConfig().nodeEnv === "development") {
        console.log(`[${namespace}] DEBUG: ${message}`, ...args);
      }
    },
    info: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.INFO)) {
        console.log(`[${namespace}] ${message}`, ...args);
      }
    },
    warn: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.WARN)) {
        console.warn(`[${namespace}] WARN: ${message}`, ...args);
      }
    },
    error: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.ERROR)) {
        console.error(`[${namespace}] ERROR: ${message}`, ...args);
      }
    },
  };
}
