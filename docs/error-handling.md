# 🧯 Error Handling

This document explains **how errors are represented, returned, and logged in X-Bid**, covering:

- Error taxonomy
- Expected API error shapes
- When to raise vs return failure
- Logging expectations
- Client-visible vs internal errors

Debuggability is a design feature. Errors should be predictable, structured, and actionable — for both users and engineers.

## 🎯 High-Level Goals

This error-handling approach is designed to:

- Provide consistent error shapes to the frontend
- Make failures easy to debug via logs and correlation
- Avoid leaking sensitive information to clients
- Distinguish expected business failures from unexpected system failures
- Keep controllers thin by centralizing error translation

## 🧠 Core Principle

> Expected failures are part of product behavior. Unexpected failures are incidents.

Expected failures return structured `ServiceResult` failures.  
Unexpected failures raise and are handled by centralized exception handling.

## 🧾 Error Taxonomy

X-Bid errors fall into a small number of categories.

### 1) Authentication errors
Identity is missing or invalid.

Examples:
- Missing `Authorization` header
- Invalid/expired JWT
- SessionToken revoked/expired
- User disabled

HTTP:
- `401 Unauthorized`

Codes (examples):
- `unauthenticated`
- `invalid_token`
- `session_revoked`

### 2) Authorization errors
Identity is valid, but the user is not allowed to perform the action.

Examples:
- Non-admin calling `Admin::*` command
- Attempt to mutate privileged attributes via public path

HTTP:
- `403 Forbidden`

Codes (examples):
- `forbidden`
- `admin_required`

### 3) Validation errors (input)
Request input is malformed or fails validations.

Examples:
- Missing required fields
- Invalid enum value
- Bad pagination params

HTTP:
- `422 Unprocessable Entity` (preferred)
- `400 Bad Request` (only for syntactically invalid JSON / malformed params)

Codes (examples):
- `invalid_params`
- `validation_failed`

### 4) Business rule errors (domain)
Input is valid, but the action violates domain rules.

Examples:
- Auction already ended
- Insufficient credits
- Bid below minimum increment (if applicable)
- Purchase not allowed in current state

HTTP:
- `409 Conflict` (preferred for state conflicts)
- `422 Unprocessable Entity` (acceptable if you keep it simple)

Codes (examples):
- `auction_closed`
- `insufficient_credits`
- `invalid_state`

### 5) Not found errors
Requested resource does not exist or is not visible.

Examples:
- Auction id not found
- User id not found (admin tools)

HTTP:
- `404 Not Found`

Codes (examples):
- `not_found`

### 6) Rate limiting / abuse errors (optional)
The client is making too many requests.

HTTP:
- `429 Too Many Requests`

Codes (examples):
- `rate_limited`

### 7) System errors (unexpected)
Bugs, outages, and infrastructure failures.

Examples:
- Unhandled exception
- DB outage
- Stripe API down (if not handled gracefully)

HTTP:
- `500 Internal Server Error` (or `503` if you distinguish dependencies)

Codes (examples):
- `internal_error`
- `dependency_unavailable`

## 📦 Expected API Error Shapes

All error responses should share a predictable envelope.

### Standard error response (`render_error`)

Most API endpoints should use `render_error` (see `app/controllers/concerns/error_renderer.rb`), which returns:

```json
{
  "error_code": "forbidden",
  "message": "Admin privileges required"
}
```

Notes:
- `details` may be included when provided to `render_error`.
- Status `422` is normalized to `422 Unprocessable Content` in this app.

Common examples:
- `403` + `error_code=email_unverified` + `message="Email verification required"` (money/wallet-impacting actions)
  - Applies to `POST /api/v1/auctions/:auction_id/bids`, `POST /api/v1/checkouts`, `GET /api/v1/checkout/success`

### Legacy / non-`render_error` shapes

Some endpoints may still return ad-hoc error payloads (for example checkout flows returning `{ "status": "error", "error": "..." }`). Prefer standardizing to `render_error` for new work.
