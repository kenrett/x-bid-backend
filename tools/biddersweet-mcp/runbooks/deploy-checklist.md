# Deploy Checklist

## Pre-Deploy
1. Confirm branch is green in CI.
2. Verify migrations are deploy-safe (no long locks or destructive changes).
3. Confirm required env vars are present:
   - `DATABASE_URL`
   - `SECRET_KEY_BASE`
   - Stripe credentials
4. Generate updated OpenAPI when contract changed:
   - `bundle exec rails openapi:generate`
5. Run local quality gates:
   - `bin/test`
   - `bin/lint`

## Deploy
1. Deploy backend service on Render.
2. Watch build logs for failures.
3. Confirm service comes up and health checks pass.

## Post-Deploy Validation
1. `GET /up` and `GET /api/v1/health` return success.
2. Smoke login/session, bid placement, and checkout.
3. Check error logs for elevated `5xx`, auth failures, and job errors.
4. If API contract changed, notify frontend owners and verify compatibility.

## Rollback Triggers
- Sustained `5xx` increase after deploy.
- Checkout/payment path regressions.
- Session/auth failures across storefronts.
