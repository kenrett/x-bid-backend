import { z } from "zod";

export type OrchestratorSignal = {
  name: string;
  status: "ok" | "warn" | "error" | "refused";
  detail: string;
  value?: string | number | boolean | null;
};

export type OrchestratorArtifact = {
  kind: string;
  id?: string;
  link?: string;
  label?: string;
};

export type OrchestratorResult = {
  summary: string;
  signals: OrchestratorSignal[];
  next_actions: string[];
  artifacts: OrchestratorArtifact[];
  confidence: number;
  refused?: boolean;
  refusal_reason?: string;
};

const MAX_DEPLOY_WINDOW_MINUTES = 180;
const DESTRUCTIVE_CONFIRM_TEXT = "ALLOW_DESTRUCTIVE";

export const OpsTriageProdErrorInputSchema = z.object({
  serviceName: z.string().trim().min(1),
  timeWindowMinutes: z.number().int().positive().max(MAX_DEPLOY_WINDOW_MINUTES).optional().default(60)
});

export const OpsVerifyDeployWindow401InputSchema = z.object({
  serviceName: z.string().trim().min(1),
  timeWindowMinutes: z.number().int().positive().optional().default(45)
});

export const OpsEnvDiffInputSchema = z.object({
  sourceEnv: z.string().trim().min(1),
  targetEnv: z.string().trim().min(1),
  sourcePath: z.string().trim().min(1).optional().default("config/env/source.env.keys"),
  targetPath: z.string().trim().min(1).optional().default("config/env/target.env.keys"),
  includeSensitive: z.boolean().optional().default(false),
  destructiveIntent: z.boolean().optional().default(false),
  confirmToken: z.string().optional(),
  confirmText: z.string().optional()
});

export type OpsTriageProdErrorInput = z.infer<typeof OpsTriageProdErrorInputSchema>;
export type OpsVerifyDeployWindow401Input = z.infer<typeof OpsVerifyDeployWindow401InputSchema>;
export type OpsEnvDiffInput = z.infer<typeof OpsEnvDiffInputSchema>;

export type OpsOrchestratorDeps = {
  getGitSummary: () => Promise<{ isGitRepo: boolean; branch: string | null; changedCount: number }>;
  getDevToolsSummary: () => Promise<{ rgPresent: boolean; gitPresent: boolean }>;
  fileExists: (relativePath: string) => Promise<boolean>;
  readTextFile: (relativePath: string) => Promise<string | null>;
};

export function runOpsTriageProdError(
  input: OpsTriageProdErrorInput,
  deps: OpsOrchestratorDeps
): Promise<OrchestratorResult> {
  return (async () => {
    const [git, tools, runbookPresent] = await Promise.all([
      deps.getGitSummary(),
      deps.getDevToolsSummary(),
      deps.fileExists("runbooks/vercel-mcp.md")
    ]);

    const signals: OrchestratorSignal[] = [
      {
        name: "service",
        status: "ok",
        detail: `triaging ${input.serviceName}`,
        value: input.serviceName
      },
      {
        name: "time_window_minutes",
        status: "ok",
        detail: "analysis window accepted",
        value: input.timeWindowMinutes
      },
      {
        name: "repo_state",
        status: git.changedCount > 0 ? "warn" : "ok",
        detail: git.changedCount > 0 ? "working tree has local changes" : "working tree is clean",
        value: git.changedCount
      },
      {
        name: "tooling",
        status: tools.rgPresent && tools.gitPresent ? "ok" : "warn",
        detail: tools.rgPresent && tools.gitPresent ? "core local tools available" : "one or more core tools missing"
      },
      {
        name: "runbook",
        status: runbookPresent ? "ok" : "warn",
        detail: runbookPresent ? "deploy/runbook doc is available" : "deploy/runbook doc is missing"
      }
    ];

    const nextActions = [
      "Correlate the error timestamp with recent deploy and auth/session changes.",
      "Check request logs for the failing endpoint and compare against expected status codes.",
      "If regression is confirmed, prepare rollback or hotfix guarded by feature flags."
    ];

    return {
      summary: `Prepared local triage context for ${input.serviceName}.`,
      signals,
      next_actions: nextActions,
      artifacts: [
        { kind: "runbook", link: "runbooks/vercel-mcp.md", label: "Vercel MCP runbook" },
        { kind: "git_branch", id: git.branch ?? "unknown", label: "Current branch" }
      ],
      confidence: 0.71
    };
  })();
}

