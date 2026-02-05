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
