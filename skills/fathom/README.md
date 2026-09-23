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
| `references/domains/*.md` | Domain packs: primary sources, expert vocabulary, signpost calendar, pitfalls for telecom, ai-ml, investing, security, software-cloud, mobile-devices. | One pack per run, at Targeted/Full |
| `references/internal-sources.md` | The internal lane: searching your own emails, documents and intranet pages; tagging, weighing against public sources, confidentiality. | Loaded when the profile lists internal sources |
| `scripts/corpus.py` | Python indexer, searcher and bundler for on-prem material (.md .txt .html .eml .mbox .docx .pptx .xlsx .pdf); returns dated snippets, nothing leaves the machine. | Claude Code, or any PC with Python |
| `scripts/fathom-bundle.ps1` + `.cmd` | The bundler for Windows PCs without Python: PowerShell 5.1, nothing to install; reads .msg through Outlook when present; lists PDFs to attach alongside; detects and lists DRM-protected files. Double-click the `.cmd`. | Web-app users on Windows |
| `profile.template.md` | Slots for your own reader, sources, house style, defaults and standing signposts. Copy it; never edit SKILL.md. | Your copy is read on every run |
| `portable/PROTOCOL.md` | Everything above compressed into one file, under 8,000 characters. | Gemini Gems, Claude Projects |
| `portable/PROTOCOL-lite.md` | Same protocol at ~4,600 characters, leaving room for a profile in an 8,000-character box. | ChatGPT custom GPTs with a profile |
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

## Make it yours: the profile

Copy `profile.template.md` to `~/.claude/fathom-profile.md` (personal) or `<repo>/fathom-profile.md` (project) and fill the slots: who reads your briefs, your default domain pack and trusted sources, house style, defaults, standing signposts, and things to never do. Keep it under about 40 lines; it is loaded on every run. On Gemini and ChatGPT, paste the filled profile after the protocol in the instructions box.

Precedence when things conflict: prompt prefixes (`quick:`, `full:`, `domain: security`) > project profile > personal profile > domain pack > skill defaults. The evidence rules (tags, two axes, the Never list) cannot be overridden; that is what keeps briefs comparable across the team.

Do not edit `SKILL.md` or the references to personalize. Updates would overwrite your changes, and briefs from different people would stop being comparable.

## Using your own data: emails, documents, intranet

Team members keep their material on their own PCs. Fathom treats it as its own evidence lane, searched before the web, because a contract date or a test result changes which public questions matter. Organize it however you like; the only preparation is exporting into ordinary files: mail as `.eml` or `.mbox`, documents as they are (`.docx`, `.pptx`, `.xlsx`, `.pdf`, `.md`, `.txt`), intranet pages saved as HTML or printed to PDF.

**On the Claude, Gemini or ChatGPT web apps (most of the team).** The chat cannot read your disk, so you hand it the relevant slice. One command, run on your PC, indexes the folders you name, keeps the documents that match your question, and writes a single dated file:

Windows, nothing installed (most of the team): copy `scripts/fathom-bundle.ps1` and `fathom-bundle.cmd` anywhere, double-click the `.cmd`, and answer three prompts (folders, question terms, since-date). Or from a prompt:

```
fathom-bundle.cmd "D:\mail-export;D:\rf-team" "upper C-band filter decision" 2026-01
```

It reads `.md .txt .csv .json .html .eml .docx .pptx .xlsx` with nothing installed, and `.msg` through Outlook when it is present. PDFs are not extracted: the bundle lists them under "attach these separately" and you drop them into the chat next to the bundle, since Claude, Gemini and ChatGPT all read PDFs natively. Every Office call runs in a separate process with a 60-second deadline (`-OfficeTimeout`), because a hidden Office instance can stall on an invisible prompt; on timeout the file is skipped and listed. `-ForceOffice` routes Office-readable files through Word, Excel and PowerPoint instead of direct extraction, for the rare file the direct reader mishandles. If your PC blocks scripts, the `.cmd` already passes `-ExecutionPolicy Bypass` for that one run; if group policy forbids even that, ask IT or use the attach-files fallback below.

With Python (macOS, Linux, or Windows with Python):

```
python3 corpus.py bundle "upper C-band filter decision" --paths ~/mail-export ~/docs/rf-team --since 2026-01 --out fathom-bundle.md
```

Attach the bundle file to the chat with your question. The protocol recognizes the file, treats each block as an internal source with its path, date and author, heads the brief `INTERNAL`, and never pastes any of it into a web search. Defaults: up to 12 documents and about 300k characters per bundle (flags `--max-docs`, `--max-chars`, `--max-doc-chars`). If you type a local path into a web chat instead, the assistant replies with the exact bundle command rather than guessing.

**No script at all.** For a one-off question, attach the two to five files that matter (Claude allows 20 per chat, Gemini and ChatGPT about 10). Save emails from Outlook as `.txt` or print to PDF. The protocol treats attached files as internal sources and cites them by filename and the document's own date; the bundle only adds automatic selection from large folders and consistent metadata.

