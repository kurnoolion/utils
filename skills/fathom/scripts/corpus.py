#!/usr/bin/env python3
"""fathom corpus — index and search on-prem material (emails, documents, saved intranet pages).

Stdlib only. Optional: `pdftotext` (poppler) for PDFs.

  corpus.py index  <folder>... [--corpus DIR]          extract text + dates into the corpus store
  corpus.py search "<terms>" [--since YYYY-MM[-DD]] [--max N] [--type eml|pdf|...] [--corpus DIR]
  corpus.py show   <doc_id> [--lines A:B] [--corpus DIR]
  corpus.py fetch  <url> [--cookies FILE] [--negotiate] [--corpus DIR]   save an intranet page via curl
  corpus.py bundle "<terms>" [--paths FOLDER...] [--since YYYY-MM] [--max-docs N] [--max-chars N] [--out FILE]
                                                     write one markdown file to attach to a web chat
  corpus.py stats  [--corpus DIR]

The store lives in $FATHOM_CORPUS or ./.fathom-corpus. Search returns snippets with doc id, path,
date and type so the caller reads only what matters. `bundle` is for teammates on the Claude, Gemini or
ChatGPT web apps: it packs the matching documents into a single file they attach to the chat.
Nothing here leaves the machine unless you attach the bundle yourself.
"""
import argparse, email, email.policy, hashlib, html, json, mailbox, os, re, subprocess, sys, time, zipfile
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

TEXT_EXT = {".md", ".txt", ".csv", ".json", ".rst", ".log"}
HTML_EXT = {".html", ".htm", ".xhtml"}
STOP = set("the a an and or of to in for on with by is are was were be been this that from as at it its into not no".split())

def corpus_dir(arg):
    d = Path(arg or os.environ.get("FATHOM_CORPUS") or ".fathom-corpus")
    d.mkdir(parents=True, exist_ok=True)
    return d

def strip_html(s):
    s = re.sub(r"(?is)<(script|style|nav|footer|header)[^>]*>.*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>", "\n", s)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    return re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n\n", s)).strip()

def html_title(s):
    m = re.search(r"(?is)<title[^>]*>(.*?)</title>", s)
    return html.unescape(m.group(1)).strip() if m else None

def xml_text(zf, name, tag):
    try:
        data = zf.read(name).decode("utf-8", "ignore")
    except KeyError:
        return ""
    parts = re.findall(rf"<{tag}[^>]*>(.*?)</{tag}>", data, flags=re.S)
    out = html.unescape(" ".join(parts))
    return re.sub(r"\s+", " ", out).strip()

def extract_docx(p):
    with zipfile.ZipFile(p) as zf:
        data = zf.read("word/document.xml").decode("utf-8", "ignore")
        data = re.sub(r"</w:p>", "\n", data)
        text = re.sub(r"<[^>]+>", "", data)
        core = zf.read("docProps/core.xml").decode("utf-8", "ignore") if "docProps/core.xml" in zf.namelist() else ""
    title = re.search(r"<dc:title>(.*?)</dc:title>", core)
    date = re.search(r"<dcterms:modified[^>]*>(.*?)</dcterms:modified>", core)
    return html.unescape(text), (title.group(1) if title else None), (date.group(1)[:10] if date else None)

def extract_pptx(p):
    with zipfile.ZipFile(p) as zf:
        slides = sorted(n for n in zf.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n))
        text = "\n\n".join(f"[slide {i+1}] " + xml_text(zf, n, "a:t") for i, n in enumerate(slides))
    return text

def extract_xlsx(p):
    with zipfile.ZipFile(p) as zf:
        return xml_text(zf, "xl/sharedStrings.xml", "t")

def extract_pdf(p):
    try:
        out = subprocess.run(["pdftotext", "-layout", str(p), "-"], capture_output=True, text=True, timeout=120)
        return out.stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None

def email_to_text(msg):
    hdr = {k: msg.get(k, "") for k in ("From", "To", "Cc", "Date", "Subject")}
    body = ""
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is not None:
        payload = part.get_content()
        body = strip_html(payload) if part.get_content_type() == "text/html" else payload
    head = "\n".join(f"{k}: {v}" for k, v in hdr.items() if v)
    date = None
    try:
        date = parsedate_to_datetime(hdr["Date"]).strftime("%Y-%m-%d") if hdr["Date"] else None
    except Exception:
        pass
    return head + "\n\n" + (body or ""), hdr.get("Subject") or None, date, hdr.get("From") or None

