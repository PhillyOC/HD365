//! Process manager for the HD365 PowerShell JSON-RPC bridge.
//!
//! Spawns `Bridge-HD365.ps1` once at app startup and keeps it alive for the lifetime of the
//! app. Requests/responses are newline-delimited JSON objects (`{id, method, params}` /
//! `{id, result}` / `{id, error}`) exchanged over the child's stdin/stdout. A background thread
//! reads response lines and resolves the matching pending call by id; `stderr` is drained to the
//! Rust app's own stderr for diagnostics AND kept as a rolling tail so a crash can be reported
//! back to the frontend instead of silently hanging until the call timeout.

use serde_json::Value;
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::oneshot;

#[cfg(windows)]
use std::os::windows::process::CommandExt;
// CREATE_NO_WINDOW (wincon.h). Without this, spawning a console-subsystem process
// (powershell.exe) from this GUI-subsystem app pops up a real (visible, briefly flashing)
// console window on Windows, even though stdio is fully redirected.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

type PendingMap = Arc<Mutex<HashMap<u64, oneshot::Sender<Value>>>>;
type StderrTail = Arc<Mutex<VecDeque<String>>>;
/// Set once the bridge process's stdout pipe closes (it exited/crashed). Holds a
/// human-readable reason (including any captured stderr) so future/pending calls can fail fast
/// instead of waiting out the full call timeout.
type DeathReason = Arc<Mutex<Option<String>>>;

const STDERR_TAIL_LINES: usize = 64;

struct BridgeInner {
    child: Child,
    stdin: ChildStdin,
    next_id: u64,
    pending: PendingMap,
}

/// Shared Tauri-managed state wrapping the live bridge child process.
pub struct BridgeState {
    inner: Mutex<BridgeInner>,
    dead: DeathReason,
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

        let mut cmd = Command::new("powershell.exe");
        cmd.args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        cmd.creation_flags(CREATE_NO_WINDOW);

        let mut child = cmd
            .spawn()
            .map_err(|e| format!("failed to spawn HD365 bridge process: {e}"))?;

        let stdin = child.stdin.take().ok_or("bridge process has no stdin handle")?;
        let stdout = child.stdout.take().ok_or("bridge process has no stdout handle")?;
        let stderr = child.stderr.take().ok_or("bridge process has no stderr handle")?;

        let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));
        let stderr_tail: StderrTail = Arc::new(Mutex::new(VecDeque::with_capacity(STDERR_TAIL_LINES)));
        let dead: DeathReason = Arc::new(Mutex::new(None));

        // Stderr drain thread: diagnostics (own stderr) + a rolling tail kept for crash reports.
        // Runs first / independently so its buffer is already populated by the time the stdout
        // reader thread below notices the process died and needs to explain why.
        {
            let stderr_tail = stderr_tail.clone();
            std::thread::spawn(move || {
                let reader = BufReader::new(stderr);
                for line in reader.lines() {
                    if let Ok(line) = line {
                        eprintln!("[hd365-bridge:stderr] {line}");
                        let mut tail = stderr_tail.lock().unwrap();
                        if tail.len() >= STDERR_TAIL_LINES {
                            tail.pop_front();
                        }
                        tail.push_back(line);
                    }
                }
            });
        }

        // Reader thread: one JSON response object per line -> resolve the matching pending call.
        // On EOF (process exited/crashed), immediately fail every pending call with a
        // diagnosable reason instead of leaving them to hang until the 180s call timeout.
        {
            let pending = pending.clone();
            let stderr_tail = stderr_tail.clone();
            let dead = dead.clone();
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

                // Bridge process exited (or closed stdout) - give a diagnosable reason and fail
                // every call still waiting right now (future calls check `dead` up front).
                let tail: Vec<String> = stderr_tail.lock().unwrap().iter().cloned().collect();
                let reason = if tail.is_empty() {
                    "HD365 bridge (PowerShell) process exited unexpectedly with no error output. \
                     It may have been blocked by antivirus, Group Policy execution restrictions, \
                     or 'powershell.exe' could not be found on PATH."
                        .to_string()
                } else {
                    format!(
                        "HD365 bridge (PowerShell) process exited unexpectedly. Last output:\n{}",
                        tail.join("\n")
                    )
                };
                eprintln!("[hd365-bridge] {reason}");
                *dead.lock().unwrap() = Some(reason.clone());

                let mut pending_map = pending.lock().unwrap();
                for (_id, tx) in pending_map.drain() {
                    let _ = tx.send(serde_json::json!({ "error": { "message": reason.clone() } }));
                }
            });
        }

        Ok(BridgeState {
            inner: Mutex::new(BridgeInner {
                child,
                stdin,
                next_id: 1,
                pending,
            }),
            dead,
        })
    }

    /// Send one JSON-RPC request and await its matching response (by id), with a timeout.
    pub async fn call(&self, method: &str, params: Value) -> Result<Value, String> {
        // Fail fast if the bridge process has already exited - no need to wait out a fresh
        // 180s timeout for a process that's already known to be gone.
        if let Some(reason) = self.dead.lock().unwrap().clone() {
            return Err(reason);
        }

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

            if let Err(e) = inner.stdin.write_all(line.as_bytes()) {
                inner.pending.lock().unwrap().remove(&id);
                return Err(self.dead_or(format!("failed to write to bridge stdin: {e}")));
            }
            if let Err(e) = inner.stdin.write_all(b"\n") {
                inner.pending.lock().unwrap().remove(&id);
                return Err(self.dead_or(format!("failed to write newline to bridge stdin: {e}")));
            }
            if let Err(e) = inner.stdin.flush() {
                inner.pending.lock().unwrap().remove(&id);
                return Err(self.dead_or(format!("failed to flush bridge stdin: {e}")));
            }

            (id, rx)
        };

        // Long timeout: some methods (pipeline.submit -> AI call, run.execute -> live Graph
        // writes) can legitimately take a while. The frontend shows its own spinner/progress UX;
        // this is a backstop against a genuinely hung PowerShell process, not a UX timeout.
        let timeout = Duration::from_secs(180);
        let resp = tokio::time::timeout(timeout, rx)
            .await
            .map_err(|_| format!("bridge call '{method}' timed out after {}s", timeout.as_secs()))?
            .map_err(|_| self.dead_or("bridge process closed its response channel unexpectedly".to_string()))?;

        if let Some(err) = resp.get("error") {
            let msg = err
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("unknown bridge error");
            return Err(msg.to_string());
        }

        Ok(resp.get("result").cloned().unwrap_or(Value::Null))
    }

    /// Prefer the captured crash reason over a raw IO error message, if one is available - it's
    /// almost always more useful (e.g. the actual PowerShell error) than "broken pipe".
    fn dead_or(&self, fallback: String) -> String {
        self.dead.lock().unwrap().clone().unwrap_or(fallback)
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
