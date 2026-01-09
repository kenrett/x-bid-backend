# Operational Runbook

## Diagnostics

### Verify Environment Configuration

To check the runtime environment (Database adapter, environment variables) without exposing secrets:

```bash
bin/rails diagnostics:env
```

This is safe to run in production.