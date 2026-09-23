# Forecasting module

Read this when the question is "will X happen / do Y by when", a timeline, an adoption or market outcome, or a strategy prediction. SKILL.md still applies; this adds the procedure that turns evidence into a calibrated call that can be audited later.

## 1. Make the question resolvable

Rewrite the forecast as a statement a neutral observer could score on a date: **actor · event · scope · deadline**.
"Will AGI become reality within the next 1–2 years?" becomes "By 31 Dec 2028, a system from a frontier lab meets a named, pre-specified definition of AGI (a stated benchmark threshold plus independent verification)" and, separately, "…is described as AGI by at least three named expert bodies." Split compound questions. A vague question yields a vague probability nobody can check.

State the horizon. Probabilities drift toward even as horizons lengthen; a five-year call gets wider bands and more scenarios than a one-year call.

## 2. Outside view first: reference class and base rate

Before reading news, ask what class of events this belongs to and how often it happens:
- Same actor, same behaviour before (how often have frontier labs met their own stated timelines for capability milestones?).
- Same industry, other actors (how often do OEMs keep a feature after carriers stop pushing it?).
- Structural analogues (feature adoption curves; standards freeze → device lag; auction → build-out rules).

Write the base rate down with its reasoning. It is the anchor. The inside view adjusts it; it does not replace it.

## 3. Inside view: decompose into conditions

Break the outcome into the 2–5 things that must all hold, and estimate each:
`P(outcome) ≈ P(A) × P(B | A) × P(C | A, B)` — e.g. compute and data scaling continue at the current pace · the chosen definition is met on the benchmark · independent verification lands inside the window · no regulatory or safety pause blocks release.

Decomposition exposes the weakest link, and the weakest link is where the signposts live. Do not multiply blindly when conditions are correlated; say so and adjust.

## 4. Read the signals, ranked by how hard they are to fake

| Signal type | Weight | Examples |
|---|---|---|
| Committed money or irreversible action | highest | capex, spectrum purchases, supplier contracts, tape-outs, hiring, regulatory applications, standards contributions |
| Operative documents | high | specs, certification listings (FCC ID, Bluetooth SIG, 3GPP UE capability), SDK/API changes, release notes, patents with claims |
| Precedent behaviour | high | what the actor did in the last comparable cycle |
| Stated intent | medium | executive statements, roadmaps, guidance — discount by the speaker's incentive to say it |
| Supply-chain and analyst reports | medium–low | rank the reporter by track record; note who benefits from the leak |
| Rumors, renders, forum sentiment | low | discovery only; never load-bearing |
| Absence of a signal | context | meaningful only when you would expect the signal by now (no FCC filing four weeks before launch) |

Log each material signal in the ledger with tag, date and direction. Then ask: **would this signal look the same if the outcome were not going to happen?** If yes, it is not diagnostic; do not let it move the estimate.

Incentives and constraints usually beat rhetoric. Follow who pays, who profits, and what physically or legally blocks the path.

## 5. Update from the base rate, then run the calibration checks

Start at the base rate. Move only for diagnostic signals. Then:
- **Independent converging signals** justify moving further from even than feels comfortable. **Correlated signals** (same origin, same incentive) justify less.
- **Horizon** — the longer it is, the more you regress toward the base rate.
- **Status quo** — by default things keep doing what they are doing; a change needs a mechanism and a date.
- **Do not hide at 50%.** "Roughly even" claims the evidence is balanced; it is not an absence of a call. If you truly cannot tell, give a range (35–65%) and what would narrow it.
- **Would I bet at these odds?** If not, adjust until you would.
- **Pre-mortem** — it is two years later and you were wrong. What is the most likely reason? If that reason is plausible today, fold it in.

## 6. Scenarios (Targeted: 2–3 · Full: 3–4)

| Scenario | Probability | What has to be true | Early tell |
|---|---|---|---|

Probabilities sum to about 100%. Scenarios differ on a **mechanism**, not on adjectives; bull/base/bear without a mechanism is decoration.

## 7. Signposts and tripwires

List 3–8 checkable events with dates or windows, each with the direction it moves the estimate:
"A frontier lab reports the agreed benchmark threshold by mid-2027 → raises to likely." "Two consecutive frontier releases show flat scores on that benchmark → falls to unlikely."
Include at least one that would **break** the thesis. This is what makes the forecast auditable and refreshable.

## 8. Write the call

> **Call:** [event] is **likely (≈65%)** by [date]. **Confidence: moderate** — [one clause on evidence quality]. **Moves to very likely if** [signpost]; **to unlikely if** [signpost].

Then, in order: reference class and base rate (2 lines) · decomposition table · signals for and against (tagged, dated) · scenarios · signposts · what the record does not show.

## Domain notes

- **Corporate behaviour (OEMs, carriers, vendors):** precedent and committed money beat statements. Executives speak to move markets, regulators and suppliers.
- **Standards and regulatory timelines:** freeze dates slip; device availability lags a freeze by roughly 18–30 months; auctions lead deployment by whatever the build-out rules say. Check the rules, not the commentary.
- **Product rumors:** weight by the reporter's track record; a single-origin rumor is one signal however many outlets repeat it.
- **Markets and trading:** price already contains public information; the only edge is synthesis or something the market misweights. Say whether the call is about the **event** or about the **price**; they are different forecasts.
- **AI/ML trends:** separate research capability (papers, evals) from deployed usage (revenue, workflows, headcount). Narrative runs 1–3 years ahead of usage; measure adoption with money and headcount, not announcements.
