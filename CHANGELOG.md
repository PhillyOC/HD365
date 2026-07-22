# Changelog

All notable changes to HD365 are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Desktop app: `powershell.exe` (the bridge child process) was spawned without the Windows
  `CREATE_NO_WINDOW` creation flag, so a real console window briefly flashed on screen every
  time the app started, even though stdio was fully redirected. It's now suppressed.
- Desktop app: if the PowerShell bridge process crashed or exited unexpectedly right after
  launch (bad `powershell.exe` path, AV/Group Policy block, script error, etc.), the app just
  sat on "Connecting to the HD365 engine..." for the full 180-second call timeout with no
  indication of what went wrong. `BridgeState` now captures a rolling tail of the bridge's
  stderr, detects the process exiting via stdout EOF, and immediately fails every
  pending/future call with a diagnosable error (including the captured PowerShell output)
  instead of hanging silently.
- Desktop app: `tauri.conf.json`'s `bundle.resources` entry for `engine/` made `cargo check` /
  `npm run tauri dev` / `cargo build` fail outright with `resource path 'engine' doesn't exist`
  on any checkout where `app/src-tauri/engine/` hadn't already been staged by
  `build\Build-HD365App.ps1` (tauri-build validates resource paths at compile time, for dev
  builds too, not just `tauri build`). A committed `app/src-tauri/engine/.gitkeep` placeholder
  (kept present via a `.gitignore` exception) now guarantees the directory always exists on a
  fresh clone; `Build-HD365App.ps1` restores it after each restage so `git status` stays clean.

## [0.2.1] - 2026-07-22

### Added
- Desktop app foundation: new JSON-RPC-over-stdio bridge (`Private\Invoke-HD365Bridge.ps1`,
  launched via `Bridge-HD365.ps1`) exposing the engine to a future Tauri + React/TypeScript
  desktop GUI. Methods: `ping`, `session.init`, `config.get`, `config.saveProvider`,
  `provider.catalog`, `ai.statusProbe`, `auth.connect`, `exo.connect`, `pipeline.submit`,
  `run.preview`, `run.execute`, `run.cancel`, `audit.tail`, `shutdown`.
- `Get-HD365RunPreview` / `Invoke-HD365ExecutePlan`: the write-confirmation gate that used to
  live entirely inside `Invoke-HD365ApprovedRun` is now two pure, non-interactive functions
  (no `Read-Host`) that any caller (console REPL or GUI) can drive. `Invoke-HD365ApprovedRun`
  is now a thin console wrapper around them; REPL behavior is unchanged.
- `Tests\Smoke-Bridge.ps1`: spawns the real bridge process and drives it over stdin/stdout to
  verify the JSON-RPC contract end to end.
- Desktop app scaffold (`app/`): Tauri 2 + React/TypeScript + Vite. Rust `BridgeState` process
  manager (`app/src-tauri/src/bridge.rs`) spawns `Bridge-HD365.ps1` once at startup and keeps it
  alive; a single generic `bridge_call(method, params)` Tauri command forwards JSON-RPC calls to
  it. In dev builds the Rust side runs directly against the live repo checkout; packaged builds
  will resolve a bundled `engine/` resource directory (wired up in a later packaging pass).
  Proven end to end: `ping` and `session.init` round-trip from React through Rust to the real
  PowerShell engine and back.
