---
name: project-init
description: Initialize a new project's AI scaffolding. Runs the 7-topic interview from the vendored meta-prompt, fuses answers with 3 base prompts to produce customized phase prompts (requirements/architecture/development), and scaffolds docs/ai/. Safe to decline. --re-init regenerates phase prompts only; never touches state files.
---

## Preconditions

The following must exist under this skill's directory (`.claude/skills/project-init/`):

- `base-prompts/00-swdev-project-customizer.md` — the meta-prompt
- `base-prompts/01-swdev-requirement-gathering.md`
- `base-prompts/02-swdev-architecture-design.md`
- `base-prompts/03-swdev-development-testing-debugging.md`
- `templates/` — skeletons for scaffolded state files

If any base prompt is missing, abort: "Re-vendor base prompts from `github.com/kurnoolion/prompts-lib`."

## Arguments

- *(none)* — fresh init.
- `--re-init` — regenerate phase prompts only; do not touch state files.
- `--fetch-latest` — re-vendor base prompts from upstream before running.

## Procedure

### 1. Detect existing state

Check `docs/ai/phases/*.md`, `docs/ai/PROJECT.md`, `docs/ai/STATUS.md`.

- Fully present, no `--re-init` flag → abort with: "Project already initialized. Use `/project-init --re-init` to regenerate phase prompts without touching state."
- `--re-init` → load `docs/ai/project-init-interview.md` (if exists) as defaults.
- Otherwise → fresh init.

### 2. Run the 7-topic interview

Read `base-prompts/00-swdev-project-customizer.md` for interview structure. Present all 7 topics as a single batch for the user to answer in one pass:

1. **What we're building** — system description, core problem
2. **How we're building** — tech stack, frameworks, dependencies
3. **Team & contribution structure** — roles across design / development / validation / correction / evaluation
4. **Domain constraints** — regulation, real-time needs, compliance, data sensitivity
5. **LLM access model** — runtime data / artifact visibility; restrictions if any
6. **Pain points** — common failures; what AI should catch
7. **Artifact preferences** — documentation, design, requirements formats

If `--re-init`, show previous answers as defaults; user may edit any.

### 3. Persist answers

Write answers to `docs/ai/project-init-interview.md` with section headings per topic. This file is the source of truth for re-customization.

### 4. Customize phase prompts

For each base prompt (`01-...`, `02-...`, `03-...`), apply the customization rules from `00-swdev-project-customizer.md`:

- Inject domain terminology naturally (not appended).
- Add stack-specific guidance only where it materially changes behavior.
- Inject team-role/contribution structure from topic 3.
- If LLM access is limited (topic 5), augment with remote-collaboration patterns: diagnostic CLI, compact pasteable reports, structured error codes and fingerprints.
- Align output contracts with artifact preferences (topic 7).
- Calibrate EIP weighting by team experience level.

Write customized prompts (~400-600 words each) to:

- `docs/ai/phases/requirements.md`
- `docs/ai/phases/architecture.md`
- `docs/ai/phases/development.md`

Each phase prompt must follow the 5-section schema:

```
**Posture**: 1-2 lines.
**Load when entering**: files to prioritize.
**Do**: bullets.
**Don't**: bullets.
**Artifacts**: what this phase produces.
**Exit criteria**: when to switch out.
```

### 5. Scaffold state files (fresh init only)

**Skip this step entirely on `--re-init`.** Never overwrite state files.

Copy from `templates/` and fill in project-specific bits:

| File | Content |
|---|---|
| `docs/ai/PROJECT.md` | Skeleton; user fills during requirements phase |
| `docs/ai/STATUS.md` | `Active phase: requirements`, dated today; Next pre-populated with "Fill in PROJECT.md during requirements phase" |
| `docs/ai/DECISIONS.md` | Empty header + comment template |
| `docs/ai/MAP.md` | Placeholder pointing at `regen-map` |
| `docs/ai/structure-conventions.md` | Derived from tech-stack answer (topic 2); for common stacks (Rust, Go, Python, TypeScript) produce a first draft; for polyglot or unusual stacks, scaffold with explicit prompts |

### 6. Print summary

- Files created: `<list>`
- Interview saved to: `docs/ai/project-init-interview.md`
- **Review `docs/ai/structure-conventions.md`** — it's derived from your tech-stack answer; confirm or edit before the first `regen-map` run.
- Next step: `/switch-phase requirements`

## Rules

- **Never overwrite** STATUS.md, PROJECT.md, DECISIONS.md, MAP.md on `--re-init`.
- Never run the interview without explicit user confirmation.
- Never fetch base prompts from the network without `--fetch-latest`.
- If the tech-stack answer is polyglot, explicitly note that `structure-conventions.md` needs manual extension per language.
