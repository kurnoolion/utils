# Brief format (Full depth)

Read this only at Full depth. Targeted and Quick shapes are in SKILL.md.

## Header

```
# <Title — what it means for <audience or decision>>
*Prepared <date>. Currency: verified <date>. Scope: <entities · region · horizon>. Depth: Full.*
```

## Sections

1. **Executive summary** — the one-page read: the one-line answer; a 3–4 sentence verdict per entity; a side-by-side table answering the core questions; the single biggest divergence or surprise; the top three actions for the reader. If forecasting, the call with likelihood and confidence sits here.
2. **Landscape in brief** — only what the reader needs. Assume domain fluency; a leadership reader knows the industry.
3. **One section per entity or dimension.** Each ends with: *what it means for <reader>* · a thesis paragraph with a confidence level · for forecasts, a projected timeline table: milestone / date / [Stated] or [Inferred] / evidence.
4. **Cross-comparison table** — rows are the dimensions the decision turns on. Include a "biggest vulnerability" row. Differentiate sharply; a table that concludes "everyone is doing everything" has failed.
5. **What we don't know** — blind spots per entity, and the questions worth putting to a human contact.
6. **Signals to watch** — dated, checkable events, each naming which thesis it confirms or breaks.
7. **Sources** — grouped by entity or category, linked, dated.

Omit any section that would add nothing. Never pad to fill a heading.

## TLDR (optional, 1–2 pages)

Headline · comparison table · the opening or the risk · top actions · watch-next timeline. Written last, from the brief, with no new claims.

## Conventions

- Tables carry a "Why it matters" column wherever the reader might ask "so what".
- Tags `[Stated]` `[Observed]` `[Inferred]` inline; `≈` for estimates; dates as "Sept 2026" or ISO.
- Direct analytic voice ("T-Mobile is buying leadership; Verizon is renting the narrative"). Bold the load-bearing phrase in a paragraph, not whole sentences.
- Cite inline as `[Source](url)` with the date on first mention. Group full links in Sources.
- No hedging filler ("it is important to note"), no throat-clearing, no restating the question.

## Deliverables and refreshes (Claude Code)

- Markdown master in the user's briefs folder; HTML/PDF via the existing conversion scripts there when asked; TLDR as `<name>_tldr.md`.
- Save the prompt that produced the brief as `_prompt_<name>.md` so a refresh run can diff against it.
- Refresh runs: read the earlier brief first; lead with "What changed since <date>"; mark each earlier signpost fired / not fired / superseded; keep the earlier structure so readers can diff.
