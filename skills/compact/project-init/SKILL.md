---
name: project-init
description: Initialize a new project's AI scaffolding. Runs the 7-topic interview from the vendored meta-prompt, fuses answers with 3 base prompts to produce customized phase prompts (requirements/architecture/development), and scaffolds docs/compact/. Safe to decline. --re-init regenerates phase prompts only; never touches state files.
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

Check `docs/compact/phases/*.md`, `docs/compact/PROJECT.md`, `docs/compact/STATUS.md`.

- Fully present, no `--re-init` flag → abort with: "Project already initialized. Use `/project-init --re-init` to regenerate phase prompts without touching state."
- `--re-init` → load `docs/compact/project-init-interview.md` (if exists) as defaults.
- Otherwise → fresh init.

### 2. Run the 7-topic interview

Read `base-prompts/00-swdev-project-customizer.md` for interview structure. Present all 7 topics as a single batch for the user to answer in one pass:

1. **What we're building** — system description, core problem
2. **How we're building** — tech stack, frameworks, dependencies; module convention + visibility mapping (feeds `structure-conventions.md`)
3. **Stakeholder map & contribution surfaces** — for every stakeholder (devs, TPMs, QA, domain experts, end users): role, technical comfort, contribution type, required interface, and feedback loop. Drives Contributors table, architecture (surfaces as modules), and tech-stack choices.
4. **Domain constraints** — regulation, real-time needs, compliance, data sensitivity
5. **LLM access model** — runtime data / artifact visibility; restrictions if any
6. **Pain points** — common failures; what AI should catch
7. **Artifact preferences** — documentation, design, requirements formats

**Cross-topic check during the interview:** if topic 3 names stakeholders needing a UI / form / review queue and topic 2's stack can't support it, surface the gap and resolve before generating phase prompts.

If `--re-init`, show previous answers as defaults; user may edit any.

### 3. Persist answers

Write answers to `docs/compact/project-init-interview.md` with section headings per topic. This file is the source of truth for re-customization.

### 4. Customize phase prompts

For each base prompt (`01-...`, `02-...`, `03-...`), follow **all rules** in `00-swdev-project-customizer.md` — Customization rules, Base-section → 5-section mapping, Contribution surfaces as first-class design, Progressive loading, Sibling skills, Observability scaling, EIP calibration, and the per-phase wiring sections. The customizer is the single source of truth; this skill is the orchestrator that runs it.

Write customized prompts (~400-600 words each) to:

- `docs/compact/phases/requirements.md`
- `docs/compact/phases/architecture.md`
- `docs/compact/phases/development.md`

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
| `docs/compact/PROJECT.md` | Skeleton; user fills during requirements phase |
| `docs/compact/STATUS.md` | `Active phase: requirements`, dated today; Next pre-populated with "Fill in PROJECT.md during requirements phase" |
| `docs/compact/DECISIONS.md` | Empty header + comment template |
| `docs/compact/MAP.md` | Placeholder pointing at `regen-map` |
| `docs/compact/structure-conventions.md` | Derived from tech-stack answer (topic 2); for common stacks (Rust, Go, Python, TypeScript) produce a first draft; for polyglot or unusual stacks, scaffold with explicit prompts |

### 6. Print summary

- Files created: `<list>`
- Interview saved to: `docs/compact/project-init-interview.md`
- **Review `docs/compact/structure-conventions.md`** — it's derived from your tech-stack answer; confirm or edit before the first `regen-map` run.
- Next step: `/switch-phase requirements`

## Rules

- **Never overwrite** STATUS.md, PROJECT.md, DECISIONS.md, MAP.md on `--re-init`.
- Never run the interview without explicit user confirmation.
- Never fetch base prompts from the network without `--fetch-latest`.
- If the tech-stack answer is polyglot, explicitly note that `structure-conventions.md` needs manual extension per language.
