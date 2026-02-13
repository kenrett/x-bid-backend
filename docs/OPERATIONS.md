# Operational Runbook

## Diagnostics

### Verify Environment Configuration

To check the runtime environment (Database adapter, environment variables) without exposing secrets:

```bash
bin/rails diagnostics:env
```

This is safe to run in production.

## Credits Reconciliation

Use this to detect or repair drift between the ledger-derived balance and the materialized `bid_credits`.

```bash
bundle exec rake credits:reconcile_balances
```

To auto-fix and limit scope:

```bash
bundle exec rake credits:reconcile_balances FIX=true LIMIT=1000
```

You can also enqueue the job:

```ruby
CreditsReconcileBalancesJob.perform_later(fix: false, limit: 1000)
```

## Incident Response: Global Session Revoke

Use this emergency kill-switch when session replay risk is suspected (for example, uncertain subdomain ownership).

```bash
bundle exec rake auth:sessions:revoke_all ACTOR_EMAIL=<superadmin-email> REASON="suspected_cookie_replay"
```

Expected output includes:

- `sessions_revoked`
- `revoked_at`
- `actor_email`
- `triggered_by`

Optional signing secret rotation hook (recommended for confirmed cookie-signing compromise):

```bash
bundle exec rake auth:sessions:revoke_all ACTOR_EMAIL=<superadmin-email> REASON="confirmed_cookie_compromise" ROTATE_SIGNING_SECRETS=1
```

When `ROTATE_SIGNING_SECRETS=1`, output and audit logs include a rotation note:

- rotate `SECRET_KEY_BASE` in Render
- redeploy backend

This invalidates pre-rotation signed cookies and bearer JWTs in addition to DB-backed session token revocation.
