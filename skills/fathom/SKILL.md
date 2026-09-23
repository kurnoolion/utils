---
name: fathom
description: Lean research protocol that produces a decision-grade brief — bottom line first, every material claim tagged [Stated]/[Observed]/[Inferred] with a dated source, rival explanations tested, and (for forward-looking questions) a calibrated forecast with probability words, a separate confidence level, and dated signposts. Use this whenever the user asks to research, investigate, assess, compare, "brief me on", or predict/forecast anything — telecom, AI/ML, trading/investing, technology, software practices, cloud, security, mobile OS/apps — even if they never say "research" or "brief". Also use for "is it true that…", "what's the status of…", "will X do Y by…", "should I expect…", and refresh/update runs on an earlier brief.
---

# Fathom — deep research, brief output

Purpose: reduce the uncertainty that matters for a decision, at the smallest cost that still gets the answer right. Most research spend is waste — repeated searches that return the same claim, pages fetched for one number, hypothesis tables built for points nobody contests, reports padded to look thorough. This protocol spends effort only where it changes the answer.

## The contract (what every brief delivers)

1. **Bottom line first.** The answer in 2–5 sentences a reader could stop at. Then evidence, then unknowns.
2. **Tagged claims.** Every material claim carries one tag and a dated source:
   - `[Stated]` — the actor said it publicly (who, when; quote or close paraphrase).
   - `[Observed]` — a verifiable action or record: filing, shipment, commit, auction result, spec, certification, measurement.
   - `[Inferred]` — your read. Give the reasoning in one clause and a confidence level.
   Readers act differently on a CEO's promise than on a filing, and differently again on your inference. Blurring them is how briefs mislead.
3. **Uncertainty on two separate axes** — likelihood and confidence — never merged into one word (Step 4).
4. **What would change the conclusion**, and for anything forward-looking, **dated signposts** to watch.
5. **What the record doesn't show**, stated as unknowns rather than smoothed over.

## Step 0 — Frame (before any search; five lines, to yourself)

- **Question behind the question** — what decision or belief does this serve? Research the underlying problem, not the wording.
- **Type** — fact/status · mechanism · comparison · cause · **forecast** · strategy/recommendation. Type decides what counts as evidence: a status question needs one dated primary source; a forecast needs base rates and diagnostic signals.
- **Anchor date and horizon** — today's date; for forecasts, the deadline by which the event must happen.
- **Starting belief** — the user's, or the conventional one, in a line. You will try to break it, not protect it.
- **Depth** — from the table below.

Ask the user a clarifying question only if the answer would change which research you do (ambiguous entity, missing region/jurisdiction, undefined horizon). Otherwise state the assumption in the brief and proceed.

## Step 1 — Pick a depth and a budget

| Depth | Use when | Searches | Page fetches | Output |
|---|---|---|---|---|
| **Quick** | one fact, status, definition, "is it true that" | ≤3 | 0–1 | ≤150 words + source |
| **Targeted** | one decision, dispute, comparison or forecast; updating one section | 4–10 | ≤4 | 300–1,200 words of prose; an evidence table and sources are extra |
| **Full** | multiple entities or dimensions, high stakes, leadership deliverable | one per lane × entity; parallelize when you can | as needed | structured brief per `references/brief-format.md` |

Default to the smallest depth that can answer. The user can force one with `quick:` / `targeted:` / `full:`. Budgets stretch when a search reveals the question was mis-framed; they do not stretch to look thorough.

## Step 2 — Investigate by lane, not by volume

