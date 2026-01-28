/**
 * Environment configuration for the attendance system server
 */

interface Config {
  database: {
    url: string;
  };
  jwt: {
    secret: string;
    expiresIn: string;
  };
  mqtt: {
    port: number;
  };
  http: {
    port: number;
  };
  retention: {
    healthRetentionDays: number;
    connectionRetentionDays: number;
  };
  nodeEnv: 'development' | 'production' | 'test';
}

function getEnvVar(name: string, defaultValue?: string): string {
  const value = process.env[name] ?? defaultValue;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getEnvVarAsInt(name: string, defaultValue?: number): number {
  const value = process.env[name];
  if (value === undefined) {
    if (defaultValue !== undefined) {
      return defaultValue;
    }
    throw new Error(`Missing required environment variable: ${name}`);
  }
  const parsed = parseInt(value, 10);
  if (isNaN(parsed)) {
    throw new Error(`Environment variable ${name} must be a valid integer`);
  }
  return parsed;
}

export function loadConfig(): Config {
  return {
    database: {
      url: getEnvVar('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5432/attendance'),
    },
    jwt: {
      secret: getEnvVar('JWT_SECRET', 'dev-secret-change-in-production'),
      expiresIn: getEnvVar('JWT_EXPIRES_IN', '24h'),
    },
    mqtt: {
      port: getEnvVarAsInt('MQTT_PORT', 1883),
    },
    http: {
      port: getEnvVarAsInt('HTTP_PORT', 3000),
    },
    retention: {
      healthRetentionDays: getEnvVarAsInt('HEALTH_RETENTION_DAYS', 7),
      connectionRetentionDays: getEnvVarAsInt('CONNECTION_RETENTION_DAYS', 30),
    },
    nodeEnv: (getEnvVar('NODE_ENV', 'development') as Config['nodeEnv']),
  };
}

// Singleton config instance
let configInstance: Config | null = null;

export function getConfig(): Config {
  if (!configInstance) {
    configInstance = loadConfig();
  }
  return configInstance;
}

export type { Config };
