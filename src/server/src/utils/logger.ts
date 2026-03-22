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
  const ts = () => new Date().toLocaleTimeString("en-GB");

  return {
    debug: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.DEBUG) && getConfig().nodeEnv === "development") {
        console.log(`[${ts()}] [${namespace}] DEBUG: ${message}`, ...args);
      }
    },
    info: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.INFO)) {
        console.log(`[${ts()}] [${namespace}] ${message}`, ...args);
      }
    },
    warn: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.WARN)) {
        console.warn(`[${ts()}] [${namespace}] WARN: ${message}`, ...args);
      }
    },
    error: (message: string, ...args: unknown[]) => {
      if (shouldLog(LogLevel.ERROR)) {
        console.error(`[${ts()}] [${namespace}] ERROR: ${message}`, ...args);
      }
    },
  };
}
