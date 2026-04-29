# Installing Ollama models behind a corporate gateway

A workflow for installing Ollama models when `ollama pull` is blocked by a
corporate TLS-inspecting / SSE proxy (Cloudflare Zero Trust, Zscaler, Netskope,
etc.) but plain HTTPS to `huggingface.co` still works.

Two scripts:

| Script | Where it runs | What it does |
|---|---|---|
| `Download-OllamaModel.ps1` | Work PC (Windows / PowerShell) | Lists GGUF files in a HuggingFace repo, picks the matching quantization, downloads them |
| `install-ollama-model.sh`  | Linux box where `ollama serve` runs | Stages the GGUF into Ollama's content-addressed blob store and writes a registry-style manifest |

Plus matching test runners: `Test-DownloadOllamaModel.ps1`, `test-install-ollama-model.sh`.

---

## 1. Why `ollama pull` fails

The exact error is:

```
Error: pull model manifest: realm host "" does not match original host "registry.ollama.ai"
```

**What's happening.** Ollama's pull does:

1. `GET https://registry.ollama.ai/v2/...` → real registry returns
   `401 Unauthorized` with header
   `Www-Authenticate: Bearer realm="https://auth.ollama.ai/token",service="ollama"`.
2. Ollama parses `realm`, fetches a token from that host, retries with the
   token, gets the manifest.

A corporate Cloudflare/Zscaler/etc. gateway intercepts step 1, replaces the
response with a `301` redirect or block page, and **strips the
`Www-Authenticate` header**. Ollama parses an empty realm → host `""` →
mismatch with `registry.ollama.ai` → it bails with the error above.

**Confirming it.**

```bash
curl -v https://registry.ollama.ai/v2/ 2>&1 \
  | grep -iE 'location|server|cf-ray|www-authenticate'
```

- `location: /v2/` (a self-redirect) and **no `Www-Authenticate`** → gateway
  is rewriting the response.
