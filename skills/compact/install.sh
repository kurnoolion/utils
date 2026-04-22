#!/usr/bin/env bash
# Install the COMPACT skill bundle into a target project.
#
# Usage: ./install.sh <target-project-root>
#
# Copies every skill subdirectory and the README into <target>/.claude/skills/,
# deliberately excluding the reference graphics (COMPACT_Cheatsheet.* and
# COMPACT_Overview.*). Those live in this source tree as onboarding material
# and do not belong inside a target project's .claude/skills/.

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: $0 <target-project-root>" >&2
  exit 2
fi

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_root="$1"
target="$target_root/.claude/skills"

if [ ! -d "$target_root" ]; then
  echo "error: target project root does not exist: $target_root" >&2
  exit 1
fi

mkdir -p "$target"

rsync -a \
  --exclude='install.sh' \
  --exclude='COMPACT_Cheatsheet.*' \
  --exclude='COMPACT_Overview.*' \
  "$src"/ "$target"/

echo "Installed COMPACT skills into $target"
