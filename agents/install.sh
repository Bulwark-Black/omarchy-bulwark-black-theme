#!/usr/bin/env bash
# Make the prepare-logo skill visible to whichever coding agent is installed.
# Mirrors what omarchy-provision-user does for Omarchy's own skills: a symlink
# into every agent's skill directory, so editing the theme updates them all.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill="$here/skills/prepare-logo"
[[ -d $skill ]] || { echo "missing $skill" >&2; exit 1; }

installed=0
for dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
  mkdir -p "$dir"
  ln -sfn "$skill" "$dir/prepare-logo"
  echo "  linked into ${dir/#$HOME/\~}"
  installed=1
done
(( installed )) && echo "prepare-logo is available to your agent."
