#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Daily flow on WORK PC. Bridges github.com <- one-way -> company git.
#
# Order (as you specified):
#   1. Pull colleague changes from company git
#   2. Pull your new changes from github.com
#   3. Merge if both changed (usually clean: different files)
#   4. Push merged state back to company git
#
# Safe to run even when only one side has new commits.
#
# Usage:
#   sync-work.sh
# ----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.sh"

cd "$WORK_REPO_DIR"

# Refuse to run with an unclean working tree. Committed local commits are fine
# — they'll be pushed to company. Only uncommitted diffs block sync, to avoid
# silently entangling unrelated in-progress edits with a merge.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean. Commit or stash before syncing." >&2
    git status --short >&2
    exit 1
fi

git checkout "$DEFAULT_BRANCH"

echo "==> [1/4] Fetching $COMPANY_REMOTE"
git fetch "$COMPANY_REMOTE"

echo "==> [2/4] Merging $COMPANY_REMOTE/$DEFAULT_BRANCH (colleague changes)"
git merge --no-edit "$COMPANY_REMOTE/$DEFAULT_BRANCH"

echo "==> [3/4] Fetching $GITHUB_REMOTE"
git fetch "$GITHUB_REMOTE"

echo "==> [3/4] Merging $GITHUB_REMOTE/$DEFAULT_BRANCH (your changes)"
git merge --no-edit "$GITHUB_REMOTE/$DEFAULT_BRANCH"

# Decide whether we need to push
LOCAL=$(git rev-parse "$DEFAULT_BRANCH")
REMOTE=$(git rev-parse "$COMPANY_REMOTE/$DEFAULT_BRANCH")
if [[ "$LOCAL" == "$REMOTE" ]]; then
    echo "==> [4/4] Company git already up to date — no push needed."
else
    echo "==> [4/4] Pushing to $COMPANY_REMOTE/$DEFAULT_BRANCH"
    git push "$COMPANY_REMOTE" "$DEFAULT_BRANCH"
fi

echo "---"
git log --oneline --decorate -n 5
echo "Done."