**In Claude Code.** Give paths in the prompt (`/fathom targeted: ... — use ~/docs/rf-team and ~/mail-export`) or list them once in your profile's `Internal sources` slot. The skill indexes and searches them itself, reading only matching snippets:

```
python3 ~/.claude/skills/fathom/scripts/corpus.py index ~/mail-export ~/docs/rf-team
python3 ~/.claude/skills/fathom/scripts/corpus.py search "upper C-band filter decision" --since 2026-01
```

Pages behind single sign-on can be pulled with `corpus.py fetch <url> --negotiate` (Kerberos) or `--cookies <jar>` and then indexed. The index lives in `./.fathom-corpus` (or `$FATHOM_CORPUS`), is plain text, and stays on the machine; add it to `.gitignore`.

**DRM-protected files.** These are encrypted on disk and unreadable to anything but authorized Office apps, so both bundlers detect and skip them and list them at the end of the bundle as "located, not accessible". Options, in order of how defensible they are: request decryption through your DRM release workflow and bundle the decrypted copies; read the document yourself and state the facts that matter in the chat; or, only with your DRM policy owner's approval, run the Windows bundler with `-OfficeForDrm`, which opens protected files through Word, Excel and PowerPoint as you and may get plaintext back (off by default, prints a warning, and depends on the DRM policy allowing it). Uploading a protected file directly to a web chat does not work either; the chat receives ciphertext.

**Connectors** (Drive, Gmail, SharePoint, Confluence, Slack, where your admin has enabled them) are a second internal source on the web apps; name them in your profile.

**Rules that apply everywhere:** internal claims keep the normal tags plus an `(internal)` marker and are cited by path, title, date and author; a brief that used any internal item is headed `INTERNAL` and lists those items separately so they can be stripped before external distribution; internal text is never pasted into a web search. Use org-managed plans (Claude Team/Enterprise, ChatGPT Business/Enterprise, Gemini via Workspace) for company material.

## Domain packs

`references/domains/` holds one file per domain with the primary sources that decide questions there, the vocabulary experts search with, a signpost calendar, and the domain's characteristic traps. The skill loads at most one per run, chosen from the question, your profile's default, or a `domain:` prefix. To add a domain, copy the closest pack, keep it under about 40 lines, and open a pull request; a pack is the right place for team knowledge that would otherwise live in someone's head.

## Reading the tags and the confidence language

- `[Stated]` the actor said it publicly (who, when). `[Observed]` a verifiable record or action. `[Inferred]` the assistant's read, with reasoning and confidence.
- Likelihood words map to ranges: almost certain 95–99% · very likely 80–95% · likely 55–80% · roughly even 45–55% · unlikely 20–45% · very unlikely 5–20% · remote 1–5%.
- Confidence (High / Moderate / Low) describes the evidence behind the judgment, not the odds of the event. The two always appear in separate sentences.

## Install

### Claude Code
Copy or symlink this folder into `~/.claude/skills/fathom/` (personal) or `<repo>/.claude/skills/fathom/` (project). Start a new session; it triggers automatically on research-shaped requests, or type `/fathom <question>`.

### Claude.ai
Either upload the packaged `fathom.skill` file under Settings → Capabilities → Skills, or create a Project and paste `portable/PROTOCOL.md` into the project instructions. Attach the `references/*.md` files and the domain packs as project knowledge if you want the full modules available; paste your profile after the protocol.

### Gemini (Gem)
Create a Gem. Paste `portable/PROTOCOL.md` followed by your filled profile into Instructions. Google's guidance recommends shorter instructions, but multi-thousand-character instructions work in practice; if the Gem misbehaves, use `portable/KERNEL.md` as the instruction and attach `PROTOCOL.md` plus the references as knowledge files (Gems accept up to 10). Turn on Google Search grounding.

### ChatGPT
Custom GPT: paste `portable/PROTOCOL-lite.md` plus your filled profile into Instructions (limit 8,000 characters; lite is ~4,600), enable Web Browsing, attach the `references/*.md` and `references/domains/*.md` files as Knowledge. Without a profile, the full `PROTOCOL.md` fits on its own. Personal custom instructions: paste `portable/KERNEL.md` (fits the 1,500-character field). Projects: PROTOCOL.md as project instructions.

## Why it is lean

- Framing before searching. A wrong frame is the most expensive search.
- Depth tiers with explicit search budgets (Quick ≤3, Targeted 4–10, Full per lane × entity).
- One query per evidence lane in expert vocabulary rather than fan-out by volume.
- A one-line-per-finding ledger instead of notes; the brief is written once from the ledger.
- Reference modules and domain packs load only when their trigger fires; hypothesis tables only when two explanations genuinely compete.
- Profiles are capped at about 40 lines so personalization never quietly becomes a second protocol.
- Subagents only at Full depth with three or more independent entities, and they return ledgers, not pages.

## Versioning

v1.0 — 2026-09-23. Feedback and refinements: keep the core under ~150 lines; put anything situational into a reference file with a clear trigger.
