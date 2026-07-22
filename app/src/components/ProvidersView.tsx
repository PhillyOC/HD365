import { useCallback, useEffect, useState } from "react";
import { HD365, ProviderCatalogEntry } from "../lib/bridge";

interface ProvidersViewProps {
  onProviderChanged?: () => void;
}

export function ProvidersView({ onProviderChanged }: ProvidersViewProps) {
  const [providers, setProviders] = useState<ProviderCatalogEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [switching, setSwitching] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const catalog = await HD365.providerCatalog();
      setProviders(catalog);
    } catch (e) {
      setError(String(e));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function handleSwitch(id: string) {
    setSwitching(id);
    setError(null);
    try {
      await HD365.saveProvider(id);
      await load();
      onProviderChanged?.();
    } catch (e) {
      setError(String(e));
    } finally {
      setSwitching(null);
    }
  }

  return (
    <div className="settings-view">
      <div className="settings-header-row">
        <h2>AI Providers</h2>
        <button onClick={() => void load()}>Refresh</button>
      </div>

      {error && (
        <div className="error-box">
          <pre>{error}</pre>
        </div>
      )}

      {!providers && !error && <p className="connecting">Loading providers...</p>}

      {providers && (
        <div className="provider-list">
          {providers.map((p) => (
            <div key={p.id} className={`provider-row ${p.active ? "active" : ""}`}>
              <div className="provider-main">
                <div className="provider-name">
                  {p.displayName}
                  {p.active && <span className="badge badge-active">ACTIVE</span>}
                  <span className={p.configured ? "badge badge-read" : "badge badge-write"}>
                    {p.configured ? "READY" : "NEEDS SETUP"}
                  </span>
                </div>
                <div className="provider-meta">
                  <span>{p.id}</span>
                  {p.needsKey && p.keyEnvVar && <span>env: {p.keyEnvVar}</span>}
                  {p.needsEndpoint && <span>needs endpoint + deployment</span>}
                </div>
                {p.notes && <p className="provider-notes">{p.notes}</p>}
              </div>
              <button
                className="btn-primary"
                disabled={p.active || switching !== null}
                onClick={() => handleSwitch(p.id)}
              >
                {switching === p.id ? "Switching..." : p.active ? "Active" : "Use this provider"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