- Chat UI (`app/src/components/ChatView.tsx`): natural-language input -> `pipeline.submit` ->
  solution card (summary, platform, READ/WRITE badge, warnings, monospace one-liner) -> Copy /
  Edit / Cancel (client-side) / Run. Run calls `run.preview`; write proposals open a red
  write-warning modal requiring the exact confirmation phrase to be typed before `run.execute`
  fires, matching the console's typed-`EXECUTE` gate. Read-only proposals execute immediately.
  Results render in a result panel. `run.preview`/`run.execute` gained an optional
  `scriptOverride` param so a client-side Edit actually takes effect at Run time (parity with
  the console's `/edit`), without adding any new bridge methods.
- `app/src/components/ChatView.test.tsx`: Vitest + Testing Library component test that mocks
  only the Tauri `invoke` boundary and drives the real `ChatView` through a full write-proposal
  flow (submit -> solution card -> Run -> modal blocks until exact phrase typed -> execute ->
  result), asserting the exact bridge method call sequence.
- App shell now has a tab bar (Chat / AI Providers / Audit Log) and an expanded status header:
  clickable Graph and Exchange Online status pills (wired to `auth.connect` / `exo.connect`,
  showing live connect state) plus an active-AI-provider pill.
- `app/src/components/ProvidersView.tsx`: lists the full provider catalog via `provider.catalog`
  (configured/not-configured, active badge, env var / endpoint hints, notes) with a one-click
  "Use this provider" switch that calls `config.saveProvider` and refreshes the header badge.
- `app/src/components/AuditView.tsx`: tails the local audit log via `audit.tail` with a
  writes-only filter and a row-count selector; each row expands to show session/machine/graph
  mode, script text, and event data, matching the console's audit story in the GUI.
- Real HD365 app icon/branding: generated shield + headset + circuit mark, run through
  `tauri icon` for the full desktop icon set (`.ico`/`.icns`/PNGs), plus an in-app logo next to
  the header title and a proper favicon (desktop-only - Android/iOS icon sets were dropped).
- CSS design tokens: `app/src/App.css` now defines the dark theme as named custom properties
  (`--color-*`, `--radius-*`) in `:root` instead of scattered hex literals, so every component
  pulls from one palette.
- First-run onboarding (`app/src/components/Onboarding.tsx`): a "Welcome to HD365" checklist
  covering the Microsoft Graph module/connection, the active AI provider's configured state,
  and optional Exchange Online, each with an inline fix action (connect button, install
  command, or a jump to the AI Providers tab). Shown once (persisted via `localStorage`) and
  reopenable any time from a "Setup guide" pill in the header. Backed by a new bridge method,
  `session.prereqCheck` (module-installed / connected / active-provider-configured flags in one
  call), covered by `Tests\Smoke-Bridge.ps1` and `app/src/App.onboarding.test.tsx`.
- `build\Build-HD365App.ps1`: builds the HD365 desktop installer(s). Syncs the desktop app's
  version (`app/package.json`, `app/src-tauri/Cargo.toml`, `app/src-tauri/tauri.conf.json`) from
  the canonical `HD365.psd1` `ModuleVersion`, stages a fresh copy of the PowerShell engine
  (`HD365.psd1`/`psm1`, `Bridge-HD365.ps1`, `Private/`, `Public/`, `Config/`) into
  `app/src-tauri/engine/` as a Tauri bundle resource, runs `npm run tauri build`, and copies the
  resulting NSIS/MSI installer(s) into `dist/` as `HD365-Desktop-Setup-<version>.exe` /
  `HD365-Desktop-<version>.msi` (finds the real cargo target dir via `cargo metadata` so it
  works under redirected/sandboxed `CARGO_TARGET_DIR`s too, e.g. CI).
- `tauri.conf.json`: added `bundle.resources` (`engine/` -> `engine/`, preserving the
  `Private`/`Public`/`Config` subfolder structure `resolve_bridge_script` expects in release
  builds) plus publisher/description/category metadata for the installer.
- `.github/workflows/release.yml`: new `build-desktop` job (Node + Rust toolchain, `npm ci`,
  `Build-HD365App.ps1 -SkipInstall`) that attaches the desktop installer(s) to the same GitHub
  Release as the existing console zip/exe, on every `v*` tag push.

### Fixed

- `build\Export-HD365Work.ps1`: the desktop app itself was never included in the work export
  (`app/`, `build\Build-HD365App.ps1`, and the root `Bridge-HD365.ps1` launcher were simply not
  in its file list), but `Private\Invoke-HD365Bridge.ps1` and `Tests\Smoke-Bridge.ps1` were
  leaking in anyway because the export copies `Private/` and `Tests/` wholesale. Both are now
  explicitly stripped, and the now-dangling `'Start-HD365Bridge'` export is removed from the
  staged `HD365.psm1`/`HD365.psd1` so the trimmed module doesn't reference a function that no
  longer exists in that build. Verified locally: the staged module imports cleanly and exports
  exactly `Start-HD365`, `Get-HD365AuditLog`, `Connect-HD365`.

## [0.2.0] - 2026-07-22

### Added
- Provider-agnostic AI adapter layer (`Invoke-HD365Providers.ps1`): a single catalog +
  `Invoke-HD365ProviderChat` dispatcher shared by every provider
- New AI providers on the consumer line: OpenAI, Anthropic Claude, Google Gemini,
  Together AI, Mistral AI, and locally-running Ollama (in addition to CopilotChat
  and Azure OpenAI)
- Interactive `/ai` command: numbered menu of configured/unconfigured providers,
  switch by number or name, or jump straight to one with `/ai <Name>`
- `Save-HD365Config` persists provider switches to `%LOCALAPPDATA%\HD365\settings.json`
- `ai.providers.*` settings schema (per-provider model/baseUrl/endpoint/apiKeyEnvVar);
  legacy flat `ai.endpoint`/`deployment`/`apiKeyEnvVar`/`model` keys auto-migrate on load

### Changed
- `Invoke-HD365Ai` now dispatches through the shared provider adapter instead of a
  per-provider switch statement; JSON-parse retry is centralized for all providers
- Work-line export (`Export-HD365Work.ps1`) now ships a trimmed 2-provider
  (`CopilotChat` + `AzureOpenAI`) `Invoke-HD365Providers.ps1`, so Pro-only providers
  are excluded from the enterprise build entirely, not just hidden from the menu

## [0.1.0] - 2026-07-22

### Added
- Graph-first natural-language helpdesk assistant (PowerShell 5.1+)
- CopilotChat AI planner via Microsoft Graph beta Copilot Chat API
- Azure OpenAI / OpenAI provider adapters (consumer line)
- Two-pass pipeline: auto discovery (read) then solution one-liner / bulk job
- Graph `$batch` bulk create for AI `job.creates` matrices
- Write gate with typed `EXECUTE` confirmation and local JSONL audit trail
- Slash commands: `/help` `/ai` `/status` `/auth` `/exo` `/run` `/edit` `/copy` `/cancel` `/audit` `/quit`
- Copilot Chat API probe on `/ai` with home-vs-work license guidance
- Windows portable zip and Inno Setup installer packaging
- Work-line export script (Copilot-only trim for enterprise Copilot Git)

[Unreleased]: https://github.com/PhillyOC/HD365/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/PhillyOC/HD365/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PhillyOC/HD365/releases/tag/v0.1.0
