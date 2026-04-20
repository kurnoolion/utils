---
name: session-start
description: Hydrate a new session with project context. Reads state files, shows current status, asks user what they're working on, then loads task-specific context on demand. Invoke at the start of any new conversation.
---

Hydrate enough context to be productive without burning the context window. Progressive loading: Tier 1 always, Tier 2 on demand, Tier 3 on reference.

## Procedure

### 1. Detect project state

Check for:
- `docs/ai/phases/requirements.md`
- `docs/ai/phases/architecture.md`
- `docs/ai/phases/development.md`
- `docs/ai/STATUS.md`
- `docs/ai/PROJECT.md`

If any phase file is missing:

> "This project isn't fully initialized. Run `/project-init`? (yes/no)"

If yes → invoke `project-init`, then continue. If no → continue with whatever files exist; note that capability is limited.

### 2. Load Tier 1 context (read-only)

Read if present:
- `docs/ai/PROJECT.md` — 1-page what we're building
- `docs/ai/MAP.md` — module layout + Mermaid
- `docs/ai/STATUS.md` — current state
- `docs/ai/phases/<active-phase>.md` — based on STATUS.md "Active phase"

**Do not load at this stage:** `DECISIONS.md`, any `MODULE.md`, `structure-conventions.md`.

Target budget: ≤5K tokens for Tier 1.

### 3. Surface state to the user

Display a compact briefing:

- **Project**: <first line of PROJECT.md>
- **Active phase**: <phase | "not set">
- **In progress**: <list from STATUS.md>
- **Next**: <list from STATUS.md>
- **Flags from last session**: <STATUS.md "Flags" section, if non-empty>
- **Uncommitted in docs/ai/**: <`git status --porcelain docs/ai/` summary, if any>

### 4. Check staleness signals

Flag any of:
- An "In progress" item with date >7 days old.
- No active phase set.
- Non-empty Flags section.

### 5. Ask intent

> "What are you working on in this session?"

### 6. Act on intent — Tier 2 load

- Task references specific modules → load their `MODULE.md` files.
- Task clearly doesn't match active phase → suggest `/switch-phase <x>`. **Do not auto-switch.**
- Task is vague → ask clarifying questions per active phase's posture.
- User wants general Q&A with no phase → skip phase adoption.

### 7. Confirm ready

End with: "Context loaded. Ready."

## Rules

- **Read-only.** Never modify files.
- Never load `MODULE.md` files proactively — only in response to a stated task.
- Never auto-invoke `/switch-phase`, `/project-init`, or any side-effecting skill.
- If a Tier 1 file is malformed, report and continue with the rest.
- If `PROJECT.md` exceeds ~2K tokens, flag that it may have drifted from "1 page."
- If `MAP.md` exceeds ~3K tokens, load only the module list; skip the diagram.
