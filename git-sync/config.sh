#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Shared configuration. Fill in these values. Same file layout on both PCs,
# but PERSONAL_* and COMPANY_* values matter on different machines.
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
