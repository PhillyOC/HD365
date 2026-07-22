import { useEffect, useState } from "react";
import { HD365, SessionInitResult } from "./lib/bridge";
import { ChatView } from "./components/ChatView";
import "./App.css";

type ConnState = "connecting" | "connected" | "error";

function App() {
  const [state, setState] = useState<ConnState>("connecting");
  const [session, setSession] = useState<SessionInitResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        await HD365.ping();
        const sessionResult = await HD365.sessionInit();
        setSession(sessionResult);
        setState("connected");
      } catch (e) {
        setError(String(e));
        setState("error");
      }
    })();
  }, []);

  return (
    <div className="app-shell">
      <header className="app-header">
        <span className="app-title">HD365</span>
        {session && (
          <span className="app-status">
            {session.graphConnected ? `Graph: ${session.graphAccount}` : "Graph: not connected"}
            {" \u00b7 "}
            {session.operator}@{session.machine}
          </span>
        )}
      </header>

      <main className="app-main">
        {state === "connecting" && <p className="connecting">Connecting to the HD365 engine...</p>}

        {state === "error" && (
          <div className="error-box">
            <strong>Bridge connection failed</strong>
            <pre>{error}</pre>
          </div>
        )}

        {state === "connected" && <ChatView />}
      </main>
    </div>
  );
}

export default App;
