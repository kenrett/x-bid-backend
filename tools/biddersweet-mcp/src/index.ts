import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

const MAX_FILE_SIZE_BYTES = 200 * 1024;
const MAX_PREVIEW_CHARS = 300;
const MAX_CMD_OUTPUT_BYTES = 10 * 1024;
const DEFAULT_SEARCH_MAX = 50;
const HARD_SEARCH_MAX = 100;
const DEFAULT_LIST_MAX = 500;
const HARD_LIST_MAX = 2000;
const DEFAULT_CMD_TIMEOUT_MS = 60_000;
const CHECK_TIMEOUT_MS = 1_500;

const SKIP_DIR_NAMES = new Set([
  "node_modules",
  "vendor",
  "dist",
  "build",
  "coverage",
  "tmp",
  "log",
  ".git"
]);

const repoRoot = resolveRepoRoot();

const server = new Server(
  {
    name: "biddersweet-mcp",
    version: "0.1.0"
  },
  {
    capabilities: {
      tools: {}
    }
  }
);

const RepoInfoInputSchema = z.object({});
const RepoSearchInputSchema = z.object({
  query: z.string().min(1),
  maxResults: z.number().int().positive().optional()
});
const RepoReadFileInputSchema = z.object({
  path: z.string()
});
const RepoListDirInputSchema = z.object({
  path: z.string().optional().default(""),
  maxEntries: z.number().int().positive().optional()
});
const DevCheckInputSchema = z.object({});
const DevRunTargetSchema = z.object({
  target: z.enum(["ruby", "js", "both"]).optional().default("both")
});

type RepoInfoInput = z.infer<typeof RepoInfoInputSchema>;
type RepoSearchInput = z.infer<typeof RepoSearchInputSchema>;
type RepoReadFileInput = z.infer<typeof RepoReadFileInputSchema>;
type RepoListDirInput = z.infer<typeof RepoListDirInputSchema>;
type DevRunTargetInput = z.infer<typeof DevRunTargetSchema>;

type DevResult = {
  ok: boolean;
  exitCode: number;
  command: string[];
  stdout: string;
  stderr: string;
  truncated: boolean;
  truncatedBytes: number;
  durationMs: number;
};

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "repo.info",
        description: "Return repo metadata and detected tooling.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "repo.search",
        description: "Search for a fixed string within the repo.",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string" },
            maxResults: { type: "number" }
          },
          required: ["query"],
          additionalProperties: false
        }
      },
      {
        name: "repo.read_file",
        description: "Read a text file within the repo.",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" }
          },
          required: ["path"],
          additionalProperties: false
        }
      },
      {
        name: "repo.list_dir",
        description: "List directory entries within the repo.",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
            maxEntries: { type: "number" }
          },
          required: ["path"],
          additionalProperties: false
        }
      },
      {
        name: "dev.check",
        description: "Check for common dev tool availability.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "dev.run_tests",
        description: "Run allowlisted test commands.",
        inputSchema: {
          type: "object",
          properties: {
            target: { type: "string", enum: ["ruby", "js", "both"] }
          },
          additionalProperties: false
        }
      },
      {
        name: "dev.run_lint",
        description: "Run allowlisted lint commands.",
        inputSchema: {
          type: "object",
          properties: {
            target: { type: "string", enum: ["ruby", "js", "both"] }
          },
          additionalProperties: false
        }
      }
    ]
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    switch (name) {
      case "repo.info": {
        const parsed = RepoInfoInputSchema.parse(args ?? {});
        const result = await handleRepoInfo(parsed);
        return jsonResult(result);
      }
      case "repo.search": {
        const parsed = RepoSearchInputSchema.parse(args ?? {});
        const result = await handleRepoSearch(parsed);
        return jsonResult(result);
      }
      case "repo.read_file": {
        const parsed = RepoReadFileInputSchema.parse(args ?? {});
        const result = await handleRepoReadFile(parsed);
        return jsonResult(result);
      }
      case "repo.list_dir": {
        const parsed = RepoListDirInputSchema.parse(args ?? {});
        const result = await handleRepoListDir(parsed);
        return jsonResult(result);
      }
      case "dev.check": {
        const parsed = DevCheckInputSchema.parse(args ?? {});
        const result = await handleDevCheck(parsed);
        return jsonResult(result);
      }
      case "dev.run_tests": {
        const parsed = DevRunTargetSchema.parse(args ?? {});
        const result = await handleDevRunTests(parsed);
        return jsonResult(result);
      }
      case "dev.run_lint": {
        const parsed = DevRunTargetSchema.parse(args ?? {});
        const result = await handleDevRunLint(parsed);
        return jsonResult(result);
      }
      default:
        return jsonResult({ error: "unknown_tool" }, true);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    return jsonResult({ error: "invalid_request", message }, true);
  }
});

