import { useCallback, useEffect, useState } from "react";
import { HD365, SessionInitResult } from "./lib/bridge";
import { ChatView } from "./components/ChatView";
import { ProvidersView } from "./components/ProvidersView";
import { AuditView } from "./components/AuditView";
import "./App.css";

type ConnState = "connecting" | "connected" | "error";
type Tab = "chat" | "providers" | "audit";

function App() {
  const [state, setState] = useState<ConnState>("connecting");
  const [session, setSession] = useState<SessionInitResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("chat");
  const [activeProvider, setActiveProvider] = useState<string | null>(null);
  const [connectingGraph, setConnectingGraph] = useState(false);
  const [connectingExo, setConnectingExo] = useState(false);

  const refreshSession = useCallback(async () => {
    try {
      const sessionResult = await HD365.sessionInit();
      setSession(sessionResult);
    } catch (e) {
      setError(String(e));
      setState("error");
    }
  }, []);

  const refreshProvider = useCallback(async () => {
    try {
      const catalog = await HD365.providerCatalog();
      const active = catalog.find((p) => p.active);
      setActiveProvider(active ? active.displayName : null);
    } catch {
      // Non-fatal - the Providers tab will surface its own error state.
    }
  }, []);

  useEffect(() => {
    (async () => {
      try {
        await HD365.ping();
        await refreshSession();
        await refreshProvider();
        setState("connected");
      } catch (e) {
        setError(String(e));
        setState("error");
      }
    })();
  }, [refreshSession, refreshProvider]);

  async function handleConnectGraph() {
    setConnectingGraph(true);
    try {
      await HD365.authConnect("Read");
      await refreshSession();
    } catch (e) {
      setError(String(e));
    } finally {
      setConnectingGraph(false);
    }
  }

  async function handleConnectExo() {
    setConnectingExo(true);
    try {
      await HD365.exoConnect();
      await refreshSession();
    } catch (e) {
      setError(String(e));
    } finally {
      setConnectingExo(false);
    }
  }

  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="app-title">HD365</span>

        {session && (
          <div className="app-status-group">
            <button
              className={`status-pill ${session.graphConnected ? "status-ok" : "status-warn"}`}
              onClick={session.graphConnected ? undefined : handleConnectGraph}
              disabled={session.graphConnected || connectingGraph}
              title={session.graphConnected ? session.graphAccount ?? "" : "Click to connect to Microsoft Graph"}
            >
              {connectingGraph
                ? "Connecting Graph..."
                : session.graphConnected
                  ? `Graph: ${session.graphAccount}`
                  : "Graph: not connected"}
            </button>

            <button
              className={`status-pill ${session.exoConnected ? "status-ok" : "status-warn"}`}
              onClick={session.exoConnected ? undefined : handleConnectExo}
              disabled={session.exoConnected || connectingExo}
              title={session.exoConnected ? "Exchange Online connected" : "Click to connect to Exchange Online"}
            >
              {connectingExo ? "Connecting EXO..." : session.exoConnected ? "EXO: connected" : "EXO: not connected"}
            </button>

            {activeProvider && <span className="status-pill status-info">AI: {activeProvider}</span>}

            <span className="app-status">
              {session.operator}@{session.machine}
            </span>
          </div>
        )}
      </header>

      {state === "connected" && (
        <nav className="app-tabs">
          <button className={tab === "chat" ? "tab-active" : ""} onClick={() => setTab("chat")}>
            Chat
          </button>
          <button className={tab === "providers" ? "tab-active" : ""} onClick={() => setTab("providers")}>
            AI Providers
          </button>
          <button className={tab === "audit" ? "tab-active" : ""} onClick={() => setTab("audit")}>
            Audit Log
          </button>
        </nav>
      )}

      <main className="app-main">
        {state === "connecting" && <p className="connecting">Connecting to the HD365 engine...</p>}

        {state === "error" && (
          <div className="error-box">
            <strong>Bridge connection failed</strong>
            <pre>{error}</pre>
          </div>
        )}

        {state === "connected" && tab === "chat" && <ChatView />}
        {state === "connected" && tab === "providers" && (
          <ProvidersView onProviderChanged={refreshProvider} />
        )}
        {state === "connected" && tab === "audit" && <AuditView />}
      </main>
    </div>
  );
}

export default App;
