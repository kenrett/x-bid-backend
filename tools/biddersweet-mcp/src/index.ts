import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import crypto from "node:crypto";
import path from "node:path";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ReadResourceRequestSchema,
  ListResourceTemplatesRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import {
  OpsEnvDiffInputSchema,
  OpsTriageProdErrorInputSchema,
  OpsVerifyDeployWindow401InputSchema,
  runOpsEnvDiff,
  runOpsTriageProdError,
  runOpsVerifyDeployWindow401
} from "./orchestrators/ops.js";
import {
  DevRouteContractCheckInputSchema,
  DevSmokeFullstackInputSchema,
  runDevRouteContractCheck
} from "./orchestrators/dev.js";

const MAX_FILE_SIZE_BYTES = 200 * 1024;
const MAX_PREVIEW_CHARS = 300;
const MAX_CMD_OUTPUT_BYTES = 10 * 1024;
const BENCHMARK_MAX_OUTPUT_BYTES = 8 * 1024;
const BENCHMARK_TIMEOUT_MS = 10_000;
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
  /(^|\/)credentials(\.|\/|$)/i,
  /(^|\/).*\.pem$/i,
  /(^|\/).*\.p12$/i,
  /(^|\/).*\.pfx$/i,
  /(^|\/).*\.jks$/i,
  /(^|\/).*\.keystore$/i,
  /(^|\/).*\.key$/i,
  /(^|\/)id_(rsa|dsa|ecdsa|ed25519)$/i
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
const MAX_GIT_DIFF_BYTES = 256 * 1024;
const CHECK_TIMEOUT_MS = 1_500;
const DEV_RUN_BASE_ENV_ALLOWLIST = ["PATH"];
const DEFAULT_ROUTES_MAX = 500;
const HARD_ROUTES_MAX = 2000;
const ROUTES_COMMAND_TIMEOUT_MS = 20_000;
const ROUTES_COMMAND_MAX_BYTES = 256 * 1024;
const DEFAULT_CAPABILITY_MODE = "READ_ONLY";
const AUDIT_LOG_DIR = ".mcp-logs";
const AUDIT_LOG_FILE = "tool.log";
const SERVER_LOG_FILE = "server.log";
const AUDIT_MAX_STRING = 200;
const AUDIT_MAX_ARRAY = 20;
const SENSITIVE_KEY_PATTERN =
  /(secret|token|password|passwd|api[-_]?key|access[-_]?key|private[-_]?key|session|cookie|authorization|credential)/i;
const WRITE_TOOL_NAMES = new Set(["repo.apply_patch"]);

type CapabilityMode = "READ_ONLY" | "READ_WRITE";

type DevRunAllowlistEntry = {
  name: string;
  command: string[];
  allowedArgs?: string[];
  timeoutMs?: number;
  maxOutputBytes?: number;
  envAllowlist?: string[];
};

type DevBenchmarkAllowlistEntry = {
  name: string;
  command: string[];
  timeoutMs?: number;
  maxOutputBytes?: number;
  envAllowlist?: string[];
};

const DEV_RUN_ALLOWLIST: DevRunAllowlistEntry[] = [
  {
    name: "node-version",
    command: ["node", "--version"],
    allowedArgs: [],
    timeoutMs: 10_000,
    maxOutputBytes: MAX_CMD_OUTPUT_BYTES,
    envAllowlist: []
  }
];

const DEV_BENCHMARK_ALLOWLIST: DevBenchmarkAllowlistEntry[] = [
  {
    name: "json-parse-smoke",
    command: [
      "node",
      "-e",
      [
        "const fs=require('fs');",
        "const path=require('path');",
        "const target=path.join(process.cwd(),'package.json');",
        "let data='{}';",
        "try{data=fs.readFileSync(target,'utf8');}catch{}",
        "let parsed=null;",
        "for(let i=0;i<2000;i++){parsed=JSON.parse(data);}",
        "if(!parsed){process.stderr.write('parse_failed');process.exit(1);}",
        "process.stdout.write(`iterations:2000\\nbytes:${data.length}\\n`);"
      ].join("")
    ],
    timeoutMs: BENCHMARK_TIMEOUT_MS,
    maxOutputBytes: BENCHMARK_MAX_OUTPUT_BYTES,
    envAllowlist: []
  }
];

const DEV_SMOKE_BACKEND_COMMANDS = [
  ["bundle", "exec", "rspec"],
  ["bin/test"]
] as const;

const DEV_SMOKE_FRONTEND_LINT_SCRIPTS = ["lint", "lint:ci"] as const;
const DEV_SMOKE_FRONTEND_TEST_SCRIPTS = ["test:ci", "ci:test", "test"] as const;
const DEV_SMOKE_TIMEOUT_MS = 20 * 60 * 1000;
const DEV_SMOKE_MAX_OUTPUT_BYTES = 64 * 1024;

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

type McpResourceCatalogEntry = {
  uri: string;
  name: string;
  description: string;
  relativePath: string;
  mimeType: string;
};

type McpTemplateParameterType = "string" | "number" | "boolean";

type McpTemplateParameter = {
  name: string;
  type: McpTemplateParameterType;
  required?: boolean;
  description: string;
  defaultValue?: string | number | boolean;
};

type McpTemplateStep = {
  tool: string;
  description: string;
  arguments: Record<string, unknown>;
  fallback?: boolean;
};

type McpWorkflowTemplateCatalogEntry = {
  templateId: string;
  uriTemplate: string;
  name: string;
  description: string;
  whatThisDoes: string;
  mimeType: string;
  parameters: McpTemplateParameter[];
  buildSteps: (params: Record<string, string | number | boolean>) => McpTemplateStep[];
};

const MCP_RESOURCE_CATALOG: McpResourceCatalogEntry[] = [
  {
    uri: "biddersweet://runbooks/incident-triage",
    name: "Incident Triage Runbook",
    description: "Production incident triage flow for backend/API outages.",
    relativePath: "tools/biddersweet-mcp/runbooks/incident-triage.md",
    mimeType: "text/markdown"
  },
  {
    uri: "biddersweet://runbooks/deploy-checklist",
    name: "Deploy Checklist",
    description: "Pre-deploy and post-deploy checklist for Render releases.",
    relativePath: "tools/biddersweet-mcp/runbooks/deploy-checklist.md",
    mimeType: "text/markdown"
  },
  {
    uri: "biddersweet://contracts/auth-session",
    name: "Auth Session Contract",
    description: "Session lifecycle contract for storefront/browser auth flows.",
    relativePath: "tools/biddersweet-mcp/contracts/auth-session.md",
    mimeType: "text/markdown"
  },
  {
    uri: "biddersweet://contracts/storefront-routing",
    name: "Storefront Routing Contract",
    description: "Storefront host routing and data isolation rules.",
    relativePath: "tools/biddersweet-mcp/contracts/storefront-routing.md",
    mimeType: "text/markdown"
  },
  {
    uri: "biddersweet://maps/services-render",
    name: "Render Services Map",
    description: "Name-to-id/url map for Render services.",
    relativePath: "tools/biddersweet-mcp/maps/services.render.json",
    mimeType: "application/json"
  },
  {
    uri: "biddersweet://maps/apps-vercel",
    name: "Vercel Apps Map",
    description: "Name-to-project/domain map for Vercel apps.",
    relativePath: "tools/biddersweet-mcp/maps/apps.vercel.json",
    mimeType: "application/json"
  }
];

const MCP_WORKFLOW_TEMPLATE_CATALOG: McpWorkflowTemplateCatalogEntry[] = [
  {
    templateId: "triage-prod-error",
    uriTemplate: "biddersweet://templates/triage-prod-error{?service,window_minutes,endpoint,filter,request_id}",
    name: "Triage Prod Error",
    description: "Run bounded production-error triage, then gather supporting repo context.",
    whatThisDoes: "Builds a fast incident summary (errors, deploy correlation, metrics) with optional endpoint/request narrowing.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Render backend service name/id." },
      { name: "window_minutes", type: "number", defaultValue: 30, description: "Triage time window in minutes." },
      { name: "endpoint", type: "string", description: "Optional API path fragment to narrow logs." },
      { name: "filter", type: "string", description: "Optional error/message filter." },
      { name: "request_id", type: "string", description: "Optional request id for single-request triage." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.triage_prod_error",
        description: "Primary orchestrator: collect top errors + deploy + metrics signals.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          endpoint: params.endpoint,
          filter: params.filter,
          request_id: params.request_id
        }
      },
      {
        tool: "git.status",
        description: "Raw fallback: confirm local branch/worktree state for incident context.",
        arguments: {},
        fallback: true
      }
    ]
  },
  {
    templateId: "deploy-window-401-check",
    uriTemplate: "biddersweet://templates/deploy-window-401-check{?service,window_minutes,frontend_hint}",
    name: "Deploy Window 401 Check",
    description: "Classify 401 bursts as transient deploy-window noise vs regression.",
    whatThisDoes: "Runs 401-focused deploy correlation first, then checks env drift for auth/session config mismatch.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Render backend service name/id." },
      { name: "window_minutes", type: "number", defaultValue: 60, description: "Window for deploy/401 correlation." },
      { name: "frontend_hint", type: "string", description: "Optional frontend domain/path hint for filtering." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.verify_deploy_window_401",
        description: "Primary orchestrator: classify transient/regression/unknown 401 pattern.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          frontend_hint: params.frontend_hint
        }
      },
      {
        tool: "ops.env_diff",
        description: "Orchestrator follow-up: compare the service against itself/peer for auth env drift.",
        arguments: {
          service_a: params.service,
          service_b: params.service
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "env-drift-report",
    uriTemplate: "biddersweet://templates/env-drift-report{?service_a,service_b,show_values}",
    name: "Env Drift Report",
    description: "Generate a key drift report between two Render services.",
    whatThisDoes: "Compares environment keys (and optional redacted value metadata) to detect release risk before deploy.",
    mimeType: "application/json",
    parameters: [
      { name: "service_a", type: "string", required: true, description: "Baseline service name/id." },
      { name: "service_b", type: "string", required: true, description: "Comparison service name/id." },
      { name: "show_values", type: "boolean", defaultValue: false, description: "Include redacted value metadata." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.env_diff",
        description: "Primary orchestrator: key-level env drift report.",
        arguments: {
          service_a: params.service_a,
          service_b: params.service_b,
          show_values: params.show_values
        }
      },
      {
        tool: "repo.search",
        description: "Raw fallback: scan repo for suspicious auth/cors/cookie key usage.",
        arguments: {
          query: "SECRET_KEY_BASE|SESSION|COOKIE|CORS|CSRF",
          maxResults: 40
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "csp-image-loading-regression-check",
    uriTemplate:
      "biddersweet://templates/csp-image-loading-regression-check{?service,window_minutes,domain,image_path}",
    name: "CSP/Image Loading Regression Check",
    description: "Check likely CSP/image loading regressions using incident + code/config signals.",
    whatThisDoes:
      "Starts with production triage for CSP/image failures, then checks 401 deploy-window auth effects and security header config in repo.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Render backend service name/id." },
      { name: "window_minutes", type: "number", defaultValue: 60, description: "Inspection window in minutes." },
      { name: "domain", type: "string", description: "Frontend domain hint for auth/csp correlation." },
      { name: "image_path", type: "string", defaultValue: "/api/v1/uploads/", description: "Image/upload endpoint hint." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.triage_prod_error",
        description: "Primary orchestrator: detect CSP/image-related error signatures and correlation.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          endpoint: params.image_path,
          filter: "csp|content security|img|image|upload|active storage|forbidden"
        }
      },
      {
        tool: "ops.verify_deploy_window_401",
        description: "Orchestrator follow-up: rule out auth/session deploy-window regressions.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          frontend_hint: params.domain
        },
        fallback: true
      },
      {
        tool: "repo.search",
        description: "Raw fallback: inspect CSP/security header config and tests in codebase.",
        arguments: {
          query: "Content-Security-Policy|security_headers|img-src|frame-src|upload",
          maxResults: 60
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "route-contract-check",
    uriTemplate: "biddersweet://templates/route-contract-check{?max_allowed_drift}",
    name: "Route Contract Check",
    description: "Check Rails route vs OpenAPI path drift.",
    whatThisDoes: "Runs route-contract orchestrator first, then raw route inventory if drift needs deeper inspection.",
    mimeType: "application/json",
    parameters: [
      { name: "max_allowed_drift", type: "number", defaultValue: 25, description: "Allowed route/openapi drift threshold." }
    ],
    buildSteps: (params) => [
      {
        tool: "dev.route_contract_check",
        description: "Primary orchestrator: compare routes inventory against OpenAPI path inventory.",
        arguments: {
          maxAllowedDrift: params.max_allowed_drift
        }
      },
      {
        tool: "rails.routes",
        description: "Raw fallback: inspect static route inventory when drift exceeds threshold.",
        arguments: {
          mode: "static",
          maxResults: 500
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "fullstack-smoke",
    uriTemplate: "biddersweet://templates/fullstack-smoke{?service,include_integration}",
    name: "Fullstack Smoke",
    description: "Run orchestrated fullstack smoke checks with optional integration scope.",
    whatThisDoes: "Performs a fast orchestrated smoke first, then lints/tests via raw tools for deeper validation.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Target service/release label." },
      {
        name: "include_integration",
        type: "boolean",
        defaultValue: false,
        description: "Include integration-oriented smoke context."
      }
    ],
    buildSteps: (params) => [
      {
        tool: "dev.smoke_fullstack",
        description: "Primary orchestrator: run read-only smoke orchestration.",
        arguments: {
          serviceName: params.service,
          includeIntegration: params.include_integration
        }
      },
      {
        tool: "dev.run_lint",
        description: "Raw fallback: run allowlisted lint after smoke pass.",
        arguments: { target: "both" },
        fallback: true
      },
      {
        tool: "dev.run_tests",
        description: "Raw fallback: run allowlisted tests after smoke pass.",
        arguments: { target: "both" },
        fallback: true
      }
    ]
  },
  {
    templateId: "deploy-readiness-gate",
    uriTemplate:
      "biddersweet://templates/deploy-readiness-gate{?service,service_a,service_b,max_allowed_drift,include_integration}",
    name: "Deploy Readiness Gate",
    description: "Run orchestrated pre-deploy checks across contract, smoke, and env drift.",
    whatThisDoes: "Combines route contract, smoke, and env drift orchestrators into one repeatable release gate.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Primary service/release label." },
      { name: "service_a", type: "string", required: true, description: "Env baseline service." },
      { name: "service_b", type: "string", required: true, description: "Env comparison service." },
      { name: "max_allowed_drift", type: "number", defaultValue: 25, description: "Route/OpenAPI drift threshold." },
      {
        name: "include_integration",
        type: "boolean",
        defaultValue: false,
        description: "Enable integration smoke context."
      }
    ],
    buildSteps: (params) => [
      {
        tool: "dev.route_contract_check",
        description: "Orchestrator #1: route/openapi drift.",
        arguments: { maxAllowedDrift: params.max_allowed_drift }
      },
      {
        tool: "dev.smoke_fullstack",
        description: "Orchestrator #2: read-only fullstack smoke.",
        arguments: {
          serviceName: params.service,
          includeIntegration: params.include_integration
        }
      },
      {
        tool: "ops.env_diff",
        description: "Orchestrator #3: env drift guard before deploy.",
        arguments: {
          service_a: params.service_a,
          service_b: params.service_b
        }
      }
    ]
  },
  {
    templateId: "auth-session-regression-check",
    uriTemplate: "biddersweet://templates/auth-session-regression-check{?service,window_minutes,frontend_hint}",
    name: "Auth Session Regression Check",
    description: "Investigate auth/session regressions with deploy-window and env signals.",
    whatThisDoes:
      "Runs deploy-window 401 classification first, then triages auth failures and checks env drift for session/cookie keys.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Render backend service name/id." },
      { name: "window_minutes", type: "number", defaultValue: 45, description: "Auth regression check window." },
      { name: "frontend_hint", type: "string", description: "Frontend host/path hint." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.verify_deploy_window_401",
        description: "Primary orchestrator: classify auth-related 401 spikes near deploys.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          frontend_hint: params.frontend_hint
        }
      },
      {
        tool: "ops.triage_prod_error",
        description: "Orchestrator follow-up: capture auth error signatures + deploy correlation.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          filter: "401|unauthorized|csrf|session|cookie"
        },
        fallback: true
      },
      {
        tool: "repo.search",
        description: "Raw fallback: locate auth/session/cookie config hotspots in code.",
        arguments: {
          query: "session|cookie|csrf|SameSite|SECRET_KEY_BASE|origin",
          maxResults: 60
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "storefront-routing-drift-check",
    uriTemplate: "biddersweet://templates/storefront-routing-drift-check{?max_allowed_drift,storefront_key}",
    name: "Storefront Routing Drift Check",
    description: "Validate storefront routing compatibility against route/contracts context.",
    whatThisDoes: "Runs route-contract orchestrator first, then scans storefront routing markers in code.",
    mimeType: "application/json",
    parameters: [
      { name: "max_allowed_drift", type: "number", defaultValue: 25, description: "Allowed route/openapi drift threshold." },
      {
        name: "storefront_key",
        type: "string",
        defaultValue: "marketplace",
        description: "Storefront key to inspect in code references."
      }
    ],
    buildSteps: (params) => [
      {
        tool: "dev.route_contract_check",
        description: "Primary orchestrator: route/openapi consistency baseline.",
        arguments: { maxAllowedDrift: params.max_allowed_drift }
      },
      {
        tool: "repo.search",
        description: "Raw fallback: scan storefront key references and routing boundaries.",
        arguments: {
          query: String(params.storefront_key),
          maxResults: 50
        },
        fallback: true
      },
      {
        tool: "rails.routes",
        description: "Raw fallback: inspect route surface for storefront namespace drift.",
        arguments: {
          mode: "static",
          maxResults: 500
        },
        fallback: true
      }
    ]
  },
  {
    templateId: "incident-to-contract-followup",
    uriTemplate:
      "biddersweet://templates/incident-to-contract-followup{?service,window_minutes,endpoint,filter,max_allowed_drift}",
    name: "Incident To Contract Follow-up",
    description: "Turn a production incident into contract/smoke follow-up checks.",
    whatThisDoes:
      "Runs incident triage first, then validates route/openapi drift and smoke readiness to prevent repeat regressions.",
    mimeType: "application/json",
    parameters: [
      { name: "service", type: "string", required: true, description: "Render backend service name/id." },
      { name: "window_minutes", type: "number", defaultValue: 30, description: "Incident triage window." },
      { name: "endpoint", type: "string", description: "Optional incident endpoint path." },
      { name: "filter", type: "string", description: "Optional incident error filter." },
      { name: "max_allowed_drift", type: "number", defaultValue: 25, description: "Route/OpenAPI drift threshold." }
    ],
    buildSteps: (params) => [
      {
        tool: "ops.triage_prod_error",
        description: "Orchestrator #1: collect incident diagnostics.",
        arguments: {
          service: params.service,
          window_minutes: params.window_minutes,
          endpoint: params.endpoint,
          filter: params.filter
        }
      },
      {
        tool: "dev.route_contract_check",
        description: "Orchestrator #2: verify contract drift after incident.",
        arguments: {
          maxAllowedDrift: params.max_allowed_drift
        }
      },
      {
        tool: "dev.smoke_fullstack",
        description: "Orchestrator #3: smoke-check post-fix readiness.",
        arguments: {
          serviceName: params.service
        }
      }
    ]
  }
];

