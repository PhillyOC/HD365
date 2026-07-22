//! Process manager for the HD365 PowerShell JSON-RPC bridge.
//!
//! Spawns `Bridge-HD365.ps1` once at app startup and keeps it alive for the lifetime of the
//! app. Requests/responses are newline-delimited JSON objects (`{id, method, params}` /
//! `{id, result}` / `{id, error}`) exchanged over the child's stdin/stdout. A background thread
//! reads response lines and resolves the matching pending call by id; `stderr` is drained to the
//! Rust app's own stderr for diagnostics only (never blocks the pipe, never parsed as protocol).

use serde_json::Value;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::oneshot;

type PendingMap = Arc<Mutex<HashMap<u64, oneshot::Sender<Value>>>>;

struct BridgeInner {
    child: Child,
    stdin: ChildStdin,
    next_id: u64,
    pending: PendingMap,
}

/// Shared Tauri-managed state wrapping the live bridge child process.
pub struct BridgeState {
    inner: Mutex<BridgeInner>,
}

impl BridgeState {
    /// Spawn `powershell.exe -File <script_path>` with piped stdio and start the background
    /// reader/stderr-drain threads. `script_path` should point at `Bridge-HD365.ps1`.
    pub fn spawn(script_path: &PathBuf, settings_path: Option<&str>) -> Result<Self, String> {
        if !script_path.exists() {
            return Err(format!(
                "Bridge script not found at '{}'. Is the HD365 PowerShell engine present next to the app?",
                script_path.display()
            ));
        }

        let mut args: Vec<String> = vec![
            "-NoLogo".into(),
            "-NoProfile".into(),
            "-ExecutionPolicy".into(),
            "Bypass".into(),
            "-File".into(),
            script_path.to_string_lossy().into_owned(),
        ];
        if let Some(settings) = settings_path {
            args.push("-SettingsPath".into());
            args.push(settings.into());
        }

        let mut child = Command::new("powershell.exe")
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("failed to spawn HD365 bridge process: {e}"))?;

        let stdin = child.stdin.take().ok_or("bridge process has no stdin handle")?;
        let stdout = child.stdout.take().ok_or("bridge process has no stdout handle")?;
        let stderr = child.stderr.take().ok_or("bridge process has no stderr handle")?;

        let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));

        // Reader thread: one JSON response object per line -> resolve the matching pending call.
        {
            let pending = pending.clone();
            std::thread::spawn(move || {
                let reader = BufReader::new(stdout);
                for line in reader.lines() {
                    let line = match line {
                        Ok(l) => l,
                        Err(_) => break,
                    };
                    if line.trim().is_empty() {
                        continue;
                    }
                    let value: Value = match serde_json::from_str(&line) {
                        Ok(v) => v,
                        Err(e) => {
                            eprintln!("[hd365-bridge] failed to parse response line as JSON: {e}; line={line}");
                            continue;
                        }
                    };
                    let id = value.get("id").and_then(|v| v.as_u64());
                    if let Some(id) = id {
                        if let Some(tx) = pending.lock().unwrap().remove(&id) {
                            let _ = tx.send(value);
                        }
                    }
                }
                // Bridge process exited (or closed stdout). Any calls still waiting will time out
                // on their own; nothing further to do here.
            });
        }

        // Stderr drain thread: diagnostics only, never part of the JSON-RPC protocol.
        std::thread::spawn(move || {
            let reader = BufReader::new(stderr);
            for line in reader.lines() {
                if let Ok(line) = line {
                    eprintln!("[hd365-bridge:stderr] {line}");
                }
            }
        });

        Ok(BridgeState {
            inner: Mutex::new(BridgeInner {
                child,
                stdin,
                next_id: 1,
                pending,
            }),
        })
    }

    /// Send one JSON-RPC request and await its matching response (by id), with a timeout.
    pub async fn call(&self, method: &str, params: Value) -> Result<Value, String> {
        let (_id, rx) = {
            let mut inner = self
                .inner
                .lock()
                .map_err(|_| "bridge state lock poisoned".to_string())?;

            let id = inner.next_id;
            inner.next_id += 1;

            let (tx, rx) = oneshot::channel();
            inner.pending.lock().unwrap().insert(id, tx);

            let mut req = serde_json::Map::new();
            req.insert("id".into(), Value::from(id));
            req.insert("method".into(), Value::from(method));
            if !params.is_null() {
                req.insert("params".into(), params);
            }
            let line = serde_json::to_string(&Value::Object(req)).map_err(|e| e.to_string())?;

            inner
                .stdin
                .write_all(line.as_bytes())
                .map_err(|e| format!("failed to write to bridge stdin: {e}"))?;
            inner
                .stdin
                .write_all(b"\n")
                .map_err(|e| format!("failed to write newline to bridge stdin: {e}"))?;
            inner
                .stdin
                .flush()
                .map_err(|e| format!("failed to flush bridge stdin: {e}"))?;

            (id, rx)
        };

        // Long timeout: some methods (pipeline.submit -> AI call, run.execute -> live Graph
        // writes) can legitimately take a while. The frontend shows its own spinner/progress UX;
        // this is a backstop against a genuinely hung PowerShell process, not a UX timeout.
        let timeout = Duration::from_secs(180);
        let resp = tokio::time::timeout(timeout, rx)
            .await
            .map_err(|_| format!("bridge call '{method}' timed out after {}s", timeout.as_secs()))?
            .map_err(|_| "bridge process closed its response channel unexpectedly".to_string())?;

        if let Some(err) = resp.get("error") {
            let msg = err
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("unknown bridge error");
            return Err(msg.to_string());
        }

        Ok(resp.get("result").cloned().unwrap_or(Value::Null))
    }
}

impl Drop for BridgeState {
    fn drop(&mut self) {
        // Best-effort graceful shutdown: ask the bridge to exit, then hard-kill if it doesn't.
        if let Ok(mut inner) = self.inner.lock() {
            let _ = inner.stdin.write_all(b"{\"id\":0,\"method\":\"shutdown\"}\n");
            let _ = inner.stdin.flush();
            let _ = inner.child.kill();
        }
    }
}