def looks_encrypted(p, ext):
    """True when a file's bytes cannot be what its extension claims — the signature of DRM/encryption at rest."""
    try:
        head = p.read_bytes()[:65536]
    except OSError:
        return False
    if not head:
        return False
    if ext in {".docx", ".pptx", ".xlsx"}:
        return not zipfile.is_zipfile(p)
    if ext == ".pdf":
        return not head.lstrip().startswith(b"%PDF")
    if ext in TEXT_EXT | HTML_EXT | {".eml", ".mbox"}:
        try:
            head.decode("utf-8")
        except UnicodeDecodeError:
            try:
                head.decode("utf-16")
                return False
            except UnicodeDecodeError:
                return True
        ctrl = sum(1 for b in head if b < 9 or 13 < b < 32)
        return ctrl / len(head) > 0.05
    return False

def skipped_path(cd): return cd / "skipped.json"
def load_skipped(cd):
    sp = skipped_path(cd)
    return json.loads(sp.read_text()) if sp.exists() else {}

def file_date(p):
    return datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%d")

def extract(p):
    """Yield (text, title, date, author, kind) records for one file (mbox yields many)."""
    ext = p.suffix.lower()
    if ext == ".mbox":
        for msg in mailbox.mbox(str(p), factory=lambda f: email.message_from_binary_file(f, policy=email.policy.default)):
            t, title, date, author = email_to_text(msg)
            yield t, title, date or file_date(p), author, "eml"
        return
    if ext == ".eml":
        with open(p, "rb") as f:
            msg = email.message_from_binary_file(f, policy=email.policy.default)
        t, title, date, author = email_to_text(msg)
        yield t, title, date or file_date(p), author, "eml"; return
    if ext in TEXT_EXT:
        t = p.read_text(errors="ignore")
        m = re.search(r"^#\s+(.+)$", t, flags=re.M)
        yield t, (m.group(1) if m else None), file_date(p), None, ext[1:]; return
    if ext in HTML_EXT:
        raw = p.read_text(errors="ignore")
        yield strip_html(raw), html_title(raw), file_date(p), None, "html"; return
    if ext == ".docx":
        t, title, date = extract_docx(p); yield t, title, date or file_date(p), None, "docx"; return
    if ext == ".pptx":
        yield extract_pptx(p), None, file_date(p), None, "pptx"; return
    if ext == ".xlsx":
        yield extract_xlsx(p), None, file_date(p), None, "xlsx"; return
    if ext == ".pdf":
        t = extract_pdf(p)
        if t is None:
            print(f"skip (pdftotext not available): {p}", file=sys.stderr); return
        yield t, None, file_date(p), None, "pdf"; return

def manifest_path(cd): return cd / "manifest.jsonl"

def load_manifest(cd):
    mp = manifest_path(cd)
    if not mp.exists(): return {}
    return {json.loads(l)["id"]: json.loads(l) for l in mp.read_text().splitlines() if l.strip()}

def cmd_index(args):
    cd = corpus_dir(args.corpus); man = load_manifest(cd); skipped = load_skipped(cd); n_new = n_skip = 0
    for folder in args.folders:
        for p in sorted(Path(folder).rglob("*")):
            if not p.is_file() or p.name.startswith("."): continue
            ext = p.suffix.lower()
            if ext not in TEXT_EXT | HTML_EXT | {".eml", ".mbox", ".docx", ".pptx", ".xlsx", ".pdf"}: continue
            if looks_encrypted(p, ext):
                skipped[str(p)] = {"reason": "appears DRM-protected or encrypted at rest", "date": file_date(p), "type": ext[1:]}
                continue
            skipped.pop(str(p), None)
            key = f"{p.resolve()}|{p.stat().st_mtime_ns}"
            for i, rec in enumerate(extract(p) or []):
                text, title, date, author, kind = rec
                if not text or not text.strip(): continue
                doc_id = hashlib.sha1(f"{key}|{i}".encode()).hexdigest()[:10]
                if doc_id in man: n_skip += 1; continue
                (cd / f"{doc_id}.txt").write_text(text)
                man[doc_id] = {"id": doc_id, "path": str(p), "title": title or p.name, "date": date,
                               "author": author, "type": kind, "chars": len(text), "indexed": time.strftime("%Y-%m-%d")}
                n_new += 1
    with open(manifest_path(cd), "w") as f:
        for rec in man.values(): f.write(json.dumps(rec) + "\n")
    skipped_path(cd).write_text(json.dumps(skipped, indent=1))
    print(f"indexed {n_new} new document(s), {n_skip} unchanged; store: {cd} ({len(man)} total)")
    if skipped:
        print(f"skipped {len(skipped)} file(s) that appear DRM-protected or encrypted (listed in bundles; request decryption through your DRM workflow):", file=sys.stderr)
        for path in list(skipped)[:10]: print(f"  {path}", file=sys.stderr)

