# Navigo3 API Reference

> Migrated from the Navigo3 instance API description page.

---

## Quick Start

A Python client library is available at [dry-apy-connector](https://pypi.org/project/dry-apy-connector/) for general Navigo3 API usage. For the Lighthouse integration, a native TypeScript connector is used instead — see `navigo3Connector.ts`.

---

## Introduction

Navigo3's architecture is a pure API server with a UI frontend. The API contains most of the business logic and is intended to remain stable as the frontend evolves. Some legacy parts of Navigo3 are written in XSLT/Java servlets and are being incrementally rewritten into the new model.

---

## Main Concepts

- The API handles: getting and listing data, updating/inserting/deleting data, validating data, UI settings, and security/authentication/authorization.
- There are three request types:
  - `EXECUTE` — full execution of a method
  - `VALIDATE` — validation only (e.g. on form field change)
  - `INPUT_FIELDS_SECURITY` — returns which fields the server will accept/return for the current user
- Each request batch is wrapped in a transaction. Everything is committed or nothing is.
- When the first request in a batch fails, the rest are not processed.
- Output from earlier requests in a batch can be mapped to the input of later ones via `inputMappings`. Useful for chained operations (e.g. create a project, then create a sub-delivery using the new project's ID).
- Each method has authorization checks for the calling user.
- API accounts (programmatic access) can be restricted to specific methods and source IP addresses.
- Some methods silently ignore portions of input or output depending on the user's rights. This is reported via `allowedInputFields` / `allowedOutputFields` in the response, which can drive form field visibility in UI clients.

---

## Authentication

### Login

Before calling any API method, a session must be established:

```
POST https://<instance>.navigo3.com/API/login
Content-Type: application/json;charset=utf-8

{ "login": "<username>", "password": "<password>" }
```

**Success (HTTP 200):**
```json
{ "succeeded": true, "sessionId": "ec2b4f90e7f4451e84e814a46b0db33e133761e16b1e499db694ca8e7be14470" }
```

**Failure (HTTP 400 / 401 / 500):**
```json
{ "succeeded": false, "problem": "Authorization failed" }
```

### Logout

Recommended on clean shutdown:

```
POST https://<instance>.navigo3.com/API/logout
Content-Type: application/json;charset=utf-8

{ "sessionId": "<sessionId>" }
```

**Success (HTTP 200):**
```json
{ "succeeded": true }
```

**Failure (HTTP 400 / 500):**
```json
{ "succeeded": false, "problem": "Please use 'content-type: application/json;charset=utf-8'" }
```

---

## Calling the API

All method calls go to:

```
POST https://<instance>.navigo3.com/API/execute
Content-Type: application/json;charset=utf-8
X-API-Session: <sessionId>
```

### HTTP Return Codes

| Code | Meaning |
|---|---|
| 200 | Batch fully processed without problems |
| 400 | One or more requests in the batch failed (controlled failure — response body contains details) |
| 401 | Not authenticated |
| 403 | Request from non-whitelisted IP address |
| 500 | Internal server error (corrupted JSON, network issue, etc.) |

For codes 200 and 400, the response body is `application/json;charset=utf-8` containing the full response structure. For codes 401, 403, and 500, only a plaintext error message is returned in production; full stack traces may be available on test instances.

### Request Structure

```json
{
  "requests": [
    {
      "qualifiedName": "firm/get",
      "requestType": "EXECUTE",
      "inputMappings": null,
      "requestUuid": "521d461b-61ad-4c0c-b6f4-a008445c9f12",
      "input": { "id": 4082 }
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `qualifiedName` | string | The method path, e.g. `attendance/embedded/start` |
| `requestType` | enum | `EXECUTE`, `VALIDATE`, or `INPUT_FIELDS_SECURITY` |
| `inputMappings` | null \| object | Output-to-input mapping for chained batch requests. `null` for independent calls. |
| `requestUuid` | string | Client-generated UUID v4. Used for tracing. |
| `input` | object | Method-specific input payload |

### Response Structure

```json
{
  "overallSuccess": true,
  "responses": [
    {
      "qualifiedName": "firm/get",
      "requestType": "EXECUTE",
      "requestUuid": "521d461b-61ad-4c0c-b6f4-a008445c9f12",
      "status": "SUCCESS",
      "output": { ... },
      "validation": null,
      "allowedInputFields": null,
      "allowedOutputFields": null,
      "errorMessage": null
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `overallSuccess` | boolean | `true` only if all requests in the batch succeeded |
| `status` | enum | See status values below |
| `output` | object \| null | Method return value. Present when `status` is `SUCCESS` and `requestType` is `EXECUTE`. |
| `validation` | object \| null | Validation result. Present when `requestType` is `VALIDATE`. Contains `items[]` with `message`, `severity` (`ERROR`/`WARNING`), and `path`. |
| `allowedInputFields` | object \| null | Field access map for `INPUT_FIELDS_SECURITY` requests. |
| `allowedOutputFields` | object \| null | Field access map for `INPUT_FIELDS_SECURITY` requests. |
| `errorMessage` | string \| null | Human-readable error detail on failure. |

### Response Status Values

| Status | Meaning |
|---|---|
| `SUCCESS` | Method executed successfully |
| `INVALID_INPUT` | Input failed validation |
| `MALFORMED_INPUT` | Input could not be parsed |
| `NOT_AUTHORIZED` | User lacks permission for this method |
| `NOT_FOUND` | Requested resource does not exist |
| `METHOD_NOT_ALLOWED` | Method name does not exist |
| `INTERNAL_ERROR_ON_EXECUTION` | Unhandled exception during execution |
| `INTERNAL_ERROR_ON_VALIDATION` | Unhandled exception during validation |
| `INTERNAL_ERROR_ON_SECURITY` | Unhandled exception during auth check |
| `INTERNAL_ERROR_ON_CLEARING_INPUT` | Internal serialization error on input |
| `INTERNAL_ERROR_ON_CLEARING_OUTPUT` | Internal serialization error on output |
| `NOT_PROCESSED_DUE_TO_PREVIOUS_ERRORS` | Skipped because an earlier request in the batch failed |

---

## Special Data Types

| Type | Format | Example |
|---|---|---|
| `DATE` | `yyyy-MM-dd` | `2026-03-22` |
| `DATETIME` | `yyyy-MM-dd HH:mm:ss` | `2026-03-22 09:45:00` |
| `TIME` | `HH:mm:ss` | `09:45:00` |

> ⚠️ ISO 8601 format is **not** accepted. The `T` separator and timezone offsets (e.g. `2026-03-22T09:45:00Z`) will be rejected.

---

## Extra Headers

| Header | Description |
|---|---|
| `X-API-Session` | Required on all `/API/execute` calls. Session ID obtained at login. |
| `X-Force-Currency-Id` | Optional. Overrides the currency associated with the authenticated user for this request. |

---

## Curl Examples

**Login:**
```bash
curl -s \
  -d '{"login":"$MYLOGIN", "password":"$MYPASSWORD"}' \
  -H "Content-Type:application/json;charset=utf-8" \
  -X POST https://mycompany.navigo3.com/API/login
```

**Execute a method:**
```bash
curl -s \
  --header "X-API-Session: mysessionid" \
  -H "Content-Type:application/json;charset=utf-8" \
  -d '{"requests":[{"qualifiedName":"firm/get","requestType":"EXECUTE","input":{"id":4082},"requestUuid":"521d461b-61ad-4c0c-b6f4-a008445c9f12"}]}' \
  -X POST https://mycompany.navigo3.com/API/execute
```

**Logout:**
```bash
curl -s \
  -d '{"sessionId": "mysessionid"}' \
  -H "Content-Type:application/json;charset=utf-8" \
  -X POST https://mycompany.navigo3.com/API/logout
```
