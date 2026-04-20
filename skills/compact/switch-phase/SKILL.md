---
name: switch-phase
description: Switch the active project phase. Takes one argument — requirements, architecture, or development. Loads the phase lens from docs/compact/phases/<phase>.md and updates Active phase in STATUS.md. Thin orchestrator; phase substance lives in data files.
---

## Argument

Phase name: one of `requirements`, `architecture`, `development`.

## Procedure

1. **Validate** the phase argument. If invalid, list the three valid options and abort.

2. **Load the phase file.** Read `docs/compact/phases/<phase>.md` in full. Adopt the posture described there for the remainder of the session.

3. **Update STATUS.md.** Set `Active phase: <phase>` and bump `Last updated` to today's date. No other edits.

4. **Confirm.** Tell the user:

   > "Active phase: <phase>. Posture: <one-line summary from the phase file>."

## Rules

- Do not change code as a side-effect of switching.
- Do not modify any file other than STATUS.md's Active phase and Last updated lines.
- If the user's described intent seems to mismatch the phase they requested (e.g., they describe architecture work but asked for development), flag the mismatch but do not override.
- If `docs/compact/phases/<phase>.md` is missing, abort and suggest `/project-init` (for a new project) or manual creation (to repair).
