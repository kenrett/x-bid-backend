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
const MAX_READ_RANGE_LINES = 400;
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
const DevCheckInputSchema = z.object({});
const DevRunTargetSchema = z.object({
    target: z.enum(["ruby", "js", "both"]).optional().default("both")
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
                return jsonResult(result, Boolean(result.error));
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
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch(() => {
    process.exit(1);
});
