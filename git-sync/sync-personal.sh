#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Daily flow on PERSONAL PC:
#  - Stage/commit any pending changes (interactive message prompt)
#  - Push to github.com
#
# Usage:
#   sync-personal.sh <config.sh>                 # prompts for commit message if needed
#   sync-personal.sh <config.sh> "my message"    # uses the given message
# Example:
#   sync-personal.sh ~/scripts/config-utils.sh "fix typo"
# ----------------------------------------------------------------------------
set -euo pipefail

CONFIG_PATH="${1:-}"
if [[ -z "$CONFIG_PATH" ]]; then
    echo "Usage: $0 <path-to-config.sh> [commit-message]" >&2
    exit 1
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "ERROR: config file not found: $CONFIG_PATH" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_PATH"
shift

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
