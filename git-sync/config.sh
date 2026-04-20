#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Template configuration. Copy this file per project (e.g. ~/scripts/config-
# <project>.sh) and pass its full path to the setup/sync scripts:
#
#   setup-personal.sh ~/scripts/config-utils.sh
#   sync-personal.sh  ~/scripts/config-utils.sh
#   setup-work.sh     ~/scripts/config-utils.sh --existing
#   sync-work.sh      ~/scripts/config-utils.sh
#
# Same field layout works on both PCs — only the relevant values are read on
# each machine (personal reads PERSONAL_*, work reads COMPANY_* and both
# reads GITHUB_*).
# ----------------------------------------------------------------------------

# --- Commit identity ---------------------------------------------------------
# Name/email baked into every commit. Recommendation: use your COMPANY identity
# on BOTH machines so company-git history never sees personal email addresses.
# Auth (how you log in to github.com or company git) is separate from this.
GIT_USER_NAME="Your Company Name"
GIT_USER_EMAIL="you@company.com"

# --- github.com repo (personal, public) --------------------------------------
# HTTPS is safest for the work PC (read-only pulls, no auth needed for public).
# On personal PC you can use SSH if you prefer.
GITHUB_HTTPS_URL="https://github.com/<your-github-user>/<your-repo>.git"
GITHUB_SSH_URL="git@github.com:<your-github-user>/<your-repo>.git"   # optional, personal PC only

# --- Company internal git (SSH) ---------------------------------------------
# Only used on the work PC.
COMPANY_SSH_URL="git@git.company.internal:<team>/<your-repo>.git"

# --- Local clone paths -------------------------------------------------------
# Where the repo lives on each machine. Pick whatever suits you.
PERSONAL_REPO_DIR="$HOME/work/<your-repo>"
WORK_REPO_DIR="$HOME/work/<your-repo>"

# --- Branch ------------------------------------------------------------------
DEFAULT_BRANCH="main"

# --- Remote names (usually leave as-is) -------------------------------------
GITHUB_REMOTE="origin"
COMPANY_REMOTE="company"
