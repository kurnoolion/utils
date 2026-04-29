#!/usr/bin/env bash
#
# Tests for install-ollama-model.sh.
# Self-contained: writes into a temp directory, no real Ollama needed.
#
# Run:   ./test-install-ollama-model.sh

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/install-ollama-model.sh"
[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAILURES+=("$1"); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }

assert_eq() {
  # $1=expected $2=actual $3=name
  if [[ "$1" == "$2" ]]; then pass "$3"
  else fail "$3" "expected: $1 | actual: $2"; fi
}

assert_file_exists() {
  if [[ -f "$1" ]]; then pass "$2"
  else fail "$2" "missing: $1"; fi
}

assert_contains() {
  # $1=haystack $2=needle $3=name
  if [[ "$1" == *"$2"* ]]; then pass "$3"
  else fail "$3" "expected substring '$2' not found"; fi
}

# Build a fake "GGUF" — content doesn't matter, only that hashing is stable.
GGUF="$TMP/fake-Qwen3-Embedding-4B-Q8_0.gguf"
# Deterministic content -> deterministic sha256.
# Avoid `yes | head` (SIGPIPE under `set -e -o pipefail`).
printf 'gguf-test-content-block-' > "$GGUF"
for _ in $(seq 1 1000); do
  printf 'gguf-test-content-block-' >> "$GGUF"
done
EXPECTED_SHA=$(sha256sum "$GGUF" | awk '{print $1}')
EXPECTED_SIZE=$(stat -c%s "$GGUF")

echo "Test fixture:"
echo "  GGUF: $GGUF ($EXPECTED_SIZE bytes, sha256=$EXPECTED_SHA)"
echo

# ---------- Test 1: missing required args ----------
echo "Test: missing args"
set +e
out=$("$SCRIPT" 2>&1); code=$?
set -e
[[ $code -ne 0 ]] && pass "exits non-zero with no args" || fail "exits non-zero with no args"
assert_contains "$out" "required" "no args -> usage error"

set +e
out=$("$SCRIPT" -f "$GGUF" -n only-name 2>&1); code=$?
set -e
[[ $code -ne 0 ]] && pass "exits non-zero without --tag" || fail "exits non-zero without --tag"

# ---------- Test 2: rejects invalid name ----------
echo "Test: invalid name"
set +e
out=$("$SCRIPT" -f "$GGUF" -n 'bad/name' -t 4b -d "$TMP/m" 2>&1); code=$?
set -e
[[ $code -ne 0 ]] && pass "rejects slash in name" || fail "rejects slash in name"
assert_contains "$out" "invalid characters" "name validation msg"

# ---------- Test 3: dry-run does not write ----------
echo "Test: dry-run"
DR_DIR="$TMP/dry"
mkdir -p "$DR_DIR"
out=$("$SCRIPT" -f "$GGUF" -n qwen3-embedding -t 4b -d "$DR_DIR" --dry-run 2>&1)
[[ ! -d "$DR_DIR/blobs" ]] && pass "dry-run does not create blobs/" || fail "dry-run does not create blobs/"
[[ ! -d "$DR_DIR/manifests" ]] && pass "dry-run does not create manifests/" || fail "dry-run does not create manifests/"
assert_contains "$out" "DRY-RUN" "dry-run banner present"

# ---------- Test 4: full install into a fake models dir ----------
echo "Test: real install (to fake models dir)"
MD="$TMP/models"
mkdir -p "$MD"

out=$("$SCRIPT" -f "$GGUF" -n qwen3-embedding -t 4b -d "$MD" 2>&1)

GGUF_BLOB="$MD/blobs/sha256-$EXPECTED_SHA"
MANIFEST="$MD/manifests/registry.ollama.ai/library/qwen3-embedding/4b"
assert_file_exists "$GGUF_BLOB" "GGUF blob written at content-addressed path"
assert_file_exists "$MANIFEST"  "manifest written at registry path"

# Blob byte-equal to source
ACTUAL_BLOB_SHA=$(sha256sum "$GGUF_BLOB" | awk '{print $1}')
assert_eq "$EXPECTED_SHA" "$ACTUAL_BLOB_SHA" "blob content matches source GGUF"

ACTUAL_BLOB_SIZE=$(stat -c%s "$GGUF_BLOB")
assert_eq "$EXPECTED_SIZE" "$ACTUAL_BLOB_SIZE" "blob size matches source"

# Manifest is valid JSON and structurally correct
if jq empty "$MANIFEST" 2>/dev/null; then pass "manifest is valid JSON"
else fail "manifest is valid JSON" "jq parse failed"; fi