- Check the cert issuer to tell apart "real Cloudflare-fronted registry" vs
  "corporate MITM":

  ```bash
  openssl s_client -connect registry.ollama.ai:443 \
    -servername registry.ollama.ai </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject
  ```

  - **Public CA** (Google Trust Services, DigiCert, Let's Encrypt) → real
    registry; you're being challenged or rate-limited by Cloudflare itself.
    Try a different network.
  - **Corporate CA** ("Acme Corp Root CA", "Cloudflare for Teams", "Zscaler",
    etc.) → corporate TLS inspection. Solve with IT or with this workflow.

---

## 2. End-to-end workflow

### Step A — On the work PC, find and download the GGUF

```powershell
# Optional: validate the script first (no Pester needed)
.\Test-DownloadOllamaModel.ps1            # offline tests
.\Test-DownloadOllamaModel.ps1 -Online    # live HF API check

# Download
.\Download-OllamaModel.ps1 `
  -RepoUrl https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF `
  -Quant   Q8_0 `
  -OutputPath C:\models\qwen3-embedding-4b
```

Quant rule of thumb (Qwen3-Embedding-4B sizes):

| Quant      | Size (~) | When to pick |
|------------|----------|--------------|
| `Q4_K_M`   | 2.5 GB   | smallest reasonable quality |
| `Q5_K_M`   | 2.9 GB   | balanced |
| `Q6_K`     | 3.3 GB   | near-lossless, slightly slower |
| `Q8_0`     | 4.3 GB   | very close to FP16 — **default for embeddings** |
| `F16`/`BF16` | 8 GB   | full precision |

Embedding quality is more sensitive to quantization than chat quality, so
prefer `Q8_0` for embedding models. For chat models, `Q4_K_M`–`Q5_K_M` is fine.

### Step B — Move the GGUF to the Linux box

Any way you like (USB, scp, OneDrive, etc.). Land it at e.g.
`/tmp/Qwen3-Embedding-4B-Q8_0.gguf`.

### Step C — On the Linux box, install it

```bash
# Optional: run the test suite first (uses a temp dir, no real Ollama needed)
chmod +x test-install-ollama-model.sh
test-install-ollama-model.sh

# Install — recommended: run as root for a system-wide, multi-user install
chmod +x install-ollama-model.sh
sudo install-ollama-model.sh \
  -f /tmp/Qwen3-Embedding-4B-Q8_0.gguf \
  -n qwen3-embedding -t 4b

# Verify (as any user on the host)
ollama list
ollama show qwen3-embedding:4b
curl http://localhost:11434/api/embeddings \
  -d '{"model":"qwen3-embedding:4b","prompt":"hello world"}'
```

---

## 3. `Download-OllamaModel.ps1` reference

### Parameters

| Parameter      | Required | Description |
|----------------|----------|-------------|
| `-RepoUrl`     | yes      | HuggingFace repo URL or `<user>/<repo>` id. Accepts `https://huggingface.co/...`, `.../tree/<branch>`, `.../blob/...`, plain id. |
| `-Quant`       | yes      | Quant tag, case-insensitive: `Q8_0`, `Q4_K_M`, `F16`, `BF16`, etc. Must be the **full token** — `Q5` won't match `Q5_0`. |
| `-OutputPath`  | yes      | Local directory. Created if missing. |
| `-Branch`      | no       | Default `main`. |
| `-ListOnly`    | no       | Show what would be downloaded, don't fetch. |

### Behavior

- Calls `https://huggingface.co/api/models/<repo>/tree/<branch>` to list files.
- Filters to `.gguf` files; matches the requested quant against names like
  `*-Q8_0.gguf`, `*.Q8_0.gguf`, `*_Q8_0.gguf`, `*-Q8_0-00001-of-00003.gguf`.
- For sharded models, downloads **all parts**, sorted ascending.
- Verifies download size against the size returned by the HF API; refuses to
  accept a partial file.
- If `curl.exe` is on PATH, uses it (resumable, real progress bar). Otherwise
  falls back to `Invoke-WebRequest` with progress UI suppressed (much faster).
- If a file already exists at the destination with the right size, skips it
  (idempotent).

### Caveats

- **The HF LFS CDN is a separate hostname.** HuggingFace 302s GGUF downloads
  to `cas-bridge.xethub.hf.co` (or `cdn-lfs*.huggingface.co` for older
  repos). If your gateway allows `huggingface.co` but blocks the CDN, the
  download will fail. Quick test:

  ```powershell
  curl.exe -I https://cas-bridge.xethub.hf.co/
  ```

  If blocked, ask IT to allowlist that too.

- **Wrong repo type.** Hitting a non-GGUF repo (e.g.
  `Qwen/Qwen3-Embedding-4B`, the safetensors one) errors out with a hint to
  try the `-GGUF` sibling repo. Many models on HF have both.

- **Partial Q-token matches.** The quant must be a complete token: `Q5_0` and
  `Q5_K_M` are different. The matcher won't return both for `Q5`.

- **Pester is not required.** The test script uses its own assertion
  helpers — corporate PCs sometimes block PSGallery.

---

## 4. `install-ollama-model.sh` reference

### Arguments

| Flag                     | Required | Description |
|--------------------------|----------|-------------|
| `-f` / `--file PATH`     | yes      | Path to the `.gguf` file. |
| `-n` / `--name NAME`     | yes      | Model name shown in `ollama list`. |
| `-t` / `--tag TAG`       | yes      | Tag (e.g. `4b`, `0.6b-q8`). |
| `-d` / `--models-dir DIR`| no       | Override Ollama's models dir. |
| `--family NAME`          | no       | `model_family` in the config blob. Default: first segment of `--name` split on `-`. |
| `--arch NAME`            | no       | architecture. Default: same as family. |
| `--file-type TYPE`       | no       | `file_type` in config blob (e.g. `Q8_0`). Default: parsed from filename. |
| `--dry-run`              | no       | Print actions, don't write. |

### Models-dir resolution order

1. `-d` / `--models-dir`
2. `$OLLAMA_MODELS`
3. **`/usr/share/ollama/.ollama/models`** if running as root (created if
   missing — this is the right path for a multi-user install)
4. `/usr/share/ollama/.ollama/models` if it already exists
5. `~/.ollama/models`

### Multi-user / root behavior

When run as `root`:

- Targets `/usr/share/ollama/.ollama/models` by default.
- Skips `sudo` indirection — runs commands directly.
- After writing files, if the `ollama` user exists, runs
  `chown -R ollama:ollama /usr/share/ollama/.ollama/models` so the daemon owns
  the tree.
- Forces `0755` on every directory in the manifest path and `0644` on the
  blob and manifest files, so any user on the host can read them via the
  local Ollama daemon.

### What it actually writes

For `-n qwen3-embedding -t 4b` with a Q8_0 GGUF:

```
/usr/share/ollama/.ollama/models/
├── blobs/
│   ├── sha256-<gguf-sha256>          # the GGUF, byte-identical to source
│   └── sha256-<config-sha256>        # ~150-byte JSON: model_format, family, etc.
└── manifests/
    └── registry.ollama.ai/
        └── library/
            └── qwen3-embedding/
                └── 4b                # Docker-style manifest v2 JSON
```

Manifest content:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "digest": "sha256:<config-sha>",
    "size": <bytes>
  },
  "layers": [
    {
      "mediaType": "application/vnd.ollama.image.model",
      "digest": "sha256:<gguf-sha>",
      "size": <bytes>
    }
  ]
}
```

### Caveats

- **The on-disk manifest path is `registry.ollama.ai/library/...` regardless
  of the public-facing domain.** Don't change it to `ollama.com/...` —
  Ollama's loader looks up `registry.ollama.ai` internally and will not find
  the model under any other registry root.

- **`sudo ollama pull` was the wrong original instinct.** `ollama pull`
  talks to the daemon over its API; the daemon is what writes to disk, not
  the CLI. Running the CLI as root just changes who initiates the API call;
  it doesn't change where models land. With this script you're acting as the
  storage layer directly, so root is meaningful here (it lets you write to
  `/usr/share/ollama/.ollama/models`).

- **Sharded GGUF.** This installer creates a single
  `application/vnd.ollama.image.model` layer pointing at one `.gguf` blob.
  Multi-shard GGUFs (rare for ≤7B models) need multiple model layers in the
  manifest — not supported here. If you hit this case, concatenating shards
  is **not** correct; ask for the multi-shard variant of the script.

- **`file_type` auto-detection.** Parses `Q4_K_M`, `Q8_0`, `Q6_K`, `IQ3_XS`,
  `F16`, `BF16`, `F32` from the filename. Falls back to `"unknown"` if the
  filename doesn't match — Ollama tolerates this, but pass `--file-type
  Q8_0` explicitly if you want it right.

- **Idempotency.** Re-running with the same GGUF re-uses the existing blob
  (content-addressed by sha256). The manifest is rewritten each time. Safe
  to re-run.

---

## 5. Tests

Both scripts ship with self-contained test runners. No external test
framework is required.

```bash
# Linux side: 34 assertions
./test-install-ollama-model.sh
```

Covers: missing-arg validation, name char validation, dry-run is
non-destructive, blob is content-addressed and byte-equal to source,
manifest is valid JSON with the right media types and digests, config
blob's filename matches its own sha256, family/file_type auto-derivation,
explicit overrides, multi-user perms (0644 / 0755), idempotency.

```powershell
# Work PC side: offline tests, optional online
.\Test-DownloadOllamaModel.ps1
.\Test-DownloadOllamaModel.ps1 -Online   # adds live HF API hit
```

Covers: URL parsing for 5 forms, rejection of 2 invalid forms,
case-insensitive quant matching, `Q5` not matching `Q5_K_M`, sharded files
sorted ascending, no false positive for unknown quants. `-Online` mode hits
the real HF tree API.

---

## 6. Alternatives, in case the workflow doesn't apply

1. **Talk to IT.** Ask them to allowlist `registry.ollama.ai`, `*.ollama.ai`,
   `huggingface.co`, and `cas-bridge.xethub.hf.co` for your account or your
   team. This is the right long-term fix.

2. **Sideload from a different machine.** Pull the model on a personal /
   home machine: `ollama pull qwen3-embedding:0.6b`. Then copy
   `~/.ollama/models/manifests/registry.ollama.ai/library/<model>/` and the
   blobs it references from `~/.ollama/models/blobs/` to the same paths on
   the work box. Same end state as this workflow, no scripts needed.

3. **`ollama create` from a local GGUF.** If you have the GGUF on disk and
   ` ollama create` works, that's the canonical one-liner — it does
   everything `install-ollama-model.sh` does, just internally:

   ```bash
   echo "FROM /tmp/Qwen3-Embedding-4B-Q8_0.gguf" > Modelfile
   ollama create qwen3-embedding:4b -f Modelfile
   ```

   The hand-rolled installer here exists because some corporate setups
   don't even allow the daemon to talk to its API endpoints reliably, and
   because this version handles multi-user perms explicitly.

4. **Convert from safetensors.** If no `-GGUF` repo exists for the model,
   convert it yourself:

   ```bash
   git clone https://github.com/ggerganov/llama.cpp
   cd llama.cpp && pip install -r requirements.txt
   python convert_hf_to_gguf.py /path/to/model --outtype f16 --outfile model-f16.gguf
   ./build/bin/llama-quantize model-f16.gguf model-q8_0.gguf Q8_0
   ```

   Then run `install-ollama-model.sh` against the resulting GGUF.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `realm host "" does not match …` | Corporate gateway stripping `Www-Authenticate` | Use this workflow. |
| `Could not parse '<user>/<repo>'` | URL has unexpected form | Pass plain `<user>/<repo>` instead. |
| `No .gguf files in <repo>` | You pointed at the safetensors repo | Use the `<repo>-GGUF` variant. |
| `No GGUF files match quant 'Q5'` | Partial quant token | Use full token: `Q5_0` or `Q5_K_M`. |
| Download stalls or 403s | LFS CDN blocked by gateway | Allowlist `cas-bridge.xethub.hf.co`. |
| `ollama list` doesn't show the model | Manifest under wrong dir, or perms wrong | `ls -la /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/<name>/`. Re-run installer as root. |
| `ollama show` errors with bad digest | `size` in manifest didn't match blob | Re-run installer (it recomputes from the actual file). Don't hand-edit the manifest. |
| `ollama embed` says model isn't an embedding model | GGUF arch not recognized as embedding | Use the official `<vendor>/<model>-GGUF` repo if available; arbitrary community GGUFs may load but refuse to embed. |
