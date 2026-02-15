import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const toolRoot = path.resolve(__dirname, "..");
const distEntry = path.join(toolRoot, "dist", "index.js");

let repoRoot = "";
let client;
let gitAvailable = false;
let renderSnapshotRelPath = "render-snapshot.json";
const execFileAsync = promisify(execFile);

async function callTool(name, args) {
  return callToolWithClient(client, name, args);
}

async function callToolWithClient(targetClient, name, args) {
  const result = await targetClient.callTool({ name, arguments: args });
  const text = result.content?.[0]?.text ?? "";
  const payload = text ? JSON.parse(text) : null;
  return { result, payload };
}

async function createClient(env) {
  const transport = new StdioClientTransport({
    command: "node",
    args: [distEntry, repoRoot],
    cwd: toolRoot,
    stderr: "pipe",
    env
  });

  const newClient = new Client({ name: "mcp-tests", version: "0.0.0" });
  await newClient.connect(transport);
  return { client: newClient, transport };
}

async function waitForAuditEntry(toolName, attempts = 10) {
  const logPath = path.join(repoRoot, ".mcp-logs", "tool.log");
  for (let i = 0; i < attempts; i += 1) {
    try {
      const content = await fs.readFile(logPath, "utf8");
      const lines = content.split("\n").filter(Boolean);
      const matching = lines.filter((line) => {
        try {
          const parsed = JSON.parse(line);
          return parsed.toolName === toolName;
        } catch {
          return false;
        }
      });
      if (matching.length > 0) {
        const line = matching[matching.length - 1];
        return { line, entry: JSON.parse(line) };
      }
    } catch {
      // ignore and retry
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`audit log entry not found for ${toolName}`);
}

before(async () => {
  repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "biddersweet-mcp-test-"));
  await fs.mkdir(path.join(repoRoot, "docs"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "subdir"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "app", "models"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "src"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "config"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "config", "env"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "db"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "docs", "api"), { recursive: true });

  await fs.writeFile(path.join(repoRoot, "docs", "search.txt"), "alpha\nneedle beta\ngamma\n");
  await fs.writeFile(path.join(repoRoot, "file.txt"), "one\ntwo\nthree\nfour");
  await fs.writeFile(path.join(repoRoot, "empty.txt"), "");
  await fs.writeFile(path.join(repoRoot, "subdir", "child.txt"), "child");
  await fs.writeFile(path.join(repoRoot, "binary.bin"), Buffer.from([0, 1, 2, 3]));

  const largeLines = Array.from({ length: 500 }, (_, i) => `line ${i + 1}`).join("\n");
  await fs.writeFile(path.join(repoRoot, "large.txt"), largeLines);
  await fs.mkdir(path.join(repoRoot, "node_modules"), { recursive: true });
  await fs.writeFile(path.join(repoRoot, "node_modules", "ignored.txt"), "ignore");
  await fs.writeFile(
    path.join(repoRoot, "app", "models", "user.rb"),
    [
      "class User < ApplicationRecord",
      "  belongs_to :account",
      "  has_many :bids",
      "  validates :email, presence: true, uniqueness: true",
      "  def name",
      "    \"Test\"",
      "  end",
      "end"
    ].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "app", "models", "account.rb"),
    ["class Account < ApplicationRecord", "  has_many :users", "end"].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "src", "app.ts"),
    ["export function greet() {}", "export type Person = { name: string }", "const local = () => {}"].join(
      "\n"
    )
  );
  await fs.writeFile(
    path.join(repoRoot, "src", "refs.ts"),
    [
      "export const targetSymbol = 1;",
      "export function useTargetSymbol() { return targetSymbol; }",
      "const local = targetSymbol + 1;",
      "export const another = targetSymbol;",
      "console.log(targetSymbol);"
    ].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "src", "todos.ts"),
    [
      "// TODO: handle paging",
      "// FIXME: recover on timeout",
      "// NOTE: remove after migration"
    ].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "src", "patch.txt"),
    ["alpha", "beta", "gamma"].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "src", "apply.txt"),
    ["first", "second", "third"].join("\n")
  );
  await fs.writeFile(path.join(repoRoot, ".env"), "SECRET=1\n");
  await fs.writeFile(path.join(repoRoot, ".env.local"), "API_TOKEN=needle-local\n");
  await fs.writeFile(path.join(repoRoot, "id_rsa"), "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n");
  await fs.writeFile(path.join(repoRoot, "tls-cert.pem"), "-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----\n");
  await fs.writeFile(path.join(repoRoot, "config", "master.key"), "local-master-key\n");
  await fs.writeFile(
    path.join(repoRoot, "config", "routes.rb"),
    [
      "Rails.application.routes.draw do",
      "  root \"home#index\"",
      "  get \"/health\", to: \"health#show\"",
      "  namespace :admin do",
      "    resources :users, only: [:index, :show]",
      "  end",
      "  resource :profile",
      "end"
    ].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "docs", "api", "openapi.json"),
    JSON.stringify(
      {
        openapi: "3.0.3",
        info: { title: "x-bid test", version: "1.0.0" },
        paths: {
          "/": { get: { responses: { "200": { description: "ok" } } } },
          "/health": { get: { responses: { "200": { description: "ok" } } } },
          "/admin/users": { get: { responses: { "200": { description: "ok" } } } }
        }
      },
      null,
      2
    )
  );
  await fs.mkdir(path.join(repoRoot, "tools", "biddersweet-mcp", "runbooks"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "tools", "biddersweet-mcp", "contracts"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "tools", "biddersweet-mcp", "maps"), { recursive: true });
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "runbooks", "incident-triage.md"),
    "# Incident Triage Runbook\n\nMinimal triage guidance.\n"
  );
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "runbooks", "deploy-checklist.md"),
    "# Deploy Checklist\n\nMinimal deploy guidance.\n"
  );
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "contracts", "auth-session.md"),
    "# Auth Session Contract\n\nSession contract.\n"
  );
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "contracts", "storefront-routing.md"),
    "# Storefront Routing Contract\n\nRouting contract.\n"
  );
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "maps", "services.render.json"),
    JSON.stringify({ services: [{ name: "x-bid-backend-api", id: "srv-backend", url: "https://x-bid-backend.onrender.com" }] })
  );
  await fs.writeFile(
    path.join(repoRoot, "tools", "biddersweet-mcp", "maps", "apps.vercel.json"),
    JSON.stringify({ projects: [{ name: "x-bid-frontend", project: "x-bid-frontend", domains: ["https://biddersweet.app"] }] })
  );
  await fs.writeFile(
    path.join(repoRoot, "config", "env", "source.env.keys"),
    ["DATABASE_URL=", "REDIS_URL=", "SECRET_KEY_BASE=", "STRIPE_API_KEY="].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "config", "env", "target.env.keys"),
    ["DATABASE_URL=", "REDIS_URL=", "SECRET_KEY_BASE=", "FEATURE_FLAG_X="].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "db", "schema.rb"),
    [
      "ActiveRecord::Schema[7.1].define(version: 20250924213845) do",
      "  create_table \"accounts\", force: :cascade do |t|",
      "    t.string \"name\", null: false",
      "    t.datetime \"created_at\", null: false",
      "  end",
      "",
      "  create_table \"users\", force: :cascade do |t|",
      "    t.string \"email\", default: \"\", null: false",
      "    t.bigint \"account_id\", null: false",
      "    t.index [\"account_id\"], name: \"index_users_on_account_id\"",
      "  end",
      "",
      "  add_index \"users\", [\"email\"], name: \"index_users_on_email\", unique: true",
      "  add_foreign_key \"users\", \"accounts\", column: \"account_id\"",
      "end"
    ].join("\n")
  );

  await fs.writeFile(path.join(repoRoot, ".ruby-version"), "3.2.2\n");
  await fs.writeFile(
    path.join(repoRoot, "Gemfile"),
    'source "https://rubygems.org"\ngem "rails", "~> 7.1.0"\ngem "pg"\n'
  );
  await fs.writeFile(
    path.join(repoRoot, "Gemfile.lock"),
    [
      "GEM",
      "  remote: https://rubygems.org/",
      "  specs:",
      "    pg (1.5.4)",
      "    rails (7.1.2)",
      "",
      "PLATFORMS",
      "  ruby",
      "",
      "DEPENDENCIES",
      "  pg",
      "  rails (~> 7.1.0)",
      "",
      "BUNDLED WITH",
      "   2.4.10"
    ].join("\n")
  );
  await fs.writeFile(path.join(repoRoot, ".node-version"), "20.11.1\n");
  await fs.writeFile(
    path.join(repoRoot, "package.json"),
    JSON.stringify(
      {
        name: "test-repo",
        private: true,
        packageManager: "pnpm@8.15.0",
        workspaces: ["packages/*"],
        scripts: { test: "vitest" },
        dependencies: { react: "^18.2.0" },
        devDependencies: { vitest: "^1.2.0" }
      },
      null,
      2
    )
  );
  await fs.writeFile(path.join(repoRoot, "package-lock.json"), "{}");
  await fs.writeFile(
    path.join(repoRoot, "tsconfig.json"),
    JSON.stringify(
      {
        compilerOptions: {
          baseUrl: ".",
          paths: {
            "@/*": ["src/*"]
          }
        },
        references: [{ path: "./packages/core" }, { path: "./packages/web" }]
      },
      null,
      2
    )
  );
  await fs.writeFile(
    path.join(repoRoot, "vite.config.ts"),
    [
      "import { defineConfig } from \"vite\";",
      "import react from \"@vitejs/plugin-react\";",
      "",
      "export default defineConfig({",
      "  plugins: [react()],",
      "  resolve: {",
      "    alias: {",
      "      \"@\": \"/src\"",
      "    }",
      "  }",
      "});"
    ].join("\n")
  );
  await fs.writeFile(
    path.join(repoRoot, "eslint.config.js"),
    [
      "export default [",
      "  {",
      "    extends: [\"eslint:recommended\", \"plugin:react/recommended\"]",
      "  }",
      "];"
    ].join("\n")
  );
  const now = Date.now();
  await fs.writeFile(
    path.join(repoRoot, renderSnapshotRelPath),
    JSON.stringify(
      {
        services: [{ id: "srv-backend", name: "x-bid-backend-api", url: "https://x-bid-backend.onrender.com" }],
        logsByServiceId: {
          "srv-backend": [
            {
              timestamp: new Date(now - 9 * 60_000).toISOString(),
              level: "error",
              message: "NoMethodError: undefined method `foo' for nil:NilClass\napp/services/payments/charge.rb:42:in `call'",
              path: "/api/v1/checkouts",
              statusCode: 500,
              requestId: "req-1"
            },
            {
              timestamp: new Date(now - 8 * 60_000).toISOString(),
              level: "error",
              message: "NoMethodError: undefined method `foo' for nil:NilClass\napp/services/payments/charge.rb:42:in `call'",
              path: "/api/v1/checkouts",
              statusCode: 500,
              requestId: "req-2"
            }
          ]
        },
        metricsByServiceId: {
          "srv-backend": [
            {
              metricType: "http_latency_p95",
              points: [
                { timestamp: new Date(now - 10 * 60_000).toISOString(), value: 120 },
                { timestamp: new Date(now - 5 * 60_000).toISOString(), value: 340 }
              ]
            },
            {
              metricType: "cpu_usage",
              points: [{ timestamp: new Date(now - 5 * 60_000).toISOString(), value: 68.3 }]
            }
          ]
        },
        deploysByServiceId: {
          "srv-backend": [{ id: "dep-1", startedAt: new Date(now - 12 * 60_000).toISOString(), status: "live" }]
        }
      },
      null,
      2
    )
  );

  try {
    await execFileAsync("git", ["--version"]);
    gitAvailable = true;
    await execFileAsync("git", ["init"], { cwd: repoRoot });
    await execFileAsync("git", ["config", "user.email", "test@example.com"], { cwd: repoRoot });
    await execFileAsync("git", ["config", "user.name", "Test User"], { cwd: repoRoot });
    await execFileAsync("git", ["add", "."], { cwd: repoRoot });
    await execFileAsync("git", ["commit", "-m", "initial"], { cwd: repoRoot });
  } catch {
    gitAvailable = false;
  }

  const transport = new StdioClientTransport({
    command: "node",
    args: [distEntry, repoRoot],
    cwd: toolRoot,
    stderr: "pipe",
    env: { MCP_CAPABILITY: "READ_WRITE" }
  });

  client = new Client({ name: "mcp-tests", version: "0.0.0" });
  await client.connect(transport);
});