async function handleRepoInfo(_input: RepoInfoInput) {
  const gemfile = await existsInRepo("Gemfile");
  const packageJson = await existsInRepo("package.json");
  const railsMarker =
    (await existsInRepo("config/application.rb")) ||
    (await existsInRepo("bin/rails")) ||
    (await existsInRepo("config.ru"));
  const railsPresent = gemfile && railsMarker;

  const packageManager = await detectPackageManager();
  const isGitRepo = await detectGitRepo();

  const availableDevCommands: string[] = [];
  if (gemfile || packageJson) {
    availableDevCommands.push("dev.run_tests", "dev.run_lint");
  }
  availableDevCommands.push("dev.check");

  return {
    repoRoot: ".",
    railsPresent,
    detectedLanguages: {
      ruby: gemfile,
      js: packageJson
    },
    packageManager,
    isGitRepo,
    availableDevCommands
  };
}

async function handleRepoSearch(input: RepoSearchInput) {
  const maxResults = Math.min(input.maxResults ?? DEFAULT_SEARCH_MAX, HARD_SEARCH_MAX);
  const query = input.query;
  const rgAvailable = await isCommandAvailable("rg");
  const gitAvailable = await isCommandAvailable("git");
  const isGitRepo = gitAvailable ? await detectGitRepo() : false;

  let results: Array<{ path: string; lineNumber: number; preview: string; column?: number }> = [];
  let truncated = false;

  if (rgAvailable) {
    const rgResults = await runSearchWithRg(query, maxResults + 1);
    results = rgResults.results.slice(0, maxResults);
    truncated = rgResults.results.length > maxResults || rgResults.truncated;
  } else if (isGitRepo) {
    const gitResults = await runSearchWithGitGrep(query, maxResults + 1);
    results = gitResults.results.slice(0, maxResults);
    truncated = gitResults.results.length > maxResults || gitResults.truncated;
  } else {
    const walkResults = await runSearchWithWalk(query, maxResults + 1);
    results = walkResults.results.slice(0, maxResults);
    truncated = walkResults.results.length > maxResults || walkResults.truncated;
  }

  return {
    query,
    results,
    truncated
  };
}

async function handleRepoReadFile(input: RepoReadFileInput) {
  const resolved = resolveRepoPath(input.path);
  if (!resolved.ok) {
    return {
      path: safeOutputPath(input.path),
      refused: true,
      reason: "not_found"
    };
  }

  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return {
      path: resolved.relative,
      refused: true,
      reason: "not_found"
    };
  }

  if (!stat.isFile()) {
    return {
      path: resolved.relative,
      refused: true,
      reason: "not_a_file"
    };
  }

  if (stat.size > MAX_FILE_SIZE_BYTES) {
    return {
      path: resolved.relative,
      refused: true,
      reason: "file_too_large",
      sizeBytes: stat.size
    };
  }

  const binary = await isBinaryFile(resolved.resolved);
  if (binary) {
    return {
      path: resolved.relative,
      refused: true,
      reason: "binary_file"
    };
  }

  const content = await fs.readFile(resolved.resolved, "utf8");
  return {
    path: resolved.relative,
    content: normalizeLineEndings(content)
  };
}

async function handleRepoListDir(input: RepoListDirInput) {
  const maxEntries = Math.min(input.maxEntries ?? DEFAULT_LIST_MAX, HARD_LIST_MAX);
  const resolved = resolveRepoPath(input.path ?? "");
  if (!resolved.ok) {
    return {
      path: safeOutputPath(input.path ?? ""),
      entries: [],
      truncated: false,
      error: "path_outside_root"
    };
  }

  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return {
      path: resolved.relative,
      entries: [],
      truncated: false,
      error: "not_found"
    };
  }

  if (!stat.isDirectory()) {
    return {
      path: resolved.relative,
      entries: [],
      truncated: false,
      error: "not_a_dir"
    };
  }

  const dirEntries = await fs.readdir(resolved.resolved, { withFileTypes: true });
  const entries = dirEntries
    .map((entry) => ({
      name: entry.name,
      type: entry.isDirectory() ? "dir" : entry.isFile() ? "file" : "other"
    }))
    .sort((a, b) => {
      if (a.type === b.type) {
        return a.name.localeCompare(b.name);
      }
      if (a.type === "dir") return -1;
      if (b.type === "dir") return 1;
      if (a.type === "file") return -1;
      if (b.type === "file") return 1;
      return a.name.localeCompare(b.name);
    });

  const truncated = entries.length > maxEntries;
  return {
    path: resolved.relative,
    entries: entries.slice(0, maxEntries),
    truncated
  };
}

