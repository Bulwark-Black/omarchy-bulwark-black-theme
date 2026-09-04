#!/usr/bin/env bash
# Remove the Bulwark Black shell plugins and hand the desktop back to Omarchy's.
#
# `omarchy plugin remove` is the piece that reads manifest.omarchy.clonedFrom:
# taking away the background fork re-enables omarchy.background rather than
# leaving the desktop with no background service at all. Where that command is
# missing we do the same three steps by hand — disable, delete, rescan — because
# deleting the folder on its own leaves the fork listed in shell.json and the
# first-party service still switched off.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins="$HOME/.config/omarchy/plugins"

# The manifest id is what the plugin was installed under; fall back to the
# folder name only when jq is gone, which is also the only case where the
# by-hand path below has to do everything itself.
plugin_id() {
  if command -v jq >/dev/null && [[ -f $1/manifest.json ]]; then
    jq -r '.id // empty' "$1/manifest.json"
  else
    basename "$1"
  fi
}

removed=0
for src in "$here"/*/; do
  src="${src%/}"
  [[ -f $src/manifest.json ]] || continue
  id=$(plugin_id "$src")
  [[ -n $id ]] || continue

  target="$plugins/$id"
  if [[ ! -e $target && ! -L $target ]]; then
    echo "  $id is not installed"
    continue
  fi

  if command -v omarchy-plugin-remove >/dev/null; then
    # It disables first, so the clonedFrom restore happens while the shell still
    # knows the plugin, then backs the folder up and rescans. Indented to sit
    # with the rest of the output; its backup path is worth keeping.
    omarchy-plugin-remove "$id" --yes | sed 's/^/  /'
  else
    cloned_from=""
    if command -v jq >/dev/null && [[ -f $target/manifest.json ]]; then
      cloned_from=$(jq -r '.omarchy.clonedFrom // empty' "$target/manifest.json")
    fi
    # Disable before deleting: setEnabled(false) is what drops the bar entry and
    # restores the cloned-from service, and it can only do that while the
    # manifest is still on disk to be read.
    omarchy-shell -q shell setPluginEnabled "$id" false >/dev/null || true
    rm -rf "$target"
    omarchy-shell -q shell rescanPlugins >/dev/null || true
    echo "  removed $id"
    if [[ -n $cloned_from ]]; then
      omarchy-shell -q shell enablePlugin "$cloned_from" '{}' >/dev/null || true
      echo "  restored $cloned_from"
    fi
  fi
  removed=1
done

if (( removed )) && [[ -f $HOME/.config/omarchy/bulwark-comets.json ]]; then
  echo "  comet settings kept at ~/.config/omarchy/bulwark-comets.json — delete it if you are done"
fi

if (( removed )); then
  echo "Plugins removed. Reinstall with: ${here/#$HOME/\~}/install.sh"
else
  echo "Nothing to remove."
fi
