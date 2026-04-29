#!/usr/bin/env bash
#
# install-ollama-model.sh - manually install a local GGUF as an Ollama model
#
# Stages a GGUF file into the Ollama blob store and writes a Docker-style
# manifest under registry.ollama.ai/library/<name>/<tag>, so that
# `ollama list` / `ollama show` / `ollama embed` see it as if pulled.
#
# Usage:
#   install-ollama-model.sh -f <gguf> -n <name> -t <tag> [options]
#
# See -h for full options.

set -euo pipefail

GGUF_PATH=""
MODEL_NAME=""
TAG=""
MODELS_DIR=""
FAMILY=""
ARCH=""
FILE_TYPE=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: install-ollama-model.sh -f <gguf-path> -n <name> -t <tag> [options]

Required:
  -f, --file PATH        Path to the .gguf file to install
  -n, --name NAME        Model name shown by `ollama list`, e.g. qwen3-embedding
  -t, --tag TAG          Tag, e.g. 4b or 0.6b-q8

Optional:
  -d, --models-dir DIR   Ollama models directory.
                         Default: $OLLAMA_MODELS, or auto-detected from
                         /usr/share/ollama/.ollama/models or ~/.ollama/models
      --family NAME      model_family in the config blob (default: derived
                         from <name>, splitting on '-')
      --arch NAME        architecture in the config blob (default: same as family)
      --file-type TYPE   file_type in the config blob, e.g. Q8_0
                         (default: parsed from filename, else "unknown")
      --dry-run          Print actions, do not write
  -h, --help             Show this help

Examples:
  # System-wide install for all users (recommended): run as root
  sudo install-ollama-model.sh -f /tmp/Qwen3-Embedding-4B-Q8_0.gguf \
                               -n qwen3-embedding -t 4b

  # Per-user install (no root)
  install-ollama-model.sh -f ./model.gguf -n my-model -t v1

When run as root, files go to /usr/share/ollama/.ollama/models, are chown'd
to the ollama daemon user, and are 0644 / 0755 so every user on the box can
read them through the local Ollama daemon.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)        GGUF_PATH="$2"; shift 2 ;;
    -n|--name)        MODEL_NAME="$2"; shift 2 ;;
    -t|--tag)         TAG="$2"; shift 2 ;;
    -d|--models-dir)  MODELS_DIR="$2"; shift 2 ;;
    --family)         FAMILY="$2"; shift 2 ;;
    --arch)           ARCH="$2"; shift 2 ;;
    --file-type)      FILE_TYPE="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

err() { echo "error: $*" >&2; exit 1; }

[[ -n "$GGUF_PATH"  ]] || err "-f/--file is required"
[[ -n "$MODEL_NAME" ]] || err "-n/--name is required"
[[ -n "$TAG"        ]] || err "-t/--tag is required"
[[ -f "$GGUF_PATH"  ]] || err "file not found: $GGUF_PATH"

