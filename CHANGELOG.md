# Changelog

All notable changes to HD365 are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
