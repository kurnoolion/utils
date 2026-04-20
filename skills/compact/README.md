# COMPACT

**C**ontext · **M**emory · **P**rompt — **A**udited, **C**o-developed, **T**eam-locked.

A portable prompt/context/memory engineering framework for team-based AI-assisted software development. Works identically in Claude Code and Cline.

The name captures the core idea: memory-as-contract (a *compact* between human and AI) and tightly-packed team lockstep.

## What this is

A set of 7 skills plus templates that, together, give a team:

- **A shared ritual** — session-start to hydrate context, close-session to persist progress and decisions.
- **Phase discipline** — explicit Requirements / Architecture / Development lenses you switch between deliberately.
- **An auditable code map** — `MODULE.md` files co-located with code, plus a regenerated `MAP.md` so AI-generated code isn't a black box.
- **A decision log** — ADR-style `DECISIONS.md` where non-obvious choices are anchored; linked from `MODULE.md` for grounded "why" queries.

Designed to work identically across Claude Code (Anthropic) and Cline (any model, including team-internal LLMs). Both tools read `.claude/skills/` and share the `SKILL.md` format.

## Installation

Copy this directory's contents to `.claude/skills/` in a project repo (same path for both tools):

```bash
cp -r /home/mohan/work/utils/skills/compact/. /path/to/project/.claude/skills/
```

Add the auto-trigger one-liner. Tools read different files, so pick based on which tool(s) the team uses — both can coexist harmlessly in the same repo:

- **Claude Code users:** create `CLAUDE.md` at repo root.
- **Cline users:** create `.clinerules` at repo root.

```
At the start of any new conversation, invoke the `session-start` skill.
If the conversation has been auto-compacted since the last `session-start`,
re-invoke it before continuing work so Tier 1 state (PROJECT.md, STATUS.md,
active phase, relevant MODULE.md) is reloaded from disk.
```

**Cline also requires:** the VS Code Cline extension installed and its model provider configured (Base URL, API key, model ID). See `COMPACT_Overview.md` Part 8 for the full Cline setup — extension, provider config, `.clineignore`, and auto-approve settings (keep writes in `docs/compact/` **off** auto-approve — every memory-file edit should be human-reviewed).

Start a new Claude Code or Cline session. `session-start` will detect the uninitialized project and offer to run `/project-init`.

## Skills

| Skill | Purpose |
|---|---|
| `compact` | Orientation only. Prints the methodology overview and points to the sub-skills. Read-only. Invoke when onboarding or for a refresher. |
| `session-start` | Hydrate session: load PROJECT/MAP/STATUS + active phase file; surface state; ask intent; load task-specific `MODULE.md` on demand. |
| `switch-phase` | Switch between `requirements`, `architecture`, `development` lenses. Loads phase file; updates active phase in STATUS.md. |
| `close-session` | Recap work; two-pass decision triage; diff-based STATUS update; MODULE.md soft/hard-flag audit; conditional `regen-map`; propose commit. Never auto-writes. |
| `regen-map` | Regenerate `MODULE.md` Structure sections + rebuild `MAP.md` from code. Phase-aware orphan detection. Self-checking (reverts any curated-section edit). |
| `project-init` | Run the 7-topic interview, customize 3 phase prompts from base prompts, scaffold `docs/compact/`. `--re-init` regenerates phase prompts without touching state files. |
| `doctor` | Audit scaffold internal consistency: schema authorities, stale refs, skill inventory, step monotonicity, tool-neutral framing, path canonicalization, cross-file references. Read-only. Auto-invoked by `close-session` when scaffold files changed. |

## Artifacts produced by `project-init`

```
docs/compact/
  PROJECT.md                    # 1-page what we're building (human-curated)
  STATUS.md                     # Active phase + Done / In progress / Next / Flags
  DECISIONS.md                  # Append-only ADR log (immutable entries)
  MAP.md                        # Regen-generated module map + Mermaid
  structure-conventions.md      # Per-repo: what's a module, visibility mapping
  project-init-interview.md     # Persisted 7-topic answers (source for --re-init)
  phases/
    requirements.md             # Customized from base prompts
    architecture.md             # Customized from base prompts
    development.md              # Customized from base prompts

src/<module>/MODULE.md          # Co-located module docs (doc-first at architecture)
```

## The `MODULE.md` schema

Each module has a `MODULE.md` co-located with its code. Curated sections are hand-written (doc-first during architecture phase); the Structure section is regenerated from code by `regen-map`.

```markdown
# <module>

**Owner**: <name>          <!-- optional; add when a single contributor owns the module -->

**Purpose**
1-2 sentences.

**Public surface**
- `signature` — semantic, incl. non-obvious failure/return.
- `impl <Trait> for <Type>` — when callers rely on it.

**Invariants**
- Threading, state lifecycle, ordering guarantees.

**Key choices**
- <choice> — [D-XXX](../../docs/compact/DECISIONS.md#d-xxx)

**Non-goals**
- What this module deliberately does NOT do.

<!-- BEGIN:STRUCTURE -->
<!-- Regenerated by regen-map. Do not hand-edit. -->
<!-- END:STRUCTURE -->

**Depends on**: [mod-a](../mod-a/MODULE.md)
**Depended on by**: [mod-b](../mod-b/MODULE.md)
```

## Design principles