async function handleDevCheck(_input: Record<string, never>) {
  const tools = await checkDevTools([
    "rg",
    "git",
    "bundle",
    "ruby",
    "npm",
    "yarn",
    "pnpm"
  ]);
  return { tools };
}

async function handleDevRunTests(input: DevRunTargetInput) {
  return handleDevRun(
    input.target,
    async () => selectRubyTestCommand(),
    async (packageManager) => selectJsTestCommand(packageManager)
  );
}

async function handleDevRunLint(input: DevRunTargetInput) {
  return handleDevRun(
    input.target,
    async () => ["bundle", "exec", "rubocop"],
    async (packageManager) => selectJsLintCommand(packageManager)
  );
}

async function handleDevRun(
  target: "ruby" | "js" | "both",
  rubyCommand: () => Promise<string[] | null>,
  jsCommand: (packageManager: PackageManager) => Promise<string[] | null>
) {
  const info = await handleRepoInfo({});
  const results: { ruby?: DevResult; js?: DevResult } = {};
  let ok = true;

  const runRuby = target === "ruby" || target === "both";
  const runJs = target === "js" || target === "both";

  if (runRuby) {
    if (!info.detectedLanguages.ruby) {
      results.ruby = missingLanguageResult("ruby");
      ok = false;
    } else {
      const command = await rubyCommand();
      if (!command) {
        results.ruby = missingCommandResult("ruby");
        ok = false;
      } else {
        const result = await runDevCommand(command);
        results.ruby = result;
        ok = ok && result.ok;
      }
    }
  }

  if (runJs) {
    if (!info.detectedLanguages.js) {
      results.js = missingLanguageResult("js");
      ok = false;
    } else {
      const command = await jsCommand(info.packageManager);
      if (!command) {
        results.js = missingCommandResult("js");
        ok = false;
      } else {
        const result = await runDevCommand(command);
        results.js = result;
        ok = ok && result.ok;
      }
    }
  }

  return { ok, results };
}

async function selectRubyTestCommand() {
  const rspec = resolveRepoPath("bin/rspec");
  if (rspec.ok) {
    try {
      const stat = await fs.stat(rspec.resolved);
      if (stat.isFile()) {
        return ["bin/rspec"];
      }
    } catch {
      return ["bundle", "exec", "rspec"];
    }
  }
  return ["bundle", "exec", "rspec"];
}

async function selectJsTestCommand(packageManager: PackageManager) {
  switch (packageManager) {
    case "pnpm":
      return ["pnpm", "test"];
    case "yarn":
      return ["yarn", "test"];
    case "npm":
      return ["npm", "test"];
    default:
      return null;
  }
}

async function selectJsLintCommand(packageManager: PackageManager) {
  switch (packageManager) {
    case "pnpm":
      return ["pnpm", "run", "lint"];
    case "yarn":
      return ["yarn", "lint"];
    case "npm":
      return ["npm", "run", "lint"];
    default:
      return null;
  }
}

function missingLanguageResult(target: "ruby" | "js"): DevResult {
  return {
    ok: false,
    exitCode: -1,
    command: [],
    stdout: "",
    stderr: `${target}_not_detected`,
    truncated: false,
    truncatedBytes: 0,
    durationMs: 0
  };
}

function missingCommandResult(target: "ruby" | "js"): DevResult {
  return {
    ok: false,
    exitCode: -1,
    command: [],
    stdout: "",
    stderr: `${target}_command_unavailable`,
    truncated: false,
    truncatedBytes: 0,
    durationMs: 0
  };
}

