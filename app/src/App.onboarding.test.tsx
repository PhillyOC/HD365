import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import App from "./App";
import type { PrereqCheckResult, SessionInitResult } from "./lib/bridge";

// Mirrors the mocking approach in components/ChatView.test.tsx - only the Tauri `invoke`
// boundary is faked; App -> Onboarding/ChatView -> HD365.* -> bridgeCall -> invoke is real.
let prereq: PrereqCheckResult;

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

    case "provider.catalog":
      return [];

    case "session.prereqCheck":
      return prereq;

    case "auth.connect":
      return { account: "tester@contoso.com", tenantId: "tid", scopes: ["User.Read"] };

    default:
      throw new Error(`unmocked bridge method '${method}'`);
  }
});

vi.mock("@tauri-apps/api/core", () => ({
  invoke: (cmd: string, args?: Record<string, unknown>) => invokeMock(cmd, args),
}));

describe("HD365 desktop onboarding", () => {
  beforeEach(() => {
    localStorage.clear();
    invokeMock.mockClear();
    prereq = {
      graphModuleInstalled: false,
      exoModuleInstalled: false,
      adModuleAvailable: false,
      graphConnected: false,
      exoConnected: false,
      activeProviderId: "CopilotChat",
      activeProviderDisplayName: "Copilot Chat",
      activeProviderConfigured: false,
    };
  });

  it("shows the setup checklist on first run and flags missing prerequisites", async () => {
    render(<App />);

    expect(await screen.findByText(/welcome to hd365/i)).toBeInTheDocument();
    expect(await screen.findByText(/not found\. run this once/i)).toBeInTheDocument();
    expect(screen.getByText("Install-Module Microsoft.Graph -Scope CurrentUser")).toBeInTheDocument();
  });

  it("dismisses on Continue and does not reappear on next mount", async () => {
    const user = userEvent.setup();
    const { unmount } = render(<App />);

    await screen.findByText(/welcome to hd365/i);
    await user.click(screen.getByRole("button", { name: /continue to hd365/i }));
    expect(screen.queryByText(/welcome to hd365/i)).not.toBeInTheDocument();
    unmount();

    render(<App />);
    await screen.findByPlaceholderText(/describe a task/i);
    expect(screen.queryByText(/welcome to hd365/i)).not.toBeInTheDocument();
  });

  it("can be reopened via the Setup guide status pill", async () => {
    const user = userEvent.setup();
    render(<App />);

    await screen.findByText(/welcome to hd365/i);
    await user.click(screen.getByRole("button", { name: /continue to hd365/i }));
    expect(screen.queryByText(/welcome to hd365/i)).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /setup guide/i }));
    expect(await screen.findByText(/welcome to hd365/i)).toBeInTheDocument();
  });

  it("connects Microsoft Graph from the onboarding step once the module is installed", async () => {
    prereq.graphModuleInstalled = true;
    const user = userEvent.setup();
    render(<App />);

    await screen.findByText(/welcome to hd365/i);
    const connectButton = await screen.findByRole("button", { name: /^connect microsoft graph$/i });
    expect(connectButton).toBeEnabled();

    prereq = { ...prereq, graphConnected: true };
    await user.click(connectButton);

    await waitFor(() =>
      expect(invokeMock.mock.calls.map(([, a]) => (a as Record<string, unknown>)?.method)).toContain(
        "auth.connect"
      )
    );
    expect(await screen.findByText(/connected - discovery and solution scripts can run/i)).toBeInTheDocument();
  });
});
