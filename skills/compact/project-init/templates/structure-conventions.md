# Structure conventions

Defines what counts as a "module" in this repository and how language-native visibility maps to `pub` / `internal` for the `regen-map` skill.

Populated during `project-init` from the tech-stack answer. Edit as conventions evolve.

## Module definition

<!-- example: "Each top-level directory under src/ is a module. A module's MODULE.md lives at src/<module>/MODULE.md." -->

## Visibility mapping

<!--
Example (Rust):
  - `pub` → pub
  - `pub(crate)` → internal
  - `pub(super)` → internal
  - (no qualifier) → internal

Example (Go):
  - Exported (Capitalized) → pub
  - Unexported (lowercase) → internal

Example (TypeScript):
  - `export` / `export default` → pub
  - non-exported → internal
  - Interfaces implemented by exported types → pub

Example (Python):
  - Listed in `__all__` → pub
  - Leading underscore → internal
  - Otherwise → pub
-->

## Module doc schema

Each module has `src/<module>/MODULE.md` with the following curated sections (plus a regen-only Structure section):

- **Owner** *(optional)* — single contributor owning the module; omit if shared or unassigned.
- **Purpose** — 1-2 sentences.
- **Public surface** — signatures + semantics. Includes trait / interface implementations callers rely on.
- **Invariants** — what callers can count on (threading, state, ordering).
- **Key choices** — each linked to DECISIONS.md by `[D-XXX]`.
- **Non-goals** — deliberate omissions.
- **Structure** — regen-only; bounded by `<!-- BEGIN:STRUCTURE -->` / `<!-- END:STRUCTURE -->`; never hand-edited.
- **Depends on** / **Depended on by** — links to other MODULE.md.

## Polyglot note

If this repo uses more than one language, extend the Visibility mapping section with a subsection per language.
