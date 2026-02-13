# Production Hardening Checklist (Authoritative)

Use this checklist before every production deploy. It is tied to the current codebase and must be updated alongside code/config changes.

Authoritative references:
- CORS config: [config/initializers/cors.rb](../config/initializers/cors.rb)
- CORS allowlist source: [app/lib/frontend_origins.rb](../app/lib/frontend_origins.rb)
- Cookie + CSRF behavior: [app/controllers/application_controller.rb](../app/controllers/application_controller.rb) and [app/lib/cookie_domain_resolver.rb](../app/lib/cookie_domain_resolver.rb)
- CSRF cookie issuance: [app/controllers/api/v1/csrf_controller.rb](../app/controllers/api/v1/csrf_controller.rb)
- CSP + security headers: [config/initializers/security_headers.rb](../config/initializers/security_headers.rb)
- Stripe webhooks: [app/controllers/api/v1/stripe_webhooks_controller.rb](../app/controllers/api/v1/stripe_webhooks_controller.rb)
- Maintenance mode: [app/controllers/application_controller.rb](../app/controllers/application_controller.rb) and [app/controllers/api/v1/admin/maintenance_controller.rb](../app/controllers/api/v1/admin/maintenance_controller.rb)

## CORS (API + Cable)

Allowed origins (production always includes these):
- `https://biddersweet.app`
- `https://www.biddersweet.app`
- `https://afterdark.biddersweet.app`
- `https://marketplace.biddersweet.app`
- `https://account.biddersweet.app`

Dynamic allowlist sources (additive):
- `CORS_ALLOWED_ORIGINS` (comma-separated list)
- `FRONTEND_ORIGINS` (comma-separated list)
- `credentials.frontend_origins[production]` (Rails credentials)

Allowed headers (preflight):
- `Authorization` and `authorization`
- `Content-Type` and `content-type`
- `X-Requested-With`
- `X-CSRF-Token` and `x-csrf-token`
- `X-Request-Id` and `x-request-id`
- `X-Storefront-Key` and `x-storefront-key`
- `sentry-trace`
- `baggage`

Allowed methods:
- `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`

Credentials:
- `Access-Control-Allow-Credentials: true` (always set for allowed origins)

Checklist:
- [ ] Confirm `FrontendOrigins.allowed_origins` is correct for production deploy (no missing/extra origins).
- [ ] Confirm `CORS_ALLOWED_ORIGINS` / `FRONTEND_ORIGINS` are set only when intended.
- [ ] Confirm preflight headers list above matches `config/initializers/cors.rb`.
- [ ] Confirm `OPTIONS /api/*` and `OPTIONS /cable` return allow-origin + allow-credentials for each allowed origin.
- [ ] If adding a new origin, add it via `FRONTEND_ORIGINS` or credentials first; only add to `BIDDERSWEET_ORIGINS` for permanent first-party domains, then update tests in `test/requests/cors_credentials_test.rb` if needed.

## Cookies + CSRF

Cookie names:
- Browser session: `__Host-bs_session_id` (signed; primary HTTP and current ActionCable auth cookie)
- Cable session: `cable_session` (signed, path `/cable`; compatibility cookie)
- CSRF: `csrf_token` (signed)

Cookie attributes (as implemented):
- `HttpOnly: true` for session + CSRF cookies.
- Domain:
  - Session cookies are host-only (no `Domain` attribute).
  - During migration, legacy `bs_session_id` is explicitly expired with `Domain=.biddersweet.app`.
- SameSite:
  - Default: `Lax`.
  - Override: `SESSION_COOKIE_SAMESITE` or `COOKIE_SAMESITE` (`strict|lax`).
- Secure:
  - Session cookies are always `Secure`.
  - CSRF cookie is `Secure` in production.