function parseTemplateUri(uri: string): { templateId: string; searchParams: URLSearchParams } | null {
  try {
    const parsed = new URL(uri);
    if (parsed.protocol !== "biddersweet:") return null;
    if (parsed.hostname !== "templates") return null;
    const templateId = parsed.pathname.replace(/^\/+/, "").trim();
    if (!templateId) return null;
    return { templateId, searchParams: parsed.searchParams };
  } catch {
    return null;
  }
}

function resolveTemplateParameters(
  parameters: McpTemplateParameter[],
  searchParams: URLSearchParams
): { values: Record<string, string | number | boolean>; missingRequired: string[] } {
  const values: Record<string, string | number | boolean> = {};
  const missingRequired: string[] = [];
  for (const parameter of parameters) {
    const raw = searchParams.get(parameter.name);
    if (raw === null || raw.length === 0) {
      if (parameter.defaultValue !== undefined) values[parameter.name] = parameter.defaultValue;
      else if (parameter.required) missingRequired.push(parameter.name);
      continue;
    }
    if (parameter.type === "number") {
      const parsedNumber = Number(raw);
      if (Number.isFinite(parsedNumber)) {
        values[parameter.name] = parsedNumber;
        continue;
      }
      if (parameter.defaultValue !== undefined) values[parameter.name] = parameter.defaultValue;
      else if (parameter.required) missingRequired.push(parameter.name);
      continue;
    }
    if (parameter.type === "boolean") {
      const normalized = raw.toLowerCase();
      values[parameter.name] = normalized === "1" || normalized === "true" || normalized === "yes" || normalized === "on";
      continue;
    }
    values[parameter.name] = raw;
  }
  return { values, missingRequired };
}

function compactTemplateArguments(input: Record<string, unknown>): Record<string, unknown> {
  const entries = Object.entries(input).filter(([, value]) => value !== undefined);
  return Object.fromEntries(entries);
}

function buildWorkflowTemplateResource(
  uri: string
):
  | {
      uri: string;
      mimeType: string;
      text: string;
    }
  | null {
  const parsed = parseTemplateUri(uri);
  if (!parsed) return null;

  const template = MCP_WORKFLOW_TEMPLATE_CATALOG.find((entry) => entry.templateId === parsed.templateId);
  if (!template) return null;

  const resolved = resolveTemplateParameters(template.parameters, parsed.searchParams);
  const steps = template
    .buildSteps(resolved.values)
    .map((step, index) => ({
      order: index + 1,
      tool: step.tool,
      description: step.description,
      fallback: Boolean(step.fallback),
      arguments: compactTemplateArguments(step.arguments)
    }));

  const payload = {
    template_id: template.templateId,
    name: template.name,
    what_this_does: template.whatThisDoes,
    uri_template: template.uriTemplate,
    required_parameters: template.parameters.filter((parameter) => parameter.required).map((parameter) => parameter.name),
    parameters: template.parameters.map((parameter) => ({
      name: parameter.name,
      type: parameter.type,
      required: Boolean(parameter.required),
      description: parameter.description,
      default: parameter.defaultValue
    })),
    provided_parameters: resolved.values,
    missing_required_parameters: resolved.missingRequired,
    runnable: resolved.missingRequired.length === 0,
    execution_policy: "orchestrator_first_then_raw_fallback",
    tool_sequence: steps
  };

  return {
    uri,
    mimeType: template.mimeType,
    text: JSON.stringify(payload, null, 2)
  };
}

const serverLogPath = path.join(repoRoot, AUDIT_LOG_DIR, SERVER_LOG_FILE);
const appendServerLog = (message: string) => {
  try {
    fsSync.mkdirSync(path.join(repoRoot, AUDIT_LOG_DIR), { recursive: true });
    fsSync.appendFileSync(serverLogPath, `${new Date().toISOString()} ${message}\n`);
  } catch {
    // best-effort logging
  }
};
process.on("uncaughtException", (err) => {
  appendServerLog(`uncaughtException: ${err?.stack || err}`);
});
process.on("unhandledRejection", (reason) => {
  appendServerLog(`unhandledRejection: ${String(reason)}`);
});
appendServerLog("server_start");

