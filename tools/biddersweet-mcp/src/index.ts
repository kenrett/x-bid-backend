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
const DEFAULT_FIND_REFS_MAX_FILES = 50;
const HARD_FIND_REFS_MAX_FILES = 200;
const DEFAULT_FIND_REFS_SNIPPETS = 3;
const HARD_FIND_REFS_SNIPPETS = 10;
const MAX_FIND_REFS_OUTPUT_BYTES = 1024 * 1024;
const FIND_REFS_CONTEXT_RADIUS = 1;
const MAX_FIND_REFS_HITS = HARD_FIND_REFS_MAX_FILES * HARD_FIND_REFS_SNIPPETS * 10;
const DEFAULT_LIST_MAX = 500;
const HARD_LIST_MAX = 2000;
const MAX_READ_RANGE_LINES = 400;
const DEFAULT_TREE_DEPTH = 3;
const DEFAULT_TREE_MAX_NODES = 400;
const DEFAULT_TREE_MAX_ENTRIES = 200;
const DEFAULT_SYMBOLS_MAX = 200;
const HARD_SYMBOLS_MAX = 500;
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
const RepoReadRangeInputSchema = z.object({
  path: z.string(),
  startLine: z.number().int(),
  endLine: z.number().int()
});
const RepoListDirInputSchema = z.object({
  path: z.string().optional().default(""),
  maxEntries: z.number().int().positive().optional()
});
const RepoDepsInputSchema = z.object({});
const RepoTreeInputSchema = z.object({
  path: z.string().optional().default("."),
  maxDepth: z.number().int().positive().optional(),
  maxNodes: z.number().int().positive().optional(),
  maxEntriesPerDir: z.number().int().positive().optional()
});
const RepoSymbolsInputSchema = z.object({
  glob: z.string().optional(),
  kinds: z.array(z.string()).optional(),
  maxResults: z.number().int().positive().optional()
});
const RepoFindRefsInputSchema = z.object({
  symbol: z.string().min(1),
  languageHint: z.enum(["ruby", "js", "ts", "any"]).optional(),
  maxFiles: z.number().int().positive().optional(),
  maxSnippetsPerFile: z.number().int().positive().optional()
});
const DevCheckInputSchema = z.object({});
const DevRunTargetSchema = z.object({
  target: z.enum(["ruby", "js", "both"]).optional().default("both")
});

type RepoInfoInput = z.infer<typeof RepoInfoInputSchema>;
type RepoSearchInput = z.infer<typeof RepoSearchInputSchema>;
type RepoReadFileInput = z.infer<typeof RepoReadFileInputSchema>;
type RepoReadRangeInput = z.infer<typeof RepoReadRangeInputSchema>;
type RepoListDirInput = z.infer<typeof RepoListDirInputSchema>;
type RepoDepsInput = z.infer<typeof RepoDepsInputSchema>;
type RepoTreeInput = z.infer<typeof RepoTreeInputSchema>;
type RepoSymbolsInput = z.infer<typeof RepoSymbolsInputSchema>;
type RepoFindRefsInput = z.infer<typeof RepoFindRefsInputSchema>;
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

type RepoTreeNode = {
  name: string;
  type: "file" | "dir";
  children?: RepoTreeNode[];
};

type RepoSymbol = {
  name: string;
  kind: string;
  path: string;
  line: number;
  language: string;
};

type RepoRefSnippet = {
  line: number;
  preview: string;
  contextStartLine?: number;
  contextEndLine?: number;
};

