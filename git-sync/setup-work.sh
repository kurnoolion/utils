#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# One-time setup on WORK PC.
#  - Clones github.com repo over HTTPS (read-only pulls from public repo)
#  - Sets commit identity (company)
#  - Adds 'company' remote (SSH)
#  - Pushes initial state to company git
#
# Prerequisites:
#  - github.com repo is public (HTTPS clone works without creds)
#  - SSH key for company git is already set up (you can `ssh -T` successfully)
#  - Empty repo already exists on company git (standard on GH Enterprise/GitLab)
# ----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.sh"

for v in GITHUB_HTTPS_URL COMPANY_SSH_URL WORK_REPO_DIR; do
    if [[ "${!v}" == *"<"* || -z "${!v}" ]]; then
        echo "ERROR: config.sh has placeholder/empty value for $v" >&2
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

echo "==> Pushing initial state to company ($COMPANY_REMOTE/$DEFAULT_BRANCH)"
git push -u "$COMPANY_REMOTE" "$DEFAULT_BRANCH"

echo "---"
git remote -v
echo "---"
echo "Identity: $(git config user.name) <$(git config user.email)>"
echo "Done. Use sync-work.sh for day-to-day syncing."