assert_eq 2                                                      "$(jq -r '.schemaVersion' "$MANIFEST")"               "manifest schemaVersion=2"
assert_eq "application/vnd.docker.distribution.manifest.v2+json" "$(jq -r '.mediaType' "$MANIFEST")"                   "manifest mediaType"
assert_eq "sha256:$EXPECTED_SHA"                                 "$(jq -r '.layers[0].digest' "$MANIFEST")"            "layer[0].digest references GGUF blob"
assert_eq "$EXPECTED_SIZE"                                       "$(jq -r '.layers[0].size' "$MANIFEST")"              "layer[0].size matches GGUF size"
assert_eq "application/vnd.ollama.image.model"                   "$(jq -r '.layers[0].mediaType' "$MANIFEST")"         "layer[0] mediaType is ollama model layer"
assert_eq "application/vnd.docker.container.image.v1+json"       "$(jq -r '.config.mediaType' "$MANIFEST")"            "config mediaType"

# Config blob: digest in manifest must point to a real file whose sha matches
CONFIG_DIGEST=$(jq -r '.config.digest' "$MANIFEST")
CONFIG_SHA="${CONFIG_DIGEST#sha256:}"
CONFIG_BLOB="$MD/blobs/sha256-$CONFIG_SHA"
assert_file_exists "$CONFIG_BLOB" "config blob exists at digest path"

ACTUAL_CFG_SHA=$(sha256sum "$CONFIG_BLOB" | awk '{print $1}')
assert_eq "$CONFIG_SHA" "$ACTUAL_CFG_SHA" "config blob filename matches its content sha"

CONFIG_SIZE_FROM_MANIFEST=$(jq -r '.config.size' "$MANIFEST")
ACTUAL_CFG_SIZE=$(stat -c%s "$CONFIG_BLOB")
assert_eq "$CONFIG_SIZE_FROM_MANIFEST" "$ACTUAL_CFG_SIZE" "config blob size matches manifest"

# Config JSON content sanity
if jq empty "$CONFIG_BLOB" 2>/dev/null; then pass "config blob is valid JSON"
else fail "config blob is valid JSON" "jq parse failed"; fi
assert_eq "gguf"             "$(jq -r '.model_format' "$CONFIG_BLOB")" "config model_format=gguf"
assert_eq "qwen3"            "$(jq -r '.model_family' "$CONFIG_BLOB")" "config model_family auto-derived (qwen3)"
assert_eq "Q8_0"             "$(jq -r '.file_type'    "$CONFIG_BLOB")" "config file_type auto-derived (Q8_0)"

# ---------- Test 5: explicit family / arch / file-type override ----------
echo "Test: overrides"
MD2="$TMP/models2"
mkdir -p "$MD2"
out=$("$SCRIPT" -f "$GGUF" -n my-model -t v1 -d "$MD2" \
        --family qwen3 --arch qwen3 --file-type Q8_0 2>&1)
CFG2_DIGEST=$(jq -r '.config.digest' "$MD2/manifests/registry.ollama.ai/library/my-model/v1")
CFG2_SHA="${CFG2_DIGEST#sha256:}"
CFG2_BLOB="$MD2/blobs/sha256-$CFG2_SHA"
assert_eq "qwen3" "$(jq -r '.model_family' "$CFG2_BLOB")" "override family applied"
assert_eq "Q8_0"  "$(jq -r '.file_type'    "$CFG2_BLOB")" "override file_type applied"

# ---------- Test 5b: world-readable perms for multi-user ----------
echo "Test: multi-user perms"
PERMS_BLOB=$(stat -c%a "$GGUF_BLOB")
PERMS_MANIFEST=$(stat -c%a "$MANIFEST")
PERMS_BLOBS_DIR=$(stat -c%a "$MD/blobs")
PERMS_MANIFEST_DIR=$(stat -c%a "$MD/manifests/registry.ollama.ai/library/qwen3-embedding")
assert_eq "644" "$PERMS_BLOB"          "GGUF blob is 0644 (world-readable)"
assert_eq "644" "$PERMS_MANIFEST"      "manifest is 0644 (world-readable)"
assert_eq "755" "$PERMS_BLOBS_DIR"     "blobs/ dir is 0755 (world-traversable)"
assert_eq "755" "$PERMS_MANIFEST_DIR"  "manifest dir is 0755 (world-traversable)"

# ---------- Test 6: idempotency ----------
echo "Test: idempotent re-install"
BEFORE_SHA=$(sha256sum "$GGUF_BLOB" | awk '{print $1}')
out=$("$SCRIPT" -f "$GGUF" -n qwen3-embedding -t 4b -d "$MD" 2>&1)
AFTER_SHA=$(sha256sum "$GGUF_BLOB" | awk '{print $1}')
assert_eq "$BEFORE_SHA" "$AFTER_SHA" "second install leaves blob unchanged"
assert_contains "$out" "already present" "second install reports skip"

echo
echo "==============================="
echo "Pass: $PASS    Fail: $FAIL"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