type RepoRefHit = {
  path: string;
  lineNumber: number;
  preview: string;
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
        name: "repo.read_range",
        description: "Read a specific line range within a text file in the repo.",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
            startLine: { type: "number" },
            endLine: { type: "number" }
          },
          required: ["path", "startLine", "endLine"],
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
        name: "repo.deps",
        description: "Summarize language/toolchain versions and key dependencies.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "repo.symbols",
        description: "Return an index of symbols (definitions) within the repo.",
        inputSchema: {
          type: "object",
          properties: {
            glob: { type: "string" },
            kinds: { type: "array", items: { type: "string" } },
            maxResults: { type: "number" }
          },
          additionalProperties: false
        }
      },
      {
        name: "repo.tree",
        description: "Return a bounded recursive directory tree within the repo.",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
            maxDepth: { type: "number" },
            maxNodes: { type: "number" },
            maxEntriesPerDir: { type: "number" }
          },
          additionalProperties: false
        }
      },
      {
        name: "repo.find_refs",
        description: "Find references to a symbol across the repo with contextual snippets.",
        inputSchema: {
          type: "object",
          properties: {
            symbol: { type: "string" },
            languageHint: { type: "string", enum: ["ruby", "js", "ts", "any"] },
            maxFiles: { type: "number" },
            maxSnippetsPerFile: { type: "number" }
          },
          required: ["symbol"],
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
      case "repo.read_range": {
        const parsed = RepoReadRangeInputSchema.parse(args ?? {});
        const result = await handleRepoReadRange(parsed);
        return jsonResult(result, Boolean((result as { error?: unknown }).error));
      }
      case "repo.list_dir": {
        const parsed = RepoListDirInputSchema.parse(args ?? {});
        const result = await handleRepoListDir(parsed);
        return jsonResult(result);
      }
      case "repo.deps": {
        const parsed = RepoDepsInputSchema.parse(args ?? {});
        const result = await handleRepoDeps(parsed);
        return jsonResult(result, Boolean((result as { error?: unknown }).error));
      }
      case "repo.symbols": {
        const parsed = RepoSymbolsInputSchema.parse(args ?? {});
        const result = await handleRepoSymbols(parsed);
        return jsonResult(result, Boolean((result as { error?: unknown }).error));
      }
      case "repo.tree": {
        const parsed = RepoTreeInputSchema.parse(args ?? {});
        const result = await handleRepoTree(parsed);
        return jsonResult(result, Boolean((result as { error?: unknown }).error));
      }
      case "repo.find_refs": {
        const parsed = RepoFindRefsInputSchema.parse(args ?? {});
        const result = await handleRepoFindRefs(parsed);
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

async function handleRepoReadRange(input: RepoReadRangeInput) {
  const resolved = resolveRepoPath(input.path);
  if (!resolved.ok) {
    return toolError("path_outside_root", "path is outside repo root", {
      path: safeOutputPath(input.path)
    });
  }

  if (input.startLine <= 0 || input.endLine <= 0 || input.startLine > input.endLine) {
    return toolError("invalid_range", "startLine and endLine must be positive and startLine <= endLine", {
      path: resolved.relative,
      startLine: input.startLine,
      endLine: input.endLine
    });
  }

  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return toolError("not_found", "file not found", { path: resolved.relative });
  }

  if (!stat.isFile()) {
    return toolError("not_a_file", "path is not a file", { path: resolved.relative });
  }

  if (stat.size > MAX_FILE_SIZE_BYTES) {
    return toolError("file_too_large", "file exceeds size limit", {
      path: resolved.relative,
      sizeBytes: stat.size
    });
  }

  const binary = await isBinaryFile(resolved.resolved);
  if (binary) {
    return toolError("binary_file", "file is binary", { path: resolved.relative });
  }

  const content = await fs.readFile(resolved.resolved, "utf8");
  const normalized = normalizeLineEndings(content);
  const lines = normalized.length === 0 ? [] : normalized.split("\n");
  const totalLines = lines.length;
  const warnings: string[] = [];

  let startLine = input.startLine;
  let endLine = input.endLine;
  let truncated = false;

  if (totalLines === 0) {
    warnings.push("file_is_empty");
    return {
      path: resolved.relative,
      startLine,
      endLine,
      text: "",
      totalLines,
      truncated,
      warnings
    };
  }

  if (startLine > totalLines) {
    warnings.push("startLine_out_of_range");
    return {
      path: resolved.relative,
      startLine,
      endLine,
      text: "",
      totalLines,
      truncated,
      warnings
    };
  }

  if (endLine > totalLines) {
    warnings.push("endLine_out_of_range");
    endLine = totalLines;
  }

  if (endLine - startLine + 1 > MAX_READ_RANGE_LINES) {
    warnings.push("range_truncated");
    endLine = startLine + MAX_READ_RANGE_LINES - 1;
    truncated = true;
  }

  const text = lines.slice(startLine - 1, endLine).join("\n");

  return {
    path: resolved.relative,
    startLine,
    endLine,
    text,
    totalLines,
    truncated,
    warnings: warnings.length > 0 ? warnings : undefined
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
  const entries: Array<{ name: string; type: "file" | "dir" | "other" }> = dirEntries
    .map((entry: fsSync.Dirent): { name: string; type: "file" | "dir" | "other" } => {
      const type = entry.isDirectory() ? "dir" : entry.isFile() ? "file" : "other";
      return { name: entry.name, type };
    })
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

async function handleRepoDeps(_input: RepoDepsInput) {
  const warnings: string[] = [];
  const filesChecked: string[] = [];

  const readTextFile = async (relPath: string) => {
    const resolved = resolveRepoPath(relPath);
    if (!resolved.ok) return { missing: true as const };
    let stat: fsSync.Stats;
    try {
      stat = await fs.stat(resolved.resolved);
    } catch {
      return { missing: true as const };
    }
    if (!stat.isFile()) {
      warnings.push(`${relPath}:not_a_file`);
      return { missing: true as const };
    }
    if (stat.size > MAX_FILE_SIZE_BYTES) {
      warnings.push(`${relPath}:file_too_large`);
      return { missing: true as const };
    }
    const binary = await isBinaryFile(resolved.resolved);
    if (binary) {
      warnings.push(`${relPath}:binary_file`);
      return { missing: true as const };
    }
    const content = await fs.readFile(resolved.resolved, "utf8");
    filesChecked.push(resolved.relative);
    return { content: normalizeLineEndings(content) };
  };

  const ruby: { version?: string; railsVersion?: string; bundlerVersion?: string } = {};
  const node: { version?: string; packageManager?: string; workspaceType?: string } = {};
  const gems: { top: Array<{ name: string; version?: string }>; hasGemfileLock: boolean } = {
    top: [],
    hasGemfileLock: false
  };
  const js: {
    dependenciesTop: Array<{ name: string; versionRange: string }>;
    scripts: Record<string, string>;
    hasLockfile: boolean;
  } = { dependenciesTop: [], scripts: {}, hasLockfile: false };

  const rubyVersionFile = await readTextFile(".ruby-version");
  if ("content" in rubyVersionFile) {
    ruby.version = rubyVersionFile.content.trim().split("\n")[0] || undefined;
  }

  const nodeVersionFile = await readTextFile(".node-version");
  if ("content" in nodeVersionFile) {
    node.version = nodeVersionFile.content.trim().split("\n")[0] || undefined;
  }

  const gemfile = await readTextFile("Gemfile");
  if ("content" in gemfile) {
    const lines = gemfile.content.split("\n");
    for (const line of lines) {
      const match = line.match(/^\s*gem\s+["']([^"']+)["'](?:\s*,\s*["']([^"']+)["'])?/);
      if (!match) continue;
      const name = match[1];
      const version = match[2];
      gems.top.push({ name, version });
      if (name === "rails" && !ruby.railsVersion && version) {
        ruby.railsVersion = version;
      }
    }
  }

  const gemfileLock = await readTextFile("Gemfile.lock");
  if ("content" in gemfileLock) {
    gems.hasGemfileLock = true;
    const lines = gemfileLock.content.split("\n");
    for (const line of lines) {
      const match = line.match(/^\s{4}rails\s+\(([^)]+)\)/);
      if (match) {
        ruby.railsVersion = match[1];
        break;
      }
    }
    const bundledIndex = lines.findIndex((line) => line.trim() === "BUNDLED WITH");
    if (bundledIndex >= 0) {
      for (let i = bundledIndex + 1; i < lines.length; i += 1) {
        const version = lines[i].trim();
        if (version.length === 0) continue;
        ruby.bundlerVersion = version;
        break;
      }
    }
  }

  const packageJson = await readTextFile("package.json");
  if ("content" in packageJson) {
    try {
      const parsed = JSON.parse(packageJson.content) as {
        dependencies?: Record<string, string>;
        devDependencies?: Record<string, string>;
        scripts?: Record<string, string>;
        packageManager?: string;
        workspaces?: unknown;
      };
      const deps: Array<{ name: string; versionRange: string }> = [];
      if (parsed.dependencies) {
        for (const [name, versionRange] of Object.entries(parsed.dependencies)) {
          deps.push({ name, versionRange });
        }
      }
      if (parsed.devDependencies) {
        for (const [name, versionRange] of Object.entries(parsed.devDependencies)) {
          deps.push({ name, versionRange });
        }
      }
      deps.sort((a, b) => a.name.localeCompare(b.name));
      js.dependenciesTop = deps.slice(0, 50);
      js.scripts = parsed.scripts ?? {};
      if (parsed.packageManager) {
        const pm = parsed.packageManager.split("@")[0];
        node.packageManager = pm;
      }
      if (parsed.workspaces) {
        node.workspaceType = "workspace";
      }
    } catch (error) {
      warnings.push(`package.json:parse_error`);
    }
  }

  if (!node.packageManager) {
    const detected = await detectPackageManager();
    if (detected !== "unknown") node.packageManager = detected;
  }

  const lockfiles = ["pnpm-lock.yaml", "yarn.lock", "package-lock.json"];
  for (const lockfile of lockfiles) {
    const resolved = resolveRepoPath(lockfile);
    if (resolved.ok && fsSync.existsSync(resolved.resolved)) {
      js.hasLockfile = true;
      if (!filesChecked.includes(resolved.relative)) {
        filesChecked.push(resolved.relative);
      }
    }
  }

  if (!node.workspaceType) {
    const pnpmWorkspace = resolveRepoPath("pnpm-workspace.yaml");
    if (pnpmWorkspace.ok && fsSync.existsSync(pnpmWorkspace.resolved)) {
      node.workspaceType = "workspace";
      filesChecked.push(pnpmWorkspace.relative);
    } else if (!node.workspaceType) {
      node.workspaceType = "single";
    }
  }

  const toolingFiles = ["Dockerfile", "render.yaml", "Procfile"];
  for (const tooling of toolingFiles) {
    const resolved = resolveRepoPath(tooling);
    if (resolved.ok && fsSync.existsSync(resolved.resolved)) {
      filesChecked.push(resolved.relative);
    }
  }

  const githubWorkflows = resolveRepoPath(".github/workflows");
  if (githubWorkflows.ok && fsSync.existsSync(githubWorkflows.resolved)) {
    filesChecked.push(githubWorkflows.relative);
  }

  return {
    ruby,
    node,
    gems: {
      top: gems.top.slice(0, 50),
      hasGemfileLock: gems.hasGemfileLock
    },
    js,
    filesChecked: Array.from(new Set(filesChecked)),
    warnings
  };
}

async function handleRepoSymbols(input: RepoSymbolsInput) {
  const maxResults = Math.min(input.maxResults ?? DEFAULT_SYMBOLS_MAX, HARD_SYMBOLS_MAX);
  const kindsFilter = (input.kinds ?? []).map((kind) => kind.toLowerCase());

  const files = await listCandidateFiles(input.glob);

  let strategy: "ctags" | "heuristic" = "heuristic";
  let results: RepoSymbol[] = [];
  const warnings: string[] = [...files.warnings];

  const ctagsAvailable = await isCommandAvailable("ctags");
  if (ctagsAvailable && files.paths.length > 0) {
    const ctags = await runCtags(files.paths, maxResults);
    if (ctags.ok) {
      strategy = "ctags";
      results = ctags.results;
      if (ctags.truncated) warnings.push("truncated");
    } else {
      warnings.push("ctags_failed");
    }
  }

  if (strategy === "heuristic") {
    const heuristic = await runHeuristicSymbols(files.paths, maxResults, kindsFilter);
    results = heuristic.results;
    if (heuristic.truncated) warnings.push("truncated");
  }

  if (kindsFilter.length > 0) {
    results = results.filter((result) => kindsFilter.includes(result.kind.toLowerCase()));
  }

  results.sort((a, b) => {
    if (a.path === b.path) return a.line - b.line;
    return a.path.localeCompare(b.path);
  });

  const truncated = results.length > maxResults || warnings.includes("truncated");
  const sliced = results.slice(0, maxResults);

  return {
    results: sliced,
    truncated,
    strategy,
    warnings
  };
}

async function handleRepoTree(input: RepoTreeInput) {
  const maxDepth = input.maxDepth ?? DEFAULT_TREE_DEPTH;
  const maxNodes = input.maxNodes ?? DEFAULT_TREE_MAX_NODES;
  const maxEntriesPerDir = input.maxEntriesPerDir ?? DEFAULT_TREE_MAX_ENTRIES;

  if (maxDepth <= 0 || maxNodes <= 0 || maxEntriesPerDir <= 0) {
    return toolError("invalid_params", "maxDepth, maxNodes, and maxEntriesPerDir must be positive integers", {
      path: input.path ?? ".",
      maxDepth,
      maxNodes,
      maxEntriesPerDir
    });
  }

  const resolved = resolveRepoPath(input.path ?? ".");
  if (!resolved.ok) {
    return toolError("path_outside_root", "path is outside repo root", {
      path: safeOutputPath(input.path ?? ".")
    });
  }

  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return toolError("not_found", "path not found", { path: resolved.relative });
  }

  let nodesReturned = 0;
  let truncated = false;

  const rootName = resolved.relative === "." ? "." : path.basename(resolved.relative);

  const shouldStop = () => nodesReturned >= maxNodes;

  const buildTree = async (fullPath: string, name: string, depth: number): Promise<RepoTreeNode> => {
    if (shouldStop()) {
      truncated = true;
      return { name, type: "dir", children: [] };
    }

    if (depth > maxDepth) {
      return { name, type: "dir", children: [] };
    }

    const nodeStat = await fs.stat(fullPath);
    if (!nodeStat.isDirectory()) {
      nodesReturned += 1;
      return { name, type: "file" };
    }

    nodesReturned += 1;
    if (depth === maxDepth) {
      return { name, type: "dir" };
    }

    let entries: fsSync.Dirent[];
    try {
      entries = await fs.readdir(fullPath, { withFileTypes: true });
    } catch {
      return { name, type: "dir" };
    }

    const filtered = entries.filter((entry) => {
      if (entry.isDirectory() && SKIP_DIR_NAMES.has(entry.name)) return false;
      return true;
    });

    filtered.sort((a, b) => {
      const aDir = a.isDirectory();
      const bDir = b.isDirectory();
      if (aDir && !bDir) return -1;
      if (!aDir && bDir) return 1;
      return a.name.localeCompare(b.name);
    });

    let working = filtered;
    if (filtered.length > maxEntriesPerDir) {
      working = filtered.slice(0, maxEntriesPerDir);
      truncated = true;
    }

    const children: RepoTreeNode[] = [];

    for (const entry of working) {
      if (shouldStop()) {
        truncated = true;
        break;
      }
      const childPath = path.join(fullPath, entry.name);
      if (entry.isDirectory()) {
        const child = await buildTree(childPath, entry.name, depth + 1);
        children.push(child);
      } else if (entry.isFile()) {
        nodesReturned += 1;
        children.push({ name: entry.name, type: "file" });
      } else {
        nodesReturned += 1;
        children.push({ name: entry.name, type: "file" });
      }
    }

    return { name, type: "dir", children: children.length > 0 ? children : undefined };
  };

  const tree = stat.isDirectory()
    ? await buildTree(resolved.resolved, rootName, 0)
    : (() => {
        nodesReturned += 1;
        return { name: rootName, type: "file" };
      })();

  return {
    path: resolved.relative,
    maxDepth,
    nodesReturned,
    truncated,
    tree
  };
}

async function handleRepoFindRefs(input: RepoFindRefsInput) {
  const symbol = input.symbol;
  const maxFiles = Math.min(input.maxFiles ?? DEFAULT_FIND_REFS_MAX_FILES, HARD_FIND_REFS_MAX_FILES);
  const maxSnippetsPerFile = Math.min(
    input.maxSnippetsPerFile ?? DEFAULT_FIND_REFS_SNIPPETS,
    HARD_FIND_REFS_SNIPPETS
  );
  const languageHint = input.languageHint ?? "any";

  const rgAvailable = await isCommandAvailable("rg");
  const gitAvailable = await isCommandAvailable("git");
  const isGitRepo = gitAvailable ? await detectGitRepo() : false;

  let strategy: "rg" | "git_grep" | "walk" = "walk";
  let hits: RepoRefHit[] = [];
  let truncated = false;

  if (rgAvailable) {
    const rgResults = await runFindRefsWithRg(symbol, languageHint);
    strategy = "rg";
    hits = rgResults.hits;
    truncated = rgResults.truncated;
  } else if (isGitRepo) {
    const gitResults = await runFindRefsWithGitGrep(symbol, languageHint);
    strategy = "git_grep";
    hits = gitResults.hits;
    truncated = gitResults.truncated;
  } else {
    const walkResults = await runFindRefsWithWalk(symbol, languageHint);
    strategy = "walk";
    hits = walkResults.hits;
    truncated = walkResults.truncated;
  }

  const grouped = new Map<string, { occurrences: number; hits: RepoRefHit[] }>();
  const perFileHitCap = Math.max(maxSnippetsPerFile * 5, maxSnippetsPerFile);

  for (const hit of hits) {
    const entry = grouped.get(hit.path) ?? { occurrences: 0, hits: [] };
    entry.occurrences += 1;
    if (entry.hits.length < perFileHitCap) {
      entry.hits.push(hit);
    }
    grouped.set(hit.path, entry);
  }

  const sortedFiles = Array.from(grouped.entries()).sort((a, b) => {
    if (a[1].occurrences === b[1].occurrences) {
      return a[0].localeCompare(b[0]);
    }
    return b[1].occurrences - a[1].occurrences;
  });

  if (sortedFiles.length > maxFiles) {
    truncated = true;
  }

  const files = [];
  for (const [filePath, info] of sortedFiles.slice(0, maxFiles)) {
    const snippets = await buildRefSnippets(filePath, info.hits, maxSnippetsPerFile);
    files.push({
      path: filePath,
      occurrences: info.occurrences,
      snippets
    });
  }

  return {
    symbol,
    files,
    truncated,
    strategy
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

async function runFindRefsWithRg(symbol: string, languageHint: string) {
  const args = ["--line-number", "--no-heading", "--fixed-strings"];
  for (const skip of SKIP_DIR_NAMES) {
    args.push("-g", `!${skip}/**`);
  }
  const globs = languageHint === "any" ? [] : languageHintToGlobs(languageHint);
  for (const glob of globs) {
    args.push("-g", glob);
  }
  args.push("--", symbol, ".");

  const result = await runCommandWithLimits(["rg", ...args], 10_000, MAX_FIND_REFS_OUTPUT_BYTES);
  const hits: RepoRefHit[] = [];
  if (result.exitCode > 1 && result.stdout.length === 0) {
    return { hits, truncated: result.truncated };
  }

  const lines = result.stdout.split("\n").filter(Boolean);
  for (const line of lines) {
    const match = line.match(/^(.*?):(\d+):(.*)$/);
    if (!match) continue;
    const relPath = normalizeRelativePath(match[1]);
    if (!fileMatchesLanguage(relPath, languageHint)) continue;
    hits.push({
      path: relPath,
      lineNumber: Number(match[2]),
      preview: match[3].slice(0, MAX_PREVIEW_CHARS)
    });
  }

  return { hits, truncated: result.truncated };
}

async function runFindRefsWithGitGrep(symbol: string, languageHint: string) {
  const args = ["-C", repoRoot, "grep", "-n", "--fixed-strings"];
  for (const skip of SKIP_DIR_NAMES) {
    args.push(`--exclude-dir=${skip}`);
  }
  args.push("--", symbol, ".");

  const result = await runCommandWithLimits(["git", ...args], 10_000, MAX_FIND_REFS_OUTPUT_BYTES);
  const hits: RepoRefHit[] = [];
  if (result.exitCode > 1 && result.stdout.length === 0) {
    return { hits, truncated: result.truncated };
  }

  const lines = result.stdout.split("\n").filter(Boolean);
  for (const line of lines) {
    const match = line.match(/^(.*?):(\d+):(.*)$/);
    if (!match) continue;
    const relPath = normalizeRelativePath(match[1]);
    if (!fileMatchesLanguage(relPath, languageHint)) continue;
    hits.push({
      path: relPath,
      lineNumber: Number(match[2]),
      preview: match[3].slice(0, MAX_PREVIEW_CHARS)
    });
  }

  return { hits, truncated: result.truncated };
}

async function runFindRefsWithWalk(symbol: string, languageHint: string) {
  const hits: RepoRefHit[] = [];
  let truncated = false;

  const shouldStop = () => hits.length >= MAX_FIND_REFS_HITS;

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
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (!fileMatchesLanguage(relPath, languageHint)) continue;
        const remaining = MAX_FIND_REFS_HITS - hits.length;
        const fileResult = await searchFile(path.join(current, entry.name), relPath, symbol, remaining);
        hits.push(...fileResult.results);
        if (fileResult.truncated || hits.length >= MAX_FIND_REFS_HITS) {
          truncated = true;
          return;
        }
      }
    }
  }

  await walk(repoRoot);
  if (hits.length >= MAX_FIND_REFS_HITS) {
    truncated = true;
  }
  return { hits, truncated };
}

async function listCandidateFiles(glob?: string) {
  const warnings: string[] = [];
  const rgAvailable = await isCommandAvailable("rg");
  let files: string[] = [];

  if (rgAvailable) {
    const args = ["--files"];
    for (const skip of SKIP_DIR_NAMES) {
      args.push("-g", `!${skip}/**`);
    }
    if (glob) {
      args.push("-g", glob);
    }
    const result = await runSimpleCommand("rg", args, 10_000, 512 * 1024);
    if (result.ok) {
      files = result.stdout.split("\n").filter(Boolean).map(normalizeRelativePath);
    } else {
      warnings.push("rg_failed");
    }
  }

  if (!rgAvailable || files.length === 0) {
    files = await listFilesWithWalk(glob);
  }

  if (glob) {
    const matcher = globToRegex(glob);
    files = files.filter((file) => matcher.test(file));
  }

  return { paths: files, warnings };
}

async function listFilesWithWalk(glob?: string) {
  const files: string[] = [];
  const matcher = glob ? globToRegex(glob) : null;

  async function walk(current: string) {
    let entries: fsSync.Dirent[];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (SKIP_DIR_NAMES.has(entry.name)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (!matcher || matcher.test(relPath)) {
          files.push(relPath);
        }
      }
    }
  }

  await walk(repoRoot);
  return files;
}