export function runOpsVerifyDeployWindow401(
  input: OpsVerifyDeployWindow401Input,
  deps: OpsOrchestratorDeps
): Promise<OrchestratorResult> {
  return (async () => {
    if (input.timeWindowMinutes > MAX_DEPLOY_WINDOW_MINUTES) {
      return refusedResult(
        "time_window_too_large",
        `Refused: requested window (${input.timeWindowMinutes}m) exceeds ${MAX_DEPLOY_WINDOW_MINUTES}m limit.`
      );
    }

    const [git, runbookPresent] = await Promise.all([
      deps.getGitSummary(),
      deps.fileExists("runbooks/vercel-mcp.md")
    ]);

    return {
      summary: `Deploy window verification prepared for ${input.serviceName}.`,
      signals: [
        {
          name: "service",
          status: "ok",
          detail: "service selected for 401 correlation",
          value: input.serviceName
        },
        {
          name: "window_minutes",
          status: "ok",
          detail: "requested verification window accepted",
          value: input.timeWindowMinutes
        },
        {
          name: "git_context",
          status: git.isGitRepo ? "ok" : "warn",
          detail: git.isGitRepo ? "git metadata available for deploy correlation" : "git metadata unavailable"
        },
        {
          name: "runbook",
          status: runbookPresent ? "ok" : "warn",
          detail: runbookPresent ? "401 runbook reference present" : "401 runbook reference missing"
        }
      ],
      next_actions: [
        "Compare 401 spikes to deploy timestamps inside the requested window.",
        "Validate cookie/session and CSRF behavior before and after the suspected deploy.",
        "Confirm auth middleware and origin settings did not drift."
      ],
      artifacts: [{ kind: "runbook", link: "runbooks/vercel-mcp.md" }],
      confidence: 0.69
    };
  })();
}

export function runOpsEnvDiff(input: OpsEnvDiffInput, deps: OpsOrchestratorDeps): Promise<OrchestratorResult> {
  return (async () => {
    if (input.destructiveIntent) {
      const confirmed =
        typeof input.confirmToken === "string" &&
        input.confirmToken.trim().length > 0 &&
        input.confirmText === DESTRUCTIVE_CONFIRM_TEXT;
      if (!confirmed) {
        return refusedResult(
          "destructive_confirmation_required",
          "Refused: destructive mode requires confirmToken and confirmText=ALLOW_DESTRUCTIVE."
        );
      }
    }

    const [sourceContent, targetContent] = await Promise.all([
      deps.readTextFile(input.sourcePath),
      deps.readTextFile(input.targetPath)
    ]);

    if (!sourceContent || !targetContent) {
      return refusedResult("env_manifest_missing", "Refused: one or more environment key manifests are missing.");
    }

    const sourceKeys = parseEnvManifestKeys(sourceContent);
    const targetKeys = parseEnvManifestKeys(targetContent);

    const onlySource = sourceKeys.filter((key) => !targetKeys.includes(key));
    const onlyTarget = targetKeys.filter((key) => !sourceKeys.includes(key));
    const symmetricDiff = onlySource.length + onlyTarget.length;

    return {
      summary: `Computed env key diff: ${input.sourceEnv} vs ${input.targetEnv}.`,
      signals: [
        { name: "source_env", status: "ok", detail: "source manifest loaded", value: input.sourceEnv },
        { name: "target_env", status: "ok", detail: "target manifest loaded", value: input.targetEnv },
        {
          name: "key_drift",
          status: symmetricDiff === 0 ? "ok" : "warn",
          detail: symmetricDiff === 0 ? "no key drift detected" : "environment key drift detected",
          value: symmetricDiff
        },
        {
          name: "sensitive_values",
          status: input.includeSensitive ? "warn" : "ok",
          detail: input.includeSensitive ? "values requested (not returned by this tool)" : "key-only comparison"
        }
      ],
      next_actions: [
        "Align missing keys in deployment environment configuration before release.",
        "Verify credentials and secrets through platform secret stores, not local files.",
        "Re-run env diff after updates to confirm zero drift."
      ],
      artifacts: [
        { kind: "env_manifest", link: input.sourcePath, label: input.sourceEnv },
        { kind: "env_manifest", link: input.targetPath, label: input.targetEnv },
        { kind: "diff_count", id: String(symmetricDiff), label: "Symmetric key drift count" }
      ],
      confidence: symmetricDiff === 0 ? 0.9 : 0.78
    };
  })();
}

function parseEnvManifestKeys(content: string): string[] {
  return content
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((line) => line.replace(/=.*/, ""))
    .filter((line) => line.length > 0)
    .sort((a, b) => a.localeCompare(b));
}

function refusedResult(reason: string, summary: string): OrchestratorResult {
  return {
    summary,
    signals: [{ name: "refusal", status: "refused", detail: reason }],
    next_actions: ["Adjust input parameters and retry with an allowed read-only configuration."],
    artifacts: [],
    confidence: 0.98,
    refused: true,
    refusal_reason: reason
  };
}