const server = new Server(
  {
    name: "biddersweet-mcp",
    version: "0.1.0"
  },
  {
    capabilities: {
      tools: {},
      resources: {}
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
  .refine(
    (value) => {
      const variants = [value.replace, value.insert, value.delete].filter(Boolean);
      return variants.length === 1;
    },
    { message: "exactly_one_operation_required" }
  );
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
  .refine(
    (value) => {
      const structured = [value.replace, value.insert, value.delete].filter(Boolean);
      if (value.diff) {
        return structured.length === 0;
      }
      return structured.length === 1;
    },
    { message: "diff_or_single_operation_required" }
  );
const DevCheckInputSchema = z.object({});
const DevRunTargetSchema = z.object({
  target: z.enum(["ruby", "js", "both"]).optional().default("both")
});
const DevRunInputSchema = z.object({
  name: z.string().min(1),
  args: z.array(z.string()).optional()
});
const DevBenchmarkInputSchema = z.object({
  name: z.string().min(1)
});
const DevExplainFailureInputSchema = z
  .object({
    stdout: z.string().optional(),
    stderr: z.string().optional(),
    runId: z.string().optional()
  })
  .refine(
    (value) => {
      if (value.runId && value.runId.trim().length > 0) return true;
      const hasStdout = typeof value.stdout === "string";
      const hasStderr = typeof value.stderr === "string";
      return hasStdout && hasStderr;
    },
    { message: "stdout_and_stderr_required_without_runId" }
  );
const RailsRoutesInputSchema = z.object({
  mode: z.enum(["static", "command"]).optional().default("static"),
  maxResults: z.number().int().positive().optional()
});
const RailsSchemaInputSchema = z.object({});
const RailsModelsInputSchema = z.object({});
const JsWorkspaceInputSchema = z.object({});
const GitStatusInputSchema = z.object({});
const GitDiffInputSchema = z.object({
  path: z.string().optional(),
  staged: z.boolean().optional().default(false)
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
type RepoTodoScanInput = z.infer<typeof RepoTodoScanInputSchema>;
type RepoFormatPatchInput = z.infer<typeof RepoFormatPatchInputSchema>;
type RepoProposePatchInput = z.infer<typeof RepoProposePatchInputSchema>;
type RepoApplyPatchInput = z.infer<typeof RepoApplyPatchInputSchema>;
type DevRunTargetInput = z.infer<typeof DevRunTargetSchema>;
type DevRunInput = z.infer<typeof DevRunInputSchema>;
type DevBenchmarkInput = z.infer<typeof DevBenchmarkInputSchema>;
type DevExplainFailureInput = z.infer<typeof DevExplainFailureInputSchema>;
type RailsRoutesInput = z.infer<typeof RailsRoutesInputSchema>;
type RailsSchemaInput = z.infer<typeof RailsSchemaInputSchema>;
type RailsModelsInput = z.infer<typeof RailsModelsInputSchema>;
type JsWorkspaceInput = z.infer<typeof JsWorkspaceInputSchema>;
type GitStatusInput = z.infer<typeof GitStatusInputSchema>;
type GitDiffInput = z.infer<typeof GitDiffInputSchema>;
type OpsTriageProdErrorInput = z.infer<typeof OpsTriageProdErrorInputSchema>;
type OpsVerifyDeployWindow401Input = z.infer<typeof OpsVerifyDeployWindow401InputSchema>;
type OpsEnvDiffInput = z.infer<typeof OpsEnvDiffInputSchema>;
type DevRouteContractCheckInput = z.infer<typeof DevRouteContractCheckInputSchema>;
type DevSmokeFullstackInput = z.infer<typeof DevSmokeFullstackInputSchema>;

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

type SmokeStageStatus = "passed" | "failed" | "skipped";

type SmokeStageOutput = {
  status: SmokeStageStatus;
  command: string;
  duration: number;
  top_failures: string[];
};

type SmokeFailureHint = {
  stage: "backend" | "frontend";
  file?: string;
  line?: number;
  message: string;
};

type SmokeStageRun = {
  output: SmokeStageOutput;
  failed: boolean;
  hints: SmokeFailureHint[];
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

type RepoTodoResult = {
  pattern: string;
  path: string;
  line: number;
  preview: string;
};

type ReadTextFileResult = { content: string } | { missing: true };

type RepoApplyPatchError = {
  code: string;
  message: string;
  details?: Record<string, unknown>;
};

type RepoApplyPatchResult = {
  path: string;
  applied: boolean;
  beforeSha256?: string;
  afterSha256?: string;
  diffApplied?: string;
  errors?: RepoApplyPatchError[];
  warnings?: string[];
};

type DevExplainError = {
  message: string;
  file?: string;
  line?: number;
  kind?: string;
};

type DevExplainStackFrame = {
  file: string;
  line: number;
  function?: string;
};

type RailsRouteEntry = {
  verb: string;
  path: string;
  controller: string;
  action: string;
  name?: string;
};
type RailsSchemaColumn = {
  name: string;
  type: string;
  null?: boolean;
  default?: string | number | boolean | null;
};
type RailsSchemaIndex = {
  columns: string[];
  unique?: boolean;
};
type RailsSchemaForeignKey = {
  from: string;
  to: string;
  column?: string;
};
type RailsSchemaTable = {
  name: string;
  columns: RailsSchemaColumn[];
  indexes: RailsSchemaIndex[];
  foreignKeys: RailsSchemaForeignKey[];
};
type RailsModelAssociation = {
  type: string;
  name: string;
};
type RailsModelValidation = {
  type: string;
  attributes: string[];
  options?: string[];
};
type RailsModelEntry = {
  name: string;
  path: string;
  associations?: RailsModelAssociation[];
  validations?: RailsModelValidation[];
};
type JsWorkspaceSummary = {
  packageManager: "npm" | "yarn" | "pnpm" | null;
  workspaces: { enabled: boolean; packages: string[] };
  tsconfig: { root?: string; references: string[]; paths?: Record<string, unknown> };
  vite: { configPath?: string; plugins?: string[]; aliases?: Record<string, string> };
  eslint: { configPath?: string; extends?: string[] };
  scripts: Record<string, string>;
  warnings: string[];
};
type GitStatusEntry = {
  path: string;
  status: "M" | "A" | "D" | "R" | "??";
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
        name: "dev.benchmark_smoke",
        description: "Run a short allowlisted benchmark for smoke performance checks.",
        inputSchema: {
          type: "object",
          properties: {
            name: { type: "string" }
          },
          required: ["name"],
          additionalProperties: false
        }
      },
      {
        name: "dev.explain_failure",
        description: "Explain stdout/stderr output with structured error extraction.",
        inputSchema: {
          type: "object",
          properties: {
            stdout: { type: "string" },
            stderr: { type: "string" },
            runId: { type: "string" }
          },
          additionalProperties: false
        }
      },
      {
        name: "rails.routes",
        description: "Return Rails routes from config/routes.rb or rails routes output.",
        inputSchema: {
          type: "object",
          properties: {
            mode: { type: "string", enum: ["static", "command"] },
            maxResults: { type: "number" }
          },
          additionalProperties: false
        }
      },
      {
        name: "rails.schema",
        description: "Summarize Rails database schema from db/schema.rb or db/structure.sql.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "rails.models",
        description: "Summarize Rails models with associations and validations.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "js.workspace",
        description: "Summarize JS/TS workspace configuration (package manager, tsconfig, Vite, ESLint).",
        inputSchema: emptyInputSchema()
      },
      {
        name: "git.status",
        description: "Read-only git status summary for the repo.",
        inputSchema: emptyInputSchema()
      },
      {
        name: "git.diff",
        description: "Read-only git diff output for the repo.",
        inputSchema: {
          type: "object",
          properties: {
            path: { type: "string" },
            staged: { type: "boolean" }
          },
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
      },
      {
        name: "ops.triage_prod_error",
        description: "Compose local diagnostics to triage a production error context.",
        inputSchema: {
          type: "object",
          properties: {
            service: { type: "string" },
            serviceName: { type: "string" },
            timeWindowMinutes: { type: "number" },
            window_minutes: { type: "number" },
            filter: { type: "string" },
            endpoint: { type: "string" },
            requestId: { type: "string" },
            request_id: { type: "string" }
          },
          additionalProperties: false
        }
      },
      {
        name: "ops.verify_deploy_window_401",
        description: "Verify likely deploy-window causes for 401s using local signals.",
        inputSchema: {
          type: "object",
          properties: {
            service: { type: "string" },
            serviceName: { type: "string" },
            timeWindowMinutes: { type: "number" },
            window_minutes: { type: "number" },
            frontend_hint: { type: "string" }
          },
          additionalProperties: false
        }
      },
      {
        name: "ops.env_diff",
        description: "Compare Render service environment keys and report drift (read-only).",
        inputSchema: {
          type: "object",
          properties: {
            service_a: { type: "string" },
            service_b: { type: "string" },
            show_values: { type: "boolean" },
            sourceEnv: { type: "string" },
            targetEnv: { type: "string" },
            includeSensitive: { type: "boolean" },
            destructiveIntent: { type: "boolean" },
            confirmToken: { type: "string" },
            confirmText: { type: "string" }
          },
          required: ["service_a", "service_b"],
          additionalProperties: false
        }
      },
      {
        name: "dev.route_contract_check",
        description: "Compare routes to OpenAPI path inventory for contract drift.",
        inputSchema: {
          type: "object",
          properties: {
            maxAllowedDrift: { type: "number" }
          },
          additionalProperties: false
        }
      },
      {
        name: "dev.smoke_fullstack",
        description: "Run a read-only fullstack smoke orchestration.",
        inputSchema: {
          type: "object",
          properties: {
            serviceName: { type: "string" }
          },
          additionalProperties: false
        }
      }
    ]
  };
});

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  appendServerLog("resources_list");
  return {
    resources: MCP_RESOURCE_CATALOG.map((entry) => ({
      uri: entry.uri,
      name: entry.name,
      description: entry.description,
      mimeType: entry.mimeType
    }))
  };
});

server.setRequestHandler(ListResourceTemplatesRequestSchema, async () => {
  appendServerLog("resources_templates_list");
  return {
    resourceTemplates: MCP_WORKFLOW_TEMPLATE_CATALOG.map((entry) => ({
      uriTemplate: entry.uriTemplate,
      name: entry.name,
      description: entry.description,
      mimeType: entry.mimeType
    }))
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;
  appendServerLog(`resource_read uri=${uri}`);

  const templateResource = buildWorkflowTemplateResource(uri);
  if (templateResource) {
    return { contents: [templateResource] };
  }

  const resource = MCP_RESOURCE_CATALOG.find((entry) => entry.uri === uri);
  if (!resource) {
    throw new Error(`Unknown resource URI: ${uri}`);
  }

  const resolved = resolveRepoPath(resource.relativePath);
  if (!resolved.ok) {
    throw new Error(`Resource path is outside repo root: ${resource.relativePath}`);
  }

  const stats = await fs.stat(resolved.resolved);
  if (!stats.isFile()) {
    throw new Error(`Resource path is not a file: ${resource.relativePath}`);
  }
  if (stats.size > MAX_FILE_SIZE_BYTES) {
    throw new Error(`Resource exceeds max size: ${resource.relativePath}`);
  }
  if (await isBinaryFile(resolved.resolved)) {
    throw new Error(`Resource is binary and cannot be read as text: ${resource.relativePath}`);
  }

  const text = normalizeLineEndings(await fs.readFile(resolved.resolved, "utf8"));
  return {
    contents: [
      {
        uri: resource.uri,
        mimeType: resource.mimeType,
        text
      }
    ]
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  const startTime = Date.now();
  let result: unknown;
  let isError = false;
  try {
    const capabilityError = enforceCapabilityMode(name);
    if (capabilityError) {
      result = capabilityError;
      isError = true;
    } else {
    switch (name) {
      case "repo.info": {
        const parsed = RepoInfoInputSchema.parse(args ?? {});
        result = await handleRepoInfo(parsed);
        isError = false;
        break;
      }
      case "repo.search": {
        const parsed = RepoSearchInputSchema.parse(args ?? {});
        result = await handleRepoSearch(parsed);
        isError = false;
        break;
      }
      case "repo.read_file": {
        const parsed = RepoReadFileInputSchema.parse(args ?? {});
        result = await handleRepoReadFile(parsed);
        isError = false;
        break;
      }
      case "repo.read_range": {
        const parsed = RepoReadRangeInputSchema.parse(args ?? {});
        result = await handleRepoReadRange(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "repo.list_dir": {
        const parsed = RepoListDirInputSchema.parse(args ?? {});
        result = await handleRepoListDir(parsed);
        isError = false;
        break;
      }
      case "repo.deps": {
        const parsed = RepoDepsInputSchema.parse(args ?? {});
        result = await handleRepoDeps(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "repo.symbols": {
        const parsed = RepoSymbolsInputSchema.parse(args ?? {});
        result = await handleRepoSymbols(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "repo.tree": {
        const parsed = RepoTreeInputSchema.parse(args ?? {});
        result = await handleRepoTree(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "repo.find_refs": {
        const parsed = RepoFindRefsInputSchema.parse(args ?? {});
        result = await handleRepoFindRefs(parsed);
        isError = false;
        break;
      }
      case "repo.todo_scan": {
        const parsed = RepoTodoScanInputSchema.parse(args ?? {});
        result = await handleRepoTodoScan(parsed);
        isError = false;
        break;
      }
      case "repo.format_patch": {
        const parsed = RepoFormatPatchInputSchema.parse(args ?? {});
        result = await handleRepoFormatPatch(parsed);
        isError = false;
        break;
      }
      case "repo.propose_patch": {
        const parsed = RepoProposePatchInputSchema.parse(args ?? {});
        result = await handleRepoProposePatch(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "repo.apply_patch": {
        const parsed = RepoApplyPatchInputSchema.parse(args ?? {});
        result = await handleRepoApplyPatch(parsed);
        isError = Boolean((result as { errors?: unknown[] }).errors?.length);
        break;
      }
      case "dev.check": {
        const parsed = DevCheckInputSchema.parse(args ?? {});
        result = await handleDevCheck(parsed);
        isError = false;
        break;
      }
      case "dev.run": {
        const parsed = DevRunInputSchema.parse(args ?? {});
        result = await handleDevRunAllowlisted(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "dev.benchmark_smoke": {
        const parsed = DevBenchmarkInputSchema.parse(args ?? {});
        result = await handleDevBenchmarkSmoke(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "dev.explain_failure": {
        const parsed = DevExplainFailureInputSchema.parse(args ?? {});
        result = await handleDevExplainFailure(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "rails.routes": {
        const parsed = RailsRoutesInputSchema.parse(args ?? {});
        result = await handleRailsRoutes(parsed);
        isError = false;
        break;
      }
      case "rails.schema": {
        const parsed = RailsSchemaInputSchema.parse(args ?? {});
        result = await handleRailsSchema(parsed);
        isError = false;
        break;
      }
      case "rails.models": {
        const parsed = RailsModelsInputSchema.parse(args ?? {});
        result = await handleRailsModels(parsed);
        isError = false;
        break;
      }
      case "js.workspace": {
        const parsed = JsWorkspaceInputSchema.parse(args ?? {});
        result = await handleJsWorkspace(parsed);
        isError = false;
        break;
      }
      case "git.status": {
        const parsed = GitStatusInputSchema.parse(args ?? {});
        result = await handleGitStatus(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "git.diff": {
        const parsed = GitDiffInputSchema.parse(args ?? {});
        result = await handleGitDiff(parsed);
        isError = Boolean((result as { error?: unknown }).error);
        break;
      }
      case "dev.run_tests": {
        const parsed = DevRunTargetSchema.parse(args ?? {});
        result = await handleDevRunTests(parsed);
        isError = false;
        break;
      }
      case "dev.run_lint": {
        const parsed = DevRunTargetSchema.parse(args ?? {});
        result = await handleDevRunLint(parsed);
        isError = false;
        break;
      }
      case "ops.triage_prod_error": {
        const parsed = OpsTriageProdErrorInputSchema.parse(args ?? {});
        result = await handleOpsTriageProdError(parsed);
        isError = false;
        break;
      }
      case "ops.verify_deploy_window_401": {
        const parsed = OpsVerifyDeployWindow401InputSchema.parse(args ?? {});
        result = await handleOpsVerifyDeployWindow401(parsed);
        isError = false;
        break;
      }
      case "ops.env_diff": {
        const parsed = OpsEnvDiffInputSchema.parse(args ?? {});
        result = await handleOpsEnvDiff(parsed);
        isError = false;
        break;
      }
      case "dev.route_contract_check": {
        const parsed = DevRouteContractCheckInputSchema.parse(args ?? {});
        result = await handleDevRouteContractCheck(parsed);
        isError = false;
        break;
      }
      case "dev.smoke_fullstack": {
        const parsed = DevSmokeFullstackInputSchema.parse(args ?? {});
        result = await handleDevSmokeFullstack(parsed);
        isError = false;
        break;
      }
      default:
        result = { error: "unknown_tool" };
        isError = true;
        break;
    }
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    result = { error: "invalid_request", message };
    isError = true;
  } finally {
    const durationMs = Date.now() - startTime;
    await writeAuditLog({
      timestamp: new Date().toISOString(),
      toolName: name,
      argsSummary: summarizeToolArgs(name, args),
      durationMs,
      resultSummary: summarizeToolResult(name, result, isError),
      error: isError ? summarizeAuditError(result) : undefined
    });
  }
  return jsonResult(result, isError);
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
    availableDevCommands.push("dev.run_tests", "dev.run_lint", "dev.smoke_fullstack");
  }
  if (DEV_RUN_ALLOWLIST.length > 0) {
    availableDevCommands.push("dev.run");
  }
  if (DEV_BENCHMARK_ALLOWLIST.length > 0) {
    availableDevCommands.push("dev.benchmark_smoke");
  }
  availableDevCommands.push("dev.explain_failure");
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

  if (isProtectedPath(resolved.relative)) {
    return {
      path: resolved.relative,
      refused: true,
      reason: "protected_path"
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

  if (isProtectedPath(resolved.relative)) {
    return toolError("protected_path", "path is protected", { path: resolved.relative });
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

  if (isProtectedPath(resolved.relative)) {
    return {
      path: resolved.relative,
      entries: [],
      truncated: false,
      error: "protected_path"
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
    .filter((entry: fsSync.Dirent) => !isProtectedPath(joinRelativePath(resolved.relative, entry.name)))
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

  const readTextFile = async (relPath: string): Promise<ReadTextFileResult> => {
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

  if (isProtectedPath(resolved.relative)) {
    return toolError("protected_path", "path is protected", { path: resolved.relative });
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

  const buildTree = async (fullPath: string, relPath: string, name: string, depth: number): Promise<RepoTreeNode> => {
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
      if (isProtectedPath(joinRelativePath(relPath, entry.name))) return false;
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
      const childRelPath = joinRelativePath(relPath, entry.name);
      if (entry.isDirectory()) {
        const child = await buildTree(childPath, childRelPath, entry.name, depth + 1);
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
    ? await buildTree(resolved.resolved, resolved.relative, rootName, 0)
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
    if (hits.length === 0 && !truncated) {
      if (isGitRepo) {
        const gitResults = await runFindRefsWithGitGrep(symbol, languageHint);
        strategy = "git_grep";
        hits = gitResults.hits;
        truncated = gitResults.truncated;
      }
      if (hits.length === 0 && !truncated) {
        const walkResults = await runFindRefsWithWalk(symbol, languageHint);
        strategy = "walk";
        hits = walkResults.hits;
        truncated = walkResults.truncated;
      }
    }
  } else if (isGitRepo) {
    const gitResults = await runFindRefsWithGitGrep(symbol, languageHint);
    strategy = "git_grep";
    hits = gitResults.hits;
    truncated = gitResults.truncated;
    if (hits.length === 0 && !truncated) {
      const walkResults = await runFindRefsWithWalk(symbol, languageHint);
      strategy = "walk";
      hits = walkResults.hits;
      truncated = walkResults.truncated;
    }
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

async function handleRepoTodoScan(input: RepoTodoScanInput) {
  const patterns = (input.patterns ?? DEFAULT_TODO_PATTERNS).filter((pattern) => pattern.trim().length > 0);
  const maxResults = Math.min(input.maxResults ?? DEFAULT_TODO_MAX, HARD_TODO_MAX);

  const rgAvailable = await isCommandAvailable("rg");
  let hits: RepoTodoResult[] = [];
  let truncated = false;

  if (rgAvailable) {
    const rgResults = await runTodoScanWithRg(patterns);
    hits = rgResults.results;
    truncated = rgResults.truncated;
  } else {
    const walkResults = await runTodoScanWithWalk(patterns, maxResults + 1);
    hits = walkResults.results;
    truncated = walkResults.truncated;
  }

  hits.sort((a, b) => {
    if (a.pattern !== b.pattern) return a.pattern.localeCompare(b.pattern);
    if (a.path !== b.path) return a.path.localeCompare(b.path);
    return a.line - b.line;
  });

  if (hits.length > maxResults) {
    truncated = true;
  }

  const limited = hits.slice(0, maxResults);
  const groupedCounts: Record<string, number> = {};
  for (const item of limited) {
    groupedCounts[item.pattern] = (groupedCounts[item.pattern] ?? 0) + 1;
  }

  return {
    results: limited,
    groupedCounts,
    truncated
  };
}

async function handleRepoFormatPatch(input: RepoFormatPatchInput) {
  const warnings: string[] = [];
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

  const normalizedSegments: string[] = [];
  const filesChanged: string[] = [];
  const seenFiles = new Set<string>();
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

    normalizedSegments.push(
      [
        `diff --git a/${pathValue} b/${pathValue}`,
        `--- a/${pathValue}`,
        `+++ b/${pathValue}`,
        ...hunkResult.lines
      ].join("\n")
    );
  }

  return formatPatchResult(
    true,
    normalizedSegments.join("\n"),
    filesChanged,
    insertions,
    deletions,
    warnings.length > 0 ? warnings : undefined
  );
}

function formatPatchResult(
  valid: boolean,
  normalizedDiff: string,
  filesChanged: string[],
  insertions: number,
  deletions: number,
  warnings?: string[]
) {
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

async function handleRepoProposePatch(input: RepoProposePatchInput) {
  const resolved = resolveRepoPath(input.path);
  if (!resolved.ok) {
    return toolError("path_outside_root", "path is outside repo root", {
      path: safeOutputPath(input.path)
    });
  }

  if (isProtectedPath(resolved.relative)) {
    return toolError("protected_path", "path is protected", { path: resolved.relative });
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

  let afterLines: string[] = [];
  let diff = "";
  let bytesChanged = 0;
  const warnings: string[] = [];

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
  } else if (input.delete) {
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
  } else if (input.replace) {
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
    diff = buildUnifiedDiffForReplace(
      resolved.relative,
      startLine,
      endLine,
      lines.slice(startLine - 1, endLine),
      newLines
    );
  } else {
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

async function handleRepoApplyPatch(input: RepoApplyPatchInput): Promise<RepoApplyPatchResult> {
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

  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
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

  const warnings: string[] = [];
  if (isLockfilePath(resolved.relative)) {
    warnings.push("lockfile_edit");
  }

  const content = normalizeLineEndings(await fs.readFile(resolved.resolved, "utf8"));
  const beforeSha256 = sha256(content);
  if (input.expectedSha256 !== beforeSha256) {
    return applyPatchError(
      resolved.relative,
      "sha_mismatch",
      "expectedSha256 does not match file content",
      {
        path: resolved.relative,
        expectedSha256: input.expectedSha256,
        actualSha256: beforeSha256
      },
      beforeSha256
    );
  }

  const lines = content.length === 0 ? [] : content.split("\n");
  let afterLines: string[] = [];
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
  } else {
    const structured = applyStructuredEdit(lines, resolved.relative, input);
    if (!structured.ok) {
      return applyPatchError(
        resolved.relative,
        structured.error.code,
        structured.error.message,
        structured.error.details,
        beforeSha256
      );
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
  } catch (error) {
    return applyPatchError(
      resolved.relative,
      "write_failed",
      "failed to write file",
      { path: resolved.relative, reason: error instanceof Error ? error.message : "unknown_error" },
      beforeSha256,
      afterSha256,
      diffApplied
    );
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

async function handleDevRunAllowlisted(input: DevRunInput) {
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

async function handleDevBenchmarkSmoke(input: DevBenchmarkInput) {
  const entry = DEV_BENCHMARK_ALLOWLIST.find((item) => item.name === input.name);
  if (!entry) {
    return toolError("benchmark_not_allowed", "benchmark is not allowlisted", { name: input.name });
  }

  const cmd = [...entry.command];
  const timeoutMs = entry.timeoutMs ?? BENCHMARK_TIMEOUT_MS;
  const maxOutputBytes = entry.maxOutputBytes ?? BENCHMARK_MAX_OUTPUT_BYTES;
  const { env } = buildAllowlistedEnv(entry.envAllowlist ?? []);

  const result = await runAllowlistedCommand(cmd, {
    timeoutMs,
    maxOutputBytes,
    env
  });

  return {
    name: entry.name,
    cmd,
    durationMs: result.durationMs,
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
    timedOut: result.timedOut,
    truncated: result.truncated
  };
}

async function handleDevExplainFailure(input: DevExplainFailureInput) {
  try {
    if (input.runId) {
      return toolError("run_history_unavailable", "runId lookup not implemented");
    }

    const stdout = input.stdout ?? "";
    const stderr = input.stderr ?? "";
    const combined = [stdout, stderr].filter(Boolean).join("\n");
    const parseResult = parseFailureOutput(combined);

    return {
      primaryError: parseResult.primaryError,
      errors: parseResult.errors,
      stackFrames: parseResult.stackFrames,
      summary: parseResult.summary,
      confidence: parseResult.confidence,
      warnings: parseResult.warnings.length > 0 ? parseResult.warnings : undefined
    };
  } catch (error) {
    return {
      primaryError: null,
      errors: [],
      stackFrames: [],
      summary: "Failed to parse output; returning best-effort defaults.",
      confidence: 0.1,
      warnings: ["explain_failure_internal_error"]
    };
  }
}

async function handleRailsRoutes(input: RailsRoutesInput) {
  const maxResults = Math.min(input.maxResults ?? DEFAULT_ROUTES_MAX, HARD_ROUTES_MAX);
  const warnings: string[] = [];

  if (!(await existsInRepo("config/routes.rb"))) {
    warnings.push("routes_file_missing");
  }

  if (input.mode === "command") {
    const commandResult = await runRailsRoutesCommand(maxResults);
    if (commandResult.ok) {
      return {
        modeUsed: "command",
        routes: commandResult.routes,
        warnings: commandResult.warnings,
        truncated: commandResult.truncated
      };
    }
    warnings.push(...commandResult.warnings);
    warnings.push("command_mode_failed_falling_back_to_static");
  }

  const staticResult = await parseRailsRoutesStatic(maxResults);
  warnings.push(...staticResult.warnings);

  return {
    modeUsed: "static",
    routes: staticResult.routes,
    warnings,
    truncated: staticResult.truncated
  };
}

async function handleRailsSchema(_input: RailsSchemaInput) {
  const warnings: string[] = [];
  const schemaPath = "db/schema.rb";
  const structurePath = "db/structure.sql";
  const hasSchema = await existsInRepo(schemaPath);
  const hasStructure = await existsInRepo(structurePath);

  if (hasSchema && hasStructure) {
    warnings.push("both_schema_and_structure_present_using_schema_rb");
  }

  if (!hasSchema && !hasStructure) {
    return {
      source: null,
      tables: [],
      warnings: ["schema_source_missing"]
    };
  }

  if (hasSchema) {
    const parsed = await parseRailsSchemaRb(schemaPath);
    return {
      source: schemaPath,
      tables: parsed.tables,
      warnings: [...warnings, ...parsed.warnings]
    };
  }

  const parsed = await parseRailsStructureSql(structurePath);
  return {
    source: structurePath,
    tables: parsed.tables,
    warnings: [...warnings, ...parsed.warnings]
  };
}

async function handleRailsModels(_input: RailsModelsInput) {
  const warnings: string[] = [];
  const modelsRoot = "app/models";
  if (!(await existsInRepo(modelsRoot))) {
    return { models: [], warnings: ["models_directory_missing"] };
  }

  const modelFiles = await listRubyFiles(modelsRoot);
  if (modelFiles.length === 0) {
    warnings.push("no_model_files_found");
  }

  const models: RailsModelEntry[] = [];
  for (const modelPath of modelFiles) {
    const contentResult = await readRepoTextFile(modelPath);
    if (!contentResult.ok) {
      warnings.push(`model_unreadable:${modelPath}:${contentResult.reason}`);
      continue;
    }
    const parsed = parseRailsModelFile(modelPath, contentResult.content);
    if (!parsed) {
      warnings.push(`model_parse_failed:${modelPath}`);
      continue;
    }
    models.push(parsed);
  }

  return {
    models,
    warnings
  };
}

async function handleJsWorkspace(_input: JsWorkspaceInput): Promise<JsWorkspaceSummary> {
  const warnings: string[] = [];

  const packageJsonResult = await readRepoJsonFile("package.json");
  if (!packageJsonResult.ok) {
    warnings.push(`package_json_unreadable:${packageJsonResult.reason}`);
  }

  const scripts: Record<string, string> = {};
  let workspaces: { enabled: boolean; packages: string[] } = { enabled: false, packages: [] };
  if (packageJsonResult.ok) {
    const pkg = packageJsonResult.data;
    if (pkg && typeof pkg === "object") {
      const rawScripts = (pkg as Record<string, unknown>).scripts;
      if (rawScripts && typeof rawScripts === "object") {
        for (const [key, value] of Object.entries(rawScripts as Record<string, unknown>)) {
          if (typeof value === "string") scripts[key] = value;
        }
      }

      const rawWorkspaces = (pkg as Record<string, unknown>).workspaces;
      if (Array.isArray(rawWorkspaces)) {
        workspaces = { enabled: true, packages: rawWorkspaces.filter((entry) => typeof entry === "string") };
      } else if (rawWorkspaces && typeof rawWorkspaces === "object") {
        const packages = Array.isArray((rawWorkspaces as Record<string, unknown>).packages)
          ? ((rawWorkspaces as Record<string, unknown>).packages as unknown[]).filter((entry) => typeof entry === "string")
          : [];
        workspaces = { enabled: packages.length > 0, packages };
      }
    }
  }

  const packageManagerDetected = await detectPackageManager();
  const packageManager =
    packageManagerDetected === "unknown" ? null : (packageManagerDetected as "npm" | "yarn" | "pnpm");

  const tsconfig = await summarizeTsconfig();
  warnings.push(...tsconfig.warnings);

  const vite = await summarizeViteConfig();
  warnings.push(...vite.warnings);

  const eslint = await summarizeEslintConfig();
  warnings.push(...eslint.warnings);

  if (!packageJsonResult.ok && scripts && Object.keys(scripts).length === 0) {
    warnings.push("scripts_unavailable_without_package_json");
  }

  return {
    packageManager,
    workspaces,
    tsconfig: tsconfig.summary,
    vite: vite.summary,
    eslint: eslint.summary,
    scripts,
    warnings
  };
}

async function handleGitStatus(_input: GitStatusInput) {
  const warnings: string[] = [];
  const isGitRepo = await detectGitRepo();
  if (!isGitRepo) {
    return toolError("not_git_repo", "not a git repository");
  }

  const result = await runCommandWithLimits(
    ["git", "-C", repoRoot, "status", "--porcelain=v1", "-b"],
    5_000,
    64 * 1024
  );

  if (result.exitCode !== 0) {
    return toolError("git_status_failed", "git status failed", { stderr: result.stderr });
  }

  if (result.truncated) warnings.push("status_output_truncated");

  const parsed = parseGitStatusPorcelain(result.stdout);
  warnings.push(...parsed.warnings);

  return {
    isGitRepo: true,
    branch: parsed.branch ?? undefined,
    changed: parsed.changed,
    warnings
  };
}

async function handleGitDiff(input: GitDiffInput) {
  const warnings: string[] = [];
  const isGitRepo = await detectGitRepo();
  if (!isGitRepo) {
    return toolError("not_git_repo", "not a git repository");
  }

  let relPath: string | null = null;
  if (input.path) {
    const resolved = resolveRepoPath(input.path);
    if (!resolved.ok) {
      return toolError("path_outside_root", "path is outside repo root", { path: safeOutputPath(input.path) });
    }
    relPath = resolved.relative;
  }

  const args = ["git", "-C", repoRoot, "diff", "--no-color", "--no-ext-diff"];
  if (input.staged) args.push("--cached");
  if (relPath) args.push("--", relPath);

  const result = await runCommandWithLimits(args, 5_000, MAX_GIT_DIFF_BYTES);
  if (result.exitCode !== 0) {
    return toolError("git_diff_failed", "git diff failed", { stderr: result.stderr });
  }

  if (result.truncated) warnings.push("diff_output_truncated");

  return {
    diff: result.stdout,
    truncated: result.truncated,
    warnings
  };
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

async function handleOpsTriageProdError(input: OpsTriageProdErrorInput) {
  return runOpsTriageProdError(input, {
    getGitSummary: getGitSummary,
    getDevToolsSummary: getDevToolsSummary,
    fileExists: existsInRepo,
    readTextFile: readTextFileForOrchestrator,
    listRenderServices: listRenderServicesForOrchestrator,
    listRenderLogs: listRenderLogsForOrchestrator,
    getRenderMetrics: getRenderMetricsForOrchestrator,
    listRenderDeploys: listRenderDeploysForOrchestrator,
    listRenderEnvVars: listRenderEnvVarsForOrchestrator
  });
}

async function handleOpsVerifyDeployWindow401(input: OpsVerifyDeployWindow401Input) {
  return runOpsVerifyDeployWindow401(input, {
    getGitSummary: getGitSummary,
    getDevToolsSummary: getDevToolsSummary,
    fileExists: existsInRepo,
    readTextFile: readTextFileForOrchestrator,
    listRenderServices: listRenderServicesForOrchestrator,
    listRenderLogs: listRenderLogsForOrchestrator,
    getRenderMetrics: getRenderMetricsForOrchestrator,
    listRenderDeploys: listRenderDeploysForOrchestrator,
    listRenderEnvVars: listRenderEnvVarsForOrchestrator
  });
}

async function handleOpsEnvDiff(input: OpsEnvDiffInput) {
  return runOpsEnvDiff(input, {
    getGitSummary: getGitSummary,
    getDevToolsSummary: getDevToolsSummary,
    fileExists: existsInRepo,
    readTextFile: readTextFileForOrchestrator,
    listRenderServices: listRenderServicesForOrchestrator,
    listRenderLogs: listRenderLogsForOrchestrator,
    getRenderMetrics: getRenderMetricsForOrchestrator,
    listRenderDeploys: listRenderDeploysForOrchestrator,
    listRenderEnvVars: listRenderEnvVarsForOrchestrator
  });
}

async function handleDevRouteContractCheck(input: DevRouteContractCheckInput) {
  return runDevRouteContractCheck(input, {
    getRoutesSummary: async () => {
      const routes = await handleRailsRoutes({ mode: "static" });
      const routeList =
        routes && typeof routes === "object" && Array.isArray((routes as { routes?: unknown[] }).routes)
          ? ((routes as { routes: unknown[] }).routes ?? [])
          : [];
      const truncated =
        Boolean(
          routes &&
            typeof routes === "object" &&
            "truncated" in (routes as Record<string, unknown>) &&
            (routes as { truncated?: boolean }).truncated
        ) || false;
      return { routeCount: routeList.length, truncated };
    },
    getOpenApiPathCount: async () => {
      const openApiText = await readTextFileForOrchestrator("docs/api/openapi.json");
      if (!openApiText) return 0;
      try {
        const parsed = JSON.parse(openApiText) as { paths?: Record<string, unknown> };
        return parsed.paths ? Object.keys(parsed.paths).length : 0;
      } catch {
        return 0;
      }
    },
    getDevToolsSummary: async () => ({ rgPresent: true, gitPresent: true, nodePresent: true }),
    runSmokeBenchmark: async () => ({ ok: true, durationMs: 0 })
  });
}

async function handleDevSmokeFullstack(input: DevSmokeFullstackInput) {
  const tools = await checkDevTools(["bundle", "npm", "yarn", "pnpm"]);
  const packageManager = await detectPackageManager();
  const packageScripts = await readPackageScripts();
  const backend = await runBackendSmokeStage(tools);

  let frontend: SmokeStageRun;
  if (backend.failed) {
    frontend = {
      output: {
        status: "skipped",
        command: formatSmokeCommand(["npm", "run", "lint"], ["npm", "run", "test:ci"]),
        duration: 0,
        top_failures: ["Skipped due to fail-fast after backend failure."]
      },
      failed: false,
      hints: []
    };
  } else {
    frontend = await runFrontendSmokeStage({ packageManager, tools, packageScripts });
  }

  return {
    backend: backend.output,
    frontend: frontend.output,
    next_actions: buildSmokeNextActions(backend, frontend, input.serviceName)
  };
}

async function runBackendSmokeStage(tools: Awaited<ReturnType<typeof checkDevTools>>): Promise<SmokeStageRun> {
  const command = await selectBackendSmokeCommand(tools);
  if (!command) {
    return {
      output: {
        status: "failed",
        command: DEV_SMOKE_BACKEND_COMMANDS.map((candidate) => candidate.join(" ")).join(" or "),
        duration: 0,
        top_failures: ["Backend smoke command unavailable (requires Gemfile + bundle/bin test command)."]
      },
      failed: true,
      hints: []
    };
  }

  const env = buildSmokeExecutionEnv();
  const result = await runAllowlistedCommand(command, {
    timeoutMs: DEV_SMOKE_TIMEOUT_MS,
    maxOutputBytes: DEV_SMOKE_MAX_OUTPUT_BYTES,
    env
  });
  const analysis = summarizeSmokeFailures("backend", result.stdout, result.stderr);

  return {
    output: {
      status: result.exitCode === 0 ? "passed" : "failed",
      command: command.join(" "),
      duration: result.durationMs,
      top_failures: result.exitCode === 0 ? [] : analysis.topFailures
    },
    failed: result.exitCode !== 0,
    hints: analysis.hints
  };
}

async function runFrontendSmokeStage(input: {
  packageManager: PackageManager;
  tools: Awaited<ReturnType<typeof checkDevTools>>;
  packageScripts: Record<string, string>;
}): Promise<SmokeStageRun> {
  const lintCommand = selectFrontendSmokeCommand(input.packageManager, input.tools, input.packageScripts, "lint");
  const testCommand = selectFrontendSmokeCommand(input.packageManager, input.tools, input.packageScripts, "test");
  const commandSummary = formatSmokeCommand(lintCommand, testCommand);

  if (!lintCommand || !testCommand) {
    const missing: string[] = [];
    if (!lintCommand) missing.push("lint command unavailable (expected lint/lint:ci script)");
    if (!testCommand) missing.push("test command unavailable (expected test:ci/ci:test/test script)");
    return {
      output: {
        status: "failed",
        command: commandSummary,
        duration: 0,
        top_failures: missing
      },
      failed: true,
      hints: []
    };
  }

  const lint = await runAllowlistedCommand(lintCommand, {
    timeoutMs: DEV_SMOKE_TIMEOUT_MS,
    maxOutputBytes: DEV_SMOKE_MAX_OUTPUT_BYTES,
    env: buildSmokeExecutionEnv()
  });
  if (lint.exitCode !== 0) {
    const lintAnalysis = summarizeSmokeFailures("frontend", lint.stdout, lint.stderr);
    return {
      output: {
        status: "failed",
        command: commandSummary,
        duration: lint.durationMs,
        top_failures: lintAnalysis.topFailures
      },
      failed: true,
      hints: lintAnalysis.hints
    };
  }

  const test = await runAllowlistedCommand(testCommand, {
    timeoutMs: DEV_SMOKE_TIMEOUT_MS,
    maxOutputBytes: DEV_SMOKE_MAX_OUTPUT_BYTES,
    env: buildSmokeExecutionEnv()
  });
  const testAnalysis = summarizeSmokeFailures("frontend", test.stdout, test.stderr);
  return {
    output: {
      status: test.exitCode === 0 ? "passed" : "failed",
      command: commandSummary,
      duration: lint.durationMs + test.durationMs,
      top_failures: test.exitCode === 0 ? [] : testAnalysis.topFailures
    },
    failed: test.exitCode !== 0,
    hints: testAnalysis.hints
  };
}

async function selectBackendSmokeCommand(
  tools: Awaited<ReturnType<typeof checkDevTools>>
): Promise<string[] | null> {
  if (!(await existsInRepo("Gemfile"))) return null;
  if (tools.bundle.present) return [...DEV_SMOKE_BACKEND_COMMANDS[0]];
  if (await existsInRepo("bin/test")) return [...DEV_SMOKE_BACKEND_COMMANDS[1]];
  return null;
}

async function readPackageScripts() {
  const parsed = await readRepoJsonFile("package.json");
  if (!parsed.ok || !parsed.data || typeof parsed.data !== "object") return {};
  const scriptsRaw = (parsed.data as Record<string, unknown>).scripts;
  if (!scriptsRaw || typeof scriptsRaw !== "object") return {};
  const scripts: Record<string, string> = {};
  for (const [key, value] of Object.entries(scriptsRaw as Record<string, unknown>)) {
    if (typeof value === "string") scripts[key] = value;
  }
  return scripts;
}

function selectFrontendSmokeCommand(
  packageManager: PackageManager,
  tools: Awaited<ReturnType<typeof checkDevTools>>,
  scripts: Record<string, string>,
  stage: "lint" | "test"
) {
  if (packageManager !== "npm") return null;
  if (!tools.npm.present) return null;

  const scriptCandidates = stage === "lint" ? DEV_SMOKE_FRONTEND_LINT_SCRIPTS : DEV_SMOKE_FRONTEND_TEST_SCRIPTS;
  const script = scriptCandidates.find((candidate) => typeof scripts[candidate] === "string");
  if (!script) return null;
  return ["npm", "run", script];
}

function formatSmokeCommand(lintCommand: string[] | null, testCommand: string[] | null) {
  const lint = lintCommand ? lintCommand.join(" ") : "npm run lint";
  const test = testCommand ? testCommand.join(" ") : "npm run test:ci";
  return `${lint} && ${test}`;
}

function buildSmokeExecutionEnv() {
  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value === "string") env[key] = value;
  }
  return env;
}

function summarizeSmokeFailures(stage: "backend" | "frontend", stdout: string, stderr: string) {
  const combined = [stdout, stderr].filter(Boolean).join("\n");
  const parsed = parseFailureOutput(combined);
  const hints: SmokeFailureHint[] = [];

  for (const error of parsed.errors.slice(0, 5)) {
    hints.push({
      stage,
      file: error.file,
      line: error.line,
      message: error.message
    });
  }

  if (hints.length === 0) {
    const fallback = extractFallbackFailureLines(combined);
    for (const message of fallback) {
      hints.push({ stage, message });
    }
  }

  return {
    topFailures: hints.slice(0, 5).map((hint) => formatSmokeFailureHint(hint)),
    hints
  };
}

function extractFallbackFailureLines(text: string) {
  const lines = normalizeLineEndings(text)
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const candidates = lines.filter((line) => /error|failed|failure|exception|fatal/i.test(line));
  const source = candidates.length > 0 ? candidates : lines;
  return source.slice(Math.max(0, source.length - 3), source.length);
}

function formatSmokeFailureHint(hint: SmokeFailureHint) {
  if (hint.file && hint.line) return `${hint.file}:${hint.line} ${hint.message}`;
  if (hint.file) return `${hint.file} ${hint.message}`;
  return hint.message;
}

function buildSmokeNextActions(
  backend: SmokeStageRun,
  frontend: SmokeStageRun,
  serviceName?: string
) {
  const actions: string[] = [];
  if (backend.failed) {
    actions.push("Fix backend smoke failures first, then rerun dev.smoke_fullstack.");
  } else if (frontend.failed) {
    actions.push("Backend passed; address frontend smoke failures and rerun dev.smoke_fullstack.");
  } else {
    actions.push("Smoke suite passed; proceed to full CI gates and deploy validation.");
  }

  const allHints = [...backend.hints, ...frontend.hints];
  const seen = new Set<string>();
  for (const hint of allHints) {
    if (!hint.file || !hint.line) continue;
    const key = `${hint.stage}:${hint.file}:${hint.line}`;
    if (seen.has(key)) continue;
    seen.add(key);
    actions.push(`Investigate ${hint.stage} failure at ${hint.file}:${hint.line}.`);
    if (actions.length >= 4) break;
  }

  if (serviceName && serviceName.trim().length > 0 && !backend.failed && !frontend.failed) {
    actions.push(`Run deploy readiness checks for ${serviceName.trim()} after CI is green.`);
  }
  return actions;
}

async function getGitSummary() {
  const status = await handleGitStatus({});
  if (!status || typeof status !== "object" || (status as { error?: unknown }).error) {
    return { isGitRepo: false, branch: null, changedCount: 0 };
  }
  const payload = status as { isGitRepo?: boolean; branch?: string; changed?: unknown[] };
  return {
    isGitRepo: Boolean(payload.isGitRepo),
    branch: payload.branch ?? null,
    changedCount: Array.isArray(payload.changed) ? payload.changed.length : 0
  };
}

async function getDevToolsSummary() {
  const check = await handleDevCheck({});
  const tools =
    check && typeof check === "object" && "tools" in (check as Record<string, unknown>)
      ? ((check as { tools?: Record<string, { present?: boolean }> }).tools ?? {})
      : {};
  return {
    rgPresent: Boolean(tools.rg?.present),
    gitPresent: Boolean(tools.git?.present)
  };
}

async function readTextFileForOrchestrator(relPath: string): Promise<string | null> {
  const resolved = resolveRepoPath(relPath);
  if (!resolved.ok) return null;
  if (isProtectedPath(resolved.relative)) return null;
  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return null;
  }
  if (!stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES) return null;
  if (await isBinaryFile(resolved.resolved)) return null;
  const content = await fs.readFile(resolved.resolved, "utf8");
  return normalizeLineEndings(content);
}

type RenderSnapshot = {
  services?: Array<{ id?: string; name?: string; url?: string | null; region?: string | null }>;
  envVarsByServiceId?: Record<
    string,
    Array<{
      key?: string;
      value?: string | null;
    }>
  >;
  logsByServiceId?: Record<
    string,
    Array<{
      timestamp?: string;
      message?: string;
      level?: string | null;
      type?: string | null;
      path?: string | null;
      statusCode?: string | number | null;
      requestId?: string | null;
    }>
  >;
  metricsByServiceId?: Record<
    string,
    Array<{
      metricType?: string;
      points?: Array<{ timestamp?: string; value?: number | null }>;
    }>
  >;
  deploysByServiceId?: Record<
    string,
    Array<{
      id?: string;
      status?: string | null;
      startedAt?: string | null;
      createdAt?: string | null;
      finishedAt?: string | null;
    }>
  >;
};

let renderSnapshotCache: Promise<RenderSnapshot | null> | null = null;

async function getRenderSnapshot(): Promise<RenderSnapshot | null> {
  if (renderSnapshotCache) return renderSnapshotCache;
  renderSnapshotCache = (async () => {
    const snapshotPath = process.env.BIDDERSWEET_RENDER_SNAPSHOT_PATH;
    if (!snapshotPath || snapshotPath.trim().length === 0) return null;
    const resolved = resolveRepoPath(snapshotPath);
    if (!resolved.ok) return null;
    if (isProtectedPath(resolved.relative)) return null;
    try {
      const content = await fs.readFile(resolved.resolved, "utf8");
      const parsed = JSON.parse(content);
      if (!parsed || typeof parsed !== "object") return null;
      return parsed as RenderSnapshot;
    } catch {
      return null;
    }
  })();
  return renderSnapshotCache;
}

async function listRenderServicesForOrchestrator() {
  const snapshot = await getRenderSnapshot();
  const services = snapshot?.services ?? [];
  return services
    .map((service) => ({
      id: typeof service.id === "string" ? service.id : "",
      name: typeof service.name === "string" ? service.name : "",
      url: typeof service.url === "string" ? service.url : null,
      region: typeof service.region === "string" ? service.region : null
    }))
    .filter((service) => service.id.length > 0 && service.name.length > 0);
}

async function listRenderLogsForOrchestrator(input: {
  serviceId: string;
  startTime: string;
  endTime: string;
  limit: number;
  filter?: string;
  endpoint?: string;
  requestId?: string;
}) {
  const snapshot = await getRenderSnapshot();
  const logs = snapshot?.logsByServiceId?.[input.serviceId] ?? [];
  const startMs = Date.parse(input.startTime);
  const endMs = Date.parse(input.endTime);
  const filtered = logs.filter((log) => {
    if (!log || typeof log !== "object") return false;
    const ts = typeof log.timestamp === "string" ? Date.parse(log.timestamp) : Number.NaN;
    if (Number.isFinite(startMs) && Number.isFinite(ts) && ts < startMs) return false;
    if (Number.isFinite(endMs) && Number.isFinite(ts) && ts > endMs) return false;
    const message = typeof log.message === "string" ? log.message : "";
    if (input.filter && !message.includes(input.filter)) return false;
    if (input.endpoint) {
      const pathValue = typeof log.path === "string" ? log.path : "";
      if (!pathValue.includes(input.endpoint) && !message.includes(input.endpoint)) return false;
    }
    if (input.requestId) {
      const requestId = typeof log.requestId === "string" ? log.requestId : "";
      if (!requestId.includes(input.requestId) && !message.includes(input.requestId)) return false;
    }
    return true;
  });

  return {
    logs: filtered.slice(0, Math.max(1, input.limit)).map((log) => ({
      timestamp: typeof log.timestamp === "string" ? log.timestamp : new Date().toISOString(),
      message: typeof log.message === "string" ? log.message : "",
      level: typeof log.level === "string" ? log.level : null,
      type: typeof log.type === "string" ? log.type : null,
      path: typeof log.path === "string" ? log.path : null,
      statusCode:
        typeof log.statusCode === "number" || typeof log.statusCode === "string" ? log.statusCode : null,
      requestId: typeof log.requestId === "string" ? log.requestId : null
    })),
    truncated: filtered.length > input.limit,
    hasMore: filtered.length > input.limit
  };
}

async function listRenderEnvVarsForOrchestrator(input: { serviceId: string }) {
  const snapshot = await getRenderSnapshot();
  const envVars = snapshot?.envVarsByServiceId?.[input.serviceId] ?? [];
  return envVars
    .map((item) => ({
      key: typeof item.key === "string" ? item.key : "",
      value: typeof item.value === "string" ? item.value : null
    }))
    .filter((item) => item.key.length > 0);
}

async function getRenderMetricsForOrchestrator(input: {
  resourceId: string;
  startTime: string;
  endTime: string;
}) {
  const snapshot = await getRenderSnapshot();
  const series = snapshot?.metricsByServiceId?.[input.resourceId] ?? [];
  const startMs = Date.parse(input.startTime);
  const endMs = Date.parse(input.endTime);

  return series
    .map((item) => ({
      metricType: typeof item.metricType === "string" ? item.metricType : "",
      points: Array.isArray(item.points)
        ? item.points
            .filter((point) => {
              const ts = typeof point.timestamp === "string" ? Date.parse(point.timestamp) : Number.NaN;
              if (Number.isFinite(startMs) && Number.isFinite(ts) && ts < startMs) return false;
              if (Number.isFinite(endMs) && Number.isFinite(ts) && ts > endMs) return false;
              return true;
            })
            .map((point) => ({
              timestamp: typeof point.timestamp === "string" ? point.timestamp : new Date().toISOString(),
              value: typeof point.value === "number" ? point.value : null
            }))
        : []
    }))
    .filter((item) => item.metricType.length > 0);
}

async function listRenderDeploysForOrchestrator(input: {
  serviceId: string;
  startTime: string;
  endTime: string;
  limit: number;
}) {
  const snapshot = await getRenderSnapshot();
  const deploys = snapshot?.deploysByServiceId?.[input.serviceId] ?? [];
  const startMs = Date.parse(input.startTime);
  const endMs = Date.parse(input.endTime);

  return deploys
    .filter((deploy) => {
      const startedAt = typeof deploy.startedAt === "string" ? deploy.startedAt : deploy.createdAt;
      if (!startedAt || typeof startedAt !== "string") return true;
      const ts = Date.parse(startedAt);
      if (Number.isFinite(startMs) && Number.isFinite(ts) && ts < startMs) return false;
      if (Number.isFinite(endMs) && Number.isFinite(ts) && ts > endMs) return false;
      return true;
    })
    .slice(0, Math.max(1, input.limit))
    .map((deploy) => ({
      id: typeof deploy.id === "string" ? deploy.id : "unknown",
      status: typeof deploy.status === "string" ? deploy.status : null,
      startedAt: typeof deploy.startedAt === "string" ? deploy.startedAt : null,
      createdAt: typeof deploy.createdAt === "string" ? deploy.createdAt : null,
      finishedAt: typeof deploy.finishedAt === "string" ? deploy.finishedAt : null
    }));
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

function validateDevRunArgs(entry: DevRunAllowlistEntry, args: string[]) {
  if (args.length === 0) return null;
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

function buildAllowlistedEnv(extraAllowlist: string[]) {
  const allowlist = new Set([...DEV_RUN_BASE_ENV_ALLOWLIST, ...extraAllowlist]);
  const env: Record<string, string> = {};
  const envUsed: string[] = [];

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

async function runAllowlistedCommand(
  command: string[],
  limits: { timeoutMs: number; maxOutputBytes: number; env: Record<string, string> }
): Promise<{ exitCode: number; stdout: string; stderr: string; timedOut: boolean; truncated: boolean; durationMs: number }> {
  return new Promise((resolve) => {
    const startTime = Date.now();
    const child = spawn(command[0], command.slice(1), {
      cwd: repoRoot,
      env: limits.env,
      shell: false
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let truncated = false;
    let timedOut = false;

    const onData = (chunk: Buffer, stream: "stdout" | "stderr") => {
      const remaining = limits.maxOutputBytes - (stdoutBytes + stderrBytes);
      if (remaining <= 0) {
        truncated = true;
        return;
      }
      const slice = chunk.length > remaining ? chunk.slice(0, remaining) : chunk;
      if (slice.length < chunk.length) truncated = true;
      if (stream === "stdout") {
        stdoutChunks.push(slice);
        stdoutBytes += slice.length;
      } else {
        stderrChunks.push(slice);
        stderrBytes += slice.length;
      }
    };

    child.stdout?.on("data", (chunk: Buffer) => onData(chunk, "stdout"));
    child.stderr?.on("data", (chunk: Buffer) => onData(chunk, "stderr"));

    let timeout: NodeJS.Timeout | undefined;
    if (limits.timeoutMs > 0) {
      timeout = setTimeout(() => {
        timedOut = true;
        truncated = true;
        child.kill("SIGKILL");
      }, limits.timeoutMs);
    }

    const finalize = (exitCode: number) => {
      if (timeout) clearTimeout(timeout);
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

    child.on("close", (code: number | null) => {
      finalize(typeof code === "number" ? code : -1);
    });

    child.on("error", () => {
      finalize(-1);
    });
  });
}

function parseFailureOutput(text: string) {
  const errors: DevExplainError[] = [];
  const stackFrames: DevExplainStackFrame[] = [];
  const warnings: string[] = [];
  const seen = new Set<string>();

  const lines = normalizeLineEndings(text).split("\n");

  const addError = (error: DevExplainError) => {
    const key = `${error.kind ?? ""}|${error.file ?? ""}|${error.line ?? ""}|${error.message}`;
    if (seen.has(key)) return;
    seen.add(key);
    errors.push(error);
  };

  const addStackFrame = (frame: DevExplainStackFrame) => {
    const key = `${frame.file}|${frame.line}|${frame.function ?? ""}`;
    if (seen.has(key)) return;
    seen.add(key);
    stackFrames.push(frame);
  };

  const tsError1 = /^(.*\.(?:ts|tsx|js|jsx))\((\d+),(\d+)\):\s*error\s*TS\d+:\s*(.*)$/;
  const tsError2 = /^(.*\.(?:ts|tsx|js|jsx)):(\d+):(\d+)\s*-\s*error\s*TS\d+:\s*(.*)$/;
  const eslintError = /^(.*):(\d+):(\d+)\s+error\s+(.*?)(?:\s+\(([^)]+)\))?$/;
  const rubocopError = /^(.*\.rb):(\d+):(\d+):\s*([A-Z]):\s*(.*)$/;
  const rubyStack = /^\s*(?:from\s+)?(.+\.rb):(\d+):in\s+`([^']+)'/;
  const jsStackFn = /^\s*at\s+([^(]+)\s+\((.*):(\d+):(\d+)\)/;
  const jsStackNoFn = /^\s*at\s+(.*):(\d+):(\d+)/;
  const jsErrorLine =
    /^\s*(Error|TypeError|ReferenceError|AssertionError|SyntaxError|RangeError|EvalError|URIError|AggregateError):\s*(.*)$/;

  for (const line of lines) {
    let match = line.match(tsError1) || line.match(tsError2);
    if (match) {
      addError({
        file: match[1],
        line: Number(match[2]),
        message: match[4].trim(),
        kind: "typescript"
      });
      continue;
    }

    match = line.match(eslintError);
    if (match) {
      addError({
        file: match[1],
        line: Number(match[2]),
        message: match[4].trim(),
        kind: "eslint"
      });
      continue;
    }

    match = line.match(rubocopError);
    if (match) {
      addError({
        file: match[1],
        line: Number(match[2]),
        message: match[5].trim(),
        kind: "rubocop"
      });
      continue;
    }

    match = line.match(jsErrorLine);
    if (match) {
      addError({
        message: match[2].trim(),
        kind: "js"
      });
      continue;
    }

    match = line.match(rubyStack);
    if (match) {
      addStackFrame({
        file: match[1],
        line: Number(match[2]),
        function: match[3]
      });
      continue;
    }

    match = line.match(jsStackFn);
    if (match) {
      addStackFrame({
        file: match[2],
        line: Number(match[3]),
        function: match[1].trim()
      });
      continue;
    }

    match = line.match(jsStackNoFn);
    if (match) {
      addStackFrame({
        file: match[1],
        line: Number(match[2])
      });
      continue;
    }
  }

  let primaryError: DevExplainError | null = errors[0] ?? null;
  if (!primaryError && stackFrames.length > 0) {
    primaryError = { message: "Stack trace detected", file: stackFrames[0].file, line: stackFrames[0].line };
  }

  if (!primaryError) {
    warnings.push("no_errors_detected");
  }

  let confidence = 0.2;
  if (errors.length > 0) confidence += 0.4;
  if (primaryError?.file && primaryError?.line) confidence += 0.2;
  if (stackFrames.length > 0) confidence += 0.1;
  confidence = Math.min(0.95, Math.max(0, confidence));

  const summary = primaryError
    ? `${primaryError.kind ?? "error"}: ${primaryError.message}`
    : "No errors detected in output.";

  return {
    primaryError,
    errors,
    stackFrames,
    summary,
    confidence,
    warnings
  };
}

async function runRailsRoutesCommand(maxResults: number) {
  const warnings: string[] = [];
  const { env } = buildAllowlistedEnv([
    "RAILS_ENV",
    "BUNDLE_GEMFILE",
    "BUNDLE_PATH",
    "BUNDLE_WITHOUT"
  ]);

  const result = await runAllowlistedCommand(
    ["bundle", "exec", "rails", "routes"],
    {
      timeoutMs: ROUTES_COMMAND_TIMEOUT_MS,
      maxOutputBytes: ROUTES_COMMAND_MAX_BYTES,
      env
    }
  );

  if (result.timedOut) {
    warnings.push("command_timed_out");
  }
  if (result.truncated) {
    warnings.push("command_output_truncated");
  }

  if (result.exitCode !== 0) {
    warnings.push("command_failed");
    return { ok: false as const, routes: [], warnings, truncated: false };
  }

  const parsed = parseRailsRoutesCommandOutput(result.stdout);
  if (parsed.routes.length === 0) {
    warnings.push("no_routes_parsed_from_command_output");
  }

  const { routes, truncated } = truncateRoutes(parsed.routes, maxResults);
  return {
    ok: true as const,
    routes,
    warnings: [...warnings, ...parsed.warnings],
    truncated
  };
}

function parseRailsRoutesCommandOutput(output: string) {
  const warnings: string[] = [];
  const routes: RailsRouteEntry[] = [];
  const lines = normalizeLineEndings(output).split("\n");

  const routeLine =
    /^(?:(\S+)\s+)?(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\s+(\S+)\s+(\S+)#(\S+)\s*$/;

  for (const line of lines) {
    if (!line.trim()) continue;
    if (line.startsWith("Prefix") || line.includes("Controller#Action")) continue;
    const match = line.match(routeLine);
    if (!match) continue;
    routes.push({
      name: match[1],
      verb: match[2],
      path: match[3],
      controller: match[4],
      action: match[5]
    });
  }

  if (routes.length === 0 && output.trim().length > 0) {
    warnings.push("command_output_unrecognized");
  }

  return { routes, warnings };
}

async function parseRailsRoutesStatic(maxResults: number) {
  const warnings: string[] = ["static_parsing_is_best_effort"];
  const routes: RailsRouteEntry[] = [];
  const resolved = resolveRepoPath("config/routes.rb");
  if (!resolved.ok) {
    warnings.push("routes_file_missing");
    return { routes, warnings, truncated: false };
  }

  let content = "";
  try {
    content = await fs.readFile(resolved.resolved, "utf8");
  } catch {
    warnings.push("routes_file_unreadable");
    return { routes, warnings, truncated: false };
  }

  const lines = normalizeLineEndings(content).split("\n");
  const scopeStack: Array<{ pathPrefix: string; modulePrefix: string }> = [];

  const currentPrefix = () => scopeStack.map((s) => s.pathPrefix).join("");
  const currentModule = () => scopeStack.map((s) => s.modulePrefix).join("");

  const addRoute = (entry: RailsRouteEntry) => {
    routes.push(entry);
  };

  for (const rawLine of lines) {
    const line = stripRubyComment(rawLine).trim();
    if (!line) continue;

    if (/^end\b/.test(line)) {
      scopeStack.pop();
      continue;
    }

    const namespaceMatch = line.match(/^namespace\s+:([a-zA-Z_]\w*)\s+do\b/);
    if (namespaceMatch) {
      const name = namespaceMatch[1];
      scopeStack.push({ pathPrefix: `/${name}`, modulePrefix: `${name}/` });
      continue;
    }

    const scopeMatch = line.match(/^scope\s+(.+?)\s+do\b/);
    if (scopeMatch) {
      const scopeArgs = scopeMatch[1];
      const path = extractOption(scopeArgs, "path") ?? extractScopePositional(scopeArgs);
      const mod = extractOption(scopeArgs, "module");
      const pathPrefix = path ? `/${stripQuotes(path)}` : "";
      const modulePrefix = mod ? `${stripQuotes(mod)}/` : "";
      scopeStack.push({ pathPrefix, modulePrefix });
      continue;
    }

    const rootMatch = line.match(/^root\s+(?:to:\s*)?["']([^"']+)#([^"']+)["']/);
    if (rootMatch) {
      addRoute({
        verb: "GET",
        path: joinRoutePath(currentPrefix(), "/"),
        controller: `${currentModule()}${rootMatch[1]}`,
        action: rootMatch[2]
      });
      continue;
    }

    const verbMatch = line.match(/^(get|post|put|patch|delete|match)\s+["']([^"']+)["'](.*)$/);
    if (verbMatch) {
      const verb = verbMatch[1].toUpperCase();
      const pathValue = verbMatch[2];
      const tail = verbMatch[3] ?? "";
      const toMatch =
        tail.match(/to:\s*["']([^"']+)#([^"']+)["']/) ||
        tail.match(/=>\s*["']([^"']+)#([^"']+)["']/);
      if (!toMatch) continue;
      const verbs = verb === "MATCH" ? extractViaVerbs(tail) : [verb];
      const name = extractOption(tail, "as");
      for (const verbValue of verbs) {
        addRoute({
          verb: verbValue,
          path: joinRoutePath(currentPrefix(), pathValue),
          controller: `${currentModule()}${toMatch[1]}`,
          action: toMatch[2],
          name: name ? stripQuotes(name) : undefined
        });
      }
      continue;
    }

    const resourcesMatch = line.match(/^(resources|resource)\s+:([a-zA-Z_]\w*)(.*)$/);
    if (resourcesMatch) {
      const kind = resourcesMatch[1];
      const resourceName = resourcesMatch[2];
      const tail = resourcesMatch[3] ?? "";
      const options = parseResourceOptions(tail);
      const controller = options.controller ?? resourceName;
      const pathSegment = options.path ?? resourceName;
      const only = options.only;
      const except = options.except;
      const isSingular = kind === "resource";

      const entries = buildResourceRoutes({
        resourceName: pathSegment,
        controller: `${currentModule()}${controller}`,
        prefix: currentPrefix(),
        singular: isSingular
      }).filter((entry) => {
        if (only && !only.includes(entry.action)) return false;
        if (except && except.includes(entry.action)) return false;
        return true;
      });

      for (const entry of entries) addRoute(entry);
      continue;
    }
  }

  const { routes: sliced, truncated } = truncateRoutes(routes, maxResults);
  return { routes: sliced, warnings, truncated };
}

function stripRubyComment(line: string) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char === "\"" && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (char === "#" && !inSingle && !inDouble) {
      return line.slice(0, i);
    }
  }
  return line;
}

function extractOption(input: string, key: string) {
  const regex = new RegExp(`${key}:\\s*([^,]+)`);
  const match = input.match(regex);
  if (!match) return null;
  return match[1].trim();
}

function extractScopePositional(input: string) {
  const match = input.match(/["']([^"']+)["']/);
  if (match) return match[1];
  const symbolMatch = input.match(/:([a-zA-Z_]\w*)/);
  return symbolMatch ? symbolMatch[1] : null;
}

function stripQuotes(value: string) {
  return value.replace(/^["']|["']$/g, "");
}

function parseResourceOptions(tail: string) {
  const onlyRaw = extractOption(tail, "only");
  const exceptRaw = extractOption(tail, "except");
  const controllerRaw = extractOption(tail, "controller");
  const pathRaw = extractOption(tail, "path");

  return {
    only: onlyRaw ? normalizeActionList(onlyRaw) : null,
    except: exceptRaw ? normalizeActionList(exceptRaw) : null,
    controller: controllerRaw ? stripQuotes(controllerRaw) : null,
    path: pathRaw ? stripQuotes(pathRaw) : null
  };
}

function normalizeActionList(value: string) {
  const trimmed = value.trim();
  if (trimmed.startsWith(":")) {
    return [trimmed.replace(/^:/, "")];
  }
  const listMatch = trimmed.match(/^\[(.*)\]$/);
  if (!listMatch) return null;
  return listMatch[1]
    .split(",")
    .map((entry) => entry.trim().replace(/^:/, "").replace(/^["']|["']$/g, ""))
    .filter(Boolean);
}

function extractViaVerbs(tail: string) {
  const via = extractOption(tail, "via");
  if (!via) return ["GET"];
  const normalized = via.trim();
  if (normalized === ":all" || normalized === "all") {
    return ["GET", "POST", "PUT", "PATCH", "DELETE"];
  }
  if (normalized.startsWith("[")) {
    return normalized
      .replace(/[\[\]]/g, "")
      .split(",")
      .map((entry) => entry.trim().replace(/^:/, "").toUpperCase())
      .filter(Boolean);
  }
  return [normalized.replace(/^:/, "").toUpperCase()];
}

function buildResourceRoutes(input: {
  resourceName: string;
  controller: string;
  prefix: string;
  singular: boolean;
}): RailsRouteEntry[] {
  const basePath = input.singular
    ? joinRoutePath(input.prefix, input.resourceName)
    : joinRoutePath(input.prefix, input.resourceName);
  const routes: RailsRouteEntry[] = [];

  if (!input.singular) {
    routes.push({ verb: "GET", path: basePath, controller: input.controller, action: "index" });
    routes.push({ verb: "POST", path: basePath, controller: input.controller, action: "create" });
    routes.push({ verb: "GET", path: `${basePath}/new`, controller: input.controller, action: "new" });
    routes.push({
      verb: "GET",
      path: `${basePath}/:id`,
      controller: input.controller,
      action: "show"
    });
    routes.push({
      verb: "GET",
      path: `${basePath}/:id/edit`,
      controller: input.controller,
      action: "edit"
    });
    routes.push({
      verb: "PATCH",
      path: `${basePath}/:id`,
      controller: input.controller,
      action: "update"
    });
    routes.push({
      verb: "PUT",
      path: `${basePath}/:id`,
      controller: input.controller,
      action: "update"
    });
    routes.push({
      verb: "DELETE",
      path: `${basePath}/:id`,
      controller: input.controller,
      action: "destroy"
    });
    return routes;
  }

  routes.push({ verb: "GET", path: basePath, controller: input.controller, action: "show" });
  routes.push({ verb: "POST", path: basePath, controller: input.controller, action: "create" });
  routes.push({ verb: "GET", path: `${basePath}/new`, controller: input.controller, action: "new" });
  routes.push({ verb: "GET", path: `${basePath}/edit`, controller: input.controller, action: "edit" });
  routes.push({ verb: "PATCH", path: basePath, controller: input.controller, action: "update" });
  routes.push({ verb: "PUT", path: basePath, controller: input.controller, action: "update" });
  routes.push({ verb: "DELETE", path: basePath, controller: input.controller, action: "destroy" });
  return routes;
}

function joinRoutePath(prefix: string, pathValue: string) {
  const cleanPrefix = prefix === "/" ? "" : prefix;
  const cleanPath = pathValue === "/" ? "" : pathValue;
  const joined = `${cleanPrefix}/${cleanPath}`.replace(/\/+/g, "/");
  return joined === "" ? "/" : joined;
}

function truncateRoutes(routes: RailsRouteEntry[], maxResults: number) {
  if (routes.length <= maxResults) {
    return { routes, truncated: false };
  }
  return { routes: routes.slice(0, maxResults), truncated: true };
}

async function parseRailsSchemaRb(relPath: string) {
  const warnings: string[] = ["schema_parsing_is_best_effort"];
  const contentResult = await readRepoTextFile(relPath);
  if (!contentResult.ok) {
    return { tables: [], warnings: [...warnings, `schema_unreadable:${contentResult.reason}`] };
  }

  const lines = normalizeLineEndings(contentResult.content).split("\n");
  const tables = new Map<string, RailsSchemaTable>();
  let currentTable: RailsSchemaTable | null = null;

  const getTable = (name: string) => {
    const existing = tables.get(name);
    if (existing) return existing;
    const created: RailsSchemaTable = { name, columns: [], indexes: [], foreignKeys: [] };
    tables.set(name, created);
    return created;
  };

  for (const rawLine of lines) {
    const line = stripRubyComment(rawLine).trim();
    if (!line) continue;

    const createMatch = line.match(/^create_table\s+"([^"]+)".*do\s+\|t\|/);
    if (createMatch) {
      currentTable = getTable(createMatch[1]);
      continue;
    }

    if (currentTable && line === "end") {
      currentTable = null;
      continue;
    }

    if (currentTable) {
      if (line.startsWith("t.index")) {
        const columns = parseRubyIndexColumns(line);
        if (columns.length > 0) {
          const unique = parseRubyBooleanOption(line, "unique");
          const index: RailsSchemaIndex = { columns };
          if (typeof unique === "boolean") index.unique = unique;
          currentTable.indexes.push(index);
        }
        continue;
      }

      const columnMatch = line.match(/^t\.(\w+)\s+"([^"]+)"(.*)$/);
      if (columnMatch) {
        const type = columnMatch[1];
        const name = columnMatch[2];
        const options = columnMatch[3] ?? "";
        const column: RailsSchemaColumn = { name, type };
        const nullValue = parseRubyBooleanOption(options, "null");
        if (typeof nullValue === "boolean") {
          column.null = nullValue;
        }
        const defaultRaw = extractRubyOption(options, "default");
        if (defaultRaw !== null) {
          column.default = parseRubyLiteral(defaultRaw);
        }
        currentTable.columns.push(column);
      }
      continue;
    }

    const addIndexMatch = line.match(/^add_index\s+"([^"]+)"\s*,\s*(\[[^\]]+\]|"[^"]+"|'[^']+')/);
    if (addIndexMatch) {
      const table = getTable(addIndexMatch[1]);
      const columns = parseRubyColumnsLiteral(addIndexMatch[2]);
      if (columns.length > 0) {
        const unique = parseRubyBooleanOption(line, "unique");
        const index: RailsSchemaIndex = { columns };
        if (typeof unique === "boolean") index.unique = unique;
        table.indexes.push(index);
      }
      continue;
    }

    const foreignKeyMatch = line.match(/^add_foreign_key\s+"([^"]+)"\s*,\s*"([^"]+)"(.*)$/);
    if (foreignKeyMatch) {
      const from = foreignKeyMatch[1];
      const to = foreignKeyMatch[2];
      const options = foreignKeyMatch[3] ?? "";
      const table = getTable(from);
      const columnRaw = extractRubyOption(options, "column");
      table.foreignKeys.push({
        from,
        to,
        column: columnRaw ? stripQuotes(columnRaw) : undefined
      });
    }
  }

  return {
    tables: Array.from(tables.values()),
    warnings
  };
}

async function parseRailsStructureSql(relPath: string) {
  const warnings: string[] = ["schema_parsing_is_best_effort"];
  const contentResult = await readRepoTextFile(relPath);
  if (!contentResult.ok) {
    return { tables: [], warnings: [...warnings, `schema_unreadable:${contentResult.reason}`] };
  }

  const lines = normalizeLineEndings(contentResult.content).split("\n");
  const tables = new Map<string, RailsSchemaTable>();

  const getTable = (name: string) => {
    const existing = tables.get(name);
    if (existing) return existing;
    const created: RailsSchemaTable = { name, columns: [], indexes: [], foreignKeys: [] };
    tables.set(name, created);
    return created;
  };

  let currentTable: RailsSchemaTable | null = null;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    const createMatch = line.match(/^CREATE TABLE\s+"?([^"\s]+)"?\s*\(/i);
    if (createMatch) {
      currentTable = getTable(createMatch[1]);
      continue;
    }

    if (currentTable) {
      if (line.startsWith(");") || line === ")") {
        currentTable = null;
        continue;
      }

      if (/^(CONSTRAINT|PRIMARY KEY|UNIQUE|CHECK)/i.test(line)) {
        continue;
      }

      const columnMatch = line.match(/^\s*"([^"]+)"\s+(.+?)(?:,)?$/);
      if (columnMatch) {
        const name = columnMatch[1];
        const rest = columnMatch[2];
        const column = parseSqlColumnDefinition(name, rest);
        currentTable.columns.push(column);
      }
      continue;
    }

    const indexMatch = line.match(
      /^CREATE\s+(UNIQUE\s+)?INDEX\s+.+?\s+ON\s+(?:ONLY\s+)?"?([^"\s]+)"?(?:\s+USING\s+\w+)?\s*\((.+)\)/i
    );
    if (indexMatch) {
      const unique = Boolean(indexMatch[1]);
      const tableName = indexMatch[2];
      const columns = parseSqlColumnList(indexMatch[3]);
      if (columns.length > 0) {
        getTable(tableName).indexes.push({ columns, unique });
      }
      continue;
    }

    const fkMatch = line.match(
      /^ALTER TABLE\s+(?:ONLY\s+)?"?([^"\s]+)"?.+FOREIGN KEY\s*\(([^)]+)\)\s+REFERENCES\s+"?([^"\s]+)"?(?:\s*\(([^)]+)\))?/i
    );
    if (fkMatch) {
      const from = fkMatch[1];
      const columns = parseSqlColumnList(fkMatch[2]);
      const to = fkMatch[3];
      getTable(from).foreignKeys.push({
        from,
        to,
        column: columns.length === 1 ? columns[0] : columns.length > 1 ? columns.join(",") : undefined
      });
    }
  }

  return {
    tables: Array.from(tables.values()),
    warnings
  };
}

async function readRepoTextFile(relPath: string): Promise<
  | { ok: true; content: string }
  | {
      ok: false;
      reason: "not_found" | "protected_path" | "not_a_file" | "file_too_large" | "binary_file" | "unreadable";
    }
> {
  const resolved = resolveRepoPath(relPath);
  if (!resolved.ok) {
    return { ok: false, reason: "not_found" };
  }
  if (isProtectedPath(resolved.relative)) {
    return { ok: false, reason: "protected_path" };
  }
  let stat: fsSync.Stats;
  try {
    stat = await fs.stat(resolved.resolved);
  } catch {
    return { ok: false, reason: "not_found" };
  }
  if (!stat.isFile()) {
    return { ok: false, reason: "not_a_file" };
  }
  if (stat.size > MAX_FILE_SIZE_BYTES) {
    return { ok: false, reason: "file_too_large" };
  }
  const binary = await isBinaryFile(resolved.resolved);
  if (binary) {
    return { ok: false, reason: "binary_file" };
  }
  try {
    const content = await fs.readFile(resolved.resolved, "utf8");
    return { ok: true, content };
  } catch {
    return { ok: false, reason: "unreadable" };
  }
}

function parseRubyIndexColumns(line: string) {
  const match = line.match(/t\.index\s+(\[[^\]]+\]|"[^"]+"|'[^']+')/);
  if (!match) return [];
  return parseRubyColumnsLiteral(match[1]);
}

function parseRubyColumnsLiteral(raw: string) {
  const trimmed = raw.trim();
  const matches = Array.from(trimmed.matchAll(/"([^"]+)"|'([^']+)'|:([a-zA-Z_]\w*)/g));
  const values = matches.map((match) => match[1] ?? match[2] ?? match[3]).filter(Boolean);
  if (values.length > 0) return values;
  const singleMatch = trimmed.match(/^["']([^"']+)["']$/) ?? trimmed.match(/^:([a-zA-Z_]\w*)/);
  return singleMatch ? [singleMatch[1]] : [];
}

function parseRubyBooleanOption(input: string, key: string) {
  const raw = extractRubyOption(input, key);
  if (!raw) return null;
  if (raw === "true") return true;
  if (raw === "false") return false;
  return null;
}

function extractRubyOption(input: string, key: string) {
  const regex = new RegExp(`${key}:\\s*([^,]+)`);
  const match = input.match(regex);
  if (!match) return null;
  return match[1].trim();
}

function parseRubyLiteral(raw: string): string | number | boolean | null {
  const trimmed = raw.trim();
  if (trimmed === "nil") return null;
  if (trimmed === "true") return true;
  if (trimmed === "false") return false;
  if (trimmed.startsWith("->")) return trimmed;
  if (/^["']/.test(trimmed)) return stripQuotes(trimmed);
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}

function parseSqlColumnDefinition(name: string, rest: string): RailsSchemaColumn {
  const constraintIndex = findConstraintIndex(rest);
  const typePart = (constraintIndex === -1 ? rest : rest.slice(0, constraintIndex)).trim();
  const constraintPart = constraintIndex === -1 ? "" : rest.slice(constraintIndex);

  const column: RailsSchemaColumn = { name, type: normalizeWhitespace(typePart) || "unknown" };
  if (/NOT NULL/i.test(constraintPart)) {
    column.null = false;
  } else if (/\bNULL\b/i.test(constraintPart)) {
    column.null = true;
  }

  const defaultMatch = constraintPart.match(
    /DEFAULT\s+([^,]+?)(?=\s+(?:NOT\s+NULL|NULL|CONSTRAINT|PRIMARY|UNIQUE|CHECK|REFERENCES)|,|$)/i
  );
  if (defaultMatch) {
    column.default = defaultMatch[1].trim();
  }

  return column;
}

function findConstraintIndex(value: string) {
  const keywords = [
    "DEFAULT",
    "NOT NULL",
    "NULL",
    "CONSTRAINT",
    "PRIMARY KEY",
    "UNIQUE",
    "CHECK",
    "REFERENCES"
  ];
  const upper = value.toUpperCase();
  let index = -1;
  for (const keyword of keywords) {
    const pos = upper.indexOf(keyword);
    if (pos === -1) continue;
    if (index === -1 || pos < index) index = pos;
  }
  return index;
}

function normalizeWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function parseSqlColumnList(raw: string) {
  return raw
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => part.replace(/^"|"$/g, ""));
}

async function listRubyFiles(relDir: string) {
  const resolved = resolveRepoPath(relDir);
  if (!resolved.ok) return [];
  const files: string[] = [];

  async function walk(current: string) {
    let entries: fsSync.Dirent[];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (SKIP_DIR_NAMES.has(entry.name)) continue;
        await walk(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".rb")) {
        const relPath = normalizeRelativePath(path.relative(repoRoot, fullPath));
        files.push(relPath);
      }
    }
  }

  await walk(resolved.resolved);
  return files.sort();
}

function parseRailsModelFile(modelPath: string, content: string): RailsModelEntry | null {
  const normalized = normalizeLineEndings(content);
  const classMatch = normalized.match(/^\s*class\s+([A-Za-z0-9_:]+)(?:\s*<\s*[A-Za-z0-9_:]+)?/m);
  if (!classMatch) return null;

  const associations: RailsModelAssociation[] = [];
  const validations: RailsModelValidation[] = [];

  for (const rawLine of normalized.split("\n")) {
    const line = stripRubyComment(rawLine).trim();
    if (!line) continue;

    const assocMatch = line.match(/\b(belongs_to|has_many|has_one|has_and_belongs_to_many)\s+:([a-zA-Z_]\w*)/);
    if (assocMatch) {
      associations.push({ type: assocMatch[1], name: assocMatch[2] });
      continue;
    }

    const validatesMatch = line.match(/\b(validates)\s+(.+)/);
    if (validatesMatch) {
      const args = validatesMatch[2];
      const parsed = parseRailsValidatesArgs(args);
      if (parsed.attributes.length > 0) {
        validations.push(parsed);
      }
      continue;
    }

    const validatesOfMatch = line.match(/\b(validates_[a-z_]+_of)\s+(.+)/);
    if (validatesOfMatch) {
      const type = validatesOfMatch[1];
      const args = validatesOfMatch[2];
      const attrs = extractSymbols(args);
      if (attrs.length > 0) {
        validations.push({ type, attributes: attrs });
      }
    }
  }

  const entry: RailsModelEntry = { name: classMatch[1], path: modelPath };
  if (associations.length > 0) entry.associations = associations;
  if (validations.length > 0) entry.validations = validations;
  return entry;
}

function parseRailsValidatesArgs(args: string): RailsModelValidation {
  const optionsStart = args.search(/\b[a-zA-Z_]\w*\s*:/);
  const attrPart = optionsStart === -1 ? args : args.slice(0, optionsStart);
  const optionsPart = optionsStart === -1 ? "" : args.slice(optionsStart);
  const attributes = extractSymbols(attrPart);
  const options = Array.from(optionsPart.matchAll(/\b([a-zA-Z_]\w*)\s*:/g)).map((match) => match[1]);

  return {
    type: "validates",
    attributes,
    options: options.length > 0 ? options : undefined
  };
}

function extractSymbols(value: string) {
  return Array.from(value.matchAll(/:([a-zA-Z_]\w*)/g)).map((match) => match[1]);
}

async function readRepoJsonFile(relPath: string): Promise<
  | { ok: true; data: unknown }
  | {
      ok: false;
      reason:
        | "not_found"
        | "protected_path"
        | "not_a_file"
        | "file_too_large"
        | "binary_file"
        | "unreadable"
        | "invalid_json";
    }
> {
  const contentResult = await readRepoTextFile(relPath);
  if (!contentResult.ok) return { ok: false, reason: contentResult.reason };
  try {
    const parsed = JSON.parse(stripJsonComments(contentResult.content));
    return { ok: true, data: parsed };
  } catch {
    return { ok: false, reason: "invalid_json" };
  }
}

function stripJsonComments(value: string) {
  return value
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^\\])\/\/.*$/gm, "$1");
}

async function summarizeTsconfig() {
  const warnings: string[] = [];
  const candidates = [
    "tsconfig.json",
    "tsconfig.base.json",
    "tsconfig.app.json",
    "tsconfig.build.json",
    "tsconfig.node.json",
    "tsconfig.shared.json"
  ];
  const tsconfigPath = await findFirstExistingFile(candidates);
  if (!tsconfigPath) {
    warnings.push("tsconfig_missing");
    return { summary: { references: [] } as JsWorkspaceSummary["tsconfig"], warnings };
  }

  const parsed = await readRepoJsonFile(tsconfigPath);
  if (!parsed.ok) {
    warnings.push(`tsconfig_unreadable:${parsed.reason}`);
    return { summary: { root: tsconfigPath, references: [] }, warnings };
  }

  const data = parsed.data as Record<string, unknown>;
  const references = Array.isArray(data.references)
    ? data.references
        .map((ref) => {
          if (typeof ref === "string") return ref;
          if (ref && typeof ref === "object" && typeof (ref as Record<string, unknown>).path === "string") {
            return (ref as Record<string, unknown>).path as string;
          }
          return null;
        })
        .filter((ref): ref is string => Boolean(ref))
    : [];
  const compilerOptions = data.compilerOptions && typeof data.compilerOptions === "object" ? data.compilerOptions : null;
  const paths =
    compilerOptions && typeof (compilerOptions as Record<string, unknown>).paths === "object"
      ? ((compilerOptions as Record<string, unknown>).paths as Record<string, unknown>)
      : undefined;

  return {
    summary: {
      root: tsconfigPath,
      references,
      paths
    },
    warnings
  };
}

async function summarizeViteConfig() {
  const warnings: string[] = [];
  const candidates = [
    "vite.config.ts",
    "vite.config.js",
    "vite.config.mjs",
    "vite.config.cjs"
  ];
  const configPath = await findFirstExistingFile(candidates);
  if (!configPath) {
    warnings.push("vite_config_missing");
    return { summary: {} as JsWorkspaceSummary["vite"], warnings };
  }

  const contentResult = await readRepoTextFile(configPath);
  if (!contentResult.ok) {
    warnings.push(`vite_config_unreadable:${contentResult.reason}`);
    return { summary: { configPath }, warnings };
  }

  const content = normalizeLineEndings(contentResult.content);
  const plugins = extractVitePlugins(content);
  const aliases = extractViteAliases(content);
  const summary: JsWorkspaceSummary["vite"] = { configPath };
  if (plugins.length > 0) summary.plugins = plugins;
  if (Object.keys(aliases).length > 0) summary.aliases = aliases;
  if (plugins.length === 0) warnings.push("vite_plugins_not_detected");
  if (Object.keys(aliases).length === 0) warnings.push("vite_aliases_not_detected");

  return { summary, warnings };
}

async function summarizeEslintConfig() {
  const warnings: string[] = [];
  const candidates = [
    "eslint.config.js",
    "eslint.config.mjs",
    "eslint.config.cjs",
    "eslint.config.ts",
    ".eslintrc.json",
    ".eslintrc",
    ".eslintrc.js",
    ".eslintrc.cjs",
    ".eslintrc.yaml",
    ".eslintrc.yml"
  ];
  const configPath = await findFirstExistingFile(candidates);
  if (!configPath) {
    warnings.push("eslint_config_missing");
    return { summary: {} as JsWorkspaceSummary["eslint"], warnings };
  }

  const summary: JsWorkspaceSummary["eslint"] = { configPath };
  const contentResult = await readRepoTextFile(configPath);
  if (!contentResult.ok) {
    warnings.push(`eslint_config_unreadable:${contentResult.reason}`);
    return { summary, warnings };
  }

  const isJson = configPath.endsWith(".json") || configPath.endsWith(".eslintrc");
  const isYaml = configPath.endsWith(".yaml") || configPath.endsWith(".yml");

  if (isYaml) {
    warnings.push("eslint_yaml_parsing_not_supported");
    return { summary, warnings };
  }

  if (isJson) {
    try {
      const parsed = JSON.parse(stripJsonComments(contentResult.content)) as Record<string, unknown>;
      const extendsValue = parsed.extends;
      const extendsArray = normalizeExtendsValue(extendsValue);
      if (extendsArray.length > 0) summary.extends = extendsArray;
      return { summary, warnings };
    } catch {
      warnings.push("eslint_config_invalid_json");
      return { summary, warnings };
    }
  }

  const extendsMatches = Array.from(
    contentResult.content.matchAll(/\bextends\s*:\s*(\[[^\]]*?\]|["'][^"']+["'])/g)
  );
  const extendsValues: string[] = [];
  for (const match of extendsMatches) {
    extendsValues.push(...normalizeExtendsValue(match[1]));
  }
  if (extendsValues.length > 0) summary.extends = uniqueStrings(extendsValues);
  if (extendsValues.length === 0) warnings.push("eslint_extends_not_detected");
  return { summary, warnings };
}

function normalizeExtendsValue(value: unknown) {
  if (!value) return [];
  if (Array.isArray(value)) return value.filter((entry) => typeof entry === "string") as string[];
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed.startsWith("[")) {
      return trimmed
        .replace(/[\[\]]/g, "")
        .split(",")
        .map((entry) => entry.trim().replace(/^["']|["']$/g, ""))
        .filter(Boolean);
    }
    return [trimmed.replace(/^["']|["']$/g, "")];
  }
  if (typeof value === "object") {
    return [];
  }
  const raw = String(value);
  if (raw.startsWith("[")) {
    return raw
      .replace(/[\[\]]/g, "")
      .split(",")
      .map((entry) => entry.trim().replace(/^["']|["']$/g, ""))
      .filter(Boolean);
  }
  return [raw.replace(/^["']|["']$/g, "")];
}

function extractVitePlugins(content: string) {
  const match = content.match(/plugins\s*:\s*\[([\s\S]*?)\]/m);
  if (!match) return [];
  const raw = match[1];
  const names: string[] = [];
  const tokens = raw.matchAll(/\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|,|\])/g);
  for (const token of tokens) {
    const name = token[1];
    if (name === "defineConfig") continue;
    names.push(name);
  }
  return uniqueStrings(names);
}

function extractViteAliases(content: string) {
  const aliases: Record<string, string> = {};
  const objectMatch = content.match(/alias\s*:\s*{([\s\S]*?)}/m);
  if (objectMatch) {
    const raw = objectMatch[1];
    const pairs = raw.matchAll(/["']?([^"'\\s:]+)["']?\s*:\s*["']([^"']+)["']/g);
    for (const match of pairs) {
      aliases[match[1]] = match[2];
    }
  }

  if (Object.keys(aliases).length === 0) {
    const arrayMatch = content.match(/alias\s*:\s*\[([\s\S]*?)\]/m);
    if (arrayMatch) {
      const raw = arrayMatch[1];
      const entryMatches = raw.matchAll(/find\s*:\s*["']([^"']+)["'][\s\S]*?replacement\s*:\s*["']([^"']+)["']/g);
      for (const match of entryMatches) {
        aliases[match[1]] = match[2];
      }
    }
  }

  return aliases;
}

async function findFirstExistingFile(candidates: string[]) {
  for (const candidate of candidates) {
    if (await existsInRepo(candidate)) return candidate;
  }
  return null;
}

function uniqueStrings(values: string[]) {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const value of values) {
    if (!value) continue;
    if (seen.has(value)) continue;
    seen.add(value);
    output.push(value);
  }
  return output;
}

function parseGitStatusPorcelain(output: string) {
  const warnings: string[] = [];
  const lines = normalizeLineEndings(output).split("\n").filter(Boolean);
  let branch: string | null = null;
  const changed: GitStatusEntry[] = [];

  for (const line of lines) {
    if (line.startsWith("##")) {
      const raw = line.slice(2).trim();
      const branchMatch = raw.match(/^([^\s.]+)(?:\.{3}|\s|$)/);
      if (branchMatch) {
        branch = branchMatch[1];
      } else if (raw.includes("HEAD")) {
        branch = "HEAD";
      }
      continue;
    }

    if (line.startsWith("??")) {
      const pathValue = line.slice(2).trim();
      changed.push({ path: pathValue, status: "??" });
      continue;
    }

    if (line.length < 3) {
      warnings.push("status_line_unrecognized");
      continue;
    }

    const statusChar = line[0] !== " " ? line[0] : line[1];
    const pathPart = line.slice(3).trim();
    if (!pathPart) continue;

    let pathValue = pathPart;
    if (statusChar === "R") {
      const renameMatch = pathPart.split(" -> ");
      pathValue = renameMatch[1] ?? renameMatch[0];
    }

    if (["M", "A", "D", "R"].includes(statusChar)) {
      changed.push({ path: pathValue, status: statusChar as GitStatusEntry["status"] });
    } else {
      warnings.push(`status_unhandled:${statusChar}`);
    }
  }

  return { branch, changed, warnings };
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
    if (isProtectedPath(relPath)) continue;
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
    if (isProtectedPath(relPath)) continue;
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
        const relPathNormalized = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPathNormalized)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const fullPath = path.join(current, entry.name);
        const relPath = path.relative(repoRoot, fullPath);
        const relPathNormalized = normalizeRelativePath(relPath);
        if (isProtectedPath(relPathNormalized)) continue;
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
    if (isProtectedPath(relPath)) continue;
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
    if (isProtectedPath(relPath)) continue;
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
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPath)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPath)) continue;
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

async function runTodoScanWithRg(patterns: string[]) {
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
  const results: RepoTodoResult[] = [];
  for (const line of lines) {
    const match = line.match(/^(.*?):(\d+):(.*)$/);
    if (!match) continue;
    const relPath = normalizeRelativePath(match[1]);
    if (isProtectedPath(relPath)) continue;
    const lineNumber = Number(match[2]);
    const preview = match[3].slice(0, MAX_PREVIEW_CHARS);
    const matchedPattern = detectTodoPattern(preview, patterns);
    if (!matchedPattern) continue;
    results.push({
      pattern: matchedPattern,
      path: relPath,
      line: lineNumber,
      preview
    });
  }

  return { results, truncated: result.truncated };
}

async function runTodoScanWithWalk(patterns: string[], maxResults: number) {
  const results: RepoTodoResult[] = [];
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
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPath)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const fullPath = path.join(current, entry.name);
        const relPath = normalizeRelativePath(path.relative(repoRoot, fullPath));
        if (isProtectedPath(relPath)) continue;
        const stat = await fs.stat(fullPath).catch(() => null);
        if (!stat || !stat.isFile() || stat.size > MAX_FILE_SIZE_BYTES) continue;
        if (await isBinaryFile(fullPath)) continue;
        const content = normalizeLineEndings(await fs.readFile(fullPath, "utf8"));
        const lines = content.split("\n");
        for (let i = 0; i < lines.length; i += 1) {
          if (shouldStop()) {
            truncated = true;
            return;
          }
          const matchedPattern = detectTodoPattern(lines[i], patterns);
          if (!matchedPattern) continue;
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
      files = result.stdout
        .split("\n")
        .filter(Boolean)
        .map(normalizeRelativePath)
        .filter((file) => !isProtectedPath(file));
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

  files = files.filter((file) => !isProtectedPath(file));

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
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPath)) continue;
        await walk(path.join(current, entry.name));
      } else if (entry.isFile()) {
        const relPath = normalizeRelativePath(path.relative(repoRoot, path.join(current, entry.name)));
        if (isProtectedPath(relPath)) continue;
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

function detectTodoPattern(preview: string, patterns: string[]) {
  for (const pattern of patterns) {
    if (preview.includes(pattern)) return pattern;
  }
  return null;
}

function sha256(value: string) {
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

function buildUnifiedDiffForInsert(pathValue: string, line: number, insertLines: string[]) {
  return [
    `diff --git a/${pathValue} b/${pathValue}`,
    `--- a/${pathValue}`,
    `+++ b/${pathValue}`,
    `@@ -${line},0 +${line},${insertLines.length} @@`,
    ...insertLines.map((text) => `+${text}`)
  ].join("\n");
}

function buildUnifiedDiffForDelete(
  pathValue: string,
  startLine: number,
  endLine: number,
  removedLines: string[]
) {
  const count = endLine - startLine + 1;
  return [
    `diff --git a/${pathValue} b/${pathValue}`,
    `--- a/${pathValue}`,
    `+++ b/${pathValue}`,
    `@@ -${startLine},${count} +${startLine},0 @@`,
    ...removedLines.map((text) => `-${text}`)
  ].join("\n");
}

function buildUnifiedDiffForReplace(
  pathValue: string,
  startLine: number,
  endLine: number,
  removedLines: string[],
  newLines: string[]
) {
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

type UnifiedDiffHunkLine = {
  type: "context" | "add" | "del";
  text: string;
};

type UnifiedDiffHunk = {
  oldStart: number;
  oldCount: number;
  newStart: number;
  newCount: number;
  lines: UnifiedDiffHunkLine[];
};

function parseUnifiedDiff(diff: string):
  | { ok: true; path?: string; hunks: UnifiedDiffHunk[] }
  | { ok: false; error: RepoApplyPatchError } {
  const normalized = normalizeLineEndings(diff);
  const lines = normalized.split("\n");
  let parsedPath: string | undefined;
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
      if (candidate) parsedPath = normalizeRelativePath(candidate);
      continue;
    }
    if (line.startsWith("+++ ")) {
      const candidate = parseDiffPath(line.slice(4));
      if (candidate) parsedPath = normalizeRelativePath(candidate);
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

  const hunks: UnifiedDiffHunk[] = [];
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

    const hunkLines: UnifiedDiffHunkLine[] = [];
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
      } else if (prefix === "+") {
        hunkLines.push({ type: "add", text });
      } else if (prefix === "-") {
        hunkLines.push({ type: "del", text });
      } else {
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

function parseDiffPath(rawPath: string) {
  if (rawPath === "/dev/null") return null;
  if (rawPath.startsWith("a/") || rawPath.startsWith("b/")) {
    return rawPath.slice(2);
  }
  return rawPath;
}

function splitUnifiedDiffSegments(diff: string, warnings: string[]) {
  const lines = diff.split("\n");
  const segments: string[] = [];
  let current: string[] = [];
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
      } else if (current.length > 0) {
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
    if (sawPrelude) warnings.push("leading_content_ignored");
    return segments.filter((segment) => segment.trim().length > 0 && segment.startsWith("diff --git "));
  }

  return diff.trim().length > 0 ? [diff] : [];
}

function normalizeUnifiedDiffHunks(hunks: UnifiedDiffHunk[]):
  | { ok: true; lines: string[]; insertions: number; deletions: number }
  | { ok: false; error: string } {
  if (hunks.length === 0) {
    return { ok: false, error: "no_hunks" };
  }

  const lines: string[] = [];
  let insertions = 0;
  let deletions = 0;

  for (const hunk of hunks) {
    if (hunk.oldStart <= 0 || hunk.newStart <= 0) {
      return { ok: false, error: "hunk_start_invalid" };
    }

    let seenOld = 0;
    let seenNew = 0;
    const hunkLines: string[] = [];

    for (const entry of hunk.lines) {
      if (entry.type === "context") {
        seenOld += 1;
        seenNew += 1;
        hunkLines.push(` ${entry.text}`);
      } else if (entry.type === "add") {
        seenNew += 1;
        insertions += 1;
        hunkLines.push(`+${entry.text}`);
      } else {
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

function applyUnifiedDiff(lines: string[], hunks: UnifiedDiffHunk[]):
  | { ok: true; lines: string[]; bytesChanged: number }
  | { ok: false; error: RepoApplyPatchError } {
  const output: string[] = [];
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
      } else if (entry.type === "del") {
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
      } else {
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

function applyStructuredEdit(lines: string[], pathValue: string, input: RepoApplyPatchInput):
  | { ok: true; lines: string[]; bytesChanged: number; diffApplied: string }
  | { ok: false; error: RepoApplyPatchError } {
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
    const bytesChanged =
      Buffer.byteLength(input.replace.newText) + Buffer.byteLength(removedLines.join("\n"));
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
  if (isProtectedPath(relPath)) {
    return { results: [], truncated: false };
  }
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
  const normalized = relativePath.split(path.sep).join("/");
  if (normalized === ".") return ".";
  return normalized.replace(/^\.\//, "");
}

function joinRelativePath(base: string, next: string) {
  if (base === "." || base.length === 0) return normalizeRelativePath(next);
  return normalizeRelativePath(`${base}/${next}`);
}

function isWithinRepoRoot(resolvedPath: string) {
  return resolvedPath === repoRoot || resolvedPath.startsWith(repoRoot + path.sep);
}

function safeOutputPath(userPath: string) {
  const resolved = resolveRepoPath(userPath);
  if (resolved.ok) return resolved.relative;
  return ".";
}

function allowProtectedPaths() {
  const raw = process.env.BIDDERSWEET_ALLOW_PROTECTED_PATHS;
  if (!raw) return false;
  return ["1", "true", "yes"].includes(raw.trim().toLowerCase());
}

function isProtectedPath(relPath: string) {
  if (allowProtectedPaths()) return false;
  const normalized = normalizeRelativePath(relPath);
  return PROTECTED_PATH_PATTERNS.some((pattern) => pattern.test(normalized));
}

function isLockfilePath(relPath: string) {
  return LOCKFILE_NAMES.has(path.basename(relPath));
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

function applyPatchError(
  pathValue: string,
  code: string,
  message: string,
  details?: Record<string, unknown>,
  beforeSha256?: string,
  afterSha256?: string,
  diffApplied?: string
): RepoApplyPatchResult {
  return {
    path: pathValue,
    applied: false,
    beforeSha256,
    afterSha256,
    diffApplied,
    errors: [{ code, message, details }]
  };
}

function enforceCapabilityMode(toolName: string) {
  const capability = readCapabilityMode();
  if (capability === "READ_WRITE") return null;
  if (!WRITE_TOOL_NAMES.has(toolName)) return null;
  return toolError("capability_denied", "tool is not allowed in READ_ONLY mode", {
    tool: toolName,
    mode: capability
  });
}

function readCapabilityMode(): CapabilityMode {
  const raw = process.env.MCP_CAPABILITY ?? DEFAULT_CAPABILITY_MODE;
  const normalized = raw.trim().toUpperCase();
  if (normalized === "READ_WRITE") return "READ_WRITE";
  return "READ_ONLY";
}

function summarizeToolArgs(toolName: string, args: unknown) {
  const safeArgs = typeof args === "object" && args !== null ? (args as Record<string, unknown>) : {};
  switch (toolName) {
    case "repo.search":
      return { query: redactString(safeArgs.query), maxResults: safeArgs.maxResults };
    case "repo.read_file":
      return { path: redactString(safeArgs.path) };
    case "repo.read_range":
      return {
        path: redactString(safeArgs.path),
        startLine: safeArgs.startLine,
        endLine: safeArgs.endLine
      };
    case "repo.list_dir":
      return { path: redactString(safeArgs.path), maxEntries: safeArgs.maxEntries };
    case "repo.symbols":
      return { glob: redactString(safeArgs.glob), kinds: summarizeArray(safeArgs.kinds), maxResults: safeArgs.maxResults };
    case "repo.tree":
      return {
        path: redactString(safeArgs.path),
        maxDepth: safeArgs.maxDepth,
        maxNodes: safeArgs.maxNodes,
        maxEntriesPerDir: safeArgs.maxEntriesPerDir
      };
    case "repo.find_refs":
      return {
        symbol: redactString(safeArgs.symbol),
        languageHint: safeArgs.languageHint,
        maxFiles: safeArgs.maxFiles,
        maxSnippetsPerFile: safeArgs.maxSnippetsPerFile
      };
    case "repo.todo_scan":
      return { patternsCount: Array.isArray(safeArgs.patterns) ? safeArgs.patterns.length : 0, maxResults: safeArgs.maxResults };
    case "repo.format_patch":
      return { diffBytes: byteLength(safeArgs.diff) };
    case "repo.propose_patch":
      return summarizePatchArgs(safeArgs, false);
    case "repo.apply_patch":
      return summarizePatchArgs(safeArgs, true);
    case "dev.run":
      return { name: safeArgs.name, argsCount: Array.isArray(safeArgs.args) ? safeArgs.args.length : 0 };
    case "dev.benchmark_smoke":
      return { name: safeArgs.name };
    case "dev.explain_failure":
      return {
        runIdPresent: Boolean(safeArgs.runId),
        stdoutBytes: byteLength(safeArgs.stdout),
        stderrBytes: byteLength(safeArgs.stderr)
      };
    case "rails.routes":
      return { mode: safeArgs.mode, maxResults: safeArgs.maxResults };
    case "git.diff":
      return { path: redactString(safeArgs.path), staged: safeArgs.staged };
    case "dev.run_tests":
    case "dev.run_lint":
      return { target: safeArgs.target };
    default:
      return redactObject(safeArgs);
  }
}

function summarizePatchArgs(args: Record<string, unknown>, includeExpectedSha: boolean) {
  const diff = typeof args.diff === "string" ? args.diff : null;
  const insert = args.insert && typeof args.insert === "object" ? (args.insert as Record<string, unknown>) : null;
  const replace = args.replace && typeof args.replace === "object" ? (args.replace as Record<string, unknown>) : null;
  const del = args.delete && typeof args.delete === "object" ? (args.delete as Record<string, unknown>) : null;
  const operation = diff
    ? "diff"
    : insert
      ? "insert"
      : replace
        ? "replace"
        : del
          ? "delete"
          : "unknown";
  const textBytes =
    (insert && byteLength(insert.text)) ||
    (replace && byteLength(replace.newText)) ||
    0;
  const summary: Record<string, unknown> = {
    path: redactString(args.path),
    operation,
    diffBytes: diff ? byteLength(diff) : undefined,
    textBytes
  };
  if (includeExpectedSha) {
    summary.expectedSha256Present = Boolean(args.expectedSha256);
  }
  return summary;
}

function summarizeToolResult(toolName: string, result: unknown, isError: boolean) {
  if (!result || typeof result !== "object") {
    return { valueType: typeof result };
  }
  const payload = result as Record<string, unknown>;
  if (payload.error) {
    return { error: summarizeAuditError(result) };
  }
  if (toolName === "repo.search") {
    return {
      resultCount: Array.isArray(payload.results) ? payload.results.length : 0,
      truncated: payload.truncated
    };
  }
  if (toolName === "repo.read_file") {
    return {
      refused: payload.refused ?? false,
      reason: payload.reason,
      contentBytes: byteLength(payload.content)
    };
  }
  if (toolName === "repo.read_range") {
    return {
      truncated: payload.truncated ?? false,
      warnings: Array.isArray(payload.warnings) ? payload.warnings.length : 0,
      textBytes: byteLength(payload.text)
    };
  }
  if (toolName === "repo.list_dir") {
    return {
      entryCount: Array.isArray(payload.entries) ? payload.entries.length : 0,
      truncated: payload.truncated ?? false,
      error: payload.error
    };
  }
  if (toolName === "repo.find_refs") {
    return {
      fileCount: Array.isArray(payload.files) ? payload.files.length : 0,
      truncated: payload.truncated ?? false,
      strategy: payload.strategy
    };
  }
  if (toolName === "repo.todo_scan") {
    return {
      resultCount: Array.isArray(payload.results) ? payload.results.length : 0,
      truncated: payload.truncated ?? false
    };
  }
  if (toolName === "repo.format_patch") {
    return {
      valid: payload.valid ?? false,
      files: payload.stats && typeof payload.stats === "object" ? (payload.stats as Record<string, unknown>).files : undefined
    };
  }
  if (toolName === "repo.propose_patch") {
    return { applied: false, warnings: Array.isArray(payload.warnings) ? payload.warnings.length : 0 };
  }
  if (toolName === "repo.apply_patch") {
    const errors = Array.isArray(payload.errors) ? payload.errors : [];
    return {
      applied: payload.applied ?? false,
      errorsCount: errors.length,
      warnings: Array.isArray(payload.warnings) ? payload.warnings.length : 0
    };
  }
  if (toolName === "dev.run" || toolName === "dev.benchmark_smoke") {
    return {
      exitCode: payload.exitCode,
      durationMs: payload.durationMs,
      timedOut: payload.timedOut,
      truncated: payload.truncated,
      stdoutBytes: byteLength(payload.stdout),
      stderrBytes: byteLength(payload.stderr)
    };
  }
  if (toolName === "dev.run_tests" || toolName === "dev.run_lint") {
    return {
      ok: payload.ok,
      hasRuby: Boolean((payload.results as Record<string, unknown> | undefined)?.ruby),
      hasJs: Boolean((payload.results as Record<string, unknown> | undefined)?.js)
    };
  }
  if (toolName === "git.diff") {
    return {
      diffBytes: byteLength(payload.diff),
      truncated: payload.truncated
    };
  }
  if (toolName === "git.status") {
    return {
      changedCount: Array.isArray(payload.changed) ? payload.changed.length : 0,
      isGitRepo: payload.isGitRepo ?? false
    };
  }
  if (toolName === "rails.routes") {
    return {
      routeCount: Array.isArray(payload.routes) ? payload.routes.length : 0,
      truncated: payload.truncated ?? false,
      modeUsed: payload.modeUsed
    };
  }
  if (toolName === "rails.schema") {
    return {
      tableCount: Array.isArray(payload.tables) ? payload.tables.length : 0,
      source: payload.source
    };
  }
  if (toolName === "rails.models") {
    return {
      modelCount: Array.isArray(payload.models) ? payload.models.length : 0
    };
  }
  if (toolName === "js.workspace") {
    return {
      packageManager: payload.packageManager,
      hasWorkspaces: Boolean((payload.workspaces as Record<string, unknown> | undefined)?.enabled)
    };
  }
  if (isError) {
    return { error: summarizeAuditError(result) };
  }
  return redactObject(payload);
}

function summarizeAuditError(result: unknown) {
  if (!result || typeof result !== "object") return { message: "unknown_error" };
  const payload = result as Record<string, unknown>;
  if (payload.error && typeof payload.error === "object") {
    const err = payload.error as Record<string, unknown>;
    return {
      code: err.code ?? "error",
      message: truncateString(String(err.message ?? ""))
    };
  }
  if (typeof payload.error === "string") {
    return { code: payload.error };
  }
  if (payload.errors && Array.isArray(payload.errors) && payload.errors.length > 0) {
    const first = payload.errors[0] as Record<string, unknown>;
    return {
      code: first.code ?? "error",
      message: truncateString(String(first.message ?? ""))
    };
  }
  return { message: "unknown_error" };
}

async function writeAuditLog(entry: {
  timestamp: string;
  toolName: string;
  argsSummary: unknown;
  durationMs: number;
  resultSummary: unknown;
  error?: unknown;
}) {
  const line = JSON.stringify(entry);
  const logDir = path.join(repoRoot, AUDIT_LOG_DIR);
  const logPath = path.join(logDir, AUDIT_LOG_FILE);
  try {
    await fs.mkdir(logDir, { recursive: true });
    await fs.appendFile(logPath, `${line}\n`, "utf8");
  } catch {
    try {
      process.stderr.write(`${line}\n`);
    } catch {
      // ignore logging failures
    }
  }
}

function redactObject(value: Record<string, unknown>, depth = 0): Record<string, unknown> {
  if (depth > 2) return { redacted: true };
  const output: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(value)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      output[key] = "[REDACTED]";
      continue;
    }
    if (typeof raw === "string") {
      output[key] = redactString(raw, key);
      continue;
    }
    if (Array.isArray(raw)) {
      output[key] = summarizeArray(raw);
      continue;
    }
    if (raw && typeof raw === "object") {
      output[key] = redactObject(raw as Record<string, unknown>, depth + 1);
      continue;
    }
    output[key] = raw;
  }
  return output;
}

function summarizeArray(value: unknown) {
  if (!Array.isArray(value)) return undefined;
  const sliced = value.slice(0, AUDIT_MAX_ARRAY).map((entry) => {
    if (typeof entry === "string") return redactString(entry);
    if (typeof entry === "number" || typeof entry === "boolean") return entry;
    if (entry && typeof entry === "object") return redactObject(entry as Record<string, unknown>, 1);
    return null;
  });
  return { count: value.length, preview: sliced };
}

function redactString(value: unknown, key?: string) {
  if (typeof value !== "string") return value;
  if (key && SENSITIVE_KEY_PATTERN.test(key)) return "[REDACTED]";
  if (looksLikeSecret(value)) return "[REDACTED]";
  return truncateString(value);
}

function truncateString(value: string) {
  if (value.length <= AUDIT_MAX_STRING) return value;
  return `${value.slice(0, AUDIT_MAX_STRING)}…`;
}

function looksLikeSecret(value: string) {
  const trimmed = value.trim();
  if (trimmed.length < 32) return false;
  if (trimmed.includes("-----BEGIN")) return true;
  if (/^[A-Fa-f0-9]{40,}$/.test(trimmed)) return true;
  if (/^[A-Za-z0-9+/_-]{40,}={0,2}$/.test(trimmed)) return true;
  return false;
}

function byteLength(value: unknown) {
  if (typeof value !== "string") return 0;
  return Buffer.byteLength(value);
}

async function writeFileAtomic(filePath: string, content: string, mode?: number) {
  const dir = path.dirname(filePath);
  const tmpName = `.biddersweet-tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const tmpPath = path.join(dir, tmpName);
  try {
    await fs.writeFile(tmpPath, content, mode ? { mode } : undefined);
    await fs.rename(tmpPath, filePath);
  } catch (error) {
    try {
      await fs.unlink(tmpPath);
    } catch {
      // ignore cleanup errors
    }
    throw error;
  }
}

async function main() {
  appendServerLog("connect_start");
  const transport = new StdioServerTransport();
  await server.connect(transport);
  appendServerLog("connect_ok");
}

main().catch((err) => {
  appendServerLog(`connect_error: ${err?.stack || err}`);
  process.exit(1);
});
