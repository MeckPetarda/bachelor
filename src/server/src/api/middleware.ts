import { Context, Next } from "hono";
import { createLogger } from "../utils/logger";

const logger = createLogger("API");

// JWT payload interface
export interface JWTPayload {
  sub: string;
  username: string;
  role: string;
  iat: number;
  exp: number;
}

// Extend Hono's context to include user info
declare module "hono" {
  interface ContextVariableMap {
    user: JWTPayload;
  }
}

/**
 * Request logging middleware
 * Logs all incoming requests with method, path, and response time
 */
export async function requestLogger(c: Context, next: Next) {
  const start = performance.now();
  const method = c.req.method;
  const path = c.req.path;

  logger.info(`→ ${method} ${path}`);

  await next();

  const duration = (performance.now() - start).toFixed(2);
  const status = c.res.status;

  logger.info(`← ${method} ${path} ${status} (${duration}ms)`);
}

/**
 * Error handling middleware
 * Catches errors and returns appropriate JSON responses
 */
export async function errorHandler(c: Context, next: Next) {
  try {
    await next();
  } catch (err) {
    const error = err as Error;
    logger.error(`Request error: ${error.message}`, error.stack);

    // Determine status code based on error type
    let status = 500;
    let message = "Internal Server Error";

    if (error.message.includes("not found") || error.message.includes("Not found")) {
      status = 404;
      message = error.message;
    } else if (error.message.includes("unauthorized") || error.message.includes("Unauthorized")) {
      status = 401;
      message = error.message;
    } else if (error.message.includes("forbidden") || error.message.includes("Forbidden")) {
      status = 403;
      message = error.message;
    } else if (error.message.includes("validation") || error.message.includes("invalid") || error.message.includes("Invalid")) {
      status = 400;
      message = error.message;
    }

    return c.json(
      {
        error: message,
        status,
        timestamp: new Date().toISOString(),
      },
      status as 400 | 401 | 403 | 404 | 500
    );
  }
}

/**
 * Decode and verify JWT token
 * Uses Bun's native crypto for HMAC verification
 */
async function verifyJWT(token: string, secret: string): Promise<JWTPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid token format");
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  // Verify signature using Bun's crypto
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );

  const data = encoder.encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlDecode(signatureB64);

  const isValid = await crypto.subtle.verify("HMAC", key, signature, data);
  if (!isValid) {
    throw new Error("Invalid token signature");
  }

  // Decode payload
  const payloadJson = atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/"));
  const payload = JSON.parse(payloadJson) as JWTPayload;

  // Check expiration
  if (payload.exp && payload.exp * 1000 < Date.now()) {
    throw new Error("Token has expired");
  }

  return payload;
}

/**
 * Create a JWT token
 */
export async function createJWT(
  payload: Omit<JWTPayload, "iat" | "exp">,
  secret: string,
  expiresIn = "24h"
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Parse expiresIn (e.g., "24h", "7d", "1h")
  let expiresInSeconds = 24 * 60 * 60; // default 24h
  const match = expiresIn.match(/^(\d+)([hdms])$/);
  if (match) {
    const value = parseInt(match[1], 10);
    const unit = match[2];
    switch (unit) {
      case "h": expiresInSeconds = value * 60 * 60; break;
      case "d": expiresInSeconds = value * 24 * 60 * 60; break;
      case "m": expiresInSeconds = value * 60; break;
      case "s": expiresInSeconds = value; break;
    }
  }

  const fullPayload: JWTPayload = {
    ...payload,
    iat: now,
    exp: now + expiresInSeconds,
  };

  const header = { alg: "HS256", typ: "JWT" };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(fullPayload));

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const data = encoder.encode(`${headerB64}.${payloadB64}`);
  const signature = await crypto.subtle.sign("HMAC", key, data);
  const signatureB64 = base64UrlEncode(String.fromCharCode(...new Uint8Array(signature)));

  return `${headerB64}.${payloadB64}.${signatureB64}`;
}

// Base64URL encoding/decoding helpers
function base64UrlEncode(str: string): string {
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  // Add padding if needed
  let padded = str.replace(/-/g, "+").replace(/_/g, "/");
  while (padded.length % 4) {
    padded += "=";
  }
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * JWT authentication middleware
 * Validates JWT token from Authorization header
 */
export function jwtAuth(secret: string) {
  return async (c: Context, next: Next) => {
    const authHeader = c.req.header("Authorization");

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return c.json(
        {
          error: "Unauthorized: Missing or invalid Authorization header",
          status: 401,
        },
        401
      );
    }

    const token = authHeader.slice(7);

    try {
      const payload = await verifyJWT(token, secret);
      c.set("user", payload);
      await next();
    } catch (err) {
      const error = err as Error;
      logger.warn(`JWT validation failed: ${error.message}`);
      return c.json(
        {
          error: `Unauthorized: ${error.message}`,
          status: 401,
        },
        401
      );
    }
  };
}