async function runDevCommand(command: string[]): Promise<DevResult> {
  const timeoutMs = resolveCommandTimeout();
  const startTime = Date.now();
  const processResult = await runCommandWithLimits(command, timeoutMs, MAX_CMD_OUTPUT_BYTES);
  const durationMs = Date.now() - startTime;

  return {
    ok: processResult.exitCode === 0,
    exitCode: processResult.exitCode,
    command,
    stdout: processResult.stdout,
    stderr: processResult.stderr,
    truncated: processResult.truncated,
    truncatedBytes: processResult.truncatedBytes,
    durationMs
  };
}

async function runSearchWithRg(query: string, maxResults: number) {
  const args = [
    "--line-number",
    "--column",
    "--no-heading",
    "--fixed-strings",
    "--",
    query,
    "."
  ];
  const result = await runSimpleCommand("rg", args, 10_000, 512 * 1024);
  if (!result.ok) {
    return { results: [], truncated: false };
  }
  const lines = result.stdout.split("\n").filter(Boolean);
  const results: Array<{ path: string; lineNumber: number; preview: string; column?: number }> = [];
  for (const line of lines) {
    const match = line.match(/^(.*?):(\d+):(\d+):(.*)$/);
    if (!match) continue;
    const relPath = normalizeRelativePath(match[1]);
    const lineNumber = Number(match[2]);
    const column = Number(match[3]);
    const preview = match[4].slice(0, MAX_PREVIEW_CHARS);
    results.push({ path: relPath, lineNumber, column, preview });
    if (results.length >= maxResults) break;
  }
  return { results, truncated: lines.length > results.length };
}

async function runSearchWithGitGrep(query: string, maxResults: number) {
  const args = ["-C", repoRoot, "grep", "-n", "--fixed-strings", "--", query];
  const result = await runSimpleCommand("git", args, 10_000, 512 * 1024);
  if (!result.ok) {
    return { results: [], truncated: false };
  }
  const lines = result.stdout.split("\n").filter(Boolean);
  const results: Array<{ path: string; lineNumber: number; preview: string }> = [];
  for (const line of lines) {
    const match = line.match(/^(.*?):(\d+):(.*)$/);
    if (!match) continue;
    const relPath = normalizeRelativePath(match[1]);
    const lineNumber = Number(match[2]);
    const preview = match[3].slice(0, MAX_PREVIEW_CHARS);
    results.push({ path: relPath, lineNumber, preview });
    if (results.length >= maxResults) break;
  }
  return { results, truncated: lines.length > results.length };
}

async function runSearchWithWalk(query: string, maxResults: number) {
  const results: Array<{ path: string; lineNumber: number; preview: string }> = [];
  let truncated = false;

  const shouldStop = () => results.length >= maxResults;

  async function walk(current: string) {
    if (shouldStop()) return;
    let entries: fsSync.Dirent[];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (shouldStop()) return;
      if (entry.isDirectory()) {
        if (SKIP_DIR_NAMES.has(entry.name)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const fullPath = path.join(current, entry.name);
        const relPath = path.relative(repoRoot, fullPath);
        const relPathNormalized = normalizeRelativePath(relPath);
        const fileResult = await searchFile(fullPath, relPathNormalized, query, maxResults - results.length);
        results.push(...fileResult.results);
        if (fileResult.truncated) {
          truncated = true;
          return;
        }
      }
    }
  }

  await walk(repoRoot);
  if (results.length >= maxResults) {
    truncated = true;
  }
  return { results, truncated };
}

async function searchFile(
  fullPath: string,
  relPath: string,
  query: string,
  remaining: number
): Promise<{ results: Array<{ path: string; lineNumber: number; preview: string }>; truncated: boolean }> {
  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(fullPath);
  } catch {
    return { results: [], truncated: false };
  }
  if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES) {
    return { results: [], truncated: false };
  }
  const binary = await isBinaryFile(fullPath);
  if (binary) {
    return { results: [], truncated: false };
  }
  const content = await fs.readFile(fullPath, "utf8");
  const normalized = normalizeLineEndings(content);
  const lines = normalized.split("\n");
  const results: Array<{ path: string; lineNumber: number; preview: string }> = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (results.length >= remaining) {
      return { results, truncated: true };
    }
    if (lines[i].includes(query)) {
      results.push({
        path: relPath,
        lineNumber: i + 1,
        preview: lines[i].slice(0, MAX_PREVIEW_CHARS)
      });
    }
  }
  return { results, truncated: false };
}

