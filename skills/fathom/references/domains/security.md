# Domain pack — security, vulnerabilities, threat activity

## Primary sources (decide)
- Vendor advisories and PSIRT pages; CVE/NVD entries; CISA KEV catalogue and advisories; GitHub security advisories; OS and platform monthly security bulletins.
- Researcher write-ups with proof of concept; conference talks with artefacts; exploit databases.
- Breach records: state attorney-general notifications, SEC 8-K Item 1.05 filings, court documents, regulator enforcement actions.
- Telemetry with methodology: GreyNoise, Shadowserver, Rapid7 Labs, honeypot reports.

## Secondary (frame, not decide)
Krebs on Security, BleepingComputer, The Record, Risky Business; vendor threat-intel reports (Mandiant, CrowdStrike, Microsoft, Google TAG) — real data, marketing incentive, tag both.

## Expert vocabulary for queries
CVSS and EPSS, KEV, zero-day / n-day, in-the-wild exploitation, TTPs, ATT&CK technique IDs, CWE class, SBOM, supply-chain compromise, secure boot, TEE, baseband and modem attack surface, SIM swap, eSIM provisioning, SS7 / Diameter, 5G core exposure, SASE, EDR bypass.

## Signpost calendar
- Patch Tuesday (second Tuesday); platform security bulletins (monthly); 90-day disclosure windows from researcher reports.
- Pwn2Own (spring and autumn), Black Hat / DEF CON (August), CISA KEV additions (rolling; a KEV add is an exploitation signal).
- Regulatory: incident-reporting deadlines (SEC four business days; EU NIS2 24/72 hours).

## Pitfalls specific to this domain
- Vulnerability ≠ exploitable ≠ exploited in the wild ≠ exploited at scale. Use the precise state; EPSS beats CVSS for likelihood.
- Attribution is inference; tag it [Inferred] with the confidence the reporting body gives.
- Proof-of-concept availability changes the base rate for exploitation; check whether one exists.
- Vendor threat reports count what their sensors see; sampling bias is structural.
- Never include exploit details beyond what the decision needs.
