import { getConfig } from "../config";

export function createLogger(namespace: string) {

return {
  info: (message: string, ...args: unknown[]) => console.log(`[${namespace}] ${message}`, ...args),
  error: (message: string, ...args: unknown[]) => console.error(`[${namespace}] ERROR: ${message}`, ...args),
  warn: (message: string, ...args: unknown[]) => console.warn(`[${namespace}] WARN: ${message}`, ...args),
  debug: (message: string, ...args: unknown[]) => {
    if (getConfig().nodeEnv === 'development') {
      console.log(`[${namespace}] DEBUG: ${message}`, ...args);
    }
  },
};
}

