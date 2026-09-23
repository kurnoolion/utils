# Internal sources module

Read this when the profile lists internal sources (a corpus folder, connectors) or the user points at on-prem material: emails, documents, decks, intranet pages, tickets. Internal material is often the most diagnostic evidence available and the easiest to mishandle, so it gets its own lane and its own rules.

## When the lane runs
- The user gives one or more paths in the prompt (these win over the profile), the profile has an `Internal sources` section, an attached file is headed `Fathom corpus bundle`, or the question is about the user's own organization, products or contacts.
- It runs **before** web lanes: internal facts (a contract date, a test result, a decision memo) reshape which public questions matter.

## How to search (Claude Code)
```
python3 <skill>/scripts/corpus.py index <folder>...        # once, then whenever material changes
python3 <skill>/scripts/corpus.py search "<expert terms>" --since 2026-01 --max 12
python3 <skill>/scripts/corpus.py show <doc_id> --lines 1:80
python3 <skill>/scripts/corpus.py fetch <intranet url> [--cookies FILE | --negotiate]   # then index
```
Search returns snippets with a doc id, path, date and type; read a whole document only when a snippet cannot carry the claim. Use the same expert vocabulary as the web lanes plus the organization's internal names for things (project codenames, ticket prefixes, team names from the profile). The store lives in `$FATHOM_CORPUS` or `./.fathom-corpus`; nothing leaves the machine.

Supported inputs: .md .txt .csv .json .html .eml .mbox .docx .pptx .xlsx .pdf (PDF needs `pdftotext`). Intranet pages behind SSO: export them (save as HTML or print to PDF) into the corpus folder, or use `fetch` with a cookie jar or Kerberos negotiate.

## How it works on the web apps (claude.ai, Gemini, ChatGPT)
The model cannot read a path on the user's PC. The user runs one command locally, which indexes the folders they name, keeps the documents that match the question, and writes a single dated file:
```
python3 corpus.py bundle "<the question's expert terms>" --paths <folder>... --since 2026-01 --out fathom-bundle.md
```
or, on a Windows PC without Python, `fathom-bundle.cmd "<folders separated by ;>" "<terms>" <since>` (PowerShell, nothing to install). They attach that file with the question, plus any PDFs the bundle lists under "Attach these PDFs separately" (the Windows bundler does not extract PDFs; the chat reads them natively). Raw attached files without a bundle are internal sources too: cite by filename and the document's own date. A file headed `Fathom corpus bundle` **is** the internal lane: each `## [id] title` block carries path, date, type and author; cite those. Do not re-derive; do not ask for the originals unless a block says it was truncated and the truncated part matters.

If the user types a local path into a web chat, do not guess at the contents. Reply with the exact bundle command above (Python or the Windows `.cmd`, substituting their path and the question's terms), or invite them to attach the few files that matter, and continue with the public lanes meanwhile, marking the internal lane *not yet run*.

Platform connectors (Drive, Gmail, SharePoint, Confluence, Slack, where an admin has enabled them) are a second internal source; query them with the same expert terms and cite by location, title, date and author.

## Tagging and citing
- Keep the three tags. An email in which a vendor promises a date is `[Stated]` (who, when, in what). A test log, a signed contract, a dated decision record is `[Observed]`.
- Cite as `path or connector · title · date · author`, never a bare "internal source". Readers must be able to find it.
- Mark internal-derived claims with `(internal)` after the tag so a reader can strip them before sharing outside: `[Observed (internal)]`.

## Weighing internal against public
- Internal is usually **newer and more specific**; public is usually **broader and independently checkable**. When they conflict, say which is newer and whether the internal item could be a draft, a single person's view, or superseded.
- One internal email is one stream. Count it once, however many threads quote it.
- Dates: use the document's own date (email header, document metadata), not the file's copy date, and say when the two differ.

## Confidentiality
- If any internal source is used, put `INTERNAL — contains company material` in the header line and list the internal items in a separate `Internal sources` block at the end so they can be removed for external distribution.
- Never paste internal text into a web search or a fetch prompt. Search the web with generic terms; use the internal detail only to judge results.
- Follow the profile's `Never name` and classification rules; when unsure whether something can be quoted, paraphrase and cite the location.

## DRM-protected files (enterprise document DRM)
Enterprise document DRM keeps files encrypted on disk and decrypts them only inside authorized applications for an authenticated user. Anything that reads the bytes directly, including both bundlers and a web-chat upload, sees ciphertext.

- Both bundlers detect this (an Office file that is not a valid zip, a PDF without its header, text that does not decode) and **skip** the file, listing it at the end of the bundle under "Skipped: appear DRM-protected or encrypted". Treat every entry there as *located, not accessible* and say so in the brief; the reader decides whether to request decryption.
- The sanctioned route is the organization's DRM release workflow: request, approval, decrypted copy, audit trail. Decrypted copies then go through the bundler like any file.
- The Windows bundler has an opt-in `-OfficeForDrm` switch that opens protected files through Word, Excel and PowerPoint as the logged-in user, which the DRM agent may decrypt on the fly. It exports protected content into an unprotected file, which is exactly what the DRM exists to prevent; it is off by default, prints a policy warning when used, and must only be used with the DRM policy owner's agreement. Whether it works at all depends on the DRM policy; some hook the application object model.
- Without either, the fallback is a human in the loop: the user reads the document and states the two or three facts that matter in the chat, cited as internal document · title · date. Tag them [Stated (internal)] or [Observed (internal)] as usual.

## Absence
"Searched the corpus for X, not located" is a finding worth one line: it tells the reader the organization has no record, or that the corpus is incomplete. Say which you believe, and why.
