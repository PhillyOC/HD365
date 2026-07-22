# Changelog

All notable changes to HD365 are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Agnostic AI providers (Together AI, Anthropic, Ollama) for the consumer line

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

[Unreleased]: https://github.com/PhillyOC/HD365/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/PhillyOC/HD365/releases/tag/v0.1.0
