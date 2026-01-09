# 🔐 Production Secrets

X-Bid uses **Kamal** to inject secrets into the production environment.

## Required Secrets

The following secrets must be available to the machine running the deployment (e.g., your laptop or CI runner).

| Secret | Source | Description |
| :--- | :--- | :--- |
| `RAILS_MASTER_KEY` | `config/master.key` | Decrypts `config/credentials/production.yml.enc`. |
| `KAMAL_REGISTRY_PASSWORD` | `ENV` | Docker registry password (or Access Token). |
| `DATABASE_URL` | `ENV` | Production PostgreSQL connection string. |

## How to Set Secrets

Secrets are resolved via `.kamal/secrets`.

### 1. `RAILS_MASTER_KEY`
Reads from the local file `config/master.key`.
- **Do not commit this file.**
- Share it securely (1Password, LastPass) with the team.

### 2. `KAMAL_REGISTRY_PASSWORD`
Export this in your shell before deploying:

```bash
export KAMAL_REGISTRY_PASSWORD="your_docker_hub_token"
```

### 3. `DATABASE_URL`
Export the full connection string in your shell:

```bash
export DATABASE_URL="postgres://user:password@db-host:5432/x_bid_production"
```

## Verification

Before deploying, run the verification script to ensure Kamal can see all secrets:

```bash
chmod +x bin/verify-secrets
bin/verify-secrets
```

If this passes, `kamal deploy` will succeed in injecting them.