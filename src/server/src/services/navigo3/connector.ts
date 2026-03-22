/**
 * Navigo3 DryAPI Connector
 *
 * Adapted from the native Navigo3 frontend ApiConnector (ApiConnector.ts).
 * Stripped to EXECUTE-only calls and extended with session lifecycle management
 * (login, logout, automatic re-authentication on 401).
 *
 * Protocol reference: Navigo3 API documentation — Authentication and Calling sections.
 * All calls go to POST /API/execute with header X-API-Session: <sessionId>.
 * DateTime values must use format "yyyy-MM-dd HH:mm:ss" — ISO 8601 is not accepted.
 */

import { v4 as generateUuid } from "uuid";
import { createLogger } from "../../utils/logger";

const logger = createLogger("Navigo3Connector");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ApiResponse {
  output?: unknown;
  status?: string;
}

export interface ApiResult {
  overallSuccess: boolean;
  responses: ApiResponse[];
}

export class Navigo3ApiError extends Error {
  constructor(
    public readonly method: string,
    public readonly status: string,
    message: string,
  ) {
    super(message);
    this.name = "Navigo3ApiError";
  }
}

// ---------------------------------------------------------------------------
// Connector
// ---------------------------------------------------------------------------

export class Navigo3Connector {
  private readonly executeUrl: string;
  private readonly loginUrl: string;
  private readonly logoutUrl: string;
  private readonly username: string;
  private readonly password: string;

  private sessionId: string | null = null;

  constructor(baseUrl: string, username: string, password: string) {
    const base = baseUrl.replace(/\/$/, "");
    this.executeUrl = `${base}/API/execute`;
    this.loginUrl = `${base}/API/login`;
    this.logoutUrl = `${base}/API/logout`;
    this.username = username;
    this.password = password;
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  async login(): Promise<void> {
    const response = await fetch(this.loginUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json;charset=utf-8" },
      body: JSON.stringify({ login: this.username, password: this.password }),
    });

    const json = (await response.json()) as {
      succeeded: boolean;
      sessionId?: string;
      problem?: string;
    };

    if (!json.succeeded || !json.sessionId) {
      throw new Error(
        `Navigo3 login failed: ${json.problem ?? "unknown error"}`,
      );
    }

    this.sessionId = json.sessionId;
    logger.info("Navigo3 session established");
  }

  async logout(): Promise<void> {
    if (!this.sessionId) return;

    try {
      await fetch(this.logoutUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json;charset=utf-8" },
        body: JSON.stringify({ sessionId: this.sessionId }),
      });
    } catch (err) {
      logger.warn("Navigo3 logout failed", { err });
    } finally {
      this.sessionId = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------------

  /**
   * Execute a single DryAPI method call.
   * On 401, re-authenticates once and retries before throwing.
   */
  async execute(method: string, input: unknown): Promise<unknown> {
    if (!this.sessionId) {
      await this.login();
    }

    try {
      return await this._execute(method, input);
    } catch (err) {
      if (err instanceof Response && err.status === 401) {
        logger.warn("Navigo3 session expired, re-authenticating");
        await this.login();
        return await this._execute(method, input);
      }
      throw err;
    }
  }

  private async _execute(method: string, input: unknown): Promise<unknown> {
    const body = {
      requests: [
        {
          qualifiedName: method,
          requestType: "EXECUTE",
          inputMappings: null,
          requestUuid: generateUuid(),
          input,
        },
      ],
    };

    const response = await fetch(
      `${this.executeUrl}?e=${encodeURIComponent(method)}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json;charset=utf-8",
          "X-API-Session": this.sessionId!,
        },
        body: JSON.stringify(body),
      },
    );

    if (response.status === 401) {
      throw response;
    }

    if (response.status !== 200 && response.status !== 400) {
      throw new Error(
        `Navigo3 HTTP error ${response.status} on method "${method}"`,
      );
    }

    const json = (await response.json()) as ApiResult;
    const resp = json.responses[0];

    if (!json.overallSuccess || !resp) {
      throw new Navigo3ApiError(
        method,
        resp?.status ?? "UNKNOWN",
        `Navigo3 method "${method}" failed with status: ${resp?.status ?? "UNKNOWN"}`,
      );
    }

    return resp.output;
  }
}
