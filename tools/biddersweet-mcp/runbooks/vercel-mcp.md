# Vercel MCP in Codex

## Setup

1. Add server config (global):

```bash
codex mcp add vercel --url https://mcp.vercel.com
```

Equivalent `~/.codex/config.toml` entry:

```toml
[mcp_servers.vercel]
url = "https://mcp.vercel.com"
```

2. Authenticate with OAuth (no static token required):

```bash
codex mcp login vercel
```

3. Verify server is enabled:

```bash
codex mcp list
codex mcp get vercel
```

## Common tasks in Codex

Use natural-language requests in Codex once `vercel` is enabled, for example:

- "List recent Vercel deployments for project `<name>` and summarize failures."
- "Fetch build logs for deployment `<id>` and identify the first error."
- "Compare environment variables between preview and production for project `<name>` and show only key-name diffs."
- "Show latest production deployment health and rollback candidate."

## Safety notes

- Keep OAuth-based auth; do not hardcode Vercel API tokens in config files.
- Confirm destructive operations explicitly (env var changes, alias changes, rollback/promote actions).
- Follow least privilege: only request/read/update the project and environment scope needed.
- Redact secrets from outputs and logs; show key names and metadata, not secret values.