async function checkDevTools(tools: string[]) {
  const result: Record<string, { present: boolean; version?: string }> = {};
  for (const tool of tools) {
    const version = await getCommandVersion(tool);
    if (version) {
      result[tool] = { present: true, version };
    } else {
      result[tool] = { present: false };
    }
  }
  return result as {
    rg: { present: boolean; version?: string };
    git: { present: boolean; version?: string };
    bundle: { present: boolean; version?: string };
    ruby: { present: boolean; version?: string };
    npm: { present: boolean; version?: string };
    yarn: { present: boolean; version?: string };
    pnpm: { present: boolean; version?: string };
  };
}

async function getCommandVersion(command: string) {
  const result = await runSimpleCommand(command, ["--version"], CHECK_TIMEOUT_MS, 8 * 1024);
  if (!result.ok) return undefined;
  const output = result.stdout.trim() || result.stderr.trim();
  return output || undefined;
}

async function isCommandAvailable(command: string) {
  const version = await getCommandVersion(command);
  return Boolean(version);
}

type RunCommandResult = {
  exitCode: number;
  stdout: string;
  stderr: string;
  truncated: boolean;
  truncatedBytes: number;
};

async function runCommandWithLimits(
  command: string[],
  timeoutMs: number,
  maxBytes: number
): Promise<RunCommandResult> {
  return new Promise((resolve) => {
    const child = spawn(command[0], command.slice(1), {
      cwd: repoRoot,
      env: process.env,
      shell: false
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let totalBytes = 0;
    let truncated = false;

    const stdoutCap = maxBytes;
    const stderrCap = maxBytes;

    const onData = (chunk: Buffer, stream: "stdout" | "stderr") => {
      totalBytes += chunk.length;
      if (stream === "stdout") {
        if (stdoutBytes < stdoutCap) {
          const slice = chunk.slice(0, stdoutCap - stdoutBytes);
          stdoutChunks.push(slice);
          stdoutBytes += slice.length;
        } else {
          truncated = true;
        }
      } else {
        if (stderrBytes < stderrCap) {
          const slice = chunk.slice(Math.max(0, chunk.length - (stderrCap - stderrBytes)));
          stderrChunks.push(slice);
          stderrBytes += slice.length;
        } else {
          truncated = true;
        }
      }
    };

    child.stdout?.on("data", (chunk: Buffer) => onData(chunk, "stdout"));
    child.stderr?.on("data", (chunk: Buffer) => onData(chunk, "stderr"));

    let timeout: NodeJS.Timeout | undefined;
    if (timeoutMs > 0) {
      timeout = setTimeout(() => {
        truncated = true;
        child.kill("SIGKILL");
      }, timeoutMs);
    }

    child.on("close", (code) => {
      if (timeout) clearTimeout(timeout);
      let stdout = Buffer.concat(stdoutChunks).toString("utf8");
      let stderr = Buffer.concat(stderrChunks).toString("utf8");
      stdout = normalizeLineEndings(stdout);
      stderr = normalizeLineEndings(stderr);

      let returnedBytes = Buffer.byteLength(stdout) + Buffer.byteLength(stderr);
      if (returnedBytes > maxBytes) {
        const allowedStdout = Math.max(0, maxBytes - Buffer.byteLength(stderr));
        if (allowedStdout < Buffer.byteLength(stdout)) {
          stdout = stdout.slice(0, allowedStdout);
          truncated = true;
        }
        returnedBytes = Buffer.byteLength(stdout) + Buffer.byteLength(stderr);
      }

      const truncatedBytes = Math.max(0, totalBytes - returnedBytes);

      resolve({
        exitCode: typeof code === "number" ? code : -1,
        stdout,
        stderr,
        truncated: truncated || truncatedBytes > 0,
        truncatedBytes
      });
    });

    child.on("error", () => {
      if (timeout) clearTimeout(timeout);
      resolve({
        exitCode: -1,
        stdout: "",
        stderr: "command_failed",
        truncated: false,
        truncatedBytes: 0
      });
    });
  });
}

async function runSimpleCommand(
  command: string,
  args: string[],
  timeoutMs: number,
  maxBytes: number
): Promise<{ ok: boolean; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    const child = spawn(command, args, {
      cwd: repoRoot,
      env: process.env,
      shell: false
    });

    const onData = (chunk: Buffer, target: "stdout" | "stderr") => {
      const text = chunk.toString("utf8");
      if (target === "stdout") {
        stdout += text;
      } else {
        stderr += text;
      }
      if (Buffer.byteLength(stdout) + Buffer.byteLength(stderr) > maxBytes) {
        child.kill("SIGKILL");
      }
    };

    child.stdout?.on("data", (chunk: Buffer) => onData(chunk, "stdout"));
    child.stderr?.on("data", (chunk: Buffer) => onData(chunk, "stderr"));

    let timeout: NodeJS.Timeout | undefined;
    if (timeoutMs > 0) {
      timeout = setTimeout(() => {
        child.kill("SIGKILL");
      }, timeoutMs);
    }

    child.on("close", (code) => {
      if (timeout) clearTimeout(timeout);
      resolve({
        ok: code === 0,
        stdout: normalizeLineEndings(stdout),
        stderr: normalizeLineEndings(stderr)
      });
    });

    child.on("error", () => {
      if (timeout) clearTimeout(timeout);
      resolve({ ok: false, stdout: "", stderr: "command_failed" });
    });
  });
}