- **Markdown files hold substance; skills orchestrate.** Everything durable is plain markdown the team can read and edit.
- **Progressive loading.** Tier 1 (PROJECT + MAP + STATUS + active phase) always; `MODULE.md` on demand; `DECISIONS.md` entries only when referenced.
- **Propose, don't write.** Skills that change files always show diffs first.
- **Detect, don't auto-resolve.** Drift, orphans, and phase-boundary violations are surfaced — humans decide.
- **Deterministic regeneration.** `regen-map` output is byte-identical for byte-identical input. Diffs reflect real changes only.
- **Immutable decision log.** `DECISIONS.md` entries are never edited; they're superseded by new entries with forward/backward links.
- **Contributors drive design.** Stakeholder interfaces (web UIs, intake forms, correction queues) are first-class modules — not admin-tool afterthoughts.

## Contributors as design driver

AI-assisted projects fail when only devs can contribute. COMPACT pulls stakeholder involvement to Day 1: the `/project-init` interview captures **every** stakeholder (TPM, QA, domain expert, end user) with their contribution type, required interface, and feedback loop. That table goes into `PROJECT.md` and drives:

- **Architecture** — every non-trivial contribution surface becomes a first-class module with its own `MODULE.md`, designed doc-first.
- **Tech stack** — must support the interfaces stakeholders need (a CLI-only stack can't serve a TPM who needs a web UI; the mismatch surfaces during the interview).
- **Sessions** — `close-session` scans file-based contribution drop-paths each session and surfaces new stakeholder artifacts for review.

See the `Contributors` table in `PROJECT.md` (worked example in `project-init/templates/PROJECT.md`).

## Vendored base prompts

The `project-init/base-prompts/` directory contains snapshots of the prompt library at [github.com/kurnoolion/prompts-lib](https://github.com/kurnoolion/prompts-lib):

- `00-swdev-project-customizer.md` — the meta-prompt (7-topic interview + customization rules)
- `01-swdev-requirement-gathering.md` — requirements-phase base prompt
- `02-swdev-architecture-design.md` — architecture-phase base prompt
- `03-swdev-development-testing-debugging.md` — development-phase base prompt

Re-vendor periodically: `curl -o base-prompts/<file> https://raw.githubusercontent.com/kurnoolion/prompts-lib/main/<file>` or invoke `project-init --fetch-latest`.

## First-run flow

Slash-command syntax below is Claude Code. In Cline, invoke the same skills by natural request — e.g. `run the project-init skill`, `run the switch-phase skill with arg architecture`. See `COMPACT_Overview.md` Part 8 for the full Cline mapping.

1. User opens a new conversation in Claude Code or Cline.
2. `CLAUDE.md` / `.clinerules` one-liner triggers `session-start`.
3. `session-start` detects an empty `docs/compact/` and offers `/project-init`.
4. `/project-init` runs an optional preflight (import existing design docs into `docs/compact/design-inputs/`), the 7-topic interview, customizes phase prompts, and scaffolds state files.
5. `session-start` re-hydrates; user runs `/switch-phase requirements`.
6. User iterates on `PROJECT.md` (seeded from design inputs if provided); `/close-session` commits.
7. Next session: `/switch-phase architecture`; draft `MODULE.md` skeletons; `/close-session` captures decisions; `/regen-map` updates MAP.
8. Subsequent sessions: `/switch-phase development`; implement against the contracts in `MODULE.md`; `/close-session` audits.

**Bringing in existing design work:** if you drafted a design doc in Claude web, ChatGPT, or another tool before starting, `/project-init` asks for it upfront. Paste it or give a file path; it lands in `docs/compact/design-inputs/` and the generated requirements + architecture phase prompts automatically reference it as a starting proposal to refine. Greenfield projects just reply `skip`.

## Long sessions and auto-compaction

Claude Code auto-summarizes earlier portions of a conversation when approaching the context limit. The summary preserves intent but can lose specific file contents. COMPACT is designed to make this largely harmless — the authoritative state (`PROJECT.md`, `STATUS.md`, `DECISIONS.md`, `MAP.md`, active phase file, `MODULE.md` files) lives on disk, not in conversation history. What compaction can lose, a re-read can restore.

Three habits make this a non-issue in practice:

1. **Re-invoke `session-start` after compaction or when context feels stale.** It's idempotent and cheap — reloads Tier 1 from disk in a single pass. Trust the files over model recall.
2. **Checkpoint often with `close-session`.** Once progress is captured into `STATUS.md` + `DECISIONS.md`, a later compaction can lose chat detail without losing the work.
3. **Ask the AI to re-read before acting on specifics.** "Re-read `src/<module>/MODULE.md` before you propose that change." Good habit on any long-running task.

Cline doesn't auto-compact, so habits 1-3 are team ritual rather than tool-enforced. Claude Code users can optionally automate a post-compaction reminder by adding a `PreCompact` hook to the project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'COMPACT: conversation being auto-compacted. After compaction completes, re-invoke /session-start to re-hydrate state from disk (PROJECT.md, STATUS.md, active phase file, relevant MODULE.md).'"
          }
        ]
      }
    ]
  }
}
```

The hook's stdout becomes part of post-compaction context, so the reminder survives the summarization step. Verify the exact schema against current Claude Code hook docs — the `PreCompact` event and the `hooks[].hooks[].command` structure are the pieces you're targeting.

## Overview deck

`COMPACT_Overview.md` in this directory is a Marp presentation that walks a team through the methodology, workflow, and dual-tool (Claude Code + Cline) setup. Render with `marp COMPACT_Overview.md -o COMPACT_Overview.pptx`, or open in VS Code with the Marp extension for live preview.

## Status

This scaffold is the implementation of a design spec that is still evolving. Expect edits as real-world use surfaces gaps.
