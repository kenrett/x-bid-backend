import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import crypto from "node:crypto";
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
const DEFAULT_TODO_PATTERNS = ["TODO", "FIXME", "HACK", "XXX", "NOTE"];
const DEFAULT_TODO_MAX = 200;
const HARD_TODO_MAX = 500;
const MAX_TODO_OUTPUT_BYTES = 1024 * 1024;
const MAX_PATCH_BYTES = 50 * 1024;
const PROTECTED_PATH_PATTERNS = [
    /(^|\/)\.env(\.|$)/i,
    /(^|\/)config\/credentials(\.|\/|$)/i,
    /(^|\/)config\/master\.key$/i,
    /(^|\/)credentials(\.|\/|$)/i
];
const LOCKFILE_NAMES = new Set(["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Gemfile.lock"]);
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
const DEV_RUN_BASE_ENV_ALLOWLIST = ["PATH"];
const DEV_RUN_ALLOWLIST = [
    {
        name: "node-version",
        command: ["node", "--version"],
        allowedArgs: [],
        timeoutMs: 10_000,
        maxOutputBytes: MAX_CMD_OUTPUT_BYTES,
        envAllowlist: []
    }
];
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
const server = new Server({
    name: "biddersweet-mcp",
    version: "0.1.0"
}, {
    capabilities: {
        tools: {}
    }
});
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
const RepoTodoScanInputSchema = z.object({
    patterns: z.array(z.string().min(1)).optional(),
    maxResults: z.number().int().positive().optional()
});
const RepoFormatPatchInputSchema = z.object({
    diff: z.string().min(1)
});
const RepoProposePatchInputSchema = z
    .object({
    path: z.string(),
    replace: z
        .object({
        startLine: z.number().int().positive(),
        endLine: z.number().int().positive(),
        newText: z.string()
    })
        .optional(),
    insert: z
        .object({
        line: z.number().int().positive(),
        text: z.string()
    })
        .optional(),
    delete: z
        .object({
        startLine: z.number().int().positive(),
        endLine: z.number().int().positive()
    })
        .optional(),
    expectedSha256: z.string().optional()
})
    .refine((value) => {
    const variants = [value.replace, value.insert, value.delete].filter(Boolean);
    return variants.length === 1;
}, { message: "exactly_one_operation_required" });
const RepoApplyPatchInputSchema = z
    .object({
    path: z.string(),
    diff: z.string().min(1).optional(),
    replace: z
        .object({
        startLine: z.number().int().positive(),
        endLine: z.number().int().positive(),
        newText: z.string()
    })
        .optional(),
    insert: z
        .object({
        line: z.number().int().positive(),
        text: z.string()
    })
        .optional(),
    delete: z
        .object({
        startLine: z.number().int().positive(),
        endLine: z.number().int().positive()
    })
        .optional(),
    expectedSha256: z.string().min(1)
})
    .refine((value) => {
    const structured = [value.replace, value.insert, value.delete].filter(Boolean);
    if (value.diff) {
        return structured.length === 0;
    }
    return structured.length === 1;
}, { message: "diff_or_single_operation_required" });
const DevCheckInputSchema = z.object({});
const DevRunTargetSchema = z.object({
    target: z.enum(["ruby", "js", "both"]).optional().default("both")
});
const DevRunInputSchema = z.object({
    name: z.string().min(1),
    args: z.array(z.string()).optional()
});
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
                name: "repo.todo_scan",
                description: "Scan for TODO/FIXME/HACK/XXX markers within the repo.",
                inputSchema: {
                    type: "object",
                    properties: {
                        patterns: { type: "array", items: { type: "string" } },
                        maxResults: { type: "number" }
                    },
                    additionalProperties: false
                }
            },
            {
                name: "repo.format_patch",
                description: "Validate and normalize a unified diff patch.",
                inputSchema: {
                    type: "object",
                    properties: {
                        diff: { type: "string" }
                    },
                    required: ["diff"],
                    additionalProperties: false
                }
            },
            {
                name: "repo.propose_patch",
                description: "Generate a unified diff patch for a change without writing to disk.",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string" },
                        replace: {
                            type: "object",
                            properties: {
                                startLine: { type: "number" },
                                endLine: { type: "number" },
                                newText: { type: "string" }
                            },
                            required: ["startLine", "endLine", "newText"],
                            additionalProperties: false
                        },
                        insert: {
                            type: "object",
                            properties: {
                                line: { type: "number" },
                                text: { type: "string" }
                            },
                            required: ["line", "text"],
                            additionalProperties: false
                        },
                        delete: {
                            type: "object",
                            properties: {
                                startLine: { type: "number" },
                                endLine: { type: "number" }
                            },
                            required: ["startLine", "endLine"],
                            additionalProperties: false
                        },
                        expectedSha256: { type: "string" }
                    },
                    required: ["path"],
                    additionalProperties: false
                }
            },
            {
                name: "repo.apply_patch",
                description: "Apply a unified diff or structured edit to a file, returning the applied diff and hashes.",
                inputSchema: {
                    type: "object",
                    properties: {
                        path: { type: "string" },
                        diff: { type: "string" },
                        replace: {
                            type: "object",
                            properties: {
                                startLine: { type: "number" },
                                endLine: { type: "number" },
                                newText: { type: "string" }
                            },
                            required: ["startLine", "endLine", "newText"],
                            additionalProperties: false
                        },
                        insert: {
                            type: "object",
                            properties: {
                                line: { type: "number" },
                                text: { type: "string" }
                            },
                            required: ["line", "text"],
                            additionalProperties: false
                        },
                        delete: {
                            type: "object",
                            properties: {
                                startLine: { type: "number" },
                                endLine: { type: "number" }
                            },
                            required: ["startLine", "endLine"],
                            additionalProperties: false
                        },
                        expectedSha256: { type: "string" }
                    },
                    required: ["path", "expectedSha256"],
                    additionalProperties: false
                }
            },
            {
                name: "dev.check",
                description: "Check for common dev tool availability.",
                inputSchema: emptyInputSchema()
            },
            {
                name: "dev.run",
                description: "Run a command by allowlisted name with strict limits.",
                inputSchema: {
                    type: "object",
                    properties: {
                        name: { type: "string" },
                        args: { type: "array", items: { type: "string" } }
                    },
                    required: ["name"],
                    additionalProperties: false
                }
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
                return jsonResult(result, Boolean(result.error));
            }
            case "repo.list_dir": {
                const parsed = RepoListDirInputSchema.parse(args ?? {});
                const result = await handleRepoListDir(parsed);
                return jsonResult(result);
            }
            case "repo.deps": {
                const parsed = RepoDepsInputSchema.parse(args ?? {});
                const result = await handleRepoDeps(parsed);
                return jsonResult(result, Boolean(result.error));
            }
            case "repo.symbols": {
                const parsed = RepoSymbolsInputSchema.parse(args ?? {});
                const result = await handleRepoSymbols(parsed);
                return jsonResult(result, Boolean(result.error));
            }
            case "repo.tree": {
                const parsed = RepoTreeInputSchema.parse(args ?? {});
                const result = await handleRepoTree(parsed);
                return jsonResult(result, Boolean(result.error));
            }
            case "repo.find_refs": {
                const parsed = RepoFindRefsInputSchema.parse(args ?? {});
                const result = await handleRepoFindRefs(parsed);
                return jsonResult(result);
            }
            case "repo.todo_scan": {
                const parsed = RepoTodoScanInputSchema.parse(args ?? {});
                const result = await handleRepoTodoScan(parsed);
                return jsonResult(result);
            }
            case "repo.format_patch": {
                const parsed = RepoFormatPatchInputSchema.parse(args ?? {});
                const result = await handleRepoFormatPatch(parsed);
                return jsonResult(result);
            }
            case "repo.propose_patch": {
                const parsed = RepoProposePatchInputSchema.parse(args ?? {});
                const result = await handleRepoProposePatch(parsed);
                return jsonResult(result, Boolean(result.error));
            }
            case "repo.apply_patch": {
                const parsed = RepoApplyPatchInputSchema.parse(args ?? {});
                const result = await handleRepoApplyPatch(parsed);
                return jsonResult(result, Boolean(result.errors?.length));
            }
            case "dev.check": {
                const parsed = DevCheckInputSchema.parse(args ?? {});
                const result = await handleDevCheck(parsed);
                return jsonResult(result);
            }
            case "dev.run": {
                const parsed = DevRunInputSchema.parse(args ?? {});
                const result = await handleDevRunAllowlisted(parsed);
                return jsonResult(result, Boolean(result.error));
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
    }
    catch (error) {
        const message = error instanceof Error ? error.message : "unknown_error";
        return jsonResult({ error: "invalid_request", message }, true);
    }
});
async function handleRepoInfo(_input) {
    const gemfile = await existsInRepo("Gemfile");
    const packageJson = await existsInRepo("package.json");
    const railsMarker = (await existsInRepo("config/application.rb")) ||
        (await existsInRepo("bin/rails")) ||
        (await existsInRepo("config.ru"));
    const railsPresent = gemfile && railsMarker;
    const packageManager = await detectPackageManager();
    const isGitRepo = await detectGitRepo();
    const availableDevCommands = [];
    if (gemfile || packageJson) {
        availableDevCommands.push("dev.run_tests", "dev.run_lint");
    }
    if (DEV_RUN_ALLOWLIST.length > 0) {
        availableDevCommands.push("dev.run");
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
async function handleRepoSearch(input) {
    const maxResults = Math.min(input.maxResults ?? DEFAULT_SEARCH_MAX, HARD_SEARCH_MAX);
    const query = input.query;
    const rgAvailable = await isCommandAvailable("rg");
    const gitAvailable = await isCommandAvailable("git");
    const isGitRepo = gitAvailable ? await detectGitRepo() : false;
    let results = [];
    let truncated = false;
    if (rgAvailable) {
        const rgResults = await runSearchWithRg(query, maxResults + 1);
        results = rgResults.results.slice(0, maxResults);
        truncated = rgResults.results.length > maxResults || rgResults.truncated;
    }
    else if (isGitRepo) {
        const gitResults = await runSearchWithGitGrep(query, maxResults + 1);
        results = gitResults.results.slice(0, maxResults);
        truncated = gitResults.results.length > maxResults || gitResults.truncated;
    }
    else {
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
async function handleRepoReadFile(input) {
    const resolved = resolveRepoPath(input.path);
    if (!resolved.ok) {
        return {
            path: safeOutputPath(input.path),
            refused: true,
            reason: "not_found"
        };
    }
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
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
async function handleRepoReadRange(input) {
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
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
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
    const warnings = [];
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
async function handleRepoListDir(input) {
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
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
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
        .map((entry) => {
        const type = entry.isDirectory() ? "dir" : entry.isFile() ? "file" : "other";
        return { name: entry.name, type };
    })
        .sort((a, b) => {
        if (a.type === b.type) {
            return a.name.localeCompare(b.name);
        }
        if (a.type === "dir")
            return -1;
        if (b.type === "dir")
            return 1;
        if (a.type === "file")
            return -1;
        if (b.type === "file")
            return 1;
        return a.name.localeCompare(b.name);
    });
    const truncated = entries.length > maxEntries;
    return {
        path: resolved.relative,
        entries: entries.slice(0, maxEntries),
        truncated
    };
}
async function handleRepoDeps(_input) {
    const warnings = [];
    const filesChecked = [];
    const readTextFile = async (relPath) => {
        const resolved = resolveRepoPath(relPath);
        if (!resolved.ok)
            return { missing: true };
        let stat;
        try {
            stat = await fs.stat(resolved.resolved);
        }
        catch {
            return { missing: true };
        }
        if (!stat.isFile()) {
            warnings.push(`${relPath}:not_a_file`);
            return { missing: true };
        }
        if (stat.size > MAX_FILE_SIZE_BYTES) {
            warnings.push(`${relPath}:file_too_large`);
            return { missing: true };
        }
        const binary = await isBinaryFile(resolved.resolved);
        if (binary) {
            warnings.push(`${relPath}:binary_file`);
            return { missing: true };
        }
        const content = await fs.readFile(resolved.resolved, "utf8");
        filesChecked.push(resolved.relative);
        return { content: normalizeLineEndings(content) };
    };
    const ruby = {};
    const node = {};
    const gems = {
        top: [],
        hasGemfileLock: false
    };
    const js = { dependenciesTop: [], scripts: {}, hasLockfile: false };
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
            if (!match)
                continue;
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
                if (version.length === 0)
                    continue;
                ruby.bundlerVersion = version;
                break;
            }
        }
    }
    const packageJson = await readTextFile("package.json");
    if ("content" in packageJson) {
        try {
            const parsed = JSON.parse(packageJson.content);
            const deps = [];
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
        }
        catch (error) {
            warnings.push(`package.json:parse_error`);
        }
    }
    if (!node.packageManager) {
        const detected = await detectPackageManager();
        if (detected !== "unknown")
            node.packageManager = detected;
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
        }
        else if (!node.workspaceType) {
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
async function handleRepoSymbols(input) {
    const maxResults = Math.min(input.maxResults ?? DEFAULT_SYMBOLS_MAX, HARD_SYMBOLS_MAX);
    const kindsFilter = (input.kinds ?? []).map((kind) => kind.toLowerCase());
    const files = await listCandidateFiles(input.glob);
    let strategy = "heuristic";
    let results = [];
    const warnings = [...files.warnings];
    const ctagsAvailable = await isCommandAvailable("ctags");
    if (ctagsAvailable && files.paths.length > 0) {
        const ctags = await runCtags(files.paths, maxResults);
        if (ctags.ok) {
            strategy = "ctags";
            results = ctags.results;
            if (ctags.truncated)
                warnings.push("truncated");
        }
        else {
            warnings.push("ctags_failed");
        }
    }
    if (strategy === "heuristic") {
        const heuristic = await runHeuristicSymbols(files.paths, maxResults, kindsFilter);
        results = heuristic.results;
        if (heuristic.truncated)
            warnings.push("truncated");
    }
    if (kindsFilter.length > 0) {
        results = results.filter((result) => kindsFilter.includes(result.kind.toLowerCase()));
    }
    results.sort((a, b) => {
        if (a.path === b.path)
            return a.line - b.line;
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
async function handleRepoTree(input) {
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
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
        return toolError("not_found", "path not found", { path: resolved.relative });
    }
    let nodesReturned = 0;
    let truncated = false;
    const rootName = resolved.relative === "." ? "." : path.basename(resolved.relative);
    const shouldStop = () => nodesReturned >= maxNodes;
    const buildTree = async (fullPath, name, depth) => {
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
        let entries;
        try {
            entries = await fs.readdir(fullPath, { withFileTypes: true });
        }
        catch {
            return { name, type: "dir" };
        }
        const filtered = entries.filter((entry) => {
            if (entry.isDirectory() && SKIP_DIR_NAMES.has(entry.name))
                return false;
            return true;
        });
        filtered.sort((a, b) => {
            const aDir = a.isDirectory();
            const bDir = b.isDirectory();
            if (aDir && !bDir)
                return -1;
            if (!aDir && bDir)
                return 1;
            return a.name.localeCompare(b.name);
        });
        let working = filtered;
        if (filtered.length > maxEntriesPerDir) {
            working = filtered.slice(0, maxEntriesPerDir);
            truncated = true;
        }
        const children = [];
        for (const entry of working) {
            if (shouldStop()) {
                truncated = true;
                break;
            }
            const childPath = path.join(fullPath, entry.name);
            if (entry.isDirectory()) {
                const child = await buildTree(childPath, entry.name, depth + 1);
                children.push(child);
            }
            else if (entry.isFile()) {
                nodesReturned += 1;
                children.push({ name: entry.name, type: "file" });
            }
            else {
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
async function handleRepoFindRefs(input) {
    const symbol = input.symbol;
    const maxFiles = Math.min(input.maxFiles ?? DEFAULT_FIND_REFS_MAX_FILES, HARD_FIND_REFS_MAX_FILES);
    const maxSnippetsPerFile = Math.min(input.maxSnippetsPerFile ?? DEFAULT_FIND_REFS_SNIPPETS, HARD_FIND_REFS_SNIPPETS);
    const languageHint = input.languageHint ?? "any";
    const rgAvailable = await isCommandAvailable("rg");
    const gitAvailable = await isCommandAvailable("git");
    const isGitRepo = gitAvailable ? await detectGitRepo() : false;
    let strategy = "walk";
    let hits = [];
    let truncated = false;
    if (rgAvailable) {
        const rgResults = await runFindRefsWithRg(symbol, languageHint);
        strategy = "rg";
        hits = rgResults.hits;
        truncated = rgResults.truncated;
    }
    else if (isGitRepo) {
        const gitResults = await runFindRefsWithGitGrep(symbol, languageHint);
        strategy = "git_grep";
        hits = gitResults.hits;
        truncated = gitResults.truncated;
    }
    else {
        const walkResults = await runFindRefsWithWalk(symbol, languageHint);
        strategy = "walk";
        hits = walkResults.hits;
        truncated = walkResults.truncated;
    }
    const grouped = new Map();
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
async function handleRepoTodoScan(input) {
    const patterns = (input.patterns ?? DEFAULT_TODO_PATTERNS).filter((pattern) => pattern.trim().length > 0);
    const maxResults = Math.min(input.maxResults ?? DEFAULT_TODO_MAX, HARD_TODO_MAX);
    const rgAvailable = await isCommandAvailable("rg");
    let hits = [];
    let truncated = false;
    if (rgAvailable) {
        const rgResults = await runTodoScanWithRg(patterns);
        hits = rgResults.results;
        truncated = rgResults.truncated;
    }
    else {
        const walkResults = await runTodoScanWithWalk(patterns, maxResults + 1);
        hits = walkResults.results;
        truncated = walkResults.truncated;
    }
    hits.sort((a, b) => {
        if (a.pattern !== b.pattern)
            return a.pattern.localeCompare(b.pattern);
        if (a.path !== b.path)
            return a.path.localeCompare(b.path);
        return a.line - b.line;
    });
    if (hits.length > maxResults) {
        truncated = true;
    }
    const limited = hits.slice(0, maxResults);
    const groupedCounts = {};
    for (const item of limited) {
        groupedCounts[item.pattern] = (groupedCounts[item.pattern] ?? 0) + 1;
    }
    return {
        results: limited,
        groupedCounts,
        truncated
    };
}
async function handleRepoFormatPatch(input) {
    const warnings = [];
    const normalizedInput = normalizeLineEndings(input.diff).trimEnd();
    if (normalizedInput.length === 0) {
        return formatPatchResult(false, "", [], 0, 0, ["empty_diff"]);
    }
    const hasDiffHeader = normalizedInput.split("\n").some((line) => line.startsWith("diff --git "));
    if (!hasDiffHeader) {
        warnings.push("missing_diff_header");
    }
    const segments = splitUnifiedDiffSegments(normalizedInput, warnings);
    if (segments.length === 0) {
        return formatPatchResult(false, "", [], 0, 0, [...warnings, "invalid_diff"]);
    }
    const normalizedSegments = [];
    const filesChanged = [];
    const seenFiles = new Set();
    let insertions = 0;
    let deletions = 0;
    for (const segment of segments) {
        const parsed = parseUnifiedDiff(segment);
        if (!parsed.ok) {
            return formatPatchResult(false, "", [], 0, 0, [...warnings, `invalid_diff:${parsed.error.code}`]);
        }
        if (!parsed.path) {
            return formatPatchResult(false, "", [], 0, 0, [...warnings, "missing_path"]);
        }
        const pathValue = normalizeRelativePath(parsed.path);
        const hunkResult = normalizeUnifiedDiffHunks(parsed.hunks);
        if (!hunkResult.ok) {
            return formatPatchResult(false, "", [], 0, 0, [...warnings, `invalid_hunk:${hunkResult.error}`]);
        }
        if (!seenFiles.has(pathValue)) {
            seenFiles.add(pathValue);
            filesChanged.push(pathValue);
        }
        insertions += hunkResult.insertions;
        deletions += hunkResult.deletions;
        normalizedSegments.push([
            `diff --git a/${pathValue} b/${pathValue}`,
            `--- a/${pathValue}`,
            `+++ b/${pathValue}`,
            ...hunkResult.lines
        ].join("\n"));
    }
    return formatPatchResult(true, normalizedSegments.join("\n"), filesChanged, insertions, deletions, warnings.length > 0 ? warnings : undefined);
}
function formatPatchResult(valid, normalizedDiff, filesChanged, insertions, deletions, warnings) {
    return {
        normalizedDiff,
        filesChanged,
        stats: {
            files: filesChanged.length,
            insertions,
            deletions
        },
        warnings: warnings && warnings.length > 0 ? warnings : undefined,
        valid
    };
}
async function handleRepoProposePatch(input) {
    const resolved = resolveRepoPath(input.path);
    if (!resolved.ok) {
        return toolError("path_outside_root", "path is outside repo root", {
            path: safeOutputPath(input.path)
        });
    }
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
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
    if (await isBinaryFile(resolved.resolved)) {
        return toolError("binary_file", "file is binary", { path: resolved.relative });
    }
    const content = normalizeLineEndings(await fs.readFile(resolved.resolved, "utf8"));
    const beforeSha256 = sha256(content);
    if (input.expectedSha256 && input.expectedSha256 !== beforeSha256) {
        return toolError("sha_mismatch", "expectedSha256 does not match file content", {
            path: resolved.relative,
            expectedSha256: input.expectedSha256,
            actualSha256: beforeSha256
        });
    }
    const lines = content.length === 0 ? [] : content.split("\n");
    const totalLines = lines.length;
    let afterLines = [];
    let diff = "";
    let bytesChanged = 0;
    const warnings = [];
    if (input.insert) {
        const line = input.insert.line;
        if (line < 1 || line > totalLines + 1) {
            return toolError("invalid_range", "insert line is out of range", {
                path: resolved.relative,
                line
            });
        }
        const insertLines = normalizeLineEndings(input.insert.text).split("\n");
        bytesChanged = Buffer.byteLength(input.insert.text);
        if (bytesChanged > MAX_PATCH_BYTES) {
            return toolError("patch_too_large", "proposed change exceeds size cap", {
                path: resolved.relative,
                maxBytes: MAX_PATCH_BYTES
            });
        }
        afterLines = [
            ...lines.slice(0, line - 1),
            ...insertLines,
            ...lines.slice(line - 1)
        ];
        diff = buildUnifiedDiffForInsert(resolved.relative, line, insertLines);
    }
    else if (input.delete) {
        const startLine = input.delete.startLine;
        const endLine = input.delete.endLine;
        if (startLine < 1 || endLine < 1 || startLine > endLine || endLine > totalLines) {
            return toolError("invalid_range", "delete range is out of bounds", {
                path: resolved.relative,
                startLine,
                endLine
            });
        }
        const removed = lines.slice(startLine - 1, endLine).join("\n");
        bytesChanged = Buffer.byteLength(removed);
        if (bytesChanged > MAX_PATCH_BYTES) {
            return toolError("patch_too_large", "proposed change exceeds size cap", {
                path: resolved.relative,
                maxBytes: MAX_PATCH_BYTES
            });
        }
        afterLines = [...lines.slice(0, startLine - 1), ...lines.slice(endLine)];
        diff = buildUnifiedDiffForDelete(resolved.relative, startLine, endLine, lines.slice(startLine - 1, endLine));
    }
    else if (input.replace) {
        const startLine = input.replace.startLine;
        const endLine = input.replace.endLine;
        if (startLine < 1 || endLine < 1 || startLine > endLine || endLine > totalLines) {
            return toolError("invalid_range", "replace range is out of bounds", {
                path: resolved.relative,
                startLine,
                endLine
            });
        }
        const newLines = normalizeLineEndings(input.replace.newText).split("\n");
        const removed = lines.slice(startLine - 1, endLine).join("\n");
        bytesChanged = Buffer.byteLength(input.replace.newText) + Buffer.byteLength(removed);
        if (bytesChanged > MAX_PATCH_BYTES) {
            return toolError("patch_too_large", "proposed change exceeds size cap", {
                path: resolved.relative,
                maxBytes: MAX_PATCH_BYTES
            });
        }
        afterLines = [...lines.slice(0, startLine - 1), ...newLines, ...lines.slice(endLine)];
        diff = buildUnifiedDiffForReplace(resolved.relative, startLine, endLine, lines.slice(startLine - 1, endLine), newLines);
    }
    else {
        warnings.push("no_changes");
        afterLines = [...lines];
    }
    const afterContent = afterLines.join("\n");
    const afterSha256 = sha256(afterContent);
    return {
        path: resolved.relative,
        beforeSha256,
        afterSha256,
        diff,
        applied: false,
        warnings: warnings.length > 0 ? warnings : undefined
    };
}
async function handleRepoApplyPatch(input) {
    const resolved = resolveRepoPath(input.path);
    const safePath = safeOutputPath(input.path);
    if (!resolved.ok) {
        return applyPatchError(safePath, "path_outside_root", "path is outside repo root");
    }
    if (isProtectedPath(resolved.relative)) {
        return applyPatchError(resolved.relative, "protected_path", "path is protected", {
            path: resolved.relative
        });
    }
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
        return applyPatchError(resolved.relative, "not_found", "file not found", { path: resolved.relative });
    }
    if (!stat.isFile()) {
        return applyPatchError(resolved.relative, "not_a_file", "path is not a file", { path: resolved.relative });
    }
    if (stat.size > MAX_FILE_SIZE_BYTES) {
        return applyPatchError(resolved.relative, "file_too_large", "file exceeds size limit", {
            path: resolved.relative,
            sizeBytes: stat.size
        });
    }
    if (await isBinaryFile(resolved.resolved)) {
        return applyPatchError(resolved.relative, "binary_file", "file is binary", { path: resolved.relative });
    }
    const warnings = [];
    if (isLockfilePath(resolved.relative)) {
        warnings.push("lockfile_edit");
    }
    const content = normalizeLineEndings(await fs.readFile(resolved.resolved, "utf8"));
    const beforeSha256 = sha256(content);
    if (input.expectedSha256 !== beforeSha256) {
        return applyPatchError(resolved.relative, "sha_mismatch", "expectedSha256 does not match file content", {
            path: resolved.relative,
            expectedSha256: input.expectedSha256,
            actualSha256: beforeSha256
        }, beforeSha256);
    }
    const lines = content.length === 0 ? [] : content.split("\n");
    let afterLines = [];
    let diffApplied = "";
    let bytesChanged = 0;
    if (input.diff) {
        const parsed = parseUnifiedDiff(input.diff);
        if (!parsed.ok) {
            return applyPatchError(resolved.relative, parsed.error.code, parsed.error.message, parsed.error.details, beforeSha256);
        }
        if (parsed.path && normalizeRelativePath(parsed.path) !== resolved.relative) {
            return applyPatchError(resolved.relative, "path_mismatch", "diff path does not match input path", {
                path: resolved.relative,
                diffPath: parsed.path
            }, beforeSha256);
        }
        const applied = applyUnifiedDiff(lines, parsed.hunks);
        if (!applied.ok) {
            return applyPatchError(resolved.relative, applied.error.code, applied.error.message, applied.error.details, beforeSha256);
        }
        afterLines = applied.lines;
        bytesChanged = applied.bytesChanged;
        diffApplied = normalizeLineEndings(input.diff).trimEnd();
    }
    else {
        const structured = applyStructuredEdit(lines, resolved.relative, input);
        if (!structured.ok) {
            return applyPatchError(resolved.relative, structured.error.code, structured.error.message, structured.error.details, beforeSha256);
        }
        afterLines = structured.lines;
        bytesChanged = structured.bytesChanged;
        diffApplied = structured.diffApplied;
    }
    if (bytesChanged > MAX_PATCH_BYTES) {
        return applyPatchError(resolved.relative, "patch_too_large", "proposed change exceeds size cap", {
            path: resolved.relative,
            maxBytes: MAX_PATCH_BYTES
        }, beforeSha256);
    }
    const afterContent = afterLines.join("\n");
    const afterSha256 = sha256(afterContent);
    if (afterContent === content) {
        warnings.push("no_changes");
        return {
            path: resolved.relative,
            applied: false,
            beforeSha256,
            afterSha256,
            diffApplied,
            warnings: warnings.length > 0 ? warnings : undefined
        };
    }
    if (Buffer.byteLength(afterContent) > MAX_FILE_SIZE_BYTES) {
        return applyPatchError(resolved.relative, "file_too_large", "resulting file exceeds size limit", {
            path: resolved.relative,
            sizeBytes: Buffer.byteLength(afterContent)
        }, beforeSha256, afterSha256, diffApplied);
    }
    try {
        await writeFileAtomic(resolved.resolved, afterContent, stat.mode);
    }
    catch (error) {
        return applyPatchError(resolved.relative, "write_failed", "failed to write file", { path: resolved.relative, reason: error instanceof Error ? error.message : "unknown_error" }, beforeSha256, afterSha256, diffApplied);
    }
    return {
        path: resolved.relative,
        applied: true,
        beforeSha256,
        afterSha256,
        diffApplied,
        warnings: warnings.length > 0 ? warnings : undefined
    };
}
async function handleDevCheck(_input) {
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
async function handleDevRunAllowlisted(input) {
    const entry = DEV_RUN_ALLOWLIST.find((item) => item.name === input.name);
    if (!entry) {
        return toolError("command_not_allowed", "command is not allowlisted", { name: input.name });
    }
    const args = input.args ?? [];
    const validationError = validateDevRunArgs(entry, args);
    if (validationError) {
        return toolError("args_not_allowed", validationError, { name: entry.name, args });
    }
    const cmd = [...entry.command, ...args];
    const timeoutMs = entry.timeoutMs ?? DEFAULT_CMD_TIMEOUT_MS;
    const maxOutputBytes = entry.maxOutputBytes ?? MAX_CMD_OUTPUT_BYTES;
    const { env, envUsed } = buildAllowlistedEnv(entry.envAllowlist ?? []);
    const result = await runAllowlistedCommand(cmd, {
        timeoutMs,
        maxOutputBytes,
        env
    });
    return {
        name: entry.name,
        cmd,
        cwd: ".",
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        durationMs: result.durationMs,
        timedOut: result.timedOut,
        truncated: result.truncated,
        limits: { timeoutMs, maxOutputBytes },
        envUsed
    };
}
async function handleDevRunTests(input) {
    return handleDevRun(input.target, async () => selectRubyTestCommand(), async (packageManager) => selectJsTestCommand(packageManager));
}
async function handleDevRunLint(input) {
    return handleDevRun(input.target, async () => ["bundle", "exec", "rubocop"], async (packageManager) => selectJsLintCommand(packageManager));
}
async function handleDevRun(target, rubyCommand, jsCommand) {
    const info = await handleRepoInfo({});
    const results = {};
    let ok = true;
    const runRuby = target === "ruby" || target === "both";
    const runJs = target === "js" || target === "both";
    if (runRuby) {
        if (!info.detectedLanguages.ruby) {
            results.ruby = missingLanguageResult("ruby");
            ok = false;
        }
        else {
            const command = await rubyCommand();
            if (!command) {
                results.ruby = missingCommandResult("ruby");
                ok = false;
            }
            else {
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
        }
        else {
            const command = await jsCommand(info.packageManager);
            if (!command) {
                results.js = missingCommandResult("js");
                ok = false;
            }
            else {
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
        }
        catch {
            return ["bundle", "exec", "rspec"];
        }
    }
    return ["bundle", "exec", "rspec"];
}
async function selectJsTestCommand(packageManager) {
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
async function selectJsLintCommand(packageManager) {
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
function missingLanguageResult(target) {
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
function missingCommandResult(target) {
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
function validateDevRunArgs(entry, args) {
    if (args.length === 0)
        return null;
    if (!entry.allowedArgs || entry.allowedArgs.length === 0) {
        return "arguments are not permitted for this command";
    }
    const allowed = new Set(entry.allowedArgs);
    const invalid = args.find((arg) => !allowed.has(arg));
    if (invalid) {
        return `argument_not_allowlisted:${invalid}`;
    }
    return null;
}
function buildAllowlistedEnv(extraAllowlist) {
    const allowlist = new Set([...DEV_RUN_BASE_ENV_ALLOWLIST, ...extraAllowlist]);
    const env = {};
    const envUsed = [];
    for (const name of allowlist) {
        const value = process.env[name];
        if (value !== undefined) {
            env[name] = value;
            envUsed.push(name);
        }
    }
    envUsed.sort();
    return { env, envUsed };
}
async function runAllowlistedCommand(command, limits) {
    return new Promise((resolve) => {
        const startTime = Date.now();
        const child = spawn(command[0], command.slice(1), {
            cwd: repoRoot,
            env: limits.env,
            shell: false
        });
        const stdoutChunks = [];
        const stderrChunks = [];
        let stdoutBytes = 0;
        let stderrBytes = 0;
        let truncated = false;
        let timedOut = false;
        const onData = (chunk, stream) => {
            const remaining = limits.maxOutputBytes - (stdoutBytes + stderrBytes);
            if (remaining <= 0) {
                truncated = true;
                return;
            }
            const slice = chunk.length > remaining ? chunk.slice(0, remaining) : chunk;
            if (slice.length < chunk.length)
                truncated = true;
            if (stream === "stdout") {
                stdoutChunks.push(slice);
                stdoutBytes += slice.length;
            }
            else {
                stderrChunks.push(slice);
                stderrBytes += slice.length;
            }
        };
        child.stdout?.on("data", (chunk) => onData(chunk, "stdout"));
        child.stderr?.on("data", (chunk) => onData(chunk, "stderr"));
        let timeout;
        if (limits.timeoutMs > 0) {
            timeout = setTimeout(() => {
                timedOut = true;
                truncated = true;
                child.kill("SIGKILL");
            }, limits.timeoutMs);
        }
        const finalize = (exitCode) => {
            if (timeout)
                clearTimeout(timeout);
            const stdout = normalizeLineEndings(Buffer.concat(stdoutChunks).toString("utf8"));
            const stderr = normalizeLineEndings(Buffer.concat(stderrChunks).toString("utf8"));
            resolve({
                exitCode,
                stdout,
                stderr,
                timedOut,
                truncated,
                durationMs: Date.now() - startTime
            });
        };
        child.on("close", (code) => {
            finalize(typeof code === "number" ? code : -1);
        });
        child.on("error", () => {
            finalize(-1);
        });
    });
}
async function runDevCommand(command) {
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
async function runSearchWithRg(query, maxResults) {
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
    const results = [];
    for (const line of lines) {
        const match = line.match(/^(.*?):(\d+):(\d+):(.*)$/);
        if (!match)
            continue;
        const relPath = normalizeRelativePath(match[1]);
        const lineNumber = Number(match[2]);
        const column = Number(match[3]);
        const preview = match[4].slice(0, MAX_PREVIEW_CHARS);
        results.push({ path: relPath, lineNumber, column, preview });
        if (results.length >= maxResults)
            break;
    }
    return { results, truncated: lines.length > results.length };
}
async function runSearchWithGitGrep(query, maxResults) {
    const args = ["-C", repoRoot, "grep", "-n", "--fixed-strings", "--", query];
    const result = await runSimpleCommand("git", args, 10_000, 512 * 1024);
    if (!result.ok) {
        return { results: [], truncated: false };
    }
    const lines = result.stdout.split("\n").filter(Boolean);
    const results = [];
    for (const line of lines) {
        const match = line.match(/^(.*?):(\d+):(.*)$/);
        if (!match)
            continue;
        const relPath = normalizeRelativePath(match[1]);
        const lineNumber = Number(match[2]);
        const preview = match[3].slice(0, MAX_PREVIEW_CHARS);
        results.push({ path: relPath, lineNumber, preview });
        if (results.length >= maxResults)
            break;
    }
    return { results, truncated: lines.length > results.length };
}
async function runSearchWithWalk(query, maxResults) {
    const results = [];
    let truncated = false;
    const shouldStop = () => results.length >= maxResults;
    async function walk(current) {
        if (shouldStop())
            return;
        let entries;
        try {
            entries = await fs.readdir(current, { withFileTypes: true });
        }
        catch {
            return;
        }
        for (const entry of entries) {
            if (shouldStop())
                return;
            if (entry.isDirectory()) {
                if (SKIP_DIR_NAMES.has(entry.name))
                    continue;
                await walk(path.join(current, entry.name));
            }
            else if (entry.isFile()) {
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
async function runFindRefsWithRg(symbol, languageHint) {
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
    const hits = [];
    if (result.exitCode > 1 && result.stdout.length === 0) {
        return { hits, truncated: result.truncated };
    }
    const lines = result.stdout.split("\n").filter(Boolean);
    for (const line of lines) {
        const match = line.match(/^(.*?):(\d+):(.*)$/);
        if (!match)
            continue;
        const relPath = normalizeRelativePath(match[1]);
        if (!fileMatchesLanguage(relPath, languageHint))
            continue;
        hits.push({
            path: relPath,
            lineNumber: Number(match[2]),
            preview: match[3].slice(0, MAX_PREVIEW_CHARS)
        });
    }
    return { hits, truncated: result.truncated };
}
async function runFindRefsWithGitGrep(symbol, languageHint) {
    const args = ["-C", repoRoot, "grep", "-n", "--fixed-strings"];
    for (const skip of SKIP_DIR_NAMES) {
        args.push(`--exclude-dir=${skip}`);
    }
    args.push("--", symbol, ".");
    const result = await runCommandWithLimits(["git", ...args], 10_000, MAX_FIND_REFS_OUTPUT_BYTES);
    const hits = [];
    if (result.exitCode > 1 && result.stdout.length === 0) {
        return { hits, truncated: result.truncated };
    }
    const lines = result.stdout.split("\n").filter(Boolean);
    for (const line of lines) {
        const match = line.match(/^(.*?):(\d+):(.*)$/);
        if (!match)
            continue;
        const relPath = normalizeRelativePath(match[1]);
        if (!fileMatchesLanguage(relPath, languageHint))
            continue;
        hits.push({
            path: relPath,
            lineNumber: Number(match[2]),
            preview: match[3].slice(0, MAX_PREVIEW_CHARS)
        });
    }
    return { hits, truncated: result.truncated };
}
async function runFindRefsWithWalk(symbol, languageHint) {
    const hits = [];
    let truncated = false;
    const shouldStop = () => hits.length >= MAX_FIND_REFS_HITS;
    async function walk(current) {
        if (shouldStop())
            return;
        let entries;
        try {
            entries = await fs.readdir(current, { withFileTypes: true });
        }
        catch {
            return;
        }
        for (const entry of entries) {
            if (shouldStop())
                return;
            if (entry.isDirectory()) {
                if (SKIP_DIR_NAMES.has(entry.name))
                    continue;
                await walk(path.join(current, entry.name));
            }
            else if (entry.isFile()) {
                const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
                if (!fileMatchesLanguage(relPath, languageHint))
                    continue;
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
async function runTodoScanWithRg(patterns) {
    const args = ["--line-number", "--no-heading", "--fixed-strings"];
    for (const skip of SKIP_DIR_NAMES) {
        args.push("-g", `!${skip}/**`);
    }
    if (patterns.length === 0) {
        return { results: [], truncated: false };
    }
    for (const pattern of patterns) {
        args.push("-e", pattern);
    }
    args.push(".");
    const result = await runCommandWithLimits(["rg", ...args], 10_000, MAX_TODO_OUTPUT_BYTES);
    if (result.exitCode > 1 && result.stdout.length === 0) {
        return { results: [], truncated: result.truncated };
    }
    const lines = result.stdout.split("\n").filter(Boolean);
    const results = [];
    for (const line of lines) {
        const match = line.match(/^(.*?):(\d+):(.*)$/);
        if (!match)
            continue;
        const relPath = normalizeRelativePath(match[1]);
        const lineNumber = Number(match[2]);
        const preview = match[3].slice(0, MAX_PREVIEW_CHARS);
        const matchedPattern = detectTodoPattern(preview, patterns);
        if (!matchedPattern)
            continue;
        results.push({
            pattern: matchedPattern,
            path: relPath,
            line: lineNumber,
            preview
        });
    }
    return { results, truncated: result.truncated };
}
async function runTodoScanWithWalk(patterns, maxResults) {
    const results = [];
    let truncated = false;
    const shouldStop = () => results.length >= maxResults;
    async function walk(current) {
        if (shouldStop())
            return;
        let entries;
        try {
            entries = await fs.readdir(current, { withFileTypes: true });
        }
        catch {
            return;
        }
        for (const entry of entries) {
            if (shouldStop())
                return;
            if (entry.isDirectory()) {
                if (SKIP_DIR_NAMES.has(entry.name))
                    continue;
                await walk(path.join(current, entry.name));
            }
            else if (entry.isFile()) {
                const fullPath = path.join(current, entry.name);
                const relPath = normalizeRelativePath(path.relative(repoRoot, fullPath));
                const stat = await fs.stat(fullPath).catch(() => null);
                if (!stat || !stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES)
                    continue;
                if (await isBinaryFile(fullPath))
                    continue;
                const content = normalizeLineEndings(await fs.readFile(fullPath, "utf8"));
                const lines = content.split("\n");
                for (let i = 0; i < lines.length; i += 1) {
                    if (shouldStop()) {
                        truncated = true;
                        return;
                    }
                    const matchedPattern = detectTodoPattern(lines[i], patterns);
                    if (!matchedPattern)
                        continue;
                    results.push({
                        pattern: matchedPattern,
                        path: relPath,
                        line: i + 1,
                        preview: lines[i].slice(0, MAX_PREVIEW_CHARS)
                    });
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
async function listCandidateFiles(glob) {
    const warnings = [];
    const rgAvailable = await isCommandAvailable("rg");
    let files = [];
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
        }
        else {
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
async function listFilesWithWalk(glob) {
    const files = [];
    const matcher = glob ? globToRegex(glob) : null;
    async function walk(current) {
        let entries;
        try {
            entries = await fs.readdir(current, { withFileTypes: true });
        }
        catch {
            return;
        }
        for (const entry of entries) {
            if (entry.isDirectory()) {
                if (SKIP_DIR_NAMES.has(entry.name))
                    continue;
                await walk(path.join(current, entry.name));
            }
            else if (entry.isFile()) {
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
function globToRegex(glob) {
    let regex = "^";
    let i = 0;
    while (i < glob.length) {
        const char = glob[i];
        if (char === "*") {
            if (glob[i + 1] === "*") {
                regex += ".*";
                i += 2;
            }
            else {
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
        }
        else {
            regex += char;
        }
        i += 1;
    }
    regex += "$";
    return new RegExp(regex);
}
function languageHintToGlobs(languageHint) {
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
function languageHintToExtensions(languageHint) {
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
function fileMatchesLanguage(relPath, languageHint) {
    if (languageHint === "any")
        return true;
    const extensions = languageHintToExtensions(languageHint);
    if (!extensions)
        return true;
    const ext = path.extname(relPath).toLowerCase();
    return extensions.has(ext);
}
function detectTodoPattern(preview, patterns) {
    for (const pattern of patterns) {
        if (preview.includes(pattern))
            return pattern;
    }
    return null;
}
function sha256(value) {
    return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}
function buildUnifiedDiffForInsert(pathValue, line, insertLines) {
    return [
        `diff --git a/${pathValue} b/${pathValue}`,
        `--- a/${pathValue}`,
        `+++ b/${pathValue}`,
        `@@ -${line},0 +${line},${insertLines.length} @@`,
        ...insertLines.map((text) => `+${text}`)
    ].join("\n");
}
function buildUnifiedDiffForDelete(pathValue, startLine, endLine, removedLines) {
    const count = endLine - startLine + 1;
    return [
        `diff --git a/${pathValue} b/${pathValue}`,
        `--- a/${pathValue}`,
        `+++ b/${pathValue}`,
        `@@ -${startLine},${count} +${startLine},0 @@`,
        ...removedLines.map((text) => `-${text}`)
    ].join("\n");
}
function buildUnifiedDiffForReplace(pathValue, startLine, endLine, removedLines, newLines) {
    const oldCount = endLine - startLine + 1;
    const newCount = newLines.length;
    return [
        `diff --git a/${pathValue} b/${pathValue}`,
        `--- a/${pathValue}`,
        `+++ b/${pathValue}`,
        `@@ -${startLine},${oldCount} +${startLine},${newCount} @@`,
        ...removedLines.map((text) => `-${text}`),
        ...newLines.map((text) => `+${text}`)
    ].join("\n");
}
function parseUnifiedDiff(diff) {
    const normalized = normalizeLineEndings(diff);
    const lines = normalized.split("\n");
    let parsedPath;
    let index = 0;
    let sawHunk = false;
    for (; index < lines.length; index += 1) {
        const line = lines[index];
        if (line.startsWith("diff --git ")) {
            const match = line.match(/^diff --git a\/(.+) b\/(.+)$/);
            if (match) {
                parsedPath = normalizeRelativePath(match[2]);
            }
            continue;
        }
        if (line.startsWith("--- ")) {
            const candidate = parseDiffPath(line.slice(4));
            if (candidate)
                parsedPath = normalizeRelativePath(candidate);
            continue;
        }
        if (line.startsWith("+++ ")) {
            const candidate = parseDiffPath(line.slice(4));
            if (candidate)
                parsedPath = normalizeRelativePath(candidate);
            continue;
        }
        if (line.startsWith("@@ ")) {
            sawHunk = true;
            break;
        }
    }
    if (!sawHunk) {
        return { ok: false, error: { code: "invalid_diff", message: "no hunks found in diff" } };
    }
    const hunks = [];
    while (index < lines.length) {
        const header = lines[index];
        if (!header.startsWith("@@ ")) {
            if (header.startsWith("diff --git ")) {
                return { ok: false, error: { code: "multi_file_diff", message: "diff contains multiple files" } };
            }
            if (header.trim().length === 0) {
                index += 1;
                continue;
            }
            return { ok: false, error: { code: "invalid_diff", message: "unexpected diff content" } };
        }
        const match = header.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
        if (!match) {
            return { ok: false, error: { code: "invalid_hunk", message: "invalid hunk header" } };
        }
        const oldStart = Number(match[1]);
        const oldCount = Number(match[2] ?? "1");
        const newStart = Number(match[3]);
        const newCount = Number(match[4] ?? "1");
        const hunkLines = [];
        index += 1;
        while (index < lines.length && !lines[index].startsWith("@@ ")) {
            const line = lines[index];
            if (line.startsWith("diff --git ")) {
                return { ok: false, error: { code: "multi_file_diff", message: "diff contains multiple files" } };
            }
            if (line.startsWith("\\ No newline")) {
                index += 1;
                continue;
            }
            const prefix = line[0];
            const text = line.slice(1);
            if (prefix === " ") {
                hunkLines.push({ type: "context", text });
            }
            else if (prefix === "+") {
                hunkLines.push({ type: "add", text });
            }
            else if (prefix === "-") {
                hunkLines.push({ type: "del", text });
            }
            else {
                return { ok: false, error: { code: "invalid_diff", message: "invalid diff line" } };
            }
            index += 1;
        }
        hunks.push({ oldStart, oldCount, newStart, newCount, lines: hunkLines });
    }
    if (hunks.length === 0) {
        return { ok: false, error: { code: "invalid_diff", message: "no hunks found in diff" } };
    }
    return { ok: true, path: parsedPath, hunks };
}
function parseDiffPath(rawPath) {
    if (rawPath === "/dev/null")
        return null;
    if (rawPath.startsWith("a/") || rawPath.startsWith("b/")) {
        return rawPath.slice(2);
    }
    return rawPath;
}
function splitUnifiedDiffSegments(diff, warnings) {
    const lines = diff.split("\n");
    const segments = [];
    let current = [];
    let sawDiffHeader = false;
    let sawPrelude = false;
    for (const line of lines) {
        if (line.startsWith("diff --git ")) {
            if (current.length > 0) {
                segments.push(current.join("\n"));
            }
            current = [line];
            sawDiffHeader = true;
            continue;
        }
        if (!sawDiffHeader) {
            if (line.trim().length > 0) {
                sawPrelude = true;
                current.push(line);
            }
            else if (current.length > 0) {
                current.push(line);
            }
            continue;
        }
        current.push(line);
    }
    if (current.length > 0) {
        segments.push(current.join("\n"));
    }
    if (sawDiffHeader) {
        if (sawPrelude)
            warnings.push("leading_content_ignored");
        return segments.filter((segment) => segment.trim().length > 0 && segment.startsWith("diff --git "));
    }
    return diff.trim().length > 0 ? [diff] : [];
}
function normalizeUnifiedDiffHunks(hunks) {
    if (hunks.length === 0) {
        return { ok: false, error: "no_hunks" };
    }
    const lines = [];
    let insertions = 0;
    let deletions = 0;
    for (const hunk of hunks) {
        if (hunk.oldStart <= 0 || hunk.newStart <= 0) {
            return { ok: false, error: "hunk_start_invalid" };
        }
        let seenOld = 0;
        let seenNew = 0;
        const hunkLines = [];
        for (const entry of hunk.lines) {
            if (entry.type === "context") {
                seenOld += 1;
                seenNew += 1;
                hunkLines.push(` ${entry.text}`);
            }
            else if (entry.type === "add") {
                seenNew += 1;
                insertions += 1;
                hunkLines.push(`+${entry.text}`);
            }
            else {
                seenOld += 1;
                deletions += 1;
                hunkLines.push(`-${entry.text}`);
            }
        }
        if (hunkLines.length === 0) {
            return { ok: false, error: "empty_hunk" };
        }
        if (seenOld !== hunk.oldCount || seenNew !== hunk.newCount) {
            return { ok: false, error: "hunk_count_mismatch" };
        }
        lines.push(`@@ -${hunk.oldStart},${seenOld} +${hunk.newStart},${seenNew} @@`);
        lines.push(...hunkLines);
    }
    return { ok: true, lines, insertions, deletions };
}
function applyUnifiedDiff(lines, hunks) {
    const output = [];
    let cursor = 0;
    let bytesChanged = 0;
    for (const hunk of hunks) {
        if (hunk.oldStart <= 0) {
            return { ok: false, error: { code: "invalid_hunk", message: "hunk start is invalid" } };
        }
        const targetIndex = hunk.oldStart - 1;
        if (targetIndex < cursor || targetIndex > lines.length) {
            return {
                ok: false,
                error: { code: "hunk_out_of_range", message: "hunk start is out of range", details: { oldStart: hunk.oldStart } }
            };
        }
        output.push(...lines.slice(cursor, targetIndex));
        cursor = targetIndex;
        let seenOld = 0;
        let seenNew = 0;
        for (const entry of hunk.lines) {
            if (entry.type === "context") {
                if (lines[cursor] !== entry.text) {
                    return {
                        ok: false,
                        error: {
                            code: "hunk_context_mismatch",
                            message: "context line does not match",
                            details: { expected: entry.text, actual: lines[cursor] ?? "" }
                        }
                    };
                }
                output.push(lines[cursor]);
                cursor += 1;
                seenOld += 1;
                seenNew += 1;
            }
            else if (entry.type === "del") {
                if (lines[cursor] !== entry.text) {
                    return {
                        ok: false,
                        error: {
                            code: "hunk_delete_mismatch",
                            message: "deleted line does not match",
                            details: { expected: entry.text, actual: lines[cursor] ?? "" }
                        }
                    };
                }
                cursor += 1;
                seenOld += 1;
                bytesChanged += Buffer.byteLength(entry.text);
            }
            else {
                output.push(entry.text);
                seenNew += 1;
                bytesChanged += Buffer.byteLength(entry.text);
            }
        }
        if (seenOld !== hunk.oldCount) {
            return {
                ok: false,
                error: {
                    code: "hunk_old_count_mismatch",
                    message: "hunk old line count mismatch",
                    details: { expected: hunk.oldCount, actual: seenOld }
                }
            };
        }
        if (seenNew !== hunk.newCount) {
            return {
                ok: false,
                error: {
                    code: "hunk_new_count_mismatch",
                    message: "hunk new line count mismatch",
                    details: { expected: hunk.newCount, actual: seenNew }
                }
            };
        }
    }
    output.push(...lines.slice(cursor));
    return { ok: true, lines: output, bytesChanged };
}
function applyStructuredEdit(lines, pathValue, input) {
    const totalLines = lines.length;
    if (input.insert) {
        const line = input.insert.line;
        if (line < 1 || line > totalLines + 1) {
            return {
                ok: false,
                error: { code: "invalid_range", message: "insert line is out of range", details: { line } }
            };
        }
        const insertLines = normalizeLineEndings(input.insert.text).split("\n");
        const bytesChanged = Buffer.byteLength(input.insert.text);
        const afterLines = [
            ...lines.slice(0, line - 1),
            ...insertLines,
            ...lines.slice(line - 1)
        ];
        return {
            ok: true,
            lines: afterLines,
            bytesChanged,
            diffApplied: buildUnifiedDiffForInsert(pathValue, line, insertLines)
        };
    }
    if (input.delete) {
        const startLine = input.delete.startLine;
        const endLine = input.delete.endLine;
        if (startLine < 1 || endLine < 1 || startLine > endLine || endLine > totalLines) {
            return {
                ok: false,
                error: {
                    code: "invalid_range",
                    message: "delete range is out of bounds",
                    details: { startLine, endLine }
                }
            };
        }
        const removedLines = lines.slice(startLine - 1, endLine);
        const bytesChanged = Buffer.byteLength(removedLines.join("\n"));
        const afterLines = [...lines.slice(0, startLine - 1), ...lines.slice(endLine)];
        return {
            ok: true,
            lines: afterLines,
            bytesChanged,
            diffApplied: buildUnifiedDiffForDelete(pathValue, startLine, endLine, removedLines)
        };
    }
    if (input.replace) {
        const startLine = input.replace.startLine;
        const endLine = input.replace.endLine;
        if (startLine < 1 || endLine < 1 || startLine > endLine || endLine > totalLines) {
            return {
                ok: false,
                error: {
                    code: "invalid_range",
                    message: "replace range is out of bounds",
                    details: { startLine, endLine }
                }
            };
        }
        const newLines = normalizeLineEndings(input.replace.newText).split("\n");
        const removedLines = lines.slice(startLine - 1, endLine);
        const bytesChanged = Buffer.byteLength(input.replace.newText) + Buffer.byteLength(removedLines.join("\n"));
        const afterLines = [...lines.slice(0, startLine - 1), ...newLines, ...lines.slice(endLine)];
        return {
            ok: true,
            lines: afterLines,
            bytesChanged,
            diffApplied: buildUnifiedDiffForReplace(pathValue, startLine, endLine, removedLines, newLines)
        };
    }
    return { ok: false, error: { code: "invalid_request", message: "no changes provided" } };
}
async function buildRefSnippets(filePath, hits, maxSnippetsPerFile) {
    const sorted = [...hits].sort((a, b) => a.lineNumber - b.lineNumber);
    const selected = [];
    const minSpacing = FIND_REFS_CONTEXT_RADIUS * 2 + 1;
    for (const hit of sorted) {
        if (selected.length >= maxSnippetsPerFile)
            break;
        const tooClose = selected.some((existing) => Math.abs(existing.lineNumber - hit.lineNumber) <= minSpacing);
        if (tooClose)
            continue;
        selected.push(hit);
    }
    const fileLines = await loadFileLinesForSnippets(filePath);
    const snippets = [];
    for (const hit of selected) {
        if (snippets.length >= maxSnippetsPerFile)
            break;
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
        }
        else {
            snippets.push({
                line,
                preview: hit.preview
            });
        }
    }
    return snippets;
}
async function loadFileLinesForSnippets(filePath) {
    const resolved = resolveRepoPath(filePath);
    if (!resolved.ok)
        return null;
    let stat;
    try {
        stat = await fs.stat(resolved.resolved);
    }
    catch {
        return null;
    }
    if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES)
        return null;
    if (await isBinaryFile(resolved.resolved))
        return null;
    const content = await fs.readFile(resolved.resolved, "utf8");
    const normalized = normalizeLineEndings(content);
    const lines = normalized.length === 0 ? [] : normalized.split("\n");
    return { lines };
}
function normalizeSymbolPath(symbolPath) {
    if (path.isAbsolute(symbolPath)) {
        if (!isWithinRepoRoot(symbolPath))
            return null;
        return normalizeRelativePath(path.relative(repoRoot, symbolPath));
    }
    const normalized = normalizeRelativePath(symbolPath);
    return normalized;
}
async function runCtags(paths, maxResults) {
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
        return { ok: false, results: [], truncated: false };
    }
    const results = [];
    const lines = result.stdout.split("\n").filter(Boolean);
    for (const line of lines) {
        let parsed;
        try {
            parsed = JSON.parse(line);
        }
        catch {
            continue;
        }
        if (!parsed.name || !parsed.path || !parsed.line || !parsed.kind)
            continue;
        const normalizedPath = normalizeSymbolPath(parsed.path);
        if (!normalizedPath)
            continue;
        results.push({
            name: parsed.name,
            kind: parsed.kind,
            path: normalizedPath,
            line: parsed.line,
            language: parsed.language ?? "unknown"
        });
        if (results.length > maxResults) {
            return { ok: true, results, truncated: true };
        }
    }
    return { ok: true, results, truncated: false };
}
async function runHeuristicSymbols(paths, maxResults, kindsFilter) {
    const results = [];
    let truncated = false;
    const includeKind = (kind) => kindsFilter.length === 0 || kindsFilter.includes(kind.toLowerCase());
    for (const relPath of paths) {
        if (results.length > maxResults) {
            truncated = true;
            break;
        }
        const fullPath = path.join(repoRoot, relPath);
        let stat;
        try {
            stat = await fs.stat(fullPath);
        }
        catch {
            continue;
        }
        if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES)
            continue;
        if (await isBinaryFile(fullPath))
            continue;
        const ext = path.extname(relPath).toLowerCase();
        let language = null;
        if (ext === ".rb")
            language = "ruby";
        if ([".js", ".jsx"].includes(ext))
            language = "javascript";
        if ([".ts", ".tsx"].includes(ext))
            language = "typescript";
        if (!language)
            continue;
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
            }
            else {
                const classMatch = line.match(/^\s*export\s+class\s+(\w+)/) || line.match(/^\s*class\s+(\w+)/);
                if (classMatch && includeKind("class")) {
                    results.push({
                        name: classMatch[1],
                        kind: "class",
                        path: relPath,
                        line: lineNumber,
                        language
                    });
                }
                const funcMatch = line.match(/^\s*export\s+function\s+(\w+)/) || line.match(/^\s*function\s+(\w+)/);
                if (funcMatch && includeKind("function")) {
                    results.push({
                        name: funcMatch[1],
                        kind: "function",
                        path: relPath,
                        line: lineNumber,
                        language
                    });
                }
                const arrowMatch = line.match(/^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?(?:\([^)]*\)|\w+)?\s*=>/);
                if (arrowMatch && includeKind("function")) {
                    results.push({
                        name: arrowMatch[1],
                        kind: "function",
                        path: relPath,
                        line: lineNumber,
                        language
                    });
                }
                const fnExprMatch = line.match(/^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?function\b/);
                if (fnExprMatch && includeKind("function")) {
                    results.push({
                        name: fnExprMatch[1],
                        kind: "function",
                        path: relPath,
                        line: lineNumber,
                        language
                    });
                }
                const interfaceMatch = line.match(/^\s*export\s+interface\s+(\w+)/) || line.match(/^\s*interface\s+(\w+)/);
                if (interfaceMatch && includeKind("interface")) {
                    results.push({
                        name: interfaceMatch[1],
                        kind: "interface",
                        path: relPath,
                        line: lineNumber,
                        language
                    });
                }
                const typeMatch = line.match(/^\s*export\s+type\s+(\w+)/) || line.match(/^\s*type\s+(\w+)/);
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
        if (truncated)
            break;
    }
    return { results, truncated };
}
async function searchFile(fullPath, relPath, query, remaining) {
    let stat;
    try {
        stat = await fs.stat(fullPath);
    }
    catch {
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
    const results = [];
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
async function checkDevTools(tools) {
    const result = {};
    for (const tool of tools) {
        const version = await getCommandVersion(tool);
        if (version) {
            result[tool] = { present: true, version };
        }
        else {
            result[tool] = { present: false };
        }
    }
    return result;
}
async function getCommandVersion(command) {
    const result = await runSimpleCommand(command, ["--version"], CHECK_TIMEOUT_MS, 8 * 1024);
    if (!result.ok)
        return undefined;
    const output = result.stdout.trim() || result.stderr.trim();
    return output || undefined;
}
async function isCommandAvailable(command) {
    const version = await getCommandVersion(command);
    return Boolean(version);
}
async function runCommandWithLimits(command, timeoutMs, maxBytes) {
    return new Promise((resolve) => {
        const child = spawn(command[0], command.slice(1), {
            cwd: repoRoot,
            env: process.env,
            shell: false
        });
        const stdoutChunks = [];
        const stderrChunks = [];
        let stdoutBytes = 0;
        let stderrBytes = 0;
        let totalBytes = 0;
        let truncated = false;
        const stdoutCap = maxBytes;
        const stderrCap = maxBytes;
        const onData = (chunk, stream) => {
            totalBytes += chunk.length;
            if (stream === "stdout") {
                if (stdoutBytes < stdoutCap) {
                    const slice = chunk.slice(0, stdoutCap - stdoutBytes);
                    stdoutChunks.push(slice);
                    stdoutBytes += slice.length;
                }
                else {
                    truncated = true;
                }
            }
            else {
                if (stderrBytes < stderrCap) {
                    const slice = chunk.slice(Math.max(0, chunk.length - (stderrCap - stderrBytes)));
                    stderrChunks.push(slice);
                    stderrBytes += slice.length;
                }
                else {
                    truncated = true;
                }
            }
        };
        child.stdout?.on("data", (chunk) => onData(chunk, "stdout"));
        child.stderr?.on("data", (chunk) => onData(chunk, "stderr"));
        let timeout;
        if (timeoutMs > 0) {
            timeout = setTimeout(() => {
                truncated = true;
                child.kill("SIGKILL");
            }, timeoutMs);
        }
        child.on("close", (code) => {
            if (timeout)
                clearTimeout(timeout);
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
            if (timeout)
                clearTimeout(timeout);
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
async function runSimpleCommand(command, args, timeoutMs, maxBytes) {
    return new Promise((resolve) => {
        let stdout = "";
        let stderr = "";
        const child = spawn(command, args, {
            cwd: repoRoot,
            env: process.env,
            shell: false
        });
        const onData = (chunk, target) => {
            const text = chunk.toString("utf8");
            if (target === "stdout") {
                stdout += text;
            }
            else {
                stderr += text;
            }
            if (Buffer.byteLength(stdout) + Buffer.byteLength(stderr) > maxBytes) {
                child.kill("SIGKILL");
            }
        };
        child.stdout?.on("data", (chunk) => onData(chunk, "stdout"));
        child.stderr?.on("data", (chunk) => onData(chunk, "stderr"));
        let timeout;
        if (timeoutMs > 0) {
            timeout = setTimeout(() => {
                child.kill("SIGKILL");
            }, timeoutMs);
        }
        child.on("close", (code) => {
            if (timeout)
                clearTimeout(timeout);
            resolve({
                ok: code === 0,
                stdout: normalizeLineEndings(stdout),
                stderr: normalizeLineEndings(stderr)
            });
        });
        child.on("error", () => {
            if (timeout)
                clearTimeout(timeout);
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
function resolveRepoPath(userPath) {
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
function normalizeRelativePath(relativePath) {
    return relativePath.split(path.sep).join("/");
}
function isWithinRepoRoot(resolvedPath) {
    return resolvedPath === repoRoot || resolvedPath.startsWith(repoRoot + path.sep);
}
function safeOutputPath(userPath) {
    const resolved = resolveRepoPath(userPath);
    if (resolved.ok)
        return resolved.relative;
    return ".";
}
function allowProtectedPaths() {
    const raw = process.env.BIDDERSWEET_ALLOW_PROTECTED_PATHS;
    if (!raw)
        return false;
    return ["1", "true", "yes"].includes(raw.trim().toLowerCase());
}
function isProtectedPath(relPath) {
    if (allowProtectedPaths())
        return false;
    const normalized = normalizeRelativePath(relPath);
    return PROTECTED_PATH_PATTERNS.some((pattern) => pattern.test(normalized));
}
function isLockfilePath(relPath) {
    return LOCKFILE_NAMES.has(path.basename(relPath));
}
async function existsInRepo(relPath) {
    const resolved = resolveRepoPath(relPath);
    if (!resolved.ok)
        return false;
    try {
        await fs.access(resolved.resolved);
        return true;
    }
    catch {
        return false;
    }
}
async function detectGitRepo() {
    const dotGit = path.join(repoRoot, ".git");
    if (fsSync.existsSync(dotGit))
        return true;
    const gitAvailable = await isCommandAvailable("git");
    if (!gitAvailable)
        return false;
    const result = await runSimpleCommand("git", ["-C", repoRoot, "rev-parse", "--is-inside-work-tree"], 2_000, 2048);
    if (!result.ok)
        return false;
    return result.stdout.trim() === "true";
}
async function detectPackageManager() {
    if (await existsInRepo("pnpm-lock.yaml"))
        return "pnpm";
    if (await existsInRepo("yarn.lock"))
        return "yarn";
    if (await existsInRepo("package-lock.json"))
        return "npm";
    return "unknown";
}
async function isBinaryFile(filePath) {
    const handle = await fs.open(filePath, "r");
    try {
        const buffer = Buffer.alloc(1024);
        const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
        for (let i = 0; i < bytesRead; i += 1) {
            if (buffer[i] === 0)
                return true;
        }
        return false;
    }
    finally {
        await handle.close();
    }
}
function normalizeLineEndings(value) {
    return value.replace(/\r\n/g, "\n");
}
function resolveCommandTimeout() {
    const raw = process.env.BIDDERSWEET_CMD_TIMEOUT_MS;
    if (!raw)
        return DEFAULT_CMD_TIMEOUT_MS;
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed <= 0)
        return DEFAULT_CMD_TIMEOUT_MS;
    return parsed;
}
function emptyInputSchema() {
    return {
        type: "object",
        properties: {},
        additionalProperties: false
    };
}
function jsonResult(payload, isError = false) {
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
function toolError(code, message, details) {
    return {
        error: {
            code,
            message,
            details
        }
    };
}
function applyPatchError(pathValue, code, message, details, beforeSha256, afterSha256, diffApplied) {
    return {
        path: pathValue,
        applied: false,
        beforeSha256,
        afterSha256,
        diffApplied,
        errors: [{ code, message, details }]
    };
}
async function writeFileAtomic(filePath, content, mode) {
    const dir = path.dirname(filePath);
    const tmpName = `.biddersweet-tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const tmpPath = path.join(dir, tmpName);
    try {
        await fs.writeFile(tmpPath, content, mode ? { mode } : undefined);
        await fs.rename(tmpPath, filePath);
    }
    catch (error) {
        try {
            await fs.unlink(tmpPath);
        }
        catch {
            // ignore cleanup errors
        }
        throw error;
    }
}
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch(() => {
    process.exit(1);
});
