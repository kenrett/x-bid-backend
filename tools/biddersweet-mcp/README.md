# biddersweet-mcp

biddersweet-mcp is a local MCP server that provides repo-scoped navigation (search/read/list) plus a small, allowlisted set of dev commands over stdio. It always returns structured JSON suitable for LLM agents and enforces strict repo-root containment and safety guardrails.

## Quickstart

```bash
cd /Users/kenrettberg/projects/x-bid-backend/tools/biddersweet-mcp
npm install
npm run build
npm run start -- /Users/kenrettberg/projects/x-bid-backend
```

Watch mode:

```bash
cd /Users/kenrettberg/projects/x-bid-backend/tools/biddersweet-mcp
npm run dev
```

You can also set the repo root via `BIDDERSWEET_REPO_ROOT`.

## Safety knobs

### Capability mode

The server defaults to read-only tooling. Enable write tools explicitly via an env var:

```bash
MCP_CAPABILITY=READ_WRITE
```

Accepted values:
- `READ_ONLY` (default)
- `READ_WRITE`

In `READ_ONLY`, write tools (currently `repo.apply_patch`) return a structured error:

```json
{
  "error": {
    "code": "capability_denied",
    "message": "tool is not allowed in READ_ONLY mode",
    "details": { "tool": "repo.apply_patch", "mode": "READ_ONLY" }
  }
}
```

### Audit logging

Every tool invocation writes a JSONL entry to `.mcp-logs/tool.log` (one line per call). If the log file cannot be written, the entry is emitted to stderr. Each entry includes:
- `timestamp`
- `toolName`
- `argsSummary` (redacted)
- `durationMs`
- `resultSummary`
- `error` (when applicable)

Redaction rules (to avoid logging secrets):
- Keys containing `secret`, `token`, `password`, `api_key`, `access_key`, `private_key`, `session`, `cookie`, `authorization`, or `credential` are replaced with `[REDACTED]`.
- Large strings are truncated to 200 characters.
- Suspected secret-looking strings (long hex/base64 or PEM markers) are redacted.
- Patch contents and file contents are never logged, only byte sizes.

## VS Code (Codex) setup

Create `/.codex/config.toml` in the repo root:

```toml
[mcp_servers.biddersweet]
command = "node"
args = [
  "/Users/kenrettberg/projects/x-bid-backend/tools/biddersweet-mcp/dist/index.js",
  "/Users/kenrettberg/projects/x-bid-backend"
]
```

Reload VS Code (or restart the Codex extension) and ensure the project is trusted so the config is picked up.

## Troubleshooting

If you see `Missing script: "build"` or `Missing script: "start"`, it usually means you ran `npm` from the repo root instead of the MCP package directory. Always run commands from `tools/biddersweet-mcp` (or `cd` into it first).

If TypeScript reports missing `node:` modules or `process`/`Buffer` types, ensure dev dependencies are installed from this folder:

```bash
cd /Users/kenrettberg/projects/x-bid-backend/tools/biddersweet-mcp
npm install
```

## Claude Desktop MCP config

`claude_desktop_config.json` snippet (with the actual paths from this repo):

```json
{
  "mcpServers": {
    "biddersweet": {
      "command": "node",
      "args": [
        "/Users/kenrettberg/projects/x-bid-backend/tools/biddersweet-mcp/dist/index.js",
        "/Users/kenrettberg/projects/x-bid-backend"
      ]
    }
  }
}
```

## Tools and examples

### repo.info

Request:

```json
{
  "tool": "repo.info",
  "arguments": {}
}
```

Example response:

```json
{
  "repoRoot": ".",
  "railsPresent": true,
  "detectedLanguages": { "ruby": true, "js": true },
  "packageManager": "npm",
  "isGitRepo": true,
  "availableDevCommands": ["dev.run_tests", "dev.run_lint", "dev.check"]
}
```

### repo.search

Request:

```json
{
  "tool": "repo.search",
  "arguments": { "query": "class User", "maxResults": 2 }
}
```

Example response:

```json
{
  "query": "class User",
  "results": [
    { "path": "app/models/user.rb", "lineNumber": 1, "preview": "class User", "column": 1 }
  ],
  "truncated": false
}
```

### repo.read_file

Request:

```json
{
  "tool": "repo.read_file",
  "arguments": { "path": "README.md" }
}
```

