import { invoke } from "@tauri-apps/api/core";

/**
 * Typed wrapper around the single generic `bridge_call` Tauri command, which forwards
 * `{method, params}` to the HD365 PowerShell JSON-RPC bridge (Bridge-HD365.ps1) and returns its
 * `result` (or throws with the bridge's `error.message`).
 */
export async function bridgeCall<TResult = unknown>(
  method: string,
  params?: Record<string, unknown>
): Promise<TResult> {
  return invoke<TResult>("bridge_call", { method, params: params ?? null });
}

// ---------------------------------------------------------------------------
// Shapes returned by the bridge. NOTE: casing intentionally mirrors whatever
// PowerShell emits for each method - methods we authored directly in
// Invoke-HD365Bridge.ps1 (ping, session.init, provider.catalog, ...) use
// lowerCamelCase; methods that pass through pre-existing engine objects
// (pipeline.submit, run.preview, run.execute - built long before the GUI
// existed) use PascalCase. Do not "fix" the casing here without also
// updating the PowerShell side, or the two will drift.
// ---------------------------------------------------------------------------

export interface PingResult {
  pong: boolean;
  bridgeVersion: string;
  moduleVersion?: unknown;
  timestampUtc: string;
}

export interface SessionInitResult {
  sessionId: string;
  phase: string;
  operator: string;
  machine: string;
  graphConnected: boolean;
  graphAccount: string | null;
  graphMode: string;
  exoConnected: boolean;
  adAvailable: boolean;
  hasPending: boolean;
  configPath: string;
}

export interface ProviderCatalogEntry {
  id: string;
  displayName: string;
  kind: string;
  needsKey: boolean;
  needsEndpoint: boolean;
  keyEnvVar: string | null;
  notes: string;
  configured: boolean;
  active: boolean;
}

/** The AI-produced plan/proposal (JSON schema documented in Invoke-HD365Ai.ps1's prompt). */
export interface AiProposal {
  summary?: string;
  intent?: string;
  platform?: string;
  isWrite?: boolean;
  leastScopes?: string[];
  warnings?: string[];
  solutionKind?: string;
  expectedCount?: number;
  discoveryScript?: string;
  executionScript?: string;
  phase?: string;
  offline?: boolean;
  [key: string]: unknown;
}

/** Result of pipeline.submit - matches $script:HD365Session.PendingProposal. */
export interface PendingProposal {
  Proposal: AiProposal;
  ExecutionScript: string;
  ScriptPath: string | null;
  DiscoveryScript: string;
  DiscoveryResult: unknown;
  SolutionSummary: string | null;
  BulkKind: string | null;
  JobData: { CreateCount?: number; [key: string]: unknown } | null;
  Approved: boolean;
  UserMessage: string;
  CreatedAt: string;
}

/** Result of run.preview - matches Get-HD365RunPreview. */
export interface RunPreview {
  HasPending: boolean;
  IsWrite?: boolean;
  ScriptText?: string;
  ScriptPath?: string | null;
  OperationCount?: number;
  RequiresConfirmation?: boolean;
  ConfirmationPhrase?: string;
  Summary?: string;
  Platform?: string;
}

/** Result of run.execute - matches Invoke-HD365ExecutePlan. */
export interface RunExecuteResult {
  Success: boolean;
  BulkKind: string | null;
  Output: unknown;
}

export interface AuditRecord {
  timestampUtc: string;
  sessionId: string;
  operator: string;
  machine: string;
  eventType: string;
  phase: string;
  isWrite: boolean;
  graphMode: string;
  scriptSha256: string | null;
  scriptText: string | null;
  data: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Convenience wrappers - one per bridge method used by the UI so call sites
// don't have to remember exact method-name strings / param shapes.
// ---------------------------------------------------------------------------

export const HD365 = {
  ping: () => bridgeCall<PingResult>("ping"),

  sessionInit: () => bridgeCall<SessionInitResult>("session.init"),

  providerCatalog: () => bridgeCall<ProviderCatalogEntry[]>("provider.catalog"),

  saveProvider: (providerId: string) =>
    bridgeCall<{ provider: string }>("config.saveProvider", { providerId }),

  authConnect: (mode: "Read" | "Write" = "Read") =>
    bridgeCall<{ account: string; tenantId: string; scopes: string[] }>("auth.connect", { mode }),

  submitPipeline: (message: string) =>
    bridgeCall<PendingProposal>("pipeline.submit", { message }),

  runPreview: (scriptOverride?: string) =>
    bridgeCall<RunPreview>("run.preview", scriptOverride ? { scriptOverride } : undefined),

  runExecute: (confirmPhrase?: string, scriptOverride?: string) =>
    bridgeCall<RunExecuteResult>("run.execute", {
      ...(confirmPhrase ? { confirmPhrase } : {}),
      ...(scriptOverride ? { scriptOverride } : {}),
    }),

  runCancel: () => bridgeCall<{ cancelled: boolean }>("run.cancel"),

  auditTail: (last = 50, writesOnly = false) =>
    bridgeCall<AuditRecord[]>("audit.tail", { last, writesOnly }),
};
