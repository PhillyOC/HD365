mod bridge;

use bridge::BridgeState;
use std::path::PathBuf;
use tauri::Manager;

/// Resolve the path to `Bridge-HD365.ps1`.
///
/// - Debug/dev builds run directly against the live repo checkout (two levels up from
///   `app/src-tauri`), so editing PowerShell files takes effect immediately without needing to
///   re-bundle resources.
/// - Release builds resolve the bundled `engine/` resource directory shipped inside the
///   installer (wired up in the packaging-release phase; `tauri.conf.json`'s `bundle.resources`
///   copies the engine files there).
fn resolve_bridge_script(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    #[cfg(debug_assertions)]
    {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        if let Some(repo_root) = manifest_dir.parent().and_then(|p| p.parent()) {
            let script = repo_root.join("Bridge-HD365.ps1");
            if script.exists() {
                return Ok(script);
            }
        }
    }

    let resource_dir = app
        .path()
        .resolve("engine", tauri::path::BaseDirectory::Resource)
        .map_err(|e| format!("could not resolve bundled engine resource dir: {e}"))?;
    Ok(strip_verbatim_prefix(resource_dir.join("Bridge-HD365.ps1")))
}

/// `app.path().resolve(..., BaseDirectory::Resource)` canonicalizes on Windows, which can
/// return an extended-length ("verbatim") path like `\\?\C:\Program Files\HD365\engine\...`.
/// Windows PowerShell 5.1 (`powershell.exe`) does not populate the `$PSScriptRoot` automatic
/// variable when invoked with `-File` against such a path - it comes back empty, which crashes
/// `Bridge-HD365.ps1` immediately (`Join-Path $PSScriptRoot ...` throws `ArgumentNull`) every
/// single time the packaged app starts. Stripping the `\\?\` prefix back to a normal
/// drive-letter path avoids the whole class of PowerShell verbatim-path quirks.
fn strip_verbatim_prefix(path: PathBuf) -> PathBuf {
    let s = path.to_string_lossy();
    if let Some(stripped) = s.strip_prefix(r"\\?\") {
        // Leave verbatim UNC paths (`\\?\UNC\server\share\...`) alone; they need the `\\` form
        // rewritten differently and aren't a path this app otherwise resolves to.
        if !stripped.to_ascii_uppercase().starts_with("UNC\\") {
            return PathBuf::from(stripped);
        }
    }
    path
}

#[tauri::command]
async fn bridge_call(
    state: tauri::State<'_, BridgeState>,
    method: String,
    params: Option<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let result = state.call(&method, params.unwrap_or(serde_json::Value::Null)).await;
    // Errors are always worth surfacing in the app's own log; full result payloads may contain
    // tenant/session data, so only echo those in debug builds for local diagnostics.
    match &result {
        Ok(_v) => {
            #[cfg(debug_assertions)]
            eprintln!("[hd365-bridge:ok] {method} -> {_v}");
        }
        Err(e) => eprintln!("[hd365-bridge:err] {method} -> {e}"),
    }
    result
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let script_path = resolve_bridge_script(&app.handle())
                .map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;
            let state = BridgeState::spawn(&script_path, None)
                .map_err(|e| -> Box<dyn std::error::Error> { e.into() })?;
            app.manage(state);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![bridge_call])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
