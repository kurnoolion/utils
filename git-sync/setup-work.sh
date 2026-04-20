#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# One-time setup on WORK PC.
#  - Clones github.com repo over HTTPS (read-only pulls from public repo)
#  - Sets commit identity (company)
#  - Adds 'company' remote (SSH)
#  - Pushes state to company git
#
# Usage:
#   setup-work.sh <config.sh>              # empty company repo (first ever setup)
#   setup-work.sh <config.sh> --existing   # company repo already has content
#                                          # (colleague commits, or a prior
#                                          # manual setup). Fetches + merges
#                                          # company/<branch> before pushing.
# Example:
#   setup-work.sh ~/scripts/config-utils.sh --existing
#
# Prerequisites:
#  - github.com repo is public (HTTPS clone works without creds)
#  - SSH key for company git is already set up (you can `ssh -T` successfully)
#  - Company-side repo exists (empty for default mode, populated for --existing)
# ----------------------------------------------------------------------------
set -euo pipefail

CONFIG_PATH="${1:-}"
if [[ -z "$CONFIG_PATH" ]]; then
    echo "Usage: $0 <path-to-config.sh> [--existing]" >&2
    exit 1
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "ERROR: config file not found: $CONFIG_PATH" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_PATH"
shift

MODE="empty"
case "${1:-}" in
    --existing) MODE="existing" ;;
    "")         MODE="empty" ;;
    *) echo "ERROR: unknown arg '$1'. Use --existing or no args." >&2; exit 1 ;;
esac

for v in GITHUB_HTTPS_URL COMPANY_SSH_URL WORK_REPO_DIR; do
    val="${!v:-}"
    if [[ -z "$val" || "$val" == *"<"* ]]; then
        echo "ERROR: $CONFIG_PATH has placeholder/empty value for $v" >&2
        exit 1
    fi
done

if [[ ! -d "$WORK_REPO_DIR/.git" ]]; then
    echo "==> Cloning (HTTPS) $GITHUB_HTTPS_URL into $WORK_REPO_DIR"
    mkdir -p "$(dirname "$WORK_REPO_DIR")"
    git clone "$GITHUB_HTTPS_URL" "$WORK_REPO_DIR"
else
    echo "==> Repo already exists at $WORK_REPO_DIR"
fi

cd "$WORK_REPO_DIR"

echo "==> Setting commit identity (company, per-repo)"
git config user.name  "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

echo "==> Ensuring '$GITHUB_REMOTE' -> github.com (HTTPS)"
if git remote get-url "$GITHUB_REMOTE" >/dev/null 2>&1; then
    git remote set-url "$GITHUB_REMOTE" "$GITHUB_HTTPS_URL"
else
    git remote add "$GITHUB_REMOTE" "$GITHUB_HTTPS_URL"
fi

echo "==> Ensuring '$COMPANY_REMOTE' -> company (SSH)"
if git remote get-url "$COMPANY_REMOTE" >/dev/null 2>&1; then
    git remote set-url "$COMPANY_REMOTE" "$COMPANY_SSH_URL"
else
    git remote add "$COMPANY_REMOTE" "$COMPANY_SSH_URL"
fi

echo "==> Testing SSH to company git"
# extract host from SSH URL for a connectivity ping
HOST_PART="${COMPANY_SSH_URL#*@}"; HOST_PART="${HOST_PART%%:*}"
ssh -o StrictHostKeyChecking=accept-new -T "git@$HOST_PART" 2>&1 | head -5 || true

git checkout "$DEFAULT_BRANCH"

if [[ "$MODE" == "existing" ]]; then
    echo "==> [--existing] Fetching $COMPANY_REMOTE"
    git fetch "$COMPANY_REMOTE"

    if git rev-parse --verify --quiet "$COMPANY_REMOTE/$DEFAULT_BRANCH" >/dev/null; then
        echo "==> [--existing] Merging $COMPANY_REMOTE/$DEFAULT_BRANCH into local $DEFAULT_BRANCH"
        git merge --no-edit "$COMPANY_REMOTE/$DEFAULT_BRANCH" || {
            echo "ERROR: merge failed. Resolve conflicts, then:" >&2
            echo "  git push -u $COMPANY_REMOTE $DEFAULT_BRANCH" >&2
            exit 1
        }
    else
        echo "==> [--existing] No $COMPANY_REMOTE/$DEFAULT_BRANCH on company yet — treating as empty."
    fi

    # Upstream tracking for the company remote (makes later 'git push' ergonomic)
    echo "==> Setting upstream of $DEFAULT_BRANCH to $COMPANY_REMOTE/$DEFAULT_BRANCH"
    git push -u "$COMPANY_REMOTE" "$DEFAULT_BRANCH"
else
    echo "==> Pushing initial state to company ($COMPANY_REMOTE/$DEFAULT_BRANCH)"
    git push -u "$COMPANY_REMOTE" "$DEFAULT_BRANCH"
fi

echo "---"
git remote -v
echo "---"
echo "Identity: $(git config user.name) <$(git config user.email)>"
echo "Mode: $MODE"
echo "Done. Use sync-work.sh for day-to-day syncing."
