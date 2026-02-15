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

const DEFAULT_TRIAGE_SERVICE = "x-bid-backend-api";
const DEFAULT_TRIAGE_WINDOW_MINUTES = 30;
const MAX_TRIAGE_WINDOW_MINUTES = 240;
const MAX_DEPLOY_WINDOW_MINUTES = 180;
const DESTRUCTIVE_CONFIRM_TEXT = "ALLOW_DESTRUCTIVE";
const TRIAGE_MAX_LOGS = 2_000;
const TRIAGE_MAX_ERROR_GROUPS = 5;
const TRIAGE_SAMPLE_MAX_CHARS = 360;
const TRIAGE_CORRELATION_WINDOW_MINUTES = 12;

const triageInputSchema = z.object({
  service: z.string().trim().min(1).optional(),
  serviceName: z.string().trim().min(1).optional(),
  timeWindowMinutes: z.number().int().positive().max(MAX_TRIAGE_WINDOW_MINUTES).optional(),
  window_minutes: z.number().int().positive().max(MAX_TRIAGE_WINDOW_MINUTES).optional(),
  filter: z.string().trim().min(1).max(256).optional(),
  endpoint: z.string().trim().min(1).max(256).optional(),
  requestId: z.string().trim().min(1).max(256).optional(),
  request_id: z.string().trim().min(1).max(256).optional()
});

export const OpsTriageProdErrorInputSchema = triageInputSchema.transform((value) => ({
  service: value.service ?? value.serviceName ?? DEFAULT_TRIAGE_SERVICE,
  timeWindowMinutes: value.timeWindowMinutes ?? value.window_minutes ?? DEFAULT_TRIAGE_WINDOW_MINUTES,
  filter: value.filter,
  endpoint: value.endpoint,
  requestId: value.requestId ?? value.request_id
}));

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

export type RenderService = {
  id: string;
  name: string;
  url?: string | null;
  region?: string | null;
};

export type RenderLogEntry = {
  timestamp: string;
  message: string;
  level?: string | null;
  type?: string | null;
  path?: string | null;
  statusCode?: string | number | null;
  requestId?: string | null;
};

export type RenderLogsResponse = {
  logs: RenderLogEntry[];
  truncated?: boolean;
  hasMore?: boolean;
};

export type RenderMetricPoint = {
  timestamp: string;
  value: number | null;
};

export type RenderMetricSeries = {
  metricType: string;
  points: RenderMetricPoint[];
};

export type RenderDeploy = {
  id: string;
  status?: string | null;
  startedAt?: string | null;
  createdAt?: string | null;
  finishedAt?: string | null;
};

export type OpsTriageProdErrorResult = {
  service: { id: string; name: string; url?: string | null } | null;
  window_minutes: number;
  time_range: { start: string; end: string };
  filters: { filter?: string; endpoint?: string; request_id?: string };
  top_errors: Array<{ signature: string; count: number; first_seen: string; sample: string }>;
  deploy_correlation: {
    likely: boolean;
    deploy_id: string | null;
    started_at: string | null;
    reason: string;
  };
  metrics_summary: {
    error_count: { latest: number; max: number; average: number } | null;
    latency_p95_ms: { latest: number; max: number; average: number } | null;
    cpu_usage_pct: { latest: number; max: number; average: number } | null;
    memory_usage_mb: { latest: number; max: number; average: number } | null;
    series_considered: number;
  };
  recommended_next_actions: string[];
  bounded_by: { max_logs: number; max_error_groups: number; sample_chars: number };
  expand_instructions: string[];
  warnings: string[];
};

export type OpsOrchestratorDeps = {
  getGitSummary: () => Promise<{ isGitRepo: boolean; branch: string | null; changedCount: number }>;
  getDevToolsSummary: () => Promise<{ rgPresent: boolean; gitPresent: boolean }>;
  fileExists: (relativePath: string) => Promise<boolean>;
  readTextFile: (relativePath: string) => Promise<string | null>;
  listRenderServices: () => Promise<RenderService[]>;
  listRenderLogs: (input: {
    serviceId: string;
    startTime: string;
    endTime: string;
    limit: number;
    filter?: string;
    endpoint?: string;
    requestId?: string;
  }) => Promise<RenderLogsResponse>;
  getRenderMetrics: (input: {
    resourceId: string;
    startTime: string;
    endTime: string;
  }) => Promise<RenderMetricSeries[]>;
  listRenderDeploys: (input: {
    serviceId: string;
    startTime: string;
    endTime: string;
    limit: number;
  }) => Promise<RenderDeploy[]>;
};

