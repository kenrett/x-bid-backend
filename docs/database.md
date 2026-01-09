# Database Configuration

## Source of Truth

The application relies on `ENV["DATABASE_URL"]` for the production database connection.

- **DATABASE_URL is environment-provided, not credentials.**
- `config/database.yml` in production simply reads this environment variable.

## Configuration

In production (Kamal), this is configured in `config/deploy.yml` to be injected from secrets.

### `config/deploy.yml`

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
```

## Preflight Verification

To confirm the application sees the database configuration without printing secrets to the logs, use the diagnostics task:

```bash
bundle exec rake diagnostics:env
```

### Expected Output

- `Rails.env`: production
- `DATABASE_URL present?`: true
- `DB adapter (ActiveRecord)`: postgresql

## Failure Mode

Production should fail fast if `DATABASE_URL` is missing. Ensure your deployment pipeline checks for this variable or that the application boot process raises an error if it is absent.