function globToRegex(glob: string) {
  let regex = "^";
  let i = 0;
  while (i < glob.length) {
    const char = glob[i];
    if (char === "*") {
      if (glob[i + 1] === "*") {
        regex += ".*";
        i += 2;
      } else {
        regex += "[^/]*";
        i += 1;
      }
      continue;
    }
    if (char === "?") {
      regex += ".";
      i += 1;
      continue;
    }
    if ("\\.[]{}()+-^$|".includes(char)) {
      regex += `\\${char}`;
    } else {
      regex += char;
    }
    i += 1;
  }
  regex += "$";
  return new RegExp(regex);
}

function languageHintToGlobs(languageHint: string) {
  switch (languageHint) {
    case "ruby":
      return ["**/*.rb", "**/*.rake", "**/*.ru", "**/*.erb", "**/*.gemspec"];
    case "js":
      return ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs"];
    case "ts":
      return ["**/*.ts", "**/*.tsx", "**/*.d.ts", "**/*.mts", "**/*.cts"];
    default:
      return [];
  }
}

function languageHintToExtensions(languageHint: string) {
  switch (languageHint) {
    case "ruby":
      return new Set([".rb", ".rake", ".ru", ".erb", ".gemspec"]);
    case "js":
      return new Set([".js", ".jsx", ".mjs", ".cjs"]);
    case "ts":
      return new Set([".ts", ".tsx", ".d.ts", ".mts", ".cts"]);
    default:
      return null;
  }
}

