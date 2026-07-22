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

export interface PingResult {
  pong: boolean;
  bridgeVersion: string;
  moduleVersion?: string;
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
