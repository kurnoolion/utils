#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# git-debug.sh — pattern-match a git error and suggest fixes for THIS workflow.
#
# Usage:
#   git-debug.sh "<the failing git command>" "<the error output>"
#   git-debug.sh            # interactive mode — paste cmd + error, then Ctrl-D
#
# This is advisory. It recognises the common failure modes for the personal
# -> github.com -> work -> company bridging workflow. It never executes
# destructive commands — it only prints suggestions.
# ----------------------------------------------------------------------------
set -uo pipefail

CMD="${1:-}"
ERR="${2:-}"
if [[ -z "$CMD" && -z "$ERR" ]]; then
    echo "Paste failing git command, blank line, then error output. Ctrl-D to finish."
    CMD=$(read -r line; echo "$line")
    ERR=$(cat)
fi
BLOB="$(printf '%s\n%s\n' "$CMD" "$ERR")"
LOWER="$(printf '%s' "$BLOB" | tr '[:upper:]' '[:lower:]')"

section() { printf '\n=== %s ===\n' "$1"; }
tip()     { printf '  - %s\n' "$1"; }
cmd()     { printf '    $ %s\n' "$1"; }

echo "git-debug: analysing..."
printf '\n--- input ---\n%s\n-------------\n' "$BLOB"

matched=0

if grep -qE 'non-fast-forward|updates were rejected|rejected.*fetch first|failed to push' <<<"$LOWER"; then
    matched=1
    section "Rejected push (non-fast-forward)"
    tip "Remote has commits you don't. Fetch + merge, then push again."
    tip "On WORK PC pushing to company:"
    cmd "git fetch company && git merge company/main && git push company main"
    tip "On PERSONAL PC pushing to github.com — this should never happen in this"
    tip "workflow (github.com is only written from personal PC). If it did, another"
    tip "machine pushed. Investigate before overwriting:"
    cmd "git fetch origin && git log --oneline origin/main ^main   # what's on remote"
fi

if grep -qE 'merge conflict|automatic merge failed|conflict.*content' <<<"$LOWER"; then
    matched=1
    section "Merge conflict"
    tip "Two sides edited overlapping lines. List the conflicted files:"
    cmd "git status --short | grep '^UU'"
    tip "Edit each conflicted file, remove <<<<<<< ======= >>>>>>> markers, then:"
    cmd "git add <files> && git commit      # complete the merge"
    tip "To bail out and return to pre-merge state:"
    cmd "git merge --abort"
fi

if grep -qE 'refusing to merge unrelated histories' <<<"$LOWER"; then
    matched=1
    section "Unrelated histories"
    tip "The two repos have independent roots. This usually means the company repo"
    tip "was initialised separately (e.g. with a README) instead of being a fresh"
    tip "push target. Safe fix on first-time setup only:"
    cmd "git pull company main --allow-unrelated-histories"
    tip "After that, merge conflicts (if any) need manual resolution."
fi

if grep -qE 'authentication failed|could not read username|invalid username or password|http 401|http 403' <<<"$LOWER"; then
    matched=1
    section "HTTPS authentication failed (github.com)"
    tip "Pulling from a PUBLIC github.com repo needs no credentials. If prompted:"
    tip "  - Confirm the repo is actually public in github.com settings."
    tip "  - Check the URL is HTTPS, not SSH (work PC shouldn't use SSH to github.com):"
    cmd "git remote -v"
    cmd "git remote set-url origin <GITHUB_HTTPS_URL from your config.sh>"
    tip "For PRIVATE repos you'd need a Personal Access Token in the credential store."
fi

if grep -qE 'permission denied \(publickey\)|host key verification failed|could not resolve hostname' <<<"$LOWER"; then
    matched=1
    section "SSH failure (likely company git)"
    tip "Verify your SSH key is loaded and reaches the company host:"
    cmd "ssh-add -l                     # keys loaded in the agent"
    cmd "ssh -vT git@<company-host>     # verbose handshake"
    tip "If the key isn't loaded:"
    cmd "eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/<your_company_key>"
    tip "If 'host key verification failed', the server key changed or is unknown:"
    cmd "ssh-keyscan <company-host> >> ~/.ssh/known_hosts"
fi

if grep -qE "does not appear to be a git repository|no such remote|remote .* does not exist" <<<"$LOWER"; then
    matched=1
    section "Missing or misnamed remote"
    tip "Inspect what's configured and compare to your config.sh expectations:"
    cmd "git remote -v"
    tip "Re-run the setup script to restore remotes (pass your config path):"
    cmd "$(dirname "$0")/setup-work.sh <path/to/config.sh>      # (or setup-personal.sh)"
fi

if grep -qE 'detached head' <<<"$LOWER"; then
    matched=1
    section "Detached HEAD"
    tip "You're not on a branch. Return to main (discards any detached commits"
    tip "unless you branch from here first):"
    cmd "git switch main"
    tip "To keep work from the detached state:"
    cmd "git switch -c rescue-\$(date +%Y%m%d) && git switch main"
fi

if grep -qE "your branch is behind|your branch and .* have diverged" <<<"$LOWER"; then
    matched=1
    section "Branch behind / diverged"
    tip "WORK PC: just run the sync script — it fetches both remotes and merges:"
    cmd "$(dirname "$0")/sync-work.sh <path/to/config.sh>"
    tip "If diverged due to a stray local commit on work PC:"
    cmd "git log --oneline main..HEAD        # what's local only"
    tip "Decide whether to keep or let sync-work.sh carry it to company git."
fi

if grep -qE 'fatal: not a git repository' <<<"$LOWER"; then
    matched=1
    section "Not inside a git repository"
    tip "cd into the repo first. Check REPO_DIR in your config.sh:"
    cmd "grep REPO_DIR <path/to/config.sh>"
fi

if grep -qE 'pathspec .* did not match|error: pathspec' <<<"$LOWER"; then
    matched=1
    section "Unknown branch/ref"
    tip "Check branch name (DEFAULT_BRANCH in your config.sh; some repos use 'master'):"
    cmd "git branch -a"
    cmd "grep DEFAULT_BRANCH <path/to/config.sh>"
fi

if grep -qE 'index.lock|another git process seems to be running' <<<"$LOWER"; then
    matched=1
    section "Stale lock file"
    tip "A previous git command was interrupted. After confirming no git is running:"
    cmd "ls -la .git/index.lock"
    cmd "rm .git/index.lock   # only if no git process is active"
fi

if [[ $matched -eq 0 ]]; then
    section "No known pattern matched"
    tip "Capture context to diagnose manually:"
    cmd "git status"
    cmd "git remote -v"
    cmd "git log --oneline --decorate -n 10"
    cmd "git branch -vv"
    tip "Re-run the failing command with GIT_TRACE=1 for verbose output:"
    cmd "GIT_TRACE=1 GIT_CURL_VERBOSE=1 <your-command>"
fi

exit 0