after(async () => {
  if (client) {
    await client.close();
  }
  if (repoRoot) {
    await fs.rm(repoRoot, { recursive: true, force: true });
  }
});

test("repo.info returns metadata for configured repo", async () => {
  const { payload } = await callTool("repo.info", {});
  assert.equal(payload.repoRoot, ".");
  assert.equal(payload.railsPresent, false);
  assert.deepEqual(payload.detectedLanguages, { ruby: true, js: true });
  assert.equal(payload.packageManager, "npm");
  assert.equal(payload.isGitRepo, gitAvailable);
  assert.deepEqual(payload.availableDevCommands, [
    "dev.run_tests",
    "dev.run_lint",
    "dev.smoke_fullstack",
    "dev.run",
    "dev.benchmark_smoke",
    "dev.explain_failure",
    "dev.check"
  ]);
});

test("repo.search finds a string", async () => {
  const { payload } = await callTool("repo.search", { query: "needle", maxResults: 5 });
  assert.equal(payload.results.length, 1);
  assert.equal(payload.results[0].path, "docs/search.txt");
  assert.equal(payload.results[0].lineNumber, 2);
});

test("repo.read_file returns file content", async () => {
  const { payload } = await callTool("repo.read_file", { path: "file.txt" });
  assert.equal(payload.path, "file.txt");
  assert.equal(payload.content, "one\ntwo\nthree\nfour");
});