def terms_of(q):
    return [t.lower() for t in re.findall(r"[A-Za-z0-9][\w.\-/]*", q) if t.lower() not in STOP and len(t) > 1]

def match(cd, man, query, since=None, type_=None, recent_bonus=None):
    """Rank corpus documents against query terms. Returns [(score, rec, matched_terms, snippet, text)]."""
    terms = terms_of(query) if query else []
    recent_bonus = recent_bonus or time.strftime("%Y-%m-%d", time.gmtime(time.time() - 180 * 86400))
    hits = []
    for rec in man.values():
        if type_ and rec["type"] != type_: continue
        if since and (rec["date"] or "") < since: continue
        text = (cd / f"{rec['id']}.txt").read_text(errors="ignore"); low = text.lower()
        if not terms:
            hits.append((0, rec, [], "", text)); continue
        counts = {t: low.count(t) for t in terms}
        matched = [t for t, c in counts.items() if c]
        if not matched: continue
        score = len(matched) * 10 + min(sum(counts.values()), 50) + (5 if (rec["date"] or "") >= recent_bonus else 0)
        first = min(low.find(t) for t in matched)
        lo = max(0, first - 160); hi = min(len(text), first + 320)
        snippet = re.sub(r"\s+", " ", text[lo:hi]).strip()
        hits.append((score, rec, matched, snippet, text))
    hits.sort(key=lambda h: (-h[0], h[1]["date"] or ""))
    return hits

def cmd_search(args):
    cd = corpus_dir(args.corpus); man = load_manifest(cd)
    if not man: print("corpus is empty — run: corpus.py index <folder>", file=sys.stderr); sys.exit(1)
    terms = terms_of(args.query)
    if not terms: print("no searchable terms", file=sys.stderr); sys.exit(1)
    hits = [h[:4] for h in match(cd, man, args.query, args.since, args.type, args.recent_bonus)]
    if not hits: print(f"no matches for: {' '.join(terms)}"); return
    print(f"{len(hits)} match(es) for [{' '.join(terms)}], showing {min(len(hits), args.max)}\n")
    for score, rec, matched, snippet in hits[:args.max]:
        who = f" · {rec['author']}" if rec.get("author") else ""
        print(f"[{rec['id']}] {rec['date'] or '????-??-??'} · {rec['type']}{who} · {rec['title']}\n    {rec['path']}\n    terms: {', '.join(matched)}\n    …{snippet}…\n")

def cmd_show(args):
    cd = corpus_dir(args.corpus); man = load_manifest(cd)
    rec = man.get(args.doc_id)
    if not rec: print("unknown doc id", file=sys.stderr); sys.exit(1)
    lines = (cd / f"{rec['id']}.txt").read_text(errors="ignore").splitlines()
    a, b = 1, len(lines)
    if args.lines:
        a, b = (int(x) if x else d for x, d in zip(args.lines.split(":"), (1, len(lines))))
    print(f"# {rec['title']} — {rec['path']} ({rec['date']}, {rec['type']}, lines {a}-{b} of {len(lines)})\n")
    print("\n".join(lines[a - 1:b]))

def cmd_fetch(args):
    cd = corpus_dir(args.corpus)
    cmd = ["curl", "-sSL", "--max-time", "60", args.url]
    if args.cookies: cmd += ["-b", args.cookies]
    if args.negotiate: cmd += ["--negotiate", "-u", ":"]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        print(f"fetch failed: {out.stderr.strip()[:200]}", file=sys.stderr); sys.exit(1)
    inbox = cd / "fetched"; inbox.mkdir(exist_ok=True)
    name = re.sub(r"[^\w.-]+", "_", args.url.split("//", 1)[-1])[:120] + ".html"
    (inbox / name).write_text(out.stdout)
    print(f"saved {inbox / name}; now run: corpus.py index {inbox}")