function fileMatchesLanguage(relPath: string, languageHint: string) {
  if (languageHint === "any") return true;
  const extensions = languageHintToExtensions(languageHint);
  if (!extensions) return true;
  const ext = path.extname(relPath).toLowerCase();
  return extensions.has(ext);
}

async function buildRefSnippets(
  filePath: string,
  hits: RepoRefHit[],
  maxSnippetsPerFile: number
): Promise<RepoRefSnippet[]> {
  const sorted = [...hits].sort((a, b) => a.lineNumber - b.lineNumber);
  const selected: RepoRefHit[] = [];
  const minSpacing = FIND_REFS_CONTEXT_RADIUS * 2 + 1;

  for (const hit of sorted) {
    if (selected.length >= maxSnippetsPerFile) break;
    const tooClose = selected.some((existing) => Math.abs(existing.lineNumber - hit.lineNumber) <= minSpacing);
    if (tooClose) continue;
    selected.push(hit);
  }

  const fileLines = await loadFileLinesForSnippets(filePath);
  const snippets: RepoRefSnippet[] = [];

  for (const hit of selected) {
    if (snippets.length >= maxSnippetsPerFile) break;
    const line = hit.lineNumber;
    if (fileLines) {
      const totalLines = fileLines.lines.length;
      const lineIndex = line - 1;
      const lineText = fileLines.lines[lineIndex] ?? hit.preview;
      const contextStart = Math.max(1, line - FIND_REFS_CONTEXT_RADIUS);
      const contextEnd = Math.min(totalLines, line + FIND_REFS_CONTEXT_RADIUS);
      snippets.push({
        line,
        preview: lineText.slice(0, MAX_PREVIEW_CHARS),
        contextStartLine: contextStart,
        contextEndLine: contextEnd
      });
    } else {
      snippets.push({
        line,
        preview: hit.preview
      });
    }
  }

  return snippets;
}

