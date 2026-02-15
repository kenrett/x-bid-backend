import {
  runOpsPlanEnvUpdate,
  runOpsConfirmEnvUpdate,
  OpsOrchestratorDeps,
  RenderService,
} from "../src/orchestrators/ops.js";
import { test, describe, it, before, after, mock } from "node:test";
import assert from "node:assert";
import * as fs from "node:fs/promises";

// Mock the dependencies
mock.method(fs, "writeFile", () => {});
mock.method(fs, "readFile", () => {});
mock.method(fs, "rm", () => {});
mock.method(fs, "appendFile", () => {});

const mockDeps: OpsOrchestratorDeps = {
  listRenderServices: mock.fn(),
  updateRenderEnvVars: mock.fn(),
  // Add other dummy functions if needed by the parts of ops.ts we are not testing
  getGitSummary: mock.fn(async () => ({ isGitRepo: true, branch: "main", changedCount: 0 })),
  getDevToolsSummary: mock.fn(async () => ({ rgPresent: true, gitPresent: true })),
  fileExists: mock.fn(async () => true),
  readTextFile: mock.fn(async () => ""),
  listRenderLogs: mock.fn(async () => ({ logs: [] })),
  getRenderMetrics: mock.fn(async () => []),
  listRenderDeploys: mock.fn(async () => []),
  listRenderEnvVars: mock.fn(async () => []),
};

const mockServices: RenderService[] = [
  { id: "srv-123", name: "my-service", url: "https://my-service.onrender.com" },
];

describe("ops env update confirmation", () => {
  after(() => {
    mock.reset();
  });

  describe("runOpsPlanEnvUpdate", () => {
    it("should create a plan and return a token for a valid request", async () => {
      mockDeps.listRenderServices.mock.mockImplementation(async () => mockServices);
      const input = {
        service: "my-service",
        env: { FOO: "bar" },
        allow_sensitive: false,
      };

      const result = await runOpsPlanEnvUpdate(input, mockDeps);

      assert(result.summary.includes("Plan created"));
      assert(result.next_actions[0].includes("ops.confirm_env_update"));
      assert.strictEqual(mock.method(fs, "writeFile").mock.callCount(), 1);
    });

    it("should refuse if service is not found", async () => {
        mockDeps.listRenderServices.mock.mockImplementation(async () => mockServices);
        const input = {
        service: "non-existent-service",
        env: { FOO: "bar" },
        allow_sensitive: false,
      };

      const result = await runOpsPlanEnvUpdate(input, mockDeps);

      assert.strictEqual(result.refused, true);
      assert.strictEqual(result.refusal_reason, "service_not_found");
    });

    it("should refuse if sensitive keys are present without acknowledgement", async () => {
        mockDeps.listRenderServices.mock.mockImplementation(async () => mockServices);
        const input = {
        service: "my-service",
        env: { SECRET_KEY: "supersecret" },
        allow_sensitive: false,
      };

      const result = await runOpsPlanEnvUpdate(input, mockDeps);

      assert.strictEqual(result.refused, true);
      assert.strictEqual(result.refusal_reason, "sensitive_keys_requires_ack");
    });

    it("should succeed if sensitive keys are present with acknowledgement", async () => {
        mockDeps.listRenderServices.mock.mockImplementation(async () => mockServices);
        const input = {
          service: "my-service",
          env: { SECRET_KEY: "supersecret" },
          allow_sensitive: true,
        };
  
        const result = await runOpsPlanEnvUpdate(input, mockDeps);
  
        assert.strictEqual(result.refused, undefined);
        assert.strictEqual(mock.method(fs, "writeFile").mock.callCount(), 1);
    });
  });

  describe("runOpsConfirmEnvUpdate", () => {
    it("should successfully update env vars with a valid token", async () => {
        const token = "valid-token";
        const plan = {
            serviceId: "srv-123",
            serviceName: "my-service",
            env: { FOO: "bar" },
            expiresAt: Date.now() + 10000,
        };
        
        mock.method(fs, "readFile", async () => JSON.stringify(plan));
        mockDeps.updateRenderEnvVars.mock.mockImplementation(async () => ({ ok: true }));

        const result = await runOpsConfirmEnvUpdate({ confirm_token: token }, mockDeps);

        assert(result.summary.includes("Successfully updated"));
        assert.strictEqual(mockDeps.updateRenderEnvVars.mock.callCount(), 1);
        assert.deepStrictEqual(mockDeps.updateRenderEnvVars.mock.calls[0].arguments, [{ serviceId: "srv-123", env: { FOO: "bar" } }]);
        assert.strictEqual(mock.method(fs, "rm").mock.callCount(), 1);
    });

    it("should refuse an invalid token", async () => {
        mock.method(fs, "readFile", async () => { throw new Error("File not found") });
        const result = await runOpsConfirmEnvUpdate({ confirm_token: "invalid-token" }, mockDeps);

        assert.strictEqual(result.refused, true);
        assert.strictEqual(result.refusal_reason, "invalid_or_expired_token");
    });

    it("should refuse an expired token", async () => {
        const token = "expired-token";
        const plan = {
            serviceId: "srv-123",
            serviceName: "my-service",
            env: { FOO: "bar" },
            expiresAt: Date.now() - 10000,
        };
        mock.method(fs, "readFile", async () => JSON.stringify(plan));
        const result = await runOpsConfirmEnvUpdate({ confirm_token: token }, mockDeps);

        assert.strictEqual(result.refused, true);
        assert.strictEqual(result.refusal_reason, "expired_token");
    });

    it("should refuse if render update fails", async () => {
        const token = "valid-token";
        const plan = {
            serviceId: "srv-123",
            serviceName: "my-service",
            env: { FOO: "bar" },
            expiresAt: Date.now() + 10000,
        };
        mock.method(fs, "readFile", async () => JSON.stringify(plan));
        mockDeps.updateRenderEnvVars.mock.mockImplementation(async () => ({ ok: false }));
        
        const result = await runOpsConfirmEnvUpdate({ confirm_token: token }, mockDeps);
        
        assert.strictEqual(result.refused, true);
        assert.strictEqual(result.refusal_reason, "update_failed");
    });
  });
});