# Validate name/tag chars (defensive — these end up in filesystem paths)
[[ "$MODEL_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid characters in name: $MODEL_NAME"
[[ "$TAG"        =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid characters in tag: $TAG"

# Resolve models dir.
# Preference order:
#   1) -d / --models-dir       explicit override
#   2) $OLLAMA_MODELS          env override
#   3) /usr/share/ollama/.ollama/models   (system-wide, the default for the
#                                          systemd-installed Ollama daemon —
#                                          and the right place when running
#                                          as root for a multi-user install)
#   4) ~/.ollama/models        (single-user fallback)
IS_ROOT=0
[[ "$(id -u)" == "0" ]] && IS_ROOT=1

if [[ -z "$MODELS_DIR" ]]; then
  if [[ -n "${OLLAMA_MODELS:-}" ]]; then
    MODELS_DIR="$OLLAMA_MODELS"
  elif [[ $IS_ROOT -eq 1 ]]; then
    # When root, always prefer the system path even if it doesn't exist yet —
    # we'll create it. This is the right call for a shared, multi-user install.
    MODELS_DIR="/usr/share/ollama/.ollama/models"
  elif [[ -d "/usr/share/ollama/.ollama/models" ]]; then
    MODELS_DIR="/usr/share/ollama/.ollama/models"
  elif [[ -d "$HOME/.ollama/models" ]]; then
    MODELS_DIR="$HOME/.ollama/models"
  else
    err "could not auto-detect Ollama models dir; pass -d"
  fi
fi

# Derive defaults
[[ -n "$FAMILY"    ]] || FAMILY="${MODEL_NAME%%-*}"
[[ -n "$ARCH"      ]] || ARCH="$FAMILY"
if [[ -z "$FILE_TYPE" ]]; then
  base=$(basename "$GGUF_PATH")
  # Match Q4_K_M, Q8_0, Q6_K, F16, BF16, F32, IQ3_XS, etc.
  if [[ "$base" =~ ([IiQq][0-9]+_[A-Za-z0-9_]+|[Ff]16|[Bb][Ff]16|[Ff]32|[Qq][0-9]+_[0-9]) ]]; then
    FILE_TYPE="${BASH_REMATCH[1]}"
  else
    FILE_TYPE="unknown"
  fi
fi

# Decide if we need sudo. As root, we never do.
SUDO=""
if [[ $IS_ROOT -eq 0 && -d "$MODELS_DIR" && ! -w "$MODELS_DIR" ]]; then SUDO="sudo"; fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    if [[ -n "$SUDO" ]]; then sudo "$@"; else "$@"; fi
  fi
}

# Make every dir / file we create world-readable so other users can use the model.
umask 022

echo "Models dir: $MODELS_DIR"
echo "Model:      $MODEL_NAME:$TAG"
echo "Family:     $FAMILY"
echo "Arch:       $ARCH"
echo "FileType:   $FILE_TYPE"
echo "GGUF:       $GGUF_PATH"
[[ $IS_ROOT -eq 1 ]] && echo "Mode:       root (system-wide install for all users)"
[[ $DRY_RUN -eq 1 ]] && echo "Mode:       DRY-RUN"

# 1) Hash + size of GGUF
echo "Hashing GGUF (this is the slow step) ..."
GGUF_SHA=$(sha256sum "$GGUF_PATH" | awk '{print $1}')
GGUF_SIZE=$(stat -c%s "$GGUF_PATH")
echo "  sha256-$GGUF_SHA  ($GGUF_SIZE bytes)"

# 2) Build config blob
TMPDIR_=$(mktemp -d)
trap 'rm -rf "$TMPDIR_"' EXIT
CONFIG_JSON="$TMPDIR_/config.json"
# Compact, deterministic JSON — recomputing the hash on the user's box will match.
printf '{"model_format":"gguf","model_family":"%s","model_families":["%s"],"model_type":"%s","file_type":"%s","architecture":"%s"}' \
  "$FAMILY" "$FAMILY" "$ARCH" "$FILE_TYPE" "$ARCH" > "$CONFIG_JSON"
CFG_SHA=$(sha256sum "$CONFIG_JSON" | awk '{print $1}')
CFG_SIZE=$(stat -c%s "$CONFIG_JSON")
echo "Config blob: sha256-$CFG_SHA ($CFG_SIZE bytes)"

# 3) Compose manifest
MANIFEST_JSON="$TMPDIR_/manifest.json"
cat > "$MANIFEST_JSON" <<EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "digest": "sha256:$CFG_SHA",
    "size": $CFG_SIZE
  },
  "layers": [
    {
      "mediaType": "application/vnd.ollama.image.model",
      "digest": "sha256:$GGUF_SHA",
      "size": $GGUF_SIZE
    }
  ]
}
EOF

# 4) Place into models dir
BLOBS_DIR="$MODELS_DIR/blobs"
MANIFEST_DIR="$MODELS_DIR/manifests/registry.ollama.ai/library/$MODEL_NAME"
MANIFEST_PATH="$MANIFEST_DIR/$TAG"
GGUF_BLOB="$BLOBS_DIR/sha256-$GGUF_SHA"
CFG_BLOB="$BLOBS_DIR/sha256-$CFG_SHA"

run mkdir -p "$BLOBS_DIR" "$MANIFEST_DIR"

if [[ -f "$GGUF_BLOB" && $DRY_RUN -eq 0 ]]; then
  echo "GGUF blob already present, skipping copy."
else
  run install -m 0644 "$GGUF_PATH" "$GGUF_BLOB"
fi
run install -m 0644 "$CONFIG_JSON"   "$CFG_BLOB"
run install -m 0644 "$MANIFEST_JSON" "$MANIFEST_PATH"

# 5) Set ownership for the daemon, and make everything world-readable.
#    The Ollama systemd unit runs as the `ollama` user; if that user exists
#    we hand the files to it, else leave them as root (still readable by all
#    via 0644 + 0755 thanks to umask 022 above).
if [[ $DRY_RUN -eq 0 ]]; then
  if [[ $IS_ROOT -eq 1 ]] && getent passwd ollama >/dev/null 2>&1; then
    DAEMON_USER="ollama"
    DAEMON_GROUP="$(id -gn ollama)"
    # chown the whole models tree so newly-created dirs (blobs/, manifests/...)
    # are also owned by the daemon user. Safe — we either created them or
    # they were already owned by ollama.
    chown -R "$DAEMON_USER:$DAEMON_GROUP" "$MODELS_DIR"
    echo "Ownership: $DAEMON_USER:$DAEMON_GROUP (system-wide)"
  else
    OWNER=$(stat -c%U "$MODELS_DIR" 2>/dev/null || echo "")
    GROUP=$(stat -c%G "$MODELS_DIR" 2>/dev/null || echo "")
    if [[ -n "$OWNER" && "$OWNER" != "$(whoami)" ]]; then
      run chown "$OWNER:$GROUP" "$GGUF_BLOB" "$CFG_BLOB" "$MANIFEST_PATH"
    fi
  fi

  # Belt-and-braces perms: dirs traversable, files readable by everyone.
  run chmod 0755 "$MODELS_DIR" "$BLOBS_DIR" \
                 "$MODELS_DIR/manifests" \
                 "$MODELS_DIR/manifests/registry.ollama.ai" \
                 "$MODELS_DIR/manifests/registry.ollama.ai/library" \
                 "$MANIFEST_DIR" 2>/dev/null || true
  run chmod 0644 "$GGUF_BLOB" "$CFG_BLOB" "$MANIFEST_PATH"
fi

echo
echo "Installed:"
echo "  manifest: $MANIFEST_PATH"
echo "  blobs:    $GGUF_BLOB"
echo "            $CFG_BLOB"
echo
echo "Verify:"
echo "  ollama list"
echo "  ollama show $MODEL_NAME:$TAG"
