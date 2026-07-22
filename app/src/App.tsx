import { useEffect, useState } from "react";
import { bridgeCall, PingResult, SessionInitResult } from "./lib/bridge";
import "./App.css";

type ConnState = "connecting" | "connected" | "error";

function App() {
  const [state, setState] = useState<ConnState>("connecting");
  const [ping, setPing] = useState<PingResult | null>(null);
  const [session, setSession] = useState<SessionInitResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const pingResult = await bridgeCall<PingResult>("ping");
        setPing(pingResult);
        const sessionResult = await bridgeCall<SessionInitResult>("session.init");
        setSession(sessionResult);
        setState("connected");
      } catch (e) {
        setError(String(e));
        setState("error");
      }
    })();
  }, []);

  return (
    <main className="container">
      <h1>HD365</h1>
      <p className="tagline">HelpDesk 365 AI - desktop bridge proof of life</p>

      {state === "connecting" && <p>Connecting to the HD365 engine...</p>}

      {state === "error" && (
        <div className="error-box">
          <strong>Bridge connection failed</strong>
          <pre>{error}</pre>
        </div>
      )}

      {state === "connected" && ping && session && (
        <div className="status-box">
          <p>
            <strong>Bridge:</strong> connected (v{ping.bridgeVersion}, module{" "}
            {ping.moduleVersion ?? "unknown"})
          </p>
          <p>
            <strong>Session:</strong> {session.sessionId} - phase {session.phase}
          </p>
          <p>
            <strong>Operator:</strong> {session.operator} @ {session.machine}
          </p>
          <p>
            <strong>Graph:</strong>{" "}
            {session.graphConnected ? `connected (${session.graphAccount})` : "not connected"}
          </p>
        </div>
      )}
    </main>
  );
}

export default App;
