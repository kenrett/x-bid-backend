import { z } from "zod";
import type { OrchestratorArtifact, OrchestratorResult, OrchestratorSignal } from "./ops.js";

const DESTRUCTIVE_CONFIRM_TEXT = "ALLOW_DESTRUCTIVE";

export const DevRouteContractCheckInputSchema = z.object({
  maxAllowedDrift: z.number().int().nonnegative().optional().default(25)
});

export const DevSmokeFullstackInputSchema = z.object({
  serviceName: z.string().trim().min(1),
  includeIntegration: z.boolean().optional().default(false),
  destructiveIntent: z.boolean().optional().default(false),
  confirmToken: z.string().optional(),
  confirmText: z.string().optional()
});

export type DevRouteContractCheckInput = z.infer<typeof DevRouteContractCheckInputSchema>;
export type DevSmokeFullstackInput = z.infer<typeof DevSmokeFullstackInputSchema>;

export type DevOrchestratorDeps = {
  getRoutesSummary: () => Promise<{ routeCount: number; truncated: boolean }>;
  getOpenApiPathCount: () => Promise<number>;
  getDevToolsSummary: () => Promise<{ rgPresent: boolean; gitPresent: boolean; nodePresent: boolean }>;
  runSmokeBenchmark: () => Promise<{ ok: boolean; durationMs: number }>;
};

export function runDevRouteContractCheck(
  input: DevRouteContractCheckInput,
  deps: DevOrchestratorDeps
): Promise<OrchestratorResult> {
  return (async () => {
    const [routes, openapiPathCount] = await Promise.all([deps.getRoutesSummary(), deps.getOpenApiPathCount()]);
    const drift = Math.abs(routes.routeCount - openapiPathCount);

    const signals: OrchestratorSignal[] = [
      {
        name: "routes_count",
        status: routes.routeCount > 0 ? "ok" : "warn",
        detail: "routes inventory collected",
        value: routes.routeCount
      },
      {
        name: "openapi_paths_count",
        status: openapiPathCount > 0 ? "ok" : "warn",
        detail: "openapi path inventory collected",
        value: openapiPathCount
      },
      {
        name: "drift_count",
        status: drift <= input.maxAllowedDrift ? "ok" : "warn",
        detail: drift <= input.maxAllowedDrift ? "contract drift within threshold" : "contract drift exceeds threshold",
        value: drift
      },
      {
        name: "routes_truncated",
        status: routes.truncated ? "warn" : "ok",
        detail: routes.truncated ? "route results were truncated" : "full route set inspected",
        value: routes.truncated
      }
    ];

    return {
      summary: "Route/OpenAPI contract check complete.",
      signals,
      next_actions: [
        "If drift exceeds threshold, regenerate and review OpenAPI contract before merge.",
        "Validate changed endpoints against frontend assumptions for path + method.",
        "Add/adjust integration tests for any newly introduced routes."
      ],
      artifacts: [
        { kind: "openapi", link: "docs/api/openapi.json", label: "OpenAPI spec" },
        { kind: "drift_count", id: String(drift), label: "Route vs OpenAPI drift count" }
      ],
      confidence: drift <= input.maxAllowedDrift ? 0.87 : 0.76
    };
  })();
}

export function runDevSmokeFullstack(input: DevSmokeFullstackInput, deps: DevOrchestratorDeps): Promise<OrchestratorResult> {
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

    const [tools, smoke] = await Promise.all([deps.getDevToolsSummary(), deps.runSmokeBenchmark()]);

    const artifacts: OrchestratorArtifact[] = [{ kind: "benchmark", id: "json-parse-smoke", label: "Smoke benchmark" }];

    return {
      summary: `Fullstack smoke prepared for ${input.serviceName}.`,
      signals: [
        {
          name: "service",
          status: "ok",
          detail: "target service selected",
          value: input.serviceName
        },
        {
          name: "tooling",
          status: tools.rgPresent && tools.gitPresent && tools.nodePresent ? "ok" : "warn",
          detail: "dev toolchain availability checked"
        },
        {
          name: "smoke_benchmark",
          status: smoke.ok ? "ok" : "warn",
          detail: smoke.ok ? "baseline smoke benchmark passed" : "baseline smoke benchmark failed",
          value: smoke.durationMs
        },
        {
          name: "integration_scope",
          status: input.includeIntegration ? "warn" : "ok",
          detail: input.includeIntegration
            ? "integration checks requested (manual follow-up required)"
            : "fast local smoke path selected"
        }
      ],
      next_actions: [
        "Run full test/lint suites before deploy when smoke signals are healthy.",
        "If smoke benchmark fails, inspect runtime/dependency drift before proceeding.",
        "Promote to deploy verification workflow only after contract checks pass."
      ],
      artifacts,
      confidence: smoke.ok ? 0.82 : 0.63
    };
  })();
}

function refusedResult(reason: string, summary: string): OrchestratorResult {
  return {
    summary,
    signals: [{ name: "refusal", status: "refused", detail: reason }],
    next_actions: ["Retry without destructive intent or provide explicit two-step confirmation."],
    artifacts: [],
    confidence: 0.99,
    refused: true,
    refusal_reason: reason
  };
}