Searches are cheap to run and expensive to read. Pick only the lanes that can change the answer, run one good query per lane in **expert vocabulary** (the words a 3GPP delegate, an FCC lawyer, a kernel maintainer or a sell-side analyst would use, not the user's phrasing), and read results as: claim · who · when · where it originated.

Lanes:
- **Current state** — what is true now. The newest dated primary source wins.
- **Primary / operative** — filings, specs and standards contributions, earnings transcripts, release notes, source code, official docs, regulator and court records.
- **Counter-evidence** — *required at Targeted and Full.* Search for the strongest version of "this is wrong" (add terms like criticism, delayed, fails, walked back, not true). Report one of: found and incorporated · found but not probative (say why) · none located in the searches run.
- **Incentives and constraints** — who profits, what it costs, what physically or legally blocks it. Usually decides forecasts.
- **Precedent** — what this actor did last time in the same situation; what comparable actors did.
- **Practitioner / field** — engineers, developers and operators reporting what actually happens (issue trackers, forums, teardowns). Discovery, not proof.
- **Lineage** — when a claim appears everywhere, find its origin. Twenty articles citing one analyst note are one source.

Rules that save effort without losing rigor:
- Fetch a page only when the snippet cannot carry a consequential claim or you need the exact figure, quote or date.
- Keep a **ledger**, one line per finding: `tag | claim | source, date | supports/weakens which conclusion`. Write nothing else while researching.
- **Stop when** the question is answerable at the chosen depth, counter-evidence has been sought, lineage is checked where it matters, and new searches return what you already hold. Do not search to feel complete.
- Never invent a source, quote, date or figure. If something could not be verified, write "unverified" and move on.

## Step 3 — Weigh

- **Rival explanations.** For any non-trivial conclusion, name the strongest alternative and the observation that would tell them apart. Build a hypothesis table only when two explanations genuinely compete on the evidence; otherwise one sentence.
- **Independence.** Count evidence streams, not citations. Two streams sharing an origin are one.
- **Conflicts are information.** When sources disagree, find out why (date, definition, region, version, incentive) before deciding. Never average them.
- **Discovery ≠ proof.** A rumor or forum post can locate a question; a filing or a measurement answers it.
- **Staleness.** Flag any load-bearing fact older than 12 months (or older than the last product cycle) as possibly moved.

For contested or high-stakes claims (money, legal, safety, a career decision) read `references/evidence.md` for the appraisal checklist and per-domain source tiers.

## Step 4 — State uncertainty on two axes

**Axis 1 — Likelihood** of the event or claim. Use these words with their ranges so briefs are comparable across authors:

| Word | Range |
|---|---|
| almost certain | 95–99% |
| very likely | 80–95% |
| likely | 55–80% |
| roughly even | 45–55% |
| unlikely | 20–45% |
| very unlikely | 5–20% |
| remote | 1–5% |

**Axis 2 — Confidence** in the judgment, i.e. the quality of the evidence behind it:
- **High** — several independent primary streams agree; mechanism understood; little left that could surprise.
- **Moderate** — credible but single-stream, partly indirect, or resting on one named assumption.
- **Low** — fragmentary, dated, conflicting, or mostly inference. Say what would raise it.

Pick one level; "low-moderate" tells the reader nothing. If two sub-claims deserve different levels, rate them separately.

Keep the axes in separate sentences: "AGI, on the definition stated in this brief, is *unlikely* (≈25%) to arrive by end-2028. Confidence: low — rests on extrapolated benchmark trends and lab statements; no agreed definition and no independent verification yet." A lone "probably" hides both.

Add **decision readiness** when the brief serves an action: *ready* · *ready with caveats* · *not ready — resolve X first*. A cheap, reversible action can be ready on thin evidence; an expensive one may not be ready even on a strong conclusion.

For forecasts and "will X do Y" questions, read `references/forecasting.md` before concluding. It adds the base-rate → decomposition → signal-ranking → scenarios → signposts procedure and the calibration checks.

## Step 5 — Write once

Write the brief in a single pass from the ledger. Shape by depth:

**Quick:** answer · qualification · dated source with a link.

**Targeted:** `Bottom line` (if forecasting: the event, the deadline it must happen by, likelihood, then confidence) · `Evidence` (tagged, dated; 3–8 bullets or one table with a "why it matters" column) · `Counter-evidence / rival read` · `What we don't know` · `What would change this` · `Signals to watch` (dated) · `Sources` (every entry linked and dated; a title without a URL cannot be checked).

**Full:** follow `references/brief-format.md` — executive summary, numbered sections per entity or dimension, cross-comparison table, unknowns, dated signals, grouped sources, optional one-page TLDR.

House style: direct analytic voice, numbered sections, tables with "why it matters" framing, no hedging filler, no padding to fill headings. Header line carries the date and "Currency: verified <date>". On a refresh of an earlier brief, lead with what changed and mark each earlier signpost fired / not fired / superseded.

## Effort discipline (why this stays lean)

- Frame first; a wrong frame is the most expensive search.
- One query per lane, expert vocabulary, budgets by depth.
- Ledger lines, not notes; no drafts; no tables for uncontested points.
- Load a reference file only when its trigger fires: forecast → `forecasting.md`; contested or high-stakes → `evidence.md`; Full → `brief-format.md`.
- Subagents (when the platform has them) only at Full depth with three or more independent entities or lanes; each returns a ≤400-word ledger, never raw pages.

## Never

Start by assuming the user's explanation is right · search only for confirmation · count repetition as confirmation · turn correlation into cause · average a contradiction · erase uncertainty while summarizing · cite what you did not inspect · pad.
