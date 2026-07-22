import { useCallback, useEffect, useState } from "react";
import { AuditRecord, HD365 } from "../lib/bridge";

export function AuditView() {
  const [records, setRecords] = useState<AuditRecord[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [writesOnly, setWritesOnly] = useState(false);
  const [limit, setLimit] = useState(50);
  const [expanded, setExpanded] = useState<number | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const rows = await HD365.auditTail(limit, writesOnly);
      setRecords(rows);
    } catch (e) {
      setError(String(e));
    }
  }, [limit, writesOnly]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="settings-view">
      <div className="settings-header-row">
        <h2>Audit Log</h2>
        <div className="audit-controls">
          <label className="audit-checkbox">
            <input
              type="checkbox"
              checked={writesOnly}
              onChange={(e) => setWritesOnly(e.target.checked)}
            />
            Writes only
          </label>
          <select value={limit} onChange={(e) => setLimit(Number(e.target.value))}>
            <option value={25}>Last 25</option>
            <option value={50}>Last 50</option>
            <option value={100}>Last 100</option>
            <option value={250}>Last 250</option>
          </select>
          <button onClick={() => void load()}>Refresh</button>
        </div>
      </div>

      {error && (
        <div className="error-box">
          <pre>{error}</pre>
        </div>
      )}

      {!records && !error && <p className="connecting">Loading audit log...</p>}

      {records && records.length === 0 && <p className="result-empty">No audit records yet.</p>}

      {records && records.length > 0 && (
        <div className="audit-list">
          {records
            .slice()
            .reverse()
            .map((r, idx) => {
              const isOpen = expanded === idx;
              return (
                <div key={`${r.timestampUtc}-${idx}`} className="audit-row">
                  <button className="audit-row-summary" onClick={() => setExpanded(isOpen ? null : idx)}>
                    <span className="audit-time">{new Date(r.timestampUtc).toLocaleString()}</span>
                    <span className={r.isWrite ? "badge badge-write" : "badge badge-read"}>
                      {r.isWrite ? "WRITE" : "READ"}
                    </span>
                    <span className="audit-event">{r.eventType}</span>
                    <span className="audit-phase">{r.phase}</span>
                    <span className="audit-operator">{r.operator}</span>
                  </button>
                  {isOpen && (
                    <div className="audit-detail">
                      <div className="provider-meta">
                        <span>session: {r.sessionId}</span>
                        <span>machine: {r.machine}</span>
                        <span>graphMode: {r.graphMode}</span>
                        {r.scriptSha256 && <span>sha256: {r.scriptSha256.slice(0, 12)}...</span>}
                      </div>
                      {r.scriptText && <pre className="script-preview">{r.scriptText}</pre>}
                      {r.data && Object.keys(r.data).length > 0 && (
                        <pre className="result-output">{JSON.stringify(r.data, null, 2)}</pre>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
        </div>
      )}
    </div>
  );
}
