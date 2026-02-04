# biddersweet-mcp

biddersweet-mcp is a local MCP server that exposes repo-scoped navigation (search/read/list) and a small, allowlisted set of dev commands over stdio, returning structured JSON suitable for LLM agents while enforcing strict repo-root containment and safety guardrails.

## Install / build / run

```bash
npm install
npm run build
npm run start -- /path/to/repo
```

Watch mode:

```bash
npm run dev
```

You can also set the repo root via `BIDDERSWEET_REPO_ROOT`.

## Claude Desktop MCP config

Example `claude_desktop_config.json` snippet:

```json
{
  "mcpServers": {
    "biddersweet": {
      "command": "node",
      "args": [
        "/absolute/path/to/tools/biddersweet-mcp/dist/index.js",
        "/path/to/repo"
      ]
    }
  }
}
```

## Example tool invocations

`repo.info`:

```json
{
  "tool": "repo.info",
  "arguments": {}
}
```

Example output:

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

`repo.search`:

```json
{
  "tool": "repo.search",
  "arguments": { "query": "class User", "maxResults": 2 }
}
```

Example output:

```json
{
  "query": "class User",
  "results": [
    { "path": "app/models/user.rb", "lineNumber": 1, "preview": "class User", "column": 1 }
  ],
  "truncated": false
}
```

`repo.read_file`:

```json
{
  "tool": "repo.read_file",
  "arguments": { "path": "README.md" }
}
```

Example output:

```json
{
  "path": "README.md",
  "content": "# Example\n..."
}
```

`repo.list_dir`:

```json
{
  "tool": "repo.list_dir",
  "arguments": { "path": "config", "maxEntries": 10 }
}
```

Example output:

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

`dev.run_tests`:

```json
{
  "tool": "dev.run_tests",
  "arguments": { "target": "both" }
}
```

Example output:

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