test("repo.read_file refuses protected files", async () => {
  const { payload } = await callTool("repo.read_file", { path: "config/master.key" });
  assert.equal(payload.path, "config/master.key");
  assert.equal(payload.refused, true);
  assert.equal(payload.reason, "protected_path");
});

test("repo.read_file refuses key/cert style protected files", async () => {
  const pem = await callTool("repo.read_file", { path: "tls-cert.pem" });
  assert.equal(pem.payload.refused, true);
  assert.equal(pem.payload.reason, "protected_path");

  const ssh = await callTool("repo.read_file", { path: "id_rsa" });
  assert.equal(ssh.payload.refused, true);
  assert.equal(ssh.payload.reason, "protected_path");
});

test("repo.read_range returns specific lines", async () => {
  const { payload } = await callTool("repo.read_range", {
    path: "file.txt",
    startLine: 2,
    endLine: 3
  });
  assert.equal(payload.text, "two\nthree");
  assert.equal(payload.startLine, 2);
  assert.equal(payload.endLine, 3);
});

test("repo.read_range returns warnings for out-of-range start", async () => {
  const { result, payload } = await callTool("repo.read_range", {
    path: "file.txt",
    startLine: 10,
    endLine: 12
  });
  assert.equal(result.isError, false);
  assert.equal(payload.text, "");
  assert.ok(payload.warnings.includes("startLine_out_of_range"));
});

test("repo.read_range truncates large ranges", async () => {
  const { payload } = await callTool("repo.read_range", {
    path: "large.txt",
    startLine: 1,
    endLine: 500
  });
  assert.equal(payload.truncated, true);
  assert.equal(payload.startLine, 1);
  assert.equal(payload.endLine, 400);
  assert.ok(payload.warnings.includes("range_truncated"));
});

