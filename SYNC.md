# HD365 line sync / firewall

HD365 has two independent distribution lines that share a name and most workflows.
"pro" and "work" are **chat-only labels** — never hardcoded in product code.

| Line | Where it lives | AI | Who uses it |
|------|----------------|----|-------------|
| Consumer (pro) | GitHub `PhillyOC/HD365`, local `E:\MS365\HD365` | CopilotChat + other providers over time | Personal / startup |
| Enterprise (work) | Work laptop → Copilot Git (GitHub blocked at work) | **CopilotChat only** | Employer environment |

## Ethical firewall

1. **No employer resources into the consumer line.** Nothing authored on employer
   equipment, time, or accounts may be committed to `PhillyOC/HD365` or `E:\MS365`.
2. **Work receives changes only via export.** Run `build\Export-HD365Work.ps1` on a
   personal machine; carry the zip to the work laptop; push to Copilot Git from there.
3. **No shared remotes.** The two repos have unrelated histories. Syncs are deliberate,
   reviewed ports — never auto-merge, never pull from Copilot Git into GitHub.
4. **Copilot-only on work.** The export script strips OpenAI/Azure OpenAI paths and
   API-key setup. Do not reintroduce non-Copilot providers into the work line.
5. **No cross-promotion.** Work packages must not reference the startup/consumer product.

## How Cursor ports changes

When asked to "port X to work":

1. Land the change on the consumer line first (or on `C:\HD365` staging).
2. Re-run `Export-HD365Work.ps1` so the work zip is Copilot-trimmed.
3. Do **not** push to Copilot Git from this home machine (unreachable / out of policy).
4. Leave the zip for manual carry to the work laptop.

When asked to "port X to pro": only after confirming the change was created on personal
time/hardware — never copy employer-authored material into GitHub.
