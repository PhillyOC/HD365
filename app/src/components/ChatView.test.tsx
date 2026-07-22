import { describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import App from "../App";
import type { PendingProposal, RunExecuteResult, RunPreview, SessionInitResult } from "../lib/bridge";

// Mock the Tauri IPC boundary. Everything above this line (App -> ChatView -> HD365.* ->
// bridgeCall -> invoke) is real; only the actual Rust<->PowerShell hop is faked, with
// responses shaped exactly like the real bridge (see Tests/Smoke-Bridge.ps1 for the
// PowerShell-side contract test of the same methods).
const invokeMock = vi.fn(async (cmd: string, args?: Record<string, unknown>) => {
  if (cmd !== "bridge_call") throw new Error(`unexpected command '${cmd}'`);
  const method = args?.method as string;

  switch (method) {
    case "ping":
      return { pong: true, bridgeVersion: "1", timestampUtc: "2026-07-22T00:00:00Z" };

    case "session.init":
      return {
        sessionId: "test-session",
        phase: "Ready",
        operator: "tester",
        machine: "TEST-PC",
        graphConnected: false,
        graphAccount: null,
        graphMode: "None",
        exoConnected: false,
        adAvailable: false,
        hasPending: false,
        configPath: "C:\\fake\\settings.json",
      } satisfies SessionInitResult;

    case "pipeline.submit":
      return {
        Proposal: {
          summary: "Create a security group for HR",
          intent: "write",
          platform: "Microsoft Graph",
          isWrite: true,
          leastScopes: ["Group.ReadWrite.All"],
          warnings: [],
          solutionKind: "PassthroughWrite",
          executionScript: "New-MgGroup -DisplayName 'HR' -MailEnabled:$false -SecurityEnabled:$true",
        },
        ExecutionScript: "New-MgGroup -DisplayName 'HR' -MailEnabled:$false -SecurityEnabled:$true",
        ScriptPath: null,
        DiscoveryScript: "Get-MgGroup -Filter \"displayName eq 'HR'\"",
        DiscoveryResult: null,
        SolutionSummary: "Create a security group for HR",
        BulkKind: null,
        JobData: null,
        Approved: true,
        UserMessage: "create a group for HR",
        CreatedAt: "2026-07-22T00:00:00Z",
      } satisfies PendingProposal;

    case "run.preview":
      return {
        HasPending: true,
        IsWrite: true,
        ScriptText: "New-MgGroup -DisplayName 'HR' -MailEnabled:$false -SecurityEnabled:$true",
        ScriptPath: null,
        OperationCount: 0,
        RequiresConfirmation: true,
        ConfirmationPhrase: "EXECUTE",
        Summary: "Create a security group for HR",
        Platform: "Microsoft Graph",
      } satisfies RunPreview;

    case "run.execute":
      if (args?.params && (args.params as Record<string, unknown>).confirmPhrase !== "EXECUTE") {
        throw new Error("Confirmation phrase did not match expected 'EXECUTE'.");
      }
      return {
        Success: true,
        BulkKind: null,
        Output: { DisplayName: "HR", Id: "11111111-1111-1111-1111-111111111111" },
      } satisfies RunExecuteResult;

    default:
      throw new Error(`unmocked bridge method '${method}'`);
  }
});

vi.mock("@tauri-apps/api/core", () => ({
  invoke: (cmd: string, args?: Record<string, unknown>) => invokeMock(cmd, args),
}));

describe("HD365 desktop chat flow", () => {
  it("submits a task, requires typed EXECUTE for a write proposal, and shows the result", async () => {
    const user = userEvent.setup();
    render(<App />);

    // 1. Bridge connects (ping + session.init) and the chat view appears.
    expect(await screen.findByPlaceholderText(/describe a task/i)).toBeInTheDocument();

    // 2. Send a natural-language request -> pipeline.submit -> solution card renders.
    await user.type(screen.getByPlaceholderText(/describe a task/i), "create a group for HR");
    await user.click(screen.getByRole("button", { name: /send/i }));

    expect(await screen.findByText(/create a security group for hr/i)).toBeInTheDocument();
    expect(screen.getByText(/write/i)).toBeInTheDocument();

    // 3. Click Run -> run.preview says RequiresConfirmation -> modal appears.
    await user.click(screen.getByRole("button", { name: /^run$/i }));
    expect(await screen.findByText(/write execution warning/i)).toBeInTheDocument();

    // Confirm button must stay disabled until the exact phrase is typed.
    const confirmButton = screen.getByRole("button", { name: /confirm & run/i });
    expect(confirmButton).toBeDisabled();

    await user.type(screen.getByRole("textbox", { name: /confirmation phrase/i }), "EXECUTE");

    await waitFor(() => expect(confirmButton).toBeEnabled());
    await user.click(confirmButton);

    // 4. run.execute succeeds -> result panel renders the real output.
    expect(await screen.findByText(/"DisplayName": "HR"/)).toBeInTheDocument();

    // Modal closes, solution card is marked executed.
    expect(screen.queryByText(/write execution warning/i)).not.toBeInTheDocument();
    expect(screen.getByText(/^executed$/i)).toBeInTheDocument();

    // Sanity: confirm the exact bridge methods were called in order.
    const methods = invokeMock.mock.calls.map(([, args]) => (args as Record<string, unknown>)?.method);
    expect(methods).toEqual([
      "ping",
      "session.init",
      "pipeline.submit",
      "run.preview",
      "run.execute",
    ]);
  });
});