async function loadFileLinesForSnippets(filePath: string) {
  const resolved = resolveRepoPath(filePath);
  if (!resolved.ok) return null;
  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return null;
  }
  if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES) return null;
  if (await isBinaryFile(resolved.resolved)) return null;
  const content = await fs.readFile(resolved.resolved, "utf8");
  const normalized = normalizeLineEndings(content);
  const lines = normalized.length === 0 ? [] : normalized.split("\n");
  return { lines };
}

function normalizeSymbolPath(symbolPath: string) {
  if (path.isAbsolute(symbolPath)) {
    if (!isWithinRepoRoot(symbolPath)) return null;
    return normalizeRelativePath(path.relative(repoRoot, symbolPath));
  }
  const normalized = normalizeRelativePath(symbolPath);
  return normalized;
}

async function runCtags(paths: string[], maxResults: number) {
  const args = [
    "--output-format=json",
    "--fields=+n",
    "--excmd=number",
    "--sort=no",
    "-f",
    "-"
  ];
  const result = await runSimpleCommand("ctags", [...args, ...paths], 20_000, 1024 * 1024);
  if (!result.ok) {
    return { ok: false as const, results: [], truncated: false };
  }

  const results: RepoSymbol[] = [];
  const lines = result.stdout.split("\n").filter(Boolean);
  for (const line of lines) {
    let parsed: { name?: string; kind?: string; path?: string; line?: number; language?: string };
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (!parsed.name || !parsed.path || !parsed.line || !parsed.kind) continue;
    const normalizedPath = normalizeSymbolPath(parsed.path);
    if (!normalizedPath) continue;
    results.push({
      name: parsed.name,
      kind: parsed.kind,
      path: normalizedPath,
      line: parsed.line,
      language: parsed.language ?? "unknown"
    });
    if (results.length > maxResults) {
      return { ok: true as const, results, truncated: true };
    }
  }

  return { ok: true as const, results, truncated: false };
}