export function runOpsTriageProdError(
  input: OpsTriageProdErrorInput,
  deps: OpsOrchestratorDeps
): Promise<OpsTriageProdErrorResult> {
  return (async () => {
    const warnings: string[] = [];
    const now = new Date();
    const start = new Date(now.getTime() - input.timeWindowMinutes * 60_000);

    let services: RenderService[] = [];
    try {
      services = await deps.listRenderServices();
    } catch {
      warnings.push("render_services_unavailable");
    }

    const selectedService = selectService(input.service, services);
    if (!selectedService) {
      warnings.push("service_not_found");
      return buildTriageResult({
        input,
        start,
        end: now,
        topErrors: [],
        deployCorrelation: {
          likely: false,
          deploy_id: null,
          started_at: null,
          reason: "service_not_found"
        },
        metricsSummary: emptyMetricsSummary(),
        warnings
      });
    }

    let logsResponse: RenderLogsResponse = { logs: [] };
    let metrics: RenderMetricSeries[] = [];
    let deploys: RenderDeploy[] = [];

    try {
      logsResponse = await deps.listRenderLogs({
        serviceId: selectedService.id,
        startTime: start.toISOString(),
        endTime: now.toISOString(),
        limit: TRIAGE_MAX_LOGS,
        filter: input.filter,
        endpoint: input.endpoint,
        requestId: input.requestId
      });
    } catch {
      warnings.push("render_logs_unavailable");
    }

    try {
      metrics = await deps.getRenderMetrics({
        resourceId: selectedService.id,
        startTime: start.toISOString(),
        endTime: now.toISOString()
      });
    } catch {
      warnings.push("render_metrics_unavailable");
    }

    try {
      deploys = await deps.listRenderDeploys({
        serviceId: selectedService.id,
        startTime: start.toISOString(),
        endTime: now.toISOString(),
        limit: 20
      });
    } catch {
      warnings.push("render_deploys_unavailable");
    }

    if (logsResponse.truncated || logsResponse.hasMore) {
      warnings.push("logs_truncated");
    }

    const topErrors = buildTopErrors(logsResponse.logs, input, warnings);
    const deployCorrelation = correlateDeploy(topErrors, deploys);
    const metricsSummary = summarizeMetrics(metrics);
    const recommendedNextActions = recommendNextActions(topErrors, deployCorrelation, input);

    return {
      service: { id: selectedService.id, name: selectedService.name, url: selectedService.url ?? null },
      window_minutes: input.timeWindowMinutes,
      time_range: { start: start.toISOString(), end: now.toISOString() },
      filters: {
        filter: input.filter,
        endpoint: input.endpoint,
        request_id: input.requestId
      },
      top_errors: topErrors,
      deploy_correlation: deployCorrelation,
      metrics_summary: metricsSummary,
      recommended_next_actions: recommendedNextActions,
      bounded_by: {
        max_logs: TRIAGE_MAX_LOGS,
        max_error_groups: TRIAGE_MAX_ERROR_GROUPS,
        sample_chars: TRIAGE_SAMPLE_MAX_CHARS
      },
      expand_instructions: [
        "Rerun with a narrower time window (for example 10-15 minutes) around first_seen.",
        "Use `filter` to focus on one error family or class name.",
        "Use `endpoint` and/or `request_id` to isolate request-level failures."
      ],
      warnings
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

function buildTriageResult(input: {
  input: OpsTriageProdErrorInput;
  start: Date;
  end: Date;
  topErrors: Array<{ signature: string; count: number; first_seen: string; sample: string }>;
  deployCorrelation: {
    likely: boolean;
    deploy_id: string | null;
    started_at: string | null;
    reason: string;
  };
  metricsSummary: {
    error_count: { latest: number; max: number; average: number } | null;
    latency_p95_ms: { latest: number; max: number; average: number } | null;
    cpu_usage_pct: { latest: number; max: number; average: number } | null;
    memory_usage_mb: { latest: number; max: number; average: number } | null;
    series_considered: number;
  };
  warnings: string[];
}): OpsTriageProdErrorResult {
  return {
    service: null,
    window_minutes: input.input.timeWindowMinutes,
    time_range: { start: input.start.toISOString(), end: input.end.toISOString() },
    filters: {
      filter: input.input.filter,
      endpoint: input.input.endpoint,
      request_id: input.input.requestId
    },
    top_errors: input.topErrors,
    deploy_correlation: input.deployCorrelation,
    metrics_summary: input.metricsSummary,
    recommended_next_actions: [
      "Confirm the Render service selector (`service`/`serviceName`) matches the backend API service.",
      "Retry with a narrower window around the incident start and a targeted `endpoint`.",
      "If issue persists, verify Render workspace/resource selection and access."
    ],
    bounded_by: {
      max_logs: TRIAGE_MAX_LOGS,
      max_error_groups: TRIAGE_MAX_ERROR_GROUPS,
      sample_chars: TRIAGE_SAMPLE_MAX_CHARS
    },
    expand_instructions: [
      "Rerun with an explicit service name or URL.",
      "Use `filter` for an exception class (for example `ActiveRecord::` or `NoMethodError`).",
      "Use `request_id` for single-request trace narrowing."
    ],
    warnings: input.warnings
  };
}

function selectService(query: string, services: RenderService[]): RenderService | null {
  if (services.length === 0) return null;
  const normalizedQuery = query.trim().toLowerCase();
  const exact =
    services.find((service) => service.id.toLowerCase() === normalizedQuery) ??
    services.find((service) => service.name.toLowerCase() === normalizedQuery) ??
    services.find((service) => (service.url ?? "").toLowerCase() === normalizedQuery);
  if (exact) return exact;
  return (
    services.find((service) => service.name.toLowerCase().includes(normalizedQuery)) ??
    services.find((service) => (service.url ?? "").toLowerCase().includes(normalizedQuery)) ??
    null
  );
}

function buildTopErrors(
  logs: RenderLogEntry[],
  input: OpsTriageProdErrorInput,
  warnings: string[]
): Array<{ signature: string; count: number; first_seen: string; sample: string }> {
  if (!Array.isArray(logs) || logs.length === 0) {
    warnings.push("no_logs_in_window");
    return [];
  }

  const regexFilter = compileFilterRegex(input.filter);
  const grouped = new Map<
    string,
    { count: number; firstSeen: number; firstSeenIso: string; sample: string }
  >();

  for (const entry of logs.slice(0, TRIAGE_MAX_LOGS)) {
    if (!matchesLogFilters(entry, input, regexFilter)) continue;
    if (!isErrorLike(entry)) continue;

    const signature = extractSignature(entry);
    if (!signature) continue;

    const firstSeen = toTimestampMs(entry.timestamp);
    const sample = extractSample(entry.message);
    const existing = grouped.get(signature);
    if (!existing) {
      grouped.set(signature, {
        count: 1,
        firstSeen,
        firstSeenIso: new Date(firstSeen).toISOString(),
        sample
      });
      continue;
    }

    existing.count += 1;
    if (firstSeen < existing.firstSeen) {
      existing.firstSeen = firstSeen;
      existing.firstSeenIso = new Date(firstSeen).toISOString();
      if (sample.length > 0) existing.sample = sample;
    }
  }

  return [...grouped.entries()]
    .map(([signature, value]) => ({
      signature,
      count: value.count,
      first_seen: value.firstSeenIso,
      sample: value.sample
    }))
    .sort((a, b) => {
      if (b.count !== a.count) return b.count - a.count;
      return toTimestampMs(a.first_seen) - toTimestampMs(b.first_seen);
    })
    .slice(0, TRIAGE_MAX_ERROR_GROUPS);
}

function correlateDeploy(
  topErrors: Array<{ signature: string; count: number; first_seen: string; sample: string }>,
  deploys: RenderDeploy[]
): {
  likely: boolean;
  deploy_id: string | null;
  started_at: string | null;
  reason: string;
} {
  if (topErrors.length === 0) {
    return { likely: false, deploy_id: null, started_at: null, reason: "no_errors_detected" };
  }
  if (!Array.isArray(deploys) || deploys.length === 0) {
    return { likely: false, deploy_id: null, started_at: null, reason: "no_deploys_in_window" };
  }

  const firstSeenMs = toTimestampMs(topErrors[0].first_seen);
  const nearest = deploys
    .map((deploy) => {
      const startedAt = deploy.startedAt ?? deploy.createdAt ?? null;
      if (!startedAt) return null;
      const startedMs = toTimestampMs(startedAt);
      const minutesAfterDeploy = (firstSeenMs - startedMs) / 60_000;
      return {
        deploy,
        startedAt,
        minutesAfterDeploy
      };
    })
    .filter(
      (
        value
      ): value is {
        deploy: RenderDeploy;
        startedAt: string;
        minutesAfterDeploy: number;
      } => Boolean(value)
    )
    .filter((value) => value.minutesAfterDeploy >= 0)
    .sort((a, b) => a.minutesAfterDeploy - b.minutesAfterDeploy)[0];

  if (!nearest) {
    return { likely: false, deploy_id: null, started_at: null, reason: "no_prior_deploy_found" };
  }

  const likely = nearest.minutesAfterDeploy <= TRIAGE_CORRELATION_WINDOW_MINUTES;
  return {
    likely,
    deploy_id: likely ? nearest.deploy.id : null,
    started_at: likely ? nearest.startedAt : null,
    reason: likely
      ? `first_error_within_${TRIAGE_CORRELATION_WINDOW_MINUTES}m_of_deploy`
      : "first_error_outside_deploy_correlation_window"
  };
}

function summarizeMetrics(series: RenderMetricSeries[]): {
  error_count: { latest: number; max: number; average: number } | null;
  latency_p95_ms: { latest: number; max: number; average: number } | null;
  cpu_usage_pct: { latest: number; max: number; average: number } | null;
  memory_usage_mb: { latest: number; max: number; average: number } | null;
  series_considered: number;
} {
  const errorSeries = pickMetric(series, /(error|5xx|http_request_count)/i);
  const latencySeries = pickMetric(series, /(latency|response_time|http_latency)/i);
  const cpuSeries = pickMetric(series, /(cpu_usage|cpu)/i);
  const memorySeries = pickMetric(series, /(memory_usage|memory)/i);

  return {
    error_count: summarizeMetricSeries(errorSeries),
    latency_p95_ms: summarizeMetricSeries(latencySeries),
    cpu_usage_pct: summarizeMetricSeries(cpuSeries),
    memory_usage_mb: summarizeMetricSeries(memorySeries),
    series_considered: Array.isArray(series) ? series.length : 0
  };
}

function pickMetric(series: RenderMetricSeries[], pattern: RegExp): RenderMetricSeries | null {
  return series.find((item) => pattern.test(item.metricType)) ?? null;
}

function summarizeMetricSeries(
  series: RenderMetricSeries | null
): { latest: number; max: number; average: number } | null {
  if (!series || !Array.isArray(series.points) || series.points.length === 0) return null;
  const values = series.points
    .map((point) => point.value)
    .filter((value): value is number => typeof value === "number" && Number.isFinite(value));
  if (values.length === 0) return null;

  const latest = values[values.length - 1];
  const max = values.reduce((acc, value) => (value > acc ? value : acc), values[0]);
  const total = values.reduce((acc, value) => acc + value, 0);
  return {
    latest: roundMetric(latest),
    max: roundMetric(max),
    average: roundMetric(total / values.length)
  };
}

function roundMetric(value: number): number {
  return Math.round(value * 100) / 100;
}

function emptyMetricsSummary() {
  return {
    error_count: null,
    latency_p95_ms: null,
    cpu_usage_pct: null,
    memory_usage_mb: null,
    series_considered: 0
  };
}

function recommendNextActions(
  topErrors: Array<{ signature: string; count: number; first_seen: string; sample: string }>,
  deployCorrelation: {
    likely: boolean;
    deploy_id: string | null;
    started_at: string | null;
    reason: string;
  },
  input: OpsTriageProdErrorInput
): string[] {
  const actions: string[] = [];
  if (deployCorrelation.likely && deployCorrelation.deploy_id) {
    actions.push(
      `Inspect deploy ${deployCorrelation.deploy_id} config/commit diff and env var changes before rollback decisions.`
    );
  }

  const signatures = topErrors.map((entry) => entry.signature).join(" | ").toLowerCase();
  if (signatures.includes("activerecord") || signatures.includes("pg::")) {
    actions.push("Run read-only SQL checks for connection pressure, locks, and long-running queries.");
  }
  if (signatures.includes("401") || signatures.includes("unauthorized") || signatures.includes("forbidden")) {
    actions.push("Check auth/session config drift (cookie domain, CSRF, token signing, and frontend origin).");
  }
  if (input.endpoint) {
    actions.push(`Inspect controller/service path for endpoint ${input.endpoint} and recent code changes.`);
  }
  actions.push("Validate the top error signature in application logs and capture one failing request timeline.");
  actions.push("If needed, rerun triage with narrower filters to isolate one signature before remediation.");

  return dedupe(actions).slice(0, 6);
}

function dedupe(values: string[]): string[] {
  return [...new Set(values)];
}

function compileFilterRegex(filter?: string): RegExp | null {
  if (!filter) return null;
  try {
    return new RegExp(filter, "i");
  } catch {
    return null;
  }
}

function matchesLogFilters(entry: RenderLogEntry, input: OpsTriageProdErrorInput, regexFilter: RegExp | null): boolean {
  const message = entry.message ?? "";
  if (input.endpoint) {
    const path = entry.path ?? "";
    if (!path.includes(input.endpoint) && !message.includes(input.endpoint)) return false;
  }
  if (input.requestId) {
    const requestId = entry.requestId ?? "";
    if (!requestId.includes(input.requestId) && !message.includes(input.requestId)) return false;
  }
  if (!input.filter) return true;
  if (regexFilter) return regexFilter.test(message);
  return message.toLowerCase().includes(input.filter.toLowerCase());
}

function isErrorLike(entry: RenderLogEntry): boolean {
  const message = (entry.message ?? "").toLowerCase();
  const level = (entry.level ?? "").toLowerCase();
  const statusCode = Number(entry.statusCode ?? NaN);
  if (Number.isFinite(statusCode) && statusCode >= 500) return true;
  if (level === "error" || level === "fatal") return true;
  return /(error|exception|fatal|panic|traceback|unhandled|failed)/i.test(message);
}

function extractSignature(entry: RenderLogEntry): string {
  const message = entry.message ?? "";
  const lines = message
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const primary = lines.find((line) => /(error|exception|fatal|panic|traceback|unhandled|failed)/i.test(line)) ?? lines[0];
  if (!primary) return "UnknownError";

  const classMatch = primary.match(/\b([A-Z][A-Za-z0-9_:]*(?:Error|Exception|Fault))\b(?::\s*(.*))?/);
  if (classMatch) {
    const detail = sanitizeSignature(classMatch[2] ?? "");
    return detail.length > 0 ? `${classMatch[1]}: ${detail}` : classMatch[1];
  }

  const statusCode = Number(entry.statusCode ?? NaN);
  if (Number.isFinite(statusCode) && statusCode >= 500) {
    const path = entry.path ? ` ${entry.path}` : "";
    return `HTTP ${statusCode}${path}`.trim();
  }

  return sanitizeSignature(primary);
}

function sanitizeSignature(value: string): string {
  return value
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, "<uuid>")
    .replace(/0x[0-9a-f]+/gi, "0x<hex>")
    .replace(/\b\d{3,}\b/g, "<n>")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 140);
}

function extractSample(message: string): string {
  const lines = message
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  if (lines.length === 0) return "";

  const stackLines = lines.filter((line) => /( at |:\d+:|\.rb:\d+|\.ts:\d+|\.js:\d+)/.test(line));
  const selected = (stackLines.length > 0 ? stackLines.slice(0, 4) : lines.slice(0, 3)).join("\n");
  return selected.slice(0, TRIAGE_SAMPLE_MAX_CHARS);
}

function toTimestampMs(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
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