CSRF strategy:
- `GET /api/v1/csrf` sets a signed `csrf_token` cookie (HttpOnly) and returns the token in JSON.
- For unsafe methods (`POST/PUT/PATCH/DELETE`) in browser cookie/origin contexts, requests must include `X-CSRF-Token` matching the signed cookie unless auth resolves via bearer.
- Failure response: `401` with `code: invalid_token` and `reason: csrf_failed`.

Checklist:
- [ ] Confirm `SESSION_COOKIE_SAMESITE` / `COOKIE_SAMESITE` are set intentionally (default is `Lax`).
- [ ] Validate CSRF flow: `GET /api/v1/csrf` then submit with `X-CSRF-Token` on unsafe requests.

## CSP + Security Headers (Backend API)

Policy source: `SecurityHeaders#static_headers` in `config/initializers/security_headers.rb`.

Current CSP (API responses + JSON responses):
- `default-src 'self'`
- `script-src 'self' https://js.stripe.com https://static.cloudflareinsights.com 'nonce-<random>'`
- `script-src-elem 'self' https://js.stripe.com https://static.cloudflareinsights.com 'nonce-<random>'`
- `connect-src 'self' https://cloudflareinsights.com https://api.biddersweet.app`
- `frame-ancestors 'none'`
- `base-uri 'none'`
- `form-action 'self'`

Additional headers:
- `Referrer-Policy: no-referrer`
- `Permissions-Policy: geolocation=(), microphone=(), camera=()`
- `X-Content-Type-Options: nosniff`
- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Resource-Policy: same-origin`
- `Strict-Transport-Security` only when `Rails.env.production?` and request is SSL

Checklist:
- [ ] Confirm CSP domains match actual production dependencies (Stripe, Cloudflare Insights, API origin).
- [ ] If adding a CSP dependency, update `SecurityHeaders#static_headers` and `test/middleware/security_headers_test.rb`.
- [ ] Confirm no CSP console errors after deploy (frontend + API calls).

## Debug Flags / Test-Only Code

Debug toggles currently in use:
- `AUTH_DEBUG_ENABLED`: enables `/api/v1/auth/debug` in any environment (default disabled).
- `DIAGNOSTICS_ENABLED`: enables `/api/v1/diagnostics/auth` in any environment (default disabled).
- `DEBUG_CSRF_PROBE=1`: adds `X-CSRF-Probe` + `X-CSRF-Cookie-Present` headers to `/api/v1/csrf`.

Checklist:
- [ ] Ensure `AUTH_DEBUG_ENABLED` is unset in production unless actively debugging.
- [ ] Ensure `DIAGNOSTICS_ENABLED` is unset in production unless actively debugging.
- [ ] Ensure `DEBUG_CSRF_PROBE` is unset in production.
- [ ] Audit before deploy: `rg "AUTH_DEBUG_ENABLED|DIAGNOSTICS_ENABLED|DEBUG_CSRF_PROBE"`.

## Secrets + Env Hygiene

Critical secrets and config (verify values exist and are correct):
- `SECRET_KEY_BASE` (JWT signing and Rails secrets)
- `DATABASE_URL`
- `REDIS_URL`
- `QUEUE_DATABASE_URL` (optional override)
- `FRONTEND_URL`
- `FRONTEND_WINS_URL` (optional override)
- `FRONTEND_ORIGINS` / `CORS_ALLOWED_ORIGINS` (only if overriding credentials)
- `SESSION_COOKIE_SAMESITE` / `COOKIE_SAMESITE`
- `SESSION_TOKEN_IDLE_TTL_MINUTES` (or legacy `SESSION_TOKEN_TTL_MINUTES`)
- `SESSION_TOKEN_ABSOLUTE_TTL_MINUTES`
- `SESSION_LAST_SEEN_DEBOUNCE_SECONDS`
- Stripe:
  - `STRIPE_WEBHOOK_SECRET` (webhook verification)
  - `credentials.stripe.secret_key` + `credentials.stripe.publishable_key` (via `RAILS_MASTER_KEY`)
