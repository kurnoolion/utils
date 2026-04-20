---
name: close-session
description: Close a work session. Recaps work (user-authoritative), captures decisions via two-pass triage, updates STATUS.md via diff, audits MODULE.md curated-section edits with soft/hard flag classification, triggers regen-map if structure changed, and proposes a commit. Never auto-writes; never auto-commits.
---

Propose-don't-write throughout: every change is a diff the user approves.

## Procedure

### 1. Recap

Summarize the session: files touched, tasks completed, problems encountered. Show to user.

Ask:

> "Does this match your memory? Anything missing?"

Long sessions have lossy recall — **treat the user's memory as authoritative.** Incorporate any additions before proceeding.

### 2. Propose STATUS.md update

Load current `docs/compact/STATUS.md`. Draft diffs:

- Completed items: move **In progress → Done** (add today's date).
- Add new **In progress** items started mid-session.
- Update **Next** based on what logically follows.
- Preserve existing structure. **Do not rewrite wholesale.**

Show the diff. Wait for approval before writing.

### 3. Capture decisions — two-pass triage

**Pass 1 (triage).** Scan the session for candidates that match the DECISIONS filter:

- Reversing would take >1 day of rework.
- A reviewer would reasonably ask "why not X?"
- Multiple options were actually considered.
- Affects module boundaries, public APIs, or persistent data shapes.
- Deliberate perf / correctness / security tradeoff.

Present candidates as a numbered list with one-line summaries. Ask the user to mark each: `log` / `skip` / `unsure`.

**Pass 2 (capture).** For each `log` and `unsure` item, walk the decision template by asking plain-language questions:

- "What problem prompted this?" → **Context**
- "What did we choose?" → **Decision**
- "Why this over the alternatives?" → **Why**
- "What does this force on us?" → **Consequences**

**Never fabricate rationale.** If the user can't answer a field, mark it `TODO` and add the item to STATUS.md Flags.

Assign the next sequential `D-XXX` ID. Show the drafted entry. On approval, append to `docs/compact/DECISIONS.md`.

### 4. Audit MODULE.md edits

For each `src/<module>/MODULE.md` touched this session:

Diff curated sections (Purpose, Public surface, Invariants, Key choices, Non-goals, Depends on / Depended on by) against the last committed version.

Classify any changes:

- **Hard flag** — signature change; invariant change; Non-goal *removed*; dependency added/removed. Require one of: capture as decision, revert, or explicit note added to STATUS.md Flags.
- **Soft flag** — purely additive: trait/interface impl added; Public surface item added with new signature; Invariant *added* (not changed); Non-goal *added*. Offer: capture as decision / accept as idiomatic (keep MODULE.md edit, no DECISIONS entry) / revert.

### 5. Detect structural changes

If any of: new module added, module renamed, module deleted, or dependency edges changed → **invoke `regen-map`**.

Otherwise skip regen and tell the user which case applied.

Surface `regen-map`'s full output, including any self-check reverts.

### 6. Produce summary

- Files changed in `docs/compact/` and `src/**/MODULE.md`.
- Unresolved items → write to STATUS.md **Flags** section for next session.
- Draft commit message: short imperative; reference any new `D-XXX` IDs.

### 7. Commit decision

Show the full diff once more. Ask: `commit` / `stage only` / `abort`.

- `commit` → commit with the drafted message.
- `stage only` → `git add` the changes; leave commit to the user.
- `abort` → do nothing further. Writes from steps 2, 3, 4 are **not** reverted — they were approved individually.

**Never auto-commit. Never skip diff review.**

## Rules

- Docs-only skill. Never modify code.
- Never auto-log decisions without user confirmation.
- Never invent decision rationale — ask the user or mark `TODO`.
- Never rewrite STATUS.md wholesale — update in place.
- Never silently accept curated-section changes in MODULE.md.
- Output should be PR-quality: a reviewer should be able to skim it.