async function runHeuristicSymbols(
  paths: string[],
  maxResults: number,
  kindsFilter: string[]
) {
  const results: RepoSymbol[] = [];
  let truncated = false;
  const includeKind = (kind: string) =>
    kindsFilter.length === 0 || kindsFilter.includes(kind.toLowerCase());

  for (const relPath of paths) {
    if (results.length > maxResults) {
      truncated = true;
      break;
    }
    const fullPath = path.join(repoRoot, relPath);
    let stat: fsSync.Stats;
    try {
      stat = await fs.stat(fullPath);
    } catch {
      continue;
    }
    if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES) continue;
    if (await isBinaryFile(fullPath)) continue;

    const ext = path.extname(relPath).toLowerCase();
    let language: string | null = null;
    if (ext === ".rb") language = "ruby";
    if ([".js", ".jsx"].includes(ext)) language = "javascript";
    if ([".ts", ".tsx"].includes(ext)) language = "typescript";
    if (!language) continue;

    const content = normalizeLineEndings(await fs.readFile(fullPath, "utf8"));
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i += 1) {
      const lineNumber = i + 1;
      const line = lines[i];

      if (language === "ruby") {
        const classMatch = line.match(/^\s*(class|module)\s+([A-Z][\w:]*)/);
        if (classMatch) {
          const kind = classMatch[1] === "class" ? "class" : "module";
          if (includeKind(kind)) {
            results.push({
              name: classMatch[2],
              kind,
              path: relPath,
              line: lineNumber,
              language
            });
          }
        }
        const defMatch = line.match(/^\s*def\s+([A-Za-z0-9_!?=\.]+)/);
        if (defMatch && includeKind("method")) {
          results.push({
            name: defMatch[1],
            kind: "method",
            path: relPath,
            line: lineNumber,
            language
          });
        }
      } else {
        const classMatch =
          line.match(/^\s*export\s+class\s+(\w+)/) || line.match(/^\s*class\s+(\w+)/);
        if (classMatch && includeKind("class")) {
          results.push({
            name: classMatch[1],
            kind: "class",
            path: relPath,
            line: lineNumber,
            language
          });
        }
        const funcMatch =
          line.match(/^\s*export\s+function\s+(\w+)/) || line.match(/^\s*function\s+(\w+)/);
        if (funcMatch && includeKind("function")) {
          results.push({
            name: funcMatch[1],
            kind: "function",
            path: relPath,
            line: lineNumber,
            language
          });
        }
        const arrowMatch = line.match(
          /^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)?\s*=>/
        );
        if (arrowMatch && includeKind("function")) {
          results.push({
            name: arrowMatch[1],
            kind: "function",
            path: relPath,
            line: lineNumber,
            language
          });
        }
        const fnExprMatch = line.match(
          /^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?function\b/
        );
        if (fnExprMatch && includeKind("function")) {
          results.push({
            name: fnExprMatch[1],
            kind: "function",
            path: relPath,
            line: lineNumber,
            language
          });
        }
        const interfaceMatch =
          line.match(/^\s*export\s+interface\s+(\w+)/) || line.match(/^\s*interface\s+(\w+)/);
        if (interfaceMatch && includeKind("interface")) {
          results.push({
            name: interfaceMatch[1],
            kind: "interface",
            path: relPath,
            line: lineNumber,
            language
          });
        }
        const typeMatch =
          line.match(/^\s*export\s+type\s+(\w+)/) || line.match(/^\s*type\s+(\w+)/);
        if (typeMatch && includeKind("type")) {
          results.push({
            name: typeMatch[1],
            kind: "type",
            path: relPath,
            line: lineNumber,
            language
          });
        }
      }

      if (results.length > maxResults) {
        truncated = true;
        break;
      }
    }
    if (truncated) break;
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

    child.on("close", (code: number | null) => {
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

    child.on("close", (code: number | null) => {
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

function toolError(code: string, message: string, details?: Record<string, unknown>) {
  return {
    error: {
      code,
      message,
      details
    }
  };
}

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(() => {
  process.exit(1);
});