Example response:

```json
{
  "path": "README.md",
  "content": "# Example\n..."
}
```

### repo.read_range

Request:

```json
{
  "tool": "repo.read_range",
  "arguments": { "path": "README.md", "startLine": 5, "endLine": 20 }
}
```

Example response:

```json
{
  "path": "README.md",
  "startLine": 5,
  "endLine": 20,
  "text": "Line 5\nLine 6\n...",
  "totalLines": 120,
  "truncated": false
}
```

Notes:
- If `startLine` is past the end of the file, the tool returns empty `text` with a warning.
- If `endLine` exceeds the file length, it is clamped to the last line and a warning is returned.
- Large ranges are truncated to a fixed cap and return `truncated: true` with a warning.

### repo.list_dir

Request:

```json
{
  "tool": "repo.list_dir",
  "arguments": { "path": "config", "maxEntries": 10 }
}
```

Example response:

```json
{
  "path": "config",
  "entries": [
    { "name": "application.rb", "type": "file" },
    { "name": "environments", "type": "dir" }
  ],
  "truncated": false
}
```

### repo.deps

Request:

```json
{
  "tool": "repo.deps",
  "arguments": {}
}
```

Example response:

```json
{
  "ruby": { "version": "3.2.2", "railsVersion": "7.1.2", "bundlerVersion": "2.4.10" },
  "node": { "version": "20.11.1", "packageManager": "pnpm", "workspaceType": "workspace" },
  "gems": { "top": [{ "name": "rails", "version": "~> 7.1.0" }], "hasGemfileLock": true },
  "js": { "dependenciesTop": [{ "name": "react", "versionRange": "^18.2.0" }], "scripts": { "test": "vitest" }, "hasLockfile": true },
  "filesChecked": ["Gemfile", "Gemfile.lock", "package.json", "package-lock.json"],
  "warnings": []
}
```

### repo.symbols

Request:

```json
{
  "tool": "repo.symbols",
  "arguments": { "glob": "app/**/*.rb", "kinds": ["class", "method"], "maxResults": 200 }
}
```

Example response:

```json
{
  "results": [
    { "name": "User", "kind": "class", "path": "app/models/user.rb", "line": 1, "language": "ruby" }
  ],
  "truncated": false,
  "strategy": "heuristic",
  "warnings": []
}
```

### repo.tree

Request:

```json
{
  "tool": "repo.tree",
  "arguments": { "path": ".", "maxDepth": 2, "maxNodes": 100, "maxEntriesPerDir": 50 }
}
```

Example response:

```json
{
  "path": ".",
  "maxDepth": 2,
  "nodesReturned": 12,
  "truncated": false,
  "tree": {
    "name": ".",
    "type": "dir",
    "children": [
      { "name": "app", "type": "dir" },
      { "name": "README.md", "type": "file" }
    ]
  }
}
```

Notes:
- Applies the same skip list as `repo.search` (e.g. `node_modules`, `dist`, `.git`).
- `maxDepth`, `maxNodes`, and `maxEntriesPerDir` enforce bounds and set `truncated: true` if exceeded.

### dev.run_tests

Request:

```json
{
  "tool": "dev.run_tests",
  "arguments": { "target": "both" }
}
```

Example response:

```json
{
  "ok": true,
  "results": {
    "ruby": {
      "ok": true,
      "exitCode": 0,
      "command": ["bundle", "exec", "rspec"],
      "stdout": "...",
      "stderr": "",
      "truncated": false,
      "truncatedBytes": 0,
      "durationMs": 1234
    },
    "js": {
      "ok": true,
      "exitCode": 0,
      "command": ["npm", "test"],
      "stdout": "...",
      "stderr": "",
      "truncated": false,
      "truncatedBytes": 0,
      "durationMs": 567
    }
  }
}
```

## Security constraints

- All filesystem paths are resolved against the repo root and rejected if they escape it or include `..` after normalization.
- Absolute paths are only allowed if they still resolve within the repo root.
- Files larger than 200KB are refused (no truncation), and binary files are refused using a null-byte heuristic.
- Dev commands run with `child_process.spawn` (no shell), are strictly allowlisted, have a 60s timeout (configurable), and cap combined stdout+stderr to 10KB with truncation metadata.
