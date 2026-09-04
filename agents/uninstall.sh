#!/usr/bin/env bash
# Undo agents/install.sh: take the prepare-logo symlink back out of every
# agent's skill directory.
#
# `omarchy theme remove bulwark-black` deletes the theme and knows nothing about
# these links, so it leaves four dangling ones behind. Run this first — it lives
# inside the theme, so removing the theme takes it with it.
#
# A link is only removed while it still points at this copy of the skill. If you
# have since pointed prepare-logo at a checkout of your own, that link is yours
# and is left exactly where it is.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill="$here/skills/prepare-logo"

removed=0
for dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
  link="$dir/prepare-logo"
  [[ -L $link ]] || continue
  target="$(readlink "$link")"
  if [[ $target == "$skill" ]]; then
    rm -f "$link"
    echo "  unlinked from ${dir/#$HOME/\~}"
    removed=1
  else
    echo "  left ${link/#$HOME/\~} alone — it points at ${target/#$HOME/\~}"
  fi
done

if (( removed )); then
  echo "prepare-logo is no longer offered to your agent."
else
  echo "nothing to undo — no agent was linked to this copy of prepare-logo."
fi