- Active Storage S3:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
  - `S3_BUCKET`
  - `AWS_ENDPOINT` (optional)
  - `AWS_FORCE_PATH_STYLE` (optional)

Checklist:
- [ ] Confirm `RAILS_MASTER_KEY` is set on Render so Stripe credentials load.
- [ ] Confirm `STRIPE_WEBHOOK_SECRET` matches the Stripe webhook endpoint for production.
- [ ] Confirm S3 env vars exist on Render (if using S3 in production).
- [ ] Run `bin/rails diagnostics:env` (safe in production) to confirm env wiring.

## Payments Safety

Webhook verification and idempotency are mandatory. References:
- Webhook controller: `Api::V1::StripeWebhooksController`
- Money loop invariants: `docs/money-loop.md`
- Payment flow overview: `docs/payments.md`

Checklist:
- [ ] Confirm Stripe webhook signature verification succeeds (`STRIPE_WEBHOOK_SECRET` set).
- [ ] Confirm webhook events are idempotent (event replays do not double-apply credits).
- [ ] Confirm credit grants are idempotent by key (`CreditTransaction.idempotency_key` is unique).
- [ ] Confirm `stripe_event_id` is recorded for Stripe events (see `StripeEvent` + `Purchase` fields).
- [ ] Confirm reconciliation tooling is available: `bundle exec rake credits:reconcile_balances`.

## Maintenance Mode

Behavior:
- Non-allowed paths return `503` with `{ error: { code: "maintenance_mode" } }`.
- Always-allowed paths include `/up`, `/api/v1/health`, auth endpoints, `/api/v1/maintenance`, and Stripe webhooks.
- Admins bypass maintenance checks (validated via session token).

How to toggle:
- `GET /api/v1/admin/maintenance`
- `POST /api/v1/admin/maintenance?enabled=true|false` (superadmin only)
- `GET /api/v1/maintenance` (public status)

Checklist:
- [ ] Confirm maintenance mode toggles via admin endpoint.
- [ ] Confirm Stripe webhooks remain accepted during maintenance.
- [ ] Confirm admin bypass works for emergency access.

## Incident Basics (Auth + Payments)

Key signals and logs:
- `auth.failure` events (missing/invalid credentials, origin not allowed)
- `stripe.webhook.*` events (`verified`, `processed`, `process_failed`, `invalid_signature`)
- `maintenance.update` audit logs
- `X-Request-Id` header for log correlation

Checklist:
- [ ] Use Render logs for backend errors (filter by `request_id` or event name).
- [ ] Use Vercel deployment logs for frontend errors.
- [ ] Check Stripe dashboard for webhook delivery status + retries.
- [ ] If auth issues spike, verify CORS allowlist and cookie domain resolution.
- [ ] If payment issues spike, verify webhook signature errors and idempotency failures first.

Rollback steps (platform-specific):
- [ ] Render: rollback the backend service to the previous deploy.
- [ ] Vercel: promote the previous frontend deployment.
- [ ] Cloudflare: revert DNS/route changes if they were part of the deploy.

## Pre-Deploy Verification Steps

Smoke tests:
- [ ] Login (session cookie issued, `X-Request-Id` present).
- [ ] Place a bid (credits debit and auction updates).
- [ ] Purchase a bid pack (Stripe checkout + webhook applies credits).
- [ ] Admin actions (create bid pack, toggle maintenance, view payments).

CORS preflight check:
- [ ] `OPTIONS /api/v1/login` with `Origin: https://biddersweet.app` returns `Access-Control-Allow-Origin` and `Access-Control-Allow-Credentials: true`.
- [ ] `OPTIONS /cable` with the same origin returns allow headers + methods.

CSP console check:
- [ ] Open the SPA, load checkout, and confirm no CSP violations in the browser console.

Webhook test event validation:
- [ ] Trigger a Stripe test event (Stripe CLI or Dashboard) and confirm logs show `stripe.webhook.verified` and `stripe.webhook.processed`.
