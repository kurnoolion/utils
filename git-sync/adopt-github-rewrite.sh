#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Recovery on WORK PC after github.com history has been rewritten
# (e.g. filter-branch + force-push performed on personal PC).
#
# When to run:
#   - sync-work.sh aborts with "history was rewritten", OR
#   - you know a public-side force-push happened and want to adopt it.
#
# What it does:
#   1. Verifies preconditions (clean tree, all local commits pushed to company).
#   2. Fetches origin and splits local commits public vs work-only:
#      preferred — EXACT split via the last-synced origin tip that
#      sync-work.sh records (public = ancestors of that tip; conflict-free
#      even when a content scrub changed public patch-ids);
#      fallback — `git cherry` patch-id matching (content-scrubbed public
#      commits then replay and conflict; resolve those with --skip).
#   3. Rebases only the work-only commits onto the new origin/<branch>
#      (`rebase --onto` in the exact-split case).
#   4. Force-pushes to company.
#   5. Updates .git/last-synced-origin-<branch> so sync-work.sh resumes
#      cleanly afterward.
#
# Coordination:
#   This force-pushes to company. After it runs, every teammate with a clone
#   of company must do their own one-time recovery on their work clone.
#   COMMUNICATE WITH THE TEAM BEFORE RUNNING THIS.
#
# Usage:
#   adopt-github-rewrite.sh <path-to-config.sh>
# ----------------------------------------------------------------------------
set -euo pipefail

CONFIG_PATH="${1:-}"
if [[ -z "$CONFIG_PATH" ]]; then
    echo "Usage: $0 <path-to-config.sh>" >&2
    exit 1
fi
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "ERROR: config file not found: $CONFIG_PATH" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_PATH"

cd "$WORK_REPO_DIR"

# Pre-condition: clean working tree
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean. Commit or stash before recovery." >&2
    git status --short >&2
    exit 1
fi

git checkout "$DEFAULT_BRANCH"

# Pre-condition: every local commit (including work-only) is already on company
echo "==> Fetching $COMPANY_REMOTE to verify local commits are pushed"
git fetch "$COMPANY_REMOTE"
UNPUSHED=$(git rev-list --count "${COMPANY_REMOTE}/${DEFAULT_BRANCH}..${DEFAULT_BRANCH}")
if [[ "$UNPUSHED" -gt 0 ]]; then
    echo "ERROR: $UNPUSHED local commit(s) not yet pushed to ${COMPANY_REMOTE}/${DEFAULT_BRANCH}." >&2
    echo "       Push them first, then re-run this script." >&2
    git log --oneline "${COMPANY_REMOTE}/${DEFAULT_BRANCH}..${DEFAULT_BRANCH}" >&2
    exit 1
fi

echo "==> Fetching $GITHUB_REMOTE"
git fetch "$GITHUB_REMOTE"

NEW_TIP="${GITHUB_REMOTE}/${DEFAULT_BRANCH}"
LAST_SYNCED_FILE="$WORK_REPO_DIR/.git/last-synced-origin-${DEFAULT_BRANCH}"

# ── Preferred split: exact, via the recorded last-synced origin tip ─────────
# sync-work.sh records the origin tip after every sync. When that commit is
# still in the local odb, the public/work-only split is EXACT:
#   public    = ancestors of the old tip. NEVER replay these — their rewritten
#               twins are already on the new origin. (Patch-id matching alone
#               misses public commits whose CONTENT a scrub changed — their
#               patch-ids differ, they'd replay, and each one conflicts.)
#   work-only = ${OLD_TIP}..${DEFAULT_BRANCH}
# `git rebase --onto NEW OLD branch` replays only the work-only range, so a
# pure content scrub adopts with zero conflicts.
OLD_TIP=""
if [[ -f "$LAST_SYNCED_FILE" ]]; then
    CAND=$(cat "$LAST_SYNCED_FILE")
    if git cat-file -e "${CAND}^{commit}" 2>/dev/null \
       && git merge-base --is-ancestor "$CAND" "$DEFAULT_BRANCH" 2>/dev/null; then
        OLD_TIP="$CAND"
    fi
fi

if [[ -n "$OLD_TIP" ]]; then
    if git merge-base --is-ancestor "$OLD_TIP" "$NEW_TIP" 2>/dev/null; then
        echo "==> Last-synced tip is still on origin — no rewrite to adopt."
        echo "    Use sync-work.sh for the normal daily flow."
        git rev-parse "$NEW_TIP" > "$LAST_SYNCED_FILE"
        exit 0
    fi
    WORK_COUNT=$(git rev-list --count "${OLD_TIP}..${DEFAULT_BRANCH}")
    echo ""
    echo "==> Rewrite detected on ${NEW_TIP} (last-synced tip no longer reachable)."
    echo "    Exact split via recorded tip ${OLD_TIP:0:12}:"
    echo "    $WORK_COUNT work-only commit(s) to preserve:"
    if [[ "$WORK_COUNT" -gt 0 ]]; then
        git log --oneline "${OLD_TIP}..${DEFAULT_BRANCH}" | sed 's/^/        /'
    else
        echo "        (none)"
    fi
    REBASE_ARGS=(--onto "$NEW_TIP" "$OLD_TIP" "$DEFAULT_BRANCH")
    REBASE_DESC="git rebase --onto ${NEW_TIP} ${OLD_TIP:0:12} ${DEFAULT_BRANCH}"
