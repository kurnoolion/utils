#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# One-time setup on PERSONAL PC.
#  - Clones github.com repo (if not already present)
#  - Sets commit identity (per-repo, not global)
#  - Verifies remote
# ----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.sh"

# Choose HTTPS or SSH URL for personal PC. Default: SSH if configured, else HTTPS.
PERSONAL_CLONE_URL="${GITHUB_SSH_URL:-$GITHUB_HTTPS_URL}"
if [[ "$PERSONAL_CLONE_URL" == *"<"* ]]; then
    echo "ERROR: Edit config.sh first — GITHUB_*_URL still has placeholders." >&2
    exit 1
fi

if [[ ! -d "$PERSONAL_REPO_DIR/.git" ]]; then
    echo "==> Cloning $PERSONAL_CLONE_URL into $PERSONAL_REPO_DIR"
    mkdir -p "$(dirname "$PERSONAL_REPO_DIR")"
    git clone "$PERSONAL_CLONE_URL" "$PERSONAL_REPO_DIR"
else
    echo "==> Repo already exists at $PERSONAL_REPO_DIR"
fi

cd "$PERSONAL_REPO_DIR"

echo "==> Setting commit identity (per-repo)"
git config user.name  "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

echo "==> Verifying remote '$GITHUB_REMOTE'"
if git remote get-url "$GITHUB_REMOTE" >/dev/null 2>&1; then
    git remote set-url "$GITHUB_REMOTE" "$PERSONAL_CLONE_URL"
else
    git remote add "$GITHUB_REMOTE" "$PERSONAL_CLONE_URL"
fi

echo "---"
git remote -v
echo "---"
echo "Identity: $(git config user.name) <$(git config user.email)>"
echo "Done. Develop in $PERSONAL_REPO_DIR as usual."