def cmd_bundle(args):
    cd = corpus_dir(args.corpus)
    if args.paths:
        ns = argparse.Namespace(corpus=args.corpus, folders=args.paths); cmd_index(ns)
    man = load_manifest(cd)
    if not man: print("corpus is empty — pass --paths <folder>... or run: corpus.py index <folder>", file=sys.stderr); sys.exit(1)
    hits = match(cd, man, args.query, args.since, args.type)
    if not hits: print("no matching documents; nothing written", file=sys.stderr); sys.exit(1)
    today = time.strftime("%Y-%m-%d"); out = Path(args.out or f"fathom-bundle-{today}.md")
    budget = args.max_chars; parts = []; included = 0
    head = (f"# Fathom corpus bundle — {today}\n\n"
            f"Query: {args.query or '(all documents)'} · since: {args.since or 'any'} · documents: {{n}} of {len(hits)} matched\n\n"
            "Internal material exported from the author's own files. Treat every item below as an internal source: keep the tags, "
            "add the (internal) marker, cite as path · title · date · author, and head the brief INTERNAL. "
            "Do not paste any of this text into a web search.\n\n---\n")
    for score, rec, matched, snippet, text in hits[: args.max_docs]:
        body = text.strip()
        if len(body) > args.max_doc_chars:
            body = body[: args.max_doc_chars] + f"\n\n[… truncated at {args.max_doc_chars} chars of {len(text)}; ask the author for the rest]"
        block = (f"\n## [{rec['id']}] {rec['title']}\n"
                 f"- path: {rec['path']}\n- date: {rec['date'] or 'unknown'} · type: {rec['type']}"
                 + (f" · author: {rec['author']}" if rec.get('author') else "")
                 + (f"\n- matched terms: {', '.join(matched)}" if matched else "") + "\n\n" + body + "\n")
        if budget - len(block) < 0 and included > 0: break
        parts.append(block); budget -= len(block); included += 1
    skipped = load_skipped(cd)
    roots = [str(Path(f).resolve()) for f in (args.paths or [])]
    skipped = {k: v for k, v in skipped.items() if not roots or any(str(Path(k).resolve()).startswith(r) for r in roots)}
    tail = ""
    if skipped:
        tail = (f"\n---\n\n## Skipped: appear DRM-protected or encrypted ({len(skipped)} file(s))\n\n"
                "These files exist but could not be read; treat them as *located, not accessible*. "
                "Ask the author to request decryption through the DRM workflow if their content matters.\n\n"
                + "".join(f"- {k} ({v['type']}, modified {v['date']})\n" for k, v in list(skipped.items())[:50]))
    out.write_text(head.replace("{n}", str(included)) + "".join(parts) + tail)
    msg = f"wrote {out} — {included} document(s), {out.stat().st_size:,} bytes."
    if skipped: msg += f" {len(skipped)} DRM-protected/encrypted file(s) listed as skipped."
    print(msg + " Attach it to your chat with the question.")

def cmd_stats(args):
    cd = corpus_dir(args.corpus); man = load_manifest(cd)
    by = {}
    for r in man.values(): by[r["type"]] = by.get(r["type"], 0) + 1
    dates = sorted(r["date"] for r in man.values() if r["date"])
    print(f"store: {cd}\ndocuments: {len(man)}  by type: {by}\ndate range: {dates[0] if dates else '-'} → {dates[-1] if dates else '-'}")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus", help="store directory (default $FATHOM_CORPUS or ./.fathom-corpus)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("index"); s.add_argument("folders", nargs="+"); s.set_defaults(fn=cmd_index)
    s = sub.add_parser("search"); s.add_argument("query"); s.add_argument("--since"); s.add_argument("--type")
    s.add_argument("--max", type=int, default=12); s.add_argument("--recent-bonus", default=time.strftime("%Y-%m-%d", time.gmtime(time.time() - 180 * 86400)), help=argparse.SUPPRESS); s.set_defaults(fn=cmd_search)
    s = sub.add_parser("show"); s.add_argument("doc_id"); s.add_argument("--lines"); s.set_defaults(fn=cmd_show)
    s = sub.add_parser("fetch"); s.add_argument("url"); s.add_argument("--cookies"); s.add_argument("--negotiate", action="store_true"); s.set_defaults(fn=cmd_fetch)
    s = sub.add_parser("bundle"); s.add_argument("query", nargs="?", default="")
    s.add_argument("--paths", nargs="+", help="index these folders first"); s.add_argument("--since"); s.add_argument("--type")
    s.add_argument("--max-docs", type=int, default=12); s.add_argument("--max-chars", type=int, default=300_000)
    s.add_argument("--max-doc-chars", type=int, default=40_000); s.add_argument("--out"); s.set_defaults(fn=cmd_bundle)
    s = sub.add_parser("stats"); s.set_defaults(fn=cmd_stats)
    args = ap.parse_args(); args.fn(args)

if __name__ == "__main__":
    main()