else
    # ── Fallback: patch-id classification (no usable state file) ────────────
    # `+ <sha>` → patch NOT in origin (treated as work-only — but see caveat)
    # `- <sha>` → patch IS in origin (duplicate from rewrite — dropped)
    # Caveat: a public commit whose content the rewrite changed shows up as
    # `+` and will replay → expect a conflict per such commit; resolve with
    # `git rebase --skip` (its rewritten twin is already upstream).
    echo ""
    echo "NOTE: no usable last-synced state file — falling back to patch-id"
    echo "      classification. Public commits altered by the rewrite will"
    echo "      conflict during rebase; resolve those with 'git rebase --skip'."
    CHERRY=$(git cherry "$NEW_TIP" "$DEFAULT_BRANCH" 2>/dev/null || true)
    WORK_COMMITS=$(echo "$CHERRY" | awk '$1=="+" {print $2}')
    DUP_COMMITS=$(echo "$CHERRY"  | awk '$1=="-" {print $2}')
    WORK_COUNT=$(echo -n "$WORK_COMMITS" | grep -c '^' || true)
    DUP_COUNT=$(echo -n "$DUP_COMMITS"   | grep -c '^' || true)

    if [[ "$DUP_COUNT" -eq 0 ]]; then
        echo "==> No duplicate-patch commits detected — no rewrite to adopt."
        echo "    Use sync-work.sh for the normal daily flow."
        git rev-parse "$NEW_TIP" > "$LAST_SYNCED_FILE"
        exit 0
    fi

    echo ""
    echo "==> Rewrite detected on ${NEW_TIP}."
    echo "    $DUP_COUNT commit(s) in local ${DEFAULT_BRANCH} have patches already on origin — will be dropped."
    echo "    $WORK_COUNT work-only commit(s) to preserve:"
    if [[ -n "$WORK_COMMITS" ]]; then
        echo "$WORK_COMMITS" | xargs -r git log --no-walk --oneline | sed 's/^/        /'
    else
        echo "        (none)"
    fi
    REBASE_ARGS=("$NEW_TIP" "$DEFAULT_BRANCH")
    REBASE_DESC="git rebase ${NEW_TIP} ${DEFAULT_BRANCH}"
fi

echo ""
echo "==> Plan:"
echo "    1. $REBASE_DESC"
echo "    2. git push --force ${COMPANY_REMOTE} ${DEFAULT_BRANCH}"
echo ""
echo "    AFTER THIS RUNS, every teammate with a clone of ${COMPANY_REMOTE} must"
echo "    do their own one-time recovery on their work clone:"
echo "        git fetch ${COMPANY_REMOTE}"
echo "        # if they have unpushed work-only commits, rebase those onto the"
echo "        # new ${COMPANY_REMOTE}/${DEFAULT_BRANCH}; otherwise:"
echo "        git checkout ${DEFAULT_BRANCH} && git reset --hard ${COMPANY_REMOTE}/${DEFAULT_BRANCH}"
echo ""
read -r -p "Proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo "==> Rebasing: $REBASE_DESC"
if ! git rebase "${REBASE_ARGS[@]}"; then
    echo "" >&2
    echo "ERROR: rebase encountered conflicts." >&2
    echo "       Genuine work-only conflicts: resolve, 'git rebase --continue'." >&2
    echo "       Replayed public commit (patch-id fallback path only): 'git rebase --skip'." >&2
    echo "       To bail out entirely: 'git rebase --abort'." >&2
    echo "       Do NOT push to company until the rebase completes cleanly." >&2
    exit 1
fi

echo "==> Force-pushing to ${COMPANY_REMOTE}/${DEFAULT_BRANCH}"
git push --force "$COMPANY_REMOTE" "$DEFAULT_BRANCH"

# Record the synced origin tip so sync-work.sh's guard has a current baseline.
git rev-parse "$NEW_TIP" > "$LAST_SYNCED_FILE"

echo ""
echo "==> Recovery complete. Recent history:"
git log --oneline --decorate -n 8

echo ""
echo "Next steps:"
echo "  - Notify teammates: ${COMPANY_REMOTE}/${DEFAULT_BRANCH} has been rewritten."
echo "  - Each teammate does their own one-time recovery on their work clone."
echo "  - From now on, sync-work.sh runs proceed normally."