function resolveRepoRoot() {
  const arg = process.argv[2];
  if (arg && arg.trim().length > 0) {
    return path.resolve(arg);
  }
  const envRoot = process.env.BIDDERSWEET_REPO_ROOT;
  if (envRoot && envRoot.trim().length > 0) {
    return path.resolve(envRoot);
  }
  return process.cwd();
}

function resolveRepoPath(userPath: string): { ok: boolean; resolved: string; relative: string } | { ok: false } {
  const normalized = path.normalize(userPath);
  const segments = normalized.split(path.sep).filter(Boolean);
  if (segments.includes("..")) {
    return { ok: false };
  }
  const resolved = path.resolve(repoRoot, userPath);
  if (!isWithinRepoRoot(resolved)) {
    return { ok: false };
  }
  const relative = normalizeRelativePath(path.relative(repoRoot, resolved)) || ".";
  return { ok: true, resolved, relative };
}

function normalizeRelativePath(relativePath: string) {
  return relativePath.split(path.sep).join("/");
}

function isWithinRepoRoot(resolvedPath: string) {
  return resolvedPath === repoRoot || resolvedPath.startsWith(repoRoot + path.sep);
}

function safeOutputPath(userPath: string) {
  const resolved = resolveRepoPath(userPath);
  if (resolved.ok) return resolved.relative;
  return ".";
}

async function existsInRepo(relPath: string) {
  const resolved = resolveRepoPath(relPath);
  if (!resolved.ok) return false;
  try {
    await fs.access(resolved.resolved);
    return true;
  } catch {
    return false;
  }
}

async function detectGitRepo() {
  const dotGit = path.join(repoRoot, ".git");
  if (fsSync.existsSync(dotGit)) return true;
  const gitAvailable = await isCommandAvailable("git");
  if (!gitAvailable) return false;
  const result = await runSimpleCommand("git", ["-C", repoRoot, "rev-parse", "--is-inside-work-tree"], 2_000, 2048);
  if (!result.ok) return false;
  return result.stdout.trim() === "true";
}

type PackageManager = "npm" | "yarn" | "pnpm" | "unknown";

async function detectPackageManager(): Promise<PackageManager> {
  if (await existsInRepo("pnpm-lock.yaml")) return "pnpm";
  if (await existsInRepo("yarn.lock")) return "yarn";
  if (await existsInRepo("package-lock.json")) return "npm";
  return "unknown";
}

async function isBinaryFile(filePath: string) {
  const handle = await fs.open(filePath, "r");
  try {
    const buffer = Buffer.alloc(1024);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    for (let i = 0; i < bytesRead; i += 1) {
      if (buffer[i] === 0) return true;
    }
    return false;
  } finally {
    await handle.close();
  }
}

function normalizeLineEndings(value: string) {
  return value.replace(/\r\n/g, "\n");
}

function resolveCommandTimeout() {
  const raw = process.env.BIDDERSWEET_CMD_TIMEOUT_MS;
  if (!raw) return DEFAULT_CMD_TIMEOUT_MS;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_CMD_TIMEOUT_MS;
  return parsed;
}

function emptyInputSchema() {
  return {
    type: "object",
    properties: {},
    additionalProperties: false
  };
}

function jsonResult(payload: unknown, isError = false) {
  return {
    isError,
    content: [
      {
        type: "text",
        text: JSON.stringify(payload)
      }
    ]
  };
}

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(() => {
  process.exit(1);
});
