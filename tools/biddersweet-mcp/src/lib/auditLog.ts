import { appendFile } from "fs/promises";

const AUDIT_LOG_PATH = "/Users/kenrettberg/.gemini/tmp/6a21c1d80e1f53246dc2e7d86c2a959eaf42e8375827bbc4380933309ded1591/mcp_audit.log";

export type AuditEvent = {
  timestamp: string;
  actor: string; // For now, we'll just use a generic identifier
  action: string;
  target: {
    type: string;
    id: string;
    name?: string;
  };
  details: Record<string, any>;
};

export async function logAuditEvent(event: Omit<AuditEvent, "timestamp" | "actor">) {
  const logEntry: AuditEvent = {
    timestamp: new Date().toISOString(),
    actor: "mcp-user", // In a real system, this would be the authenticated user
    ...event,
  };

  const logLine = JSON.stringify(logEntry) + "
";

  try {
    await appendFile(AUDIT_LOG_PATH, logLine);
  } catch (error) {
    console.error("Failed to write to audit log:", error);
    // In a real system, you might want to handle this more gracefully
  }
}
