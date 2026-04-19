#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Daily flow on PERSONAL PC:
#  - Stage/commit any pending changes (interactive message prompt)
#  - Push to github.com
#
# Usage:
#   sync-personal.sh                 # prompts for commit message if needed
#   sync-personal.sh "my message"    # uses the given message
# ----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.sh"

cd "$PERSONAL_REPO_DIR"
git checkout "$DEFAULT_BRANCH"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "==> Uncommitted changes detected:"
    git status --short
    MSG="${1:-}"
    if [[ -z "$MSG" ]]; then
        read -rp "Commit message: " MSG
    fi
    [[ -z "$MSG" ]] && { echo "ERROR: empty commit message" >&2; exit 1; }
    git add -A
    git commit -m "$MSG"
else
    echo "==> Working tree clean — nothing to commit."
fi

echo "==> Pushing $DEFAULT_BRANCH to $GITHUB_REMOTE"
git push "$GITHUB_REMOTE" "$DEFAULT_BRANCH"
echo "Done."
