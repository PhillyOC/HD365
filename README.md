# HelpDesk 365 AI (HD365)

Graph-first PowerShell assistant for Microsoft 365 helpdesk work: natural language → AI-planned discovery → solution one-liner (or bulk Graph `$batch` job) → `/run` with write warning + typed `EXECUTE` + local audit trail.

**Version:** see [`HD365.psd1`](HD365.psd1) / [`VERSIONING.md`](VERSIONING.md) · **Repo:** [github.com/PhillyOC/HD365](https://github.com/PhillyOC/HD365)

## Quick start

```powershell
# From a release zip, or clone:
.\Install-HD365.ps1
# Defaults: ai.provider = CopilotChat (needs M365 Copilot license)
.\Start-HD365.ps1
```

Or install via the Windows setup (`HD365-Setup-*.exe`) from [Releases](https://github.com/PhillyOC/HD365/releases).

In-session:

```text
HD365:Ready> /ai
HD365:Ready> create security groups for every Mexican state, nest Accounts Payable under each
```

Automatic flow:

1. **Discovery** — AI returns a read-only one-liner; host runs it immediately
2. **Solution** — AI returns a filled one-liner and/or `job.creates` for bulk
3. **`/run`** — executes (writes require typing `EXECUTE`)

Geography / taxonomy is **AI-driven** (any country/region/custom names). The host does not hardcode US state catalogs for planning.

## Safety model

| Phase | Graph scopes | Behavior |
|-------|--------------|----------|
| **Discovery** | Read / least + Copilot scopes when using CopilotChat | Auto-runs; write cmdlets blocked |
| **Solution** | — | Review / edit / copy one-liner (real data baked in) |
| **Execute** | Write catalog if needed | Warning + typed `EXECUTE` before writes |

Audit:

- `%LOCALAPPDATA%\HD365\audit\hd365-audit-YYYY-MM-DD.jsonl`
- `%LOCALAPPDATA%\HD365\audit\hd365-writes.jsonl` (writes only)
- Scripts: `%LOCALAPPDATA%\HD365\scripts\`

## Slash commands

`/help` `/ai` `/status` `/auth read|write` `/exo` `/run` (`/r`) `/edit` `/copy` `/cancel` `/audit` `/quit`

## AI providers

Configured in `%LOCALAPPDATA%\HD365\settings.json` (`ai.provider` + `ai.providers.*`). Type `/ai` in-session for an interactive status + switcher (includes a Copilot Chat API create-conversation probe), or jump straight to one with `/ai <Name>`:

| Provider | Notes |
|----------|-------|
| **CopilotChat** (default) | Microsoft 365 Copilot Chat API via Graph beta (`POST /beta/copilot/conversations`) |
| **AzureOpenAI** | Set `endpoint` + `deployment` + `HD365_AZURE_OPENAI_KEY` |
| **OpenAI** | Set `HD365_OPENAI_KEY` |
| **Anthropic** | Claude; set `HD365_ANTHROPIC_KEY` |
| **Gemini** | Google Gemini; set `HD365_GEMINI_KEY` |
| **Together** | Together AI (OpenAI-compatible); set `HD365_TOGETHER_KEY` |
| **Mistral** | Mistral AI (OpenAI-compatible); set `HD365_MISTRAL_KEY` |
| **Ollama** | Local models via `ollama serve`; no API key |

Complex natural language **requires AI** (`allowOfflineFallback` defaults to `false`).

### Home vs work (important)

- The **Windows/desktop Copilot app** is not HD365’s backend. HD365 uses the **Microsoft 365 Copilot Chat API** on Graph.
- That API needs a **work/school account with a Microsoft 365 Copilot add-on license**. Personal/home Graph sign-in can succeed (`/auth read` OK) while Chat API still returns **401/403/500**.
- Validate on a work laptop/tenant: `/auth read` → `/ai` (expect `CopilotApi = OK`) → then natural-language requests.

## Bulk jobs

When the AI returns `job.creates`, HD365 uses Graph `$batch` (20/request), parents first, optional nest membership. Prefer this for large matrices instead of megabyte one-liners.

## Your Graph consent list

Read/write catalogs live in `Config\scopes.json` (includes Copilot Chat scopes). Proposals advertise **least** scopes for the task; CopilotChat keeps Chat API scopes on the session so planning does not re-consent every phase.

## Modules used

- Microsoft Graph PowerShell SDK
- ExchangeOnlineManagement (classic DLs)
- ActiveDirectory RSAT when present
- Azure CLI when `az` is on PATH

## PIM / roles

Activate PIM roles in Entra as needed (e.g. Groups Administrator). HD365 documents suggested roles; it does not activate PIM for you yet.