test("repo.read_range rejects invalid ranges", async () => {
  const { result, payload } = await callTool("repo.read_range", {
    path: "file.txt",
    startLine: 5,
    endLine: 3
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "invalid_range");
});

test("repo.read_range rejects protected files", async () => {
  const { result, payload } = await callTool("repo.read_range", {
    path: ".env.local",
    startLine: 1,
    endLine: 1
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "protected_path");
});

test("repo.list_dir lists directory entries", async () => {
  const { payload } = await callTool("repo.list_dir", { path: "subdir", maxEntries: 10 });
  assert.equal(payload.path, "subdir");
  assert.equal(payload.truncated, false);
  assert.deepEqual(payload.entries, [{ name: "child.txt", type: "file" }]);
});

test("repo.list_dir hides protected files", async () => {
  const { payload } = await callTool("repo.list_dir", { path: ".", maxEntries: 500 });
  const names = payload.entries.map((entry) => entry.name);
  assert.ok(!names.includes(".env"));
  assert.ok(!names.includes(".env.local"));
});

test("repo.deps summarizes versions and dependencies", async () => {
  const { payload } = await callTool("repo.deps", {});
  assert.equal(payload.ruby.version, "3.2.2");
  assert.equal(payload.ruby.railsVersion, "7.1.2");
  assert.equal(payload.ruby.bundlerVersion, "2.4.10");
  assert.equal(payload.node.version, "20.11.1");
  assert.equal(payload.node.packageManager, "pnpm");
  assert.equal(payload.node.workspaceType, "workspace");
  assert.equal(payload.gems.hasGemfileLock, true);
  assert.ok(payload.gems.top.some((gem) => gem.name === "rails"));
  assert.ok(payload.js.dependenciesTop.some((dep) => dep.name === "react"));
  assert.equal(payload.js.scripts.test, "vitest");
  assert.equal(payload.js.hasLockfile, true);
  assert.ok(Array.isArray(payload.filesChecked));
  assert.deepEqual(payload.warnings, []);
});

test("repo.symbols returns definitions with optional filters", async () => {
  const { payload } = await callTool("repo.symbols", {
    glob: "app/**/*.rb",
    kinds: ["class", "method"],
    maxResults: 50
  });
  assert.ok(["ctags", "heuristic"].includes(payload.strategy));
  assert.equal(payload.truncated, false);
  assert.ok(payload.results.some((item) => item.name === "User" && item.kind === "class"));
  assert.ok(payload.results.some((item) => item.name === "name" && item.kind === "method"));
  assert.ok(payload.results.every((item) => item.path.startsWith("app/")));
});

test("repo.find_refs returns summarized references with snippets", async () => {
  const { payload } = await callTool("repo.find_refs", {
    symbol: "targetSymbol",
    languageHint: "ts",
    maxFiles: 5,
    maxSnippetsPerFile: 2
  });
  assert.equal(payload.symbol, "targetSymbol");
  assert.ok(["rg", "git_grep", "walk"].includes(payload.strategy));
  assert.equal(payload.truncated, false);
  assert.ok(payload.files.length >= 1);
  const entry = payload.files.find((file) => file.path === "src/refs.ts");
  assert.ok(entry);
  assert.equal(entry.occurrences, 5);
  assert.equal(entry.snippets.length, 2);
  assert.ok(entry.snippets.every((snippet) => typeof snippet.preview === "string"));
});

test("repo.todo_scan finds todo markers with stable ordering", async () => {
  const { payload } = await callTool("repo.todo_scan", {
    patterns: ["TODO", "FIXME", "NOTE"],
    maxResults: 10
  });
  assert.equal(payload.truncated, false);
  assert.ok(payload.results.length >= 3);
  assert.equal(payload.results[0].pattern, "FIXME");
  assert.equal(payload.results[0].path, "src/todos.ts");
  assert.equal(payload.results[0].line, 2);
  assert.equal(payload.groupedCounts.TODO, 1);
  assert.equal(payload.groupedCounts.FIXME, 1);
  assert.equal(payload.groupedCounts.NOTE, 1);
});

test("repo.format_patch normalizes diff and returns stats", async () => {
  const diff = [
    "--- a/src/apply.txt",
    "+++ b/src/apply.txt",
    "@@ -1,3 +1,4 @@",
    " first",
    "+between",
    " second",
    " third"
  ].join("\n");
  const { payload } = await callTool("repo.format_patch", { diff });
  assert.equal(payload.valid, true);
  assert.deepEqual(payload.filesChanged, ["src/apply.txt"]);
  assert.equal(payload.stats.files, 1);
  assert.equal(payload.stats.insertions, 1);
  assert.equal(payload.stats.deletions, 0);
  assert.ok(payload.normalizedDiff.startsWith("diff --git a/src/apply.txt b/src/apply.txt"));
  assert.ok(payload.normalizedDiff.includes("@@ -1,3 +1,4 @@"));
  assert.ok(payload.warnings.includes("missing_diff_header"));
});

test("repo.format_patch detects malformed diff", async () => {
  const diff = [
    "diff --git a/src/apply.txt b/src/apply.txt",
    "--- a/src/apply.txt",
    "+++ b/src/apply.txt",
    "@@ -1,2 +1,2 @@",
    " first",
    "+second"
  ].join("\n");
  const { payload } = await callTool("repo.format_patch", { diff });
  assert.equal(payload.valid, false);
  assert.ok(payload.warnings.some((warning) => warning.startsWith("invalid_hunk")));
});

test("repo.propose_patch generates unified diff without applying", async () => {
  const { payload } = await callTool("repo.propose_patch", {
    path: "src/patch.txt",
    replace: { startLine: 2, endLine: 2, newText: "beta-updated" }
  });
  assert.equal(payload.path, "src/patch.txt");
  assert.equal(payload.applied, false);
  assert.ok(payload.diff.includes("@@ -2,1 +2,1 @@"));
  assert.ok(payload.diff.includes("-beta"));
  assert.ok(payload.diff.includes("+beta-updated"));
});

test("repo.propose_patch enforces expected sha", async () => {
  const original = ["alpha", "beta", "gamma"].join("\n");
  const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
  const { result, payload } = await callTool("repo.propose_patch", {
    path: "src/patch.txt",
    delete: { startLine: 1, endLine: 1 },
    expectedSha256: `${expected}bad`
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "sha_mismatch");
});

test("repo.propose_patch rejects protected paths", async () => {
  const { result, payload } = await callTool("repo.propose_patch", {
    path: ".env",
    insert: { line: 2, text: "SECRET=2" }
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "protected_path");
});

test("repo.apply_patch applies structured edit with expected sha", async () => {
  const original = ["alpha", "beta", "gamma"].join("\n");
  const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
  const { result, payload } = await callTool("repo.apply_patch", {
    path: "src/patch.txt",
    replace: { startLine: 2, endLine: 2, newText: "beta-applied" },
    expectedSha256: expected
  });
  assert.equal(result.isError, false);
  assert.equal(payload.path, "src/patch.txt");
  assert.equal(payload.applied, true);
  assert.ok(payload.diffApplied.includes("-beta"));
  assert.ok(payload.diffApplied.includes("+beta-applied"));
  const updated = await fs.readFile(path.join(repoRoot, "src", "patch.txt"), "utf8");
  assert.equal(updated.trim(), ["alpha", "beta-applied", "gamma"].join("\n"));
});

test("capability mode denies write tools in READ_ONLY", async () => {
  const readOnly = await createClient({ MCP_CAPABILITY: "READ_ONLY" });
  try {
    const original = ["alpha", "beta", "gamma"].join("\n");
    const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
    const { result, payload } = await callToolWithClient(readOnly.client, "repo.apply_patch", {
      path: "src/patch.txt",
      replace: { startLine: 2, endLine: 2, newText: "blocked" },
      expectedSha256: expected
    });
    assert.equal(result.isError, true);
    assert.equal(payload.error.code, "capability_denied");
  } finally {
    await readOnly.client.close();
  }
});

test("audit log writes JSONL entries with summaries", async () => {
  await callTool("repo.search", { query: "needle", maxResults: 1 });
  const { entry } = await waitForAuditEntry("repo.search");
  assert.equal(entry.toolName, "repo.search");
  assert.equal(entry.argsSummary.query, "needle");
  assert.equal(typeof entry.durationMs, "number");
  assert.ok(entry.resultSummary);
});

test("audit log does not include patch contents", async () => {
  const secret = "supersecret-1234567890-supersecret-1234567890";
  await callTool("repo.propose_patch", {
    path: "src/patch.txt",
    replace: { startLine: 1, endLine: 1, newText: secret }
  });
  const { line, entry } = await waitForAuditEntry("repo.propose_patch");
  assert.ok(!line.includes(secret));
  assert.ok(entry.argsSummary.textBytes > 0);
  assert.equal(entry.argsSummary.newText, undefined);
});

test("repo.apply_patch applies unified diff", async () => {
  const original = ["first", "second", "third"].join("\n");
  const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
  const diff = [
    "diff --git a/src/apply.txt b/src/apply.txt",
    "--- a/src/apply.txt",
    "+++ b/src/apply.txt",
    "@@ -1,3 +1,3 @@",
    " first",
    "-second",
    "+second-updated",
    " third"
  ].join("\n");
  const { result, payload } = await callTool("repo.apply_patch", {
    path: "src/apply.txt",
    diff,
    expectedSha256: expected
  });
  assert.equal(result.isError, false);
  assert.equal(payload.applied, true);
  assert.ok(payload.diffApplied.includes("+second-updated"));
  const updated = await fs.readFile(path.join(repoRoot, "src", "apply.txt"), "utf8");
  assert.equal(updated.trim(), ["first", "second-updated", "third"].join("\n"));
});

test("repo.apply_patch rejects protected paths", async () => {
  const original = "SECRET=1\n";
  const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
  const { result, payload } = await callTool("repo.apply_patch", {
    path: ".env",
    insert: { line: 2, text: "SECRET=2" },
    expectedSha256: expected
  });
  assert.equal(result.isError, true);
  assert.equal(payload.errors[0].code, "protected_path");
});

test("repo.apply_patch rejects sha mismatch", async () => {
  const original = ["first", "second-updated", "third"].join("\n");
  const expected = crypto.createHash("sha256").update(original, "utf8").digest("hex");
  const { result, payload } = await callTool("repo.apply_patch", {
    path: "src/apply.txt",
    delete: { startLine: 1, endLine: 1 },
    expectedSha256: `${expected}bad`
  });
  assert.equal(result.isError, true);
  assert.equal(payload.errors[0].code, "sha_mismatch");
});

test("repo.tree returns bounded directory tree and skips node_modules", async () => {
  const { payload } = await callTool("repo.tree", { path: ".", maxDepth: 1, maxNodes: 200 });
  assert.equal(payload.path, ".");
  assert.equal(payload.maxDepth, 1);
  assert.ok(payload.nodesReturned > 0);
  assert.equal(payload.truncated, false);
  assert.equal(payload.tree.type, "dir");
  const childNames = (payload.tree.children ?? []).map((child) => child.name);
  assert.ok(childNames.includes("docs"));
  assert.ok(childNames.includes("file.txt"));
  assert.ok(!childNames.includes("node_modules"));
  assert.ok(!childNames.includes(".env"));
  assert.ok(!childNames.includes(".env.local"));
});

test("dev.check reports tool presence", async () => {
  const { payload } = await callTool("dev.check", {});
  assert.ok(payload.tools);
  assert.ok(Object.prototype.hasOwnProperty.call(payload.tools, "rg"));
  assert.ok(Object.prototype.hasOwnProperty.call(payload.tools, "git"));
});

test("dev.run executes an allowlisted command", async () => {
  const { result, payload } = await callTool("dev.run", { name: "node-version" });
  assert.equal(result.isError, false);
  assert.equal(payload.name, "node-version");
  assert.equal(payload.cwd, ".");
  assert.ok(Array.isArray(payload.cmd));
  assert.equal(payload.cmd[0], "node");
  assert.equal(payload.timedOut, false);
  assert.equal(typeof payload.exitCode, "number");
  assert.equal(payload.limits.maxOutputBytes, 10240);
  assert.ok(Array.isArray(payload.envUsed));
});

test("dev.run rejects args that are not allowlisted", async () => {
  const { result, payload } = await callTool("dev.run", {
    name: "node-version",
    args: ["--help"]
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "args_not_allowed");
});

test("dev.benchmark_smoke executes an allowlisted benchmark", async () => {
  const { result, payload } = await callTool("dev.benchmark_smoke", { name: "json-parse-smoke" });
  assert.equal(result.isError, false);
  assert.equal(payload.name, "json-parse-smoke");
  assert.ok(Array.isArray(payload.cmd));
  assert.equal(payload.cmd[0], "node");
  assert.equal(typeof payload.durationMs, "number");
  assert.equal(typeof payload.stdout, "string");
  assert.equal(typeof payload.stderr, "string");
  assert.equal(typeof payload.exitCode, "number");
  assert.equal(payload.timedOut, false);
  assert.equal(typeof payload.truncated, "boolean");
});

test("dev.benchmark_smoke rejects unknown names", async () => {
  const { result, payload } = await callTool("dev.benchmark_smoke", { name: "nope" });
  assert.equal(result.isError, true);
  assert.equal(payload.error.code, "benchmark_not_allowed");
});

test("dev.explain_failure extracts structured errors", async () => {
  const stdout = [
    "src/foo.ts(12,5): error TS2322: Type 'string' is not assignable to type 'number'.",
    "FAIL  src/foo.test.ts",
    "  TypeError: Cannot read properties of undefined (reading 'bar')",
    "    at Object.<anonymous> (src/foo.test.ts:5:11)"
  ].join("\n");
  const stderr = [
    "src/foo.ts:3:10 error 'x' is defined but never used (no-unused-vars)",
    "app/models/user.rb:5:3: C: Layout/IndentationWidth: Use 2 spaces for indentation.",
    "app/models/user.rb:10:in `name'"
  ].join("\n");
  const { result, payload } = await callTool("dev.explain_failure", { stdout, stderr });
  assert.equal(result.isError, false);
  assert.ok(payload.primaryError);
  assert.ok(Array.isArray(payload.errors));
  assert.ok(payload.errors.length >= 2);
  assert.ok(Array.isArray(payload.stackFrames));
  assert.ok(payload.stackFrames.length >= 1);
  assert.equal(typeof payload.summary, "string");
  assert.ok(payload.confidence >= 0 && payload.confidence <= 1);
});

test("dev.explain_failure handles empty output", async () => {
  const { result, payload } = await callTool("dev.explain_failure", { stdout: "", stderr: "" });
  assert.equal(result.isError, false);
  assert.equal(payload.primaryError, null);
  assert.ok(payload.warnings.includes("no_errors_detected"));
});

test("rails.routes parses static routes", async () => {
  const { result, payload } = await callTool("rails.routes", { mode: "static" });
  assert.equal(result.isError, false);
  assert.equal(payload.modeUsed, "static");
  assert.ok(Array.isArray(payload.routes));
  assert.ok(
    payload.routes.some(
      (route) => route.path === "/" && route.controller === "home" && route.action === "index"
    )
  );
  assert.ok(
    payload.routes.some(
      (route) => route.path === "/health" && route.controller === "health" && route.action === "show"
    )
  );
  assert.ok(
    payload.routes.some(
      (route) => route.path === "/admin/users" && route.controller === "admin/users" && route.action === "index"
    )
  );
  assert.ok(payload.warnings.includes("static_parsing_is_best_effort"));
});

test("rails.schema summarizes schema tables", async () => {
  const { result, payload } = await callTool("rails.schema", {});
  assert.equal(result.isError, false);
  assert.equal(payload.source, "db/schema.rb");
  assert.ok(Array.isArray(payload.tables));
  const users = payload.tables.find((table) => table.name === "users");
  assert.ok(users);
  assert.ok(users.columns.some((col) => col.name === "email" && col.type === "string" && col.null === false));
  assert.ok(users.indexes.some((idx) => idx.unique === true && idx.columns.includes("email")));
  assert.ok(users.foreignKeys.some((fk) => fk.from === "users" && fk.to === "accounts"));
});

test("rails.models summarizes model associations and validations", async () => {
  const { result, payload } = await callTool("rails.models", {});
  assert.equal(result.isError, false);
  assert.ok(Array.isArray(payload.models));
  const user = payload.models.find((model) => model.name === "User");
  assert.ok(user);
  assert.equal(user.path, "app/models/user.rb");
  assert.ok(user.associations.some((assoc) => assoc.type === "belongs_to" && assoc.name === "account"));
  assert.ok(user.associations.some((assoc) => assoc.type === "has_many" && assoc.name === "bids"));
  assert.ok(
    user.validations.some(
      (validation) =>
        validation.type === "validates" &&
        validation.attributes.includes("email") &&
        validation.options.includes("presence")
    )
  );
});

test("js.workspace summarizes JS tooling configuration", async () => {
  const { result, payload } = await callTool("js.workspace", {});
  assert.equal(result.isError, false);
  assert.equal(payload.packageManager, "npm");
  assert.equal(payload.workspaces.enabled, true);
  assert.ok(payload.workspaces.packages.includes("packages/*"));
  assert.equal(payload.tsconfig.root, "tsconfig.json");
  assert.ok(payload.tsconfig.references.includes("./packages/core"));
  assert.ok(payload.tsconfig.paths["@/*"]);
  assert.equal(payload.vite.configPath, "vite.config.ts");
  assert.ok(payload.vite.plugins.includes("react"));
  assert.equal(payload.vite.aliases["@"], "/src");
  assert.equal(payload.eslint.configPath, "eslint.config.js");
  assert.ok(payload.eslint.extends.includes("eslint:recommended"));
  assert.ok(payload.scripts.test);
});

test("git.status summarizes working tree changes", async () => {
  if (!gitAvailable) {
    return test.skip("git unavailable");
  }
  await fs.writeFile(path.join(repoRoot, "file.txt"), "one\ntwo\nthree\nfour\nfive\n");
  await fs.writeFile(path.join(repoRoot, "new.txt"), "new file\n");
  await fs.rm(path.join(repoRoot, "empty.txt"));

  const { result, payload } = await callTool("git.status", {});
  assert.equal(result.isError, false);
  assert.equal(payload.isGitRepo, true);
  assert.ok(payload.branch);
  const paths = payload.changed.map((entry) => entry.path);
  assert.ok(paths.includes("file.txt"));
  assert.ok(paths.includes("new.txt"));
  assert.ok(paths.includes("empty.txt"));
});

test("git.diff returns diff output with optional path", async () => {
  if (!gitAvailable) {
    return test.skip("git unavailable");
  }
  const { result, payload } = await callTool("git.diff", { path: "file.txt" });
  assert.equal(result.isError, false);
  assert.equal(payload.truncated, false);
  assert.ok(payload.diff.includes("file.txt"));
});

test("rails.routes truncates static results", async () => {
  const { payload } = await callTool("rails.routes", { mode: "static", maxResults: 2 });
  assert.equal(payload.truncated, true);
  assert.equal(payload.routes.length, 2);
});

test("dev.run_tests returns structured result", async () => {
  const { payload } = await callTool("dev.run_tests", { target: "both" });
  assert.ok(payload.results.ruby);
  assert.ok(payload.results.js);
  assert.ok(Array.isArray(payload.results.ruby.command));
  assert.ok(Array.isArray(payload.results.js.command));
  assert.equal(typeof payload.results.ruby.stderr, "string");
  assert.equal(typeof payload.results.js.stderr, "string");
});

test("dev.run_lint returns structured result", async () => {
  const { payload } = await callTool("dev.run_lint", { target: "both" });
  assert.ok(payload.results.ruby);
  assert.ok(payload.results.js);
  assert.ok(Array.isArray(payload.results.ruby.command));
  assert.ok(Array.isArray(payload.results.js.command));
  assert.equal(typeof payload.results.ruby.stderr, "string");
  assert.equal(typeof payload.results.js.stderr, "string");
});

test("orchestrator tools are listed by MCP server", async () => {
  const tools = await client.listTools();
  const names = tools.tools.map((tool) => tool.name);
  assert.ok(names.includes("ops.triage_prod_error"));
  assert.ok(names.includes("ops.verify_deploy_window_401"));
  assert.ok(names.includes("ops.env_diff"));
  assert.ok(names.includes("dev.route_contract_check"));
  assert.ok(names.includes("dev.smoke_fullstack"));
});

test("catalog resources are listed by MCP server", async () => {
  const resourcesResult = await client.listResources();
  const uris = resourcesResult.resources.map((resource) => resource.uri);
  assert.ok(uris.includes("biddersweet://runbooks/incident-triage"));
  assert.ok(uris.includes("biddersweet://runbooks/deploy-checklist"));
  assert.ok(uris.includes("biddersweet://contracts/auth-session"));
  assert.ok(uris.includes("biddersweet://contracts/storefront-routing"));
  assert.ok(uris.includes("biddersweet://maps/services-render"));
  assert.ok(uris.includes("biddersweet://maps/apps-vercel"));
});

test("catalog resources are readable by URI", async () => {
  const readResult = await client.readResource({ uri: "biddersweet://runbooks/incident-triage" });
  const text = readResult.contents?.[0]?.text ?? "";
  assert.ok(text.includes("Incident Triage Runbook"));
});

test("ops.triage_prod_error returns bounded triage report payload", async () => {
  const { result, payload } = await callTool("ops.triage_prod_error", {});
  assert.equal(result.isError, false);
  assert.ok(payload);
  assert.ok("service" in payload);
  assert.ok("top_errors" in payload);
  assert.ok("deploy_correlation" in payload);
  assert.ok("metrics_summary" in payload);
  assert.ok(Array.isArray(payload.top_errors));
  assert.equal(typeof payload.deploy_correlation.likely, "boolean");
  assert.ok(Array.isArray(payload.recommended_next_actions));
  assert.ok(Array.isArray(payload.expand_instructions));
  assert.equal(typeof payload.bounded_by.max_logs, "number");
});

test("ops.triage_prod_error correlates deploy from snapshot data", async () => {
  const { client: snapshotClient } = await createClient({
    MCP_CAPABILITY: "READ_WRITE",
    BIDDERSWEET_RENDER_SNAPSHOT_PATH: renderSnapshotRelPath
  });
  try {
    const { result, payload } = await callToolWithClient(snapshotClient, "ops.triage_prod_error", {
      service: "x-bid-backend-api",
      timeWindowMinutes: 30
    });
    assert.equal(result.isError, false);
    assert.equal(payload.service.id, "srv-backend");
    assert.ok(payload.top_errors.length > 0);
    assert.equal(payload.top_errors[0].signature.startsWith("NoMethodError"), true);
    assert.equal(payload.deploy_correlation.likely, true);
    assert.equal(payload.deploy_correlation.deploy_id, "dep-1");
  } finally {
    await snapshotClient.close();
  }
});

test("ops.triage_prod_error rejects oversized time window via schema", async () => {
  const { result, payload } = await callTool("ops.triage_prod_error", {
    timeWindowMinutes: 999
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error, "invalid_request");
});

test("ops.verify_deploy_window_401 returns refusal for oversized window", async () => {
  const { result, payload } = await callTool("ops.verify_deploy_window_401", {
    serviceName: "x-bid-api",
    timeWindowMinutes: 999
  });
  assert.equal(result.isError, false);
  assert.equal(payload.refused, true);
  assert.equal(payload.refusal_reason, "time_window_too_large");
  assert.ok(Array.isArray(payload.signals));
});

test("ops.verify_deploy_window_401 classifies transient deploy-window 401s", async () => {
  const now = Date.now();
  const snapshotPath = "render-snapshot-401-transient.json";
  await fs.writeFile(
    path.join(repoRoot, snapshotPath),
    JSON.stringify(
      {
        services: [{ id: "srv-backend", name: "x-bid-backend-api", url: "https://x-bid-backend.onrender.com" }],
        logsByServiceId: {
          "srv-backend": [
            {
              timestamp: new Date(now - 24 * 60_000).toISOString(),
              level: "warn",
              message: "401 unauthorized missing session cookie",
              statusCode: 401
            },
            {
              timestamp: new Date(now - 23 * 60_000).toISOString(),
              level: "warn",
              message: "Unauthorized: missing cookie",
              statusCode: 401
            },
            {
              timestamp: new Date(now - 21 * 60_000).toISOString(),
              level: "warn",
              message: "request unauthorized",
              statusCode: 401
            }
          ]
        },
        metricsByServiceId: {
          "srv-backend": [
            {
              metricType: "http_request_count",
              points: [
                { timestamp: new Date(now - 30 * 60_000).toISOString(), value: 30 },
                { timestamp: new Date(now - 5 * 60_000).toISOString(), value: 10 }
              ]
            }
          ]
        },
        deploysByServiceId: {
          "srv-backend": [
            {
              id: "dep-auth",
              startedAt: new Date(now - 25 * 60_000).toISOString(),
              finishedAt: new Date(now - 20 * 60_000).toISOString(),
              status: "live"
            }
          ]
        }
      },
      null,
      2
    )
  );

  const { client: snapshotClient } = await createClient({
    MCP_CAPABILITY: "READ_WRITE",
    BIDDERSWEET_RENDER_SNAPSHOT_PATH: snapshotPath
  });
  try {
    const { result, payload } = await callToolWithClient(snapshotClient, "ops.verify_deploy_window_401", {
      service: "x-bid-backend-api",
      window_minutes: 40
    });
    assert.equal(result.isError, false);
    assert.equal(payload.classification, "transient");
    assert.ok(Array.isArray(payload.evidence));
    assert.ok(payload.evidence.length > 0);
    assert.ok(Array.isArray(payload.recommended_actions));
    assert.ok(payload.recommended_actions[0].includes("retry once before logout"));
  } finally {
    await snapshotClient.close();
  }
});

test("ops.verify_deploy_window_401 classifies persistent 401s as regression", async () => {
  const now = Date.now();
  const snapshotPath = "render-snapshot-401-regression.json";
  await fs.writeFile(
    path.join(repoRoot, snapshotPath),
    JSON.stringify(
      {
        services: [{ id: "srv-backend", name: "x-bid-backend-api", url: "https://x-bid-backend.onrender.com" }],
        logsByServiceId: {
          "srv-backend": [
            {
              timestamp: new Date(now - 10 * 60_000).toISOString(),
              level: "warn",
              message: "401 unauthorized",
              statusCode: 401
            },
            {
              timestamp: new Date(now - 6 * 60_000).toISOString(),
              level: "warn",
              message: "missing session",
              statusCode: 401
            },
            {
              timestamp: new Date(now - 2 * 60_000).toISOString(),
              level: "warn",
              message: "401 unauthorized",
              statusCode: 401
            }
          ]
        },
        metricsByServiceId: {
          "srv-backend": [
            {
              metricType: "http_request_count",
              points: [
                { timestamp: new Date(now - 30 * 60_000).toISOString(), value: 10 },
                { timestamp: new Date(now - 1 * 60_000).toISOString(), value: 35 }
              ]
            }
          ]
        },
        deploysByServiceId: {
          "srv-backend": [
            {
              id: "dep-auth-old",
              startedAt: new Date(now - 45 * 60_000).toISOString(),
              finishedAt: new Date(now - 40 * 60_000).toISOString(),
              status: "live"
            }
          ]
        }
      },
      null,
      2
    )
  );

  const { client: snapshotClient } = await createClient({
    MCP_CAPABILITY: "READ_WRITE",
    BIDDERSWEET_RENDER_SNAPSHOT_PATH: snapshotPath
  });
  try {
    const { result, payload } = await callToolWithClient(snapshotClient, "ops.verify_deploy_window_401", {
      serviceName: "x-bid-backend-api",
      timeWindowMinutes: 60
    });
    assert.equal(result.isError, false);
    assert.equal(payload.classification, "regression");
    assert.ok(payload.recommended_actions.some((line) => line.includes("cookie domain")));
  } finally {
    await snapshotClient.close();
  }
});

test("ops.env_diff returns deterministic Render env drift report", async () => {
  const snapshotPath = "render-snapshot-env-diff.json";
  await fs.writeFile(
    path.join(repoRoot, snapshotPath),
    JSON.stringify(
      {
        services: [
          { id: "srv-prod", name: "x-bid-backend-prod", url: "https://api.example.com" },
          { id: "srv-staging", name: "x-bid-backend-staging", url: "https://staging-api.example.com" }
        ],
        envVarsByServiceId: {
          "srv-prod": [
            { key: "DATABASE_URL", value: "postgres://prod-db" },
            { key: "REDIS_URL", value: "redis://prod-cache" },
            { key: "SECRET_KEY_BASE", value: "prod-secret-key-base" },
            { key: "ALLOWED_ORIGINS", value: "https://www.example.com" },
            { key: "AUTH_JWT_ISSUER", value: "issuer-prod" }
          ],
          "srv-staging": [
            { key: "DATABASE_URL", value: "postgres://staging-db" },
            { key: "REDIS_URL", value: "redis://staging-cache" },
            { key: "SECRET_KEY_BASE", value: "staging-secret-key-base" },
            { key: "FEATURE_FLAG_X", value: "true" },
            { key: "AUTH_JWT_ISSUER", value: "issuer-staging" }
          ]
        }
      },
      null,
      2
    )
  );

  const { client: snapshotClient } = await createClient({
    MCP_CAPABILITY: "READ_WRITE",
    BIDDERSWEET_RENDER_SNAPSHOT_PATH: snapshotPath
  });
  try {
    const { result, payload } = await callToolWithClient(snapshotClient, "ops.env_diff", {
      service_a: "x-bid-backend-prod",
      service_b: "x-bid-backend-staging"
    });
    assert.equal(result.isError, false);
    assert.equal(typeof payload.summary, "string");
    assert.ok(payload.summary.includes("Env drift detected"));
    assert.deepEqual(payload.missing_in_a, ["FEATURE_FLAG_X"]);
    assert.deepEqual(payload.missing_in_b, ["ALLOWED_ORIGINS"]);
    assert.deepEqual(payload.in_both, ["AUTH_JWT_ISSUER", "DATABASE_URL", "REDIS_URL", "SECRET_KEY_BASE"]);
    assert.ok(Array.isArray(payload.suspicious_keys));
    assert.ok(payload.suspicious_keys.includes("ALLOWED_ORIGINS"));
    assert.ok(payload.suspicious_keys.includes("AUTH_JWT_ISSUER"));
    assert.ok(payload.suspicious_keys.includes("SECRET_KEY_BASE"));
    assert.equal(payload.value_preview, undefined);
    assert.equal(typeof payload.drift_summary, "object");
    assert.equal(payload.drift_summary.symmetric_drift_count, 2);
    assert.equal(typeof payload.report_json, "object");
  } finally {
    await snapshotClient.close();
  }
});

test("ops.env_diff show_values mode redacts sensitive values", async () => {
  const snapshotPath = "render-snapshot-env-diff-values.json";
  await fs.writeFile(
    path.join(repoRoot, snapshotPath),
    JSON.stringify(
      {
        services: [
          { id: "srv-prod", name: "x-bid-backend-prod" },
          { id: "srv-staging", name: "x-bid-backend-staging" }
        ],
        envVarsByServiceId: {
          "srv-prod": [
            { key: "FEATURE_FLAG_X", value: "enabled" },
            { key: "SECRET_KEY_BASE", value: "super-secret-value" }
          ],
          "srv-staging": [
            { key: "FEATURE_FLAG_X", value: "disabled" },
            { key: "SECRET_KEY_BASE", value: "another-secret-value" }
          ]
        }
      },
      null,
      2
    )
  );

  const { client: snapshotClient } = await createClient({
    MCP_CAPABILITY: "READ_WRITE",
    BIDDERSWEET_RENDER_SNAPSHOT_PATH: snapshotPath
  });
  try {
    const { result, payload } = await callToolWithClient(snapshotClient, "ops.env_diff", {
      service_a: "x-bid-backend-prod",
      service_b: "x-bid-backend-staging",
      show_values: true
    });
    assert.equal(result.isError, false);
    assert.equal(payload.value_preview.service_a.SECRET_KEY_BASE.redacted, true);
    assert.equal(payload.value_preview.service_a.SECRET_KEY_BASE.last4, undefined);
    assert.equal(payload.value_preview.service_a.FEATURE_FLAG_X.last4, "bled");
    assert.equal(payload.value_preview.service_b.FEATURE_FLAG_X.last4, "bled");
  } finally {
    await snapshotClient.close();
  }
});

test("ops.env_diff refuses destructive mode without two-step confirmation", async () => {
  const { result, payload } = await callTool("ops.env_diff", {
    service_a: "staging",
    service_b: "production",
    destructiveIntent: true
  });
  assert.equal(result.isError, false);
  assert.equal(payload.refused, true);
  assert.equal(payload.refusal_reason, "destructive_confirmation_required");
});

test("dev.route_contract_check returns structured contract check payload", async () => {
  const { result, payload } = await callTool("dev.route_contract_check", {
    maxAllowedDrift: 10
  });
  assert.equal(result.isError, false);
  assert.equal(typeof payload.summary, "string");
  assert.ok(Array.isArray(payload.signals));
  assert.ok(Array.isArray(payload.next_actions));
  assert.ok(Array.isArray(payload.artifacts));
  assert.equal(typeof payload.confidence, "number");
});

test("dev.route_contract_check rejects invalid threshold", async () => {
  const { result, payload } = await callTool("dev.route_contract_check", {
    maxAllowedDrift: -1
  });
  assert.equal(result.isError, true);
  assert.equal(payload.error, "invalid_request");
});

test("dev.smoke_fullstack returns backend/frontend smoke summary", async () => {
  const { result, payload } = await callTool("dev.smoke_fullstack", {});
  assert.equal(result.isError, false);
  assert.ok(payload.backend);
  assert.ok(payload.frontend);
  assert.ok(Array.isArray(payload.next_actions));
  assert.equal(typeof payload.backend.command, "string");
  assert.equal(typeof payload.frontend.command, "string");
  assert.equal(typeof payload.backend.duration, "number");
  assert.equal(typeof payload.frontend.duration, "number");
  assert.ok(Array.isArray(payload.backend.top_failures));
  assert.ok(Array.isArray(payload.frontend.top_failures));
  assert.ok(["passed", "failed", "skipped"].includes(payload.backend.status));
  assert.ok(["passed", "failed", "skipped"].includes(payload.frontend.status));
});

test("dev.smoke_fullstack fail-fast skips frontend when backend fails", async () => {
  const { payload } = await callTool("dev.smoke_fullstack", {});
  if (payload.backend.status === "failed") {
    assert.equal(payload.frontend.status, "skipped");
    assert.ok(payload.frontend.top_failures.some((item) => /fail-fast/i.test(item)));
  }
});
