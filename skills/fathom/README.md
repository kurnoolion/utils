# Fathom

*Deep research, brief output.*

A lean research methodology for LLM assistants (Claude, Gemini, ChatGPT) that produces decision-grade briefs: bottom line first, every material claim tagged and dated, rival explanations tested, and calibrated forecasts with a separate confidence level and dated signposts.

It borrows the disciplines that earn their keep from heavier protocols (Research Pass, intelligence-community analytic standards, superforecasting) and drops the machinery that only makes a run look thorough.

## What is in this folder

| File | Purpose | Who loads it |
|---|---|---|
| `SKILL.md` | The core protocol (~120 lines). Always loaded when the skill triggers. | Claude Code / Claude.ai skills |
| `references/forecasting.md` | Base rate → decomposition → signal ranking → scenarios → signposts. | Loaded only for "will X do Y" questions |
| `references/evidence.md` | Claim appraisal, lineage check, conflict checklist, source tiers by domain. | Loaded only for contested or high-stakes claims |
| `references/brief-format.md` | Full-brief template and house style. | Loaded only at Full depth |
| `portable/PROTOCOL.md` | Everything above compressed into one file, under 8,000 characters. | Gemini Gems, ChatGPT custom GPTs, Claude Projects |
| `portable/KERNEL.md` | 1,500-character version for tight instruction fields. | ChatGPT personal custom instructions, quick paste |

## How to invoke it

Just ask the question. Optional prefixes control depth and type:

```
quick: what's the current status of the FCC upper C-band auction?
targeted: is L4S on Android actually shipping yet, or still iOS-only?
full: brief me on the 6G strategies of the three US Tier-1 carriers and what they mean for our modem roadmap
forecast: will AGI become reality within the next 1–2 years?
refresh: update briefs/l4s_android_mno.md — what changed since May 2026?
```

Every answer comes back as: bottom line → tagged evidence → counter-evidence → what we don't know → what would change this → signals to watch → sources. Forecasts add a probability word with a numeric range and a separate confidence level.

## Reading the tags and the confidence language

- `[Stated]` the actor said it publicly (who, when). `[Observed]` a verifiable record or action. `[Inferred]` the assistant's read, with reasoning and confidence.
- Likelihood words map to ranges: almost certain 95–99% · very likely 80–95% · likely 55–80% · roughly even 45–55% · unlikely 20–45% · very unlikely 5–20% · remote 1–5%.
- Confidence (High / Moderate / Low) describes the evidence behind the judgment, not the odds of the event. The two always appear in separate sentences.

## Install

### Claude Code
Copy or symlink this folder into `~/.claude/skills/fathom/` (personal) or `<repo>/.claude/skills/fathom/` (project). Start a new session; it triggers automatically on research-shaped requests, or type `/fathom <question>`.

### Claude.ai
Either upload the packaged `fathom.skill` file under Settings → Capabilities → Skills, or create a Project and paste `portable/PROTOCOL.md` into the project instructions. Attach the three `references/*.md` files as project knowledge if you want the full modules available.

### Gemini (Gem)
Create a Gem. Paste `portable/PROTOCOL.md` into Instructions. Google's guidance recommends shorter instructions, but multi-thousand-character instructions work in practice; if the Gem misbehaves, use `portable/KERNEL.md` as the instruction and attach `PROTOCOL.md` plus the references as knowledge files (Gems accept up to 10). Turn on Google Search grounding.

### ChatGPT
Custom GPT: paste `portable/PROTOCOL.md` into Instructions (limit 8,000 characters; PROTOCOL is ~7,000), enable Web Browsing, attach the `references/*.md` files as Knowledge. Personal custom instructions: paste `portable/KERNEL.md` (fits the 1,500-character field). Projects: PROTOCOL.md as project instructions.

## Why it is lean

- Framing before searching. A wrong frame is the most expensive search.
- Depth tiers with explicit search budgets (Quick ≤3, Targeted 4–10, Full per lane × entity).
- One query per evidence lane in expert vocabulary rather than fan-out by volume.
- A one-line-per-finding ledger instead of notes; the brief is written once from the ledger.
- Reference modules load only when their trigger fires; hypothesis tables only when two explanations genuinely compete.
- Subagents only at Full depth with three or more independent entities, and they return ledgers, not pages.

## Versioning

v1.0 — 2026-09-23. Feedback and refinements: keep the core under ~150 lines; put anything situational into a reference file with a clear trigger.
