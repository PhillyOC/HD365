import { useEffect, useState } from "react";
import { HD365, PrereqCheckResult } from "../lib/bridge";
import hd365Logo from "../assets/hd365-logo.png";

interface OnboardingProps {
  onDismiss: () => void;
  onConnectGraph: () => Promise<void>;
  onConnectExo: () => Promise<void>;
  onOpenProviders: () => void;
}

export function Onboarding({ onDismiss, onConnectGraph, onConnectExo, onOpenProviders }: OnboardingProps) {
  const [prereq, setPrereq] = useState<PrereqCheckResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"graph" | "exo" | null>(null);

  async function refresh() {
    try {
      const result = await HD365.prereqCheck();
      setPrereq(result);
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  }

  useEffect(() => {
    void refresh();
  }, []);

  async function handleConnectGraph() {
    setBusy("graph");
    try {
      await onConnectGraph();
      await refresh();
    } catch {
      // Header already surfaces connect errors; keep the onboarding modal on-screen.
    } finally {
      setBusy(null);
    }
  }

  async function handleConnectExo() {
    setBusy("exo");
    try {
      await onConnectExo();
      await refresh();
    } catch {
      // Same as above - non-fatal to the onboarding flow.
    } finally {
      setBusy(null);
    }
  }

  const ready = !!prereq;
  const graphOk = prereq?.graphModuleInstalled && prereq?.graphConnected;
  const graphModuleMissing = prereq && !prereq.graphModuleInstalled;
  const providerOk = prereq?.activeProviderConfigured;

  return (
    <div className="onboarding-overlay">
      <div className="onboarding-card">
        <div className="onboarding-header">
          <img src={hd365Logo} alt="" className="onboarding-logo" />
          <h1>Welcome to HD365</h1>
        </div>
        <p className="onboarding-subtitle">
          A quick check of what HD365 needs before it can discover and run admin tasks against
          your tenant.
        </p>

        {error && (
          <div className="error-box">
            <pre>{error}</pre>
          </div>
        )}

        {!ready && !error && <p className="connecting">Checking prerequisites...</p>}

        {ready && (
          <div className="onboarding-steps">
            <div className={`onboarding-step ${prereq!.graphModuleInstalled ? "step-ok" : "step-warn"}`}>
              <span className="onboarding-step-icon">{prereq!.graphModuleInstalled ? "\u2713" : "!"}</span>
              <div className="onboarding-step-body">
                <div className="onboarding-step-title">Microsoft Graph PowerShell module</div>
                <p className="onboarding-step-detail">
                  {prereq!.graphModuleInstalled
                    ? "Installed - HD365 can talk to Microsoft Graph."
                    : "Not found. Run this once in an elevated PowerShell window, then restart HD365:"}
                </p>
                {graphModuleMissing && (
                  <pre className="script-preview">Install-Module Microsoft.Graph -Scope CurrentUser</pre>
                )}
              </div>
            </div>

            <div className={`onboarding-step ${graphOk ? "step-ok" : "step-warn"}`}>
              <span className="onboarding-step-icon">{graphOk ? "\u2713" : "!"}</span>
              <div className="onboarding-step-body">
                <div className="onboarding-step-title">Connect to Microsoft Graph</div>
                <p className="onboarding-step-detail">
                  {prereq!.graphConnected
                    ? "Connected - discovery and solution scripts can run."
                    : "Sign in with an account that can read (and, when you approve a write, change) your tenant."}
                </p>
                {!prereq!.graphConnected && (
                  <div className="onboarding-step-actions">
                    <button
                      className="btn-primary"
                      onClick={handleConnectGraph}
                      disabled={busy !== null || !prereq!.graphModuleInstalled}
                    >
                      {busy === "graph" ? "Connecting..." : "Connect Microsoft Graph"}
                    </button>
                  </div>
                )}
              </div>
            </div>

            <div className={`onboarding-step ${providerOk ? "step-ok" : "step-warn"}`}>
              <span className="onboarding-step-icon">{providerOk ? "\u2713" : "!"}</span>
              <div className="onboarding-step-body">
                <div className="onboarding-step-title">AI provider - {prereq!.activeProviderDisplayName}</div>
                <p className="onboarding-step-detail">
                  {providerOk
                    ? "Configured - HD365 can turn requests into a plan."
                    : "Needs an API key/endpoint (or pick a different provider) before it can plan tasks."}
                </p>
                {!providerOk && (
                  <div className="onboarding-step-actions">
                    <button className="btn-primary" onClick={onOpenProviders}>
                      Open AI Providers
                    </button>
                  </div>
                )}
              </div>
            </div>

            <div className={`onboarding-step ${prereq!.exoConnected ? "step-ok" : "step-warn"}`}>
              <span className="onboarding-step-icon">{prereq!.exoConnected ? "\u2713" : "\u25CB"}</span>
              <div className="onboarding-step-body">
                <div className="onboarding-step-title">Exchange Online (optional)</div>
                <p className="onboarding-step-detail">
                  {prereq!.exoConnected
                    ? "Connected."
                    : prereq!.exoModuleInstalled
                      ? "Only needed for mailbox/transport tasks - connect any time from the header."
                      : "Only needed for mailbox/transport tasks. Install-Module ExchangeOnlineManagement -Scope CurrentUser"}
                </p>
                {!prereq!.exoConnected && prereq!.exoModuleInstalled && (
                  <div className="onboarding-step-actions">
                    <button onClick={handleConnectExo} disabled={busy !== null}>
                      {busy === "exo" ? "Connecting..." : "Connect Exchange Online"}
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        <div className="onboarding-footer">
          <button className="onboarding-skip" onClick={onDismiss}>
            Skip for now
          </button>
          <button className="btn-primary" onClick={onDismiss}>
            Continue to HD365
          </button>
        </div>
      </div>
    </div>
  );
}
