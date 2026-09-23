# Evidence module

Read this when a load-bearing claim is contested or high-stakes, or when you notice "everyone says" with no visible origin.

## Appraise the claim, not the source

For each consequential claim ask only the dimensions that matter here:
- **Directness** — does it answer this question, or an adjacent one (other market, model, version, date)?
- **Rigor** — measured, filed or tested, versus asserted? What sample, method or record sits behind it?
- **Independence** — does it share an origin with the other "sources"?
- **Currency** — dated? Has anything since changed it?
- **Incentive** — who gains if the claim is believed?
- **Replication** — does anyone with a different method or incentive find the same?

Prestige is not strength. A wire service repeating a vendor press release is the press release.

## Lineage check (two searches at most)

1. Search the claim's distinctive figure or phrase together with "according to", "report", "analyst" or "sources say" to find the first appearance.
2. Read the origin's actual wording. Restatements usually drop the qualifier that matters ("in China", "in trials", "up to", "planned").

Record: `origin: <who, when> → repeated by N outlets; mutation: <what changed>`.

## Conflict resolution checklist

When two credible sources disagree, one of these usually explains it, and the explanation becomes a finding: definition · scope, market or region · product version or release · date · metric or unit · sample or population · the speaker's incentive · lineage.

## Retrieval and absence

Say precisely which applies: *not searched* · *searched, not located* (say where) · *located* · *located, not accessible* · *confirmed does not exist* (by whom). Not finding something is evidence about the search, not about the world.

## Source tiers by domain (primary → secondary → discovery)

- **Telecom and spectrum:** 3GPP specs, TDocs and meeting reports; FCC, NTIA and Ofcom dockets and auction results; SEC filings; earnings transcripts; GSMA and CTIA data → carrier and vendor press releases; Light Reading, Fierce, SDxCentral, RCR, Mobile World Live analysis → forums, LinkedIn posts.
- **Devices and mobile OS:** developer docs, release notes, OS and kernel source commits, FCC ID and certification listings, developer-conference sessions, teardowns (iFixit, TechInsights) → reporters and analysts with a scored track record, trade-press roundups → anonymous leakers, renders, concept videos.
- **AI/ML:** papers with code and evals, model cards, lab blogs, leaderboards, pricing pages → analyst notes, reputable newsletters → social media.
- **Trading and investing:** filings (10-K, 10-Q, 8-K, S-1), transcripts, regulator data, primary datasets → sell-side notes, financial press → forums, X.
- **Cloud, software and dev practices:** official docs, changelogs, RFCs, incident post-mortems, DORA and "State of X" surveys (check methodology) → conference talks, engineering blogs → opinion posts.
- **Security:** vendor advisories, CVE/NVD, CISA KEV, researcher write-ups with proof of concept → security press → social media.

Within a tier prefer the newest dated item. Across tiers, a lower tier can discover but not decide.

## Ledger line format

`[tag] claim — source (date) — role: primary | secondary | discovery | counter — independence: shares origin with #n? — bearing: supports / weakens <conclusion>`
