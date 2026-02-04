import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const toolRoot = path.resolve(__dirname, "..");
const distEntry = path.join(toolRoot, "dist", "index.js");

let repoRoot = "";
let client;

async function callTool(name, args) {
  const result = await client.callTool({ name, arguments: args });
  const text = result.content?.[0]?.text ?? "";
  const payload = text ? JSON.parse(text) : null;
  return { result, payload };
}

before(async () => {
  repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "biddersweet-mcp-test-"));
  await fs.mkdir(path.join(repoRoot, "docs"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "subdir"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "app", "models"), { recursive: true });
  await fs.mkdir(path.join(repoRoot, "src"), { recursive: true });

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
    ["class User", "  def name", "    \"Test\"", "  end", "end"].join("\n")
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

  const transport = new StdioClientTransport({
    command: "node",
    args: [distEntry, repoRoot],
    cwd: toolRoot,
    stderr: "pipe"
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
  assert.equal(payload.isGitRepo, false);
  assert.deepEqual(payload.availableDevCommands, ["dev.run_tests", "dev.run_lint", "dev.check"]);
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

test("repo.list_dir lists directory entries", async () => {
  const { payload } = await callTool("repo.list_dir", { path: "subdir", maxEntries: 10 });
  assert.equal(payload.path, "subdir");
  assert.equal(payload.truncated, false);
  assert.deepEqual(payload.entries, [{ name: "child.txt", type: "file" }]);
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
});

test("dev.check reports tool presence", async () => {
  const { payload } = await callTool("dev.check", {});
  assert.ok(payload.tools);
  assert.ok(Object.prototype.hasOwnProperty.call(payload.tools, "rg"));
  assert.ok(Object.prototype.hasOwnProperty.call(payload.tools, "git"));
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
