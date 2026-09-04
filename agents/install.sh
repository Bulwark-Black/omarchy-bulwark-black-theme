#!/usr/bin/env bash
# Make the prepare-logo skill visible to whichever coding agent is installed.
# Mirrors what omarchy-provision-user does for Omarchy's own skills: a symlink
# into every agent's skill directory, so editing the theme updates them all.
#
# All four directories are created whether or not you run that agent, because
# that is exactly what Omarchy itself does — omarchy-provision-user mkdir -p's
# the same four before linking its own skills into them. On any Omarchy machine
# they already exist, so this seeds nothing new, and guessing which agents are
# installed would only make the theme disagree with the system it ships for.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill="$here/skills/prepare-logo"
[[ -d $skill ]] || { echo "missing $skill" >&2; exit 1; }

for dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
  mkdir -p "$dir"
  ln -sfn "$skill" "$dir/prepare-logo"
  echo "  linked into ${dir/#$HOME/\~}"
done
echo "prepare-logo is available to your agent. Undo with: ${here/#$HOME/\~}/uninstall.sh"
