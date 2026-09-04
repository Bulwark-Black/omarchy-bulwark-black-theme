#!/usr/bin/env bash
# Install the Bulwark Black shell plugins.
#
# `omarchy plugin add` git-clones a URL and expects manifest.json at the clone
# root, so it cannot reach a plugin that lives inside a theme repo; `omarchy
# theme install` does copy plugins/ across, but the shell only ever scans
# ~/.config/omarchy/plugins, so a copy sitting in the theme dir is never loaded.
# This does by hand what add would have done: validate, copy into the directory
# the registry watches, make the running shell rescan, then enable.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins="$HOME/.config/omarchy/plugins"

for cmd in jq omarchy-plugin-validate omarchy-plugin-enable omarchy-plugin-list omarchy-shell; do
  command -v "$cmd" >/dev/null || { echo "$cmd not found — is Omarchy installed?" >&2; exit 1; }
done

# Everything after the copy is an IPC call into the running shell, so say so now
# rather than half-installing and failing on the enable.
omarchy-shell shell ping >/dev/null 2>&1 ||
  { echo "omarchy-shell is not answering. Start the shell, then run this again." >&2; exit 1; }

# Read and check every plugin before copying any of them, so a manifest the
# registry would reject leaves the machine as it found it rather than half
# installed.
declare -A source_of=()
ids=()
for src in "$here"/*/; do
  src="${src%/}"
  [[ -f $src/manifest.json ]] || continue

  # The folder is only a convenience; the manifest id is what the registry keys
  # on and what `omarchy plugin remove <id>` looks for on disk, so install under
  # the id even where the two disagree.
  id=$(jq -r '.id // empty' "$src/manifest.json")
  [[ -n $id ]] || { echo "${src##*/}/manifest.json has no id" >&2; exit 1; }

  # The same check omarchy-plugin-add runs before it accepts a clone. A plugin
  # runs unsandboxed inside the shell process; anything the registry would
  # reject at load time is refused here instead, while there is still someone
  # to tell.
  omarchy-plugin-validate "$src" || { echo "refusing to install $id" >&2; exit 1; }

  ids+=("$id")
  source_of["$id"]="$src"
done
(( ${#ids[@]} )) || { echo "no plugins found in ${here/#$HOME/\~}" >&2; exit 1; }

stage=""
cleanup() { [[ -z $stage ]] || rm -rf "$stage"; }
trap cleanup EXIT

mkdir -p "$plugins"

copied=()
for id in "${ids[@]}"; do
  dest="$plugins/$id"
  if [[ -L $dest ]]; then
    echo "  $id is a symlink to $(readlink "$dest") — left alone"
    continue
  fi
  if [[ -d $dest/.git ]]; then
    echo "  $id is a git checkout — update it with: omarchy plugin update $id"
    continue
  fi

  # Build the new copy beside the old one and swap, so a half-copied plugin is
  # never what the shell rescans, and a re-run after a theme update refreshes
  # the files rather than merging into them. The leading dot keeps the staging
  # folder out of omarchy-plugin-catalog's scan the way add's .add.tmp does.
  stage="$plugins/.install.tmp.$$.$id"
  rm -rf "$stage"
  cp -R "${source_of[$id]}" "$stage"
  rm -rf "$dest"
  mv "$stage" "$dest"
  stage=""
  echo "  copied $id into ${plugins/#$HOME/\~}/"
  copied+=("$id")
done
(( ${#copied[@]} )) || { echo "Nothing copied; the installed plugins are managed elsewhere."; exit 0; }

# omarchy-plugin-add does this straight after its own copy, and a hand copy has
# to do it too: without the rescan the shell keeps the plugin list it built at
# startup, and enable answers "not known" for a plugin sitting right there on
# disk.
omarchy-shell shell rescanPlugins >/dev/null

for id in "${copied[@]}"; do
  # The rescan is a subprocess and the IPC call returns before it finishes, so
  # give the id a moment to show up rather than treating a slow scan as absent.
  entry=""
  for (( attempt = 0; attempt < 40; attempt++ )); do
    entry=$(omarchy-plugin-list --json 2>/dev/null |
      jq -c --arg id "$id" 'map(select(.id == $id))[0] // empty' 2>/dev/null || true)
    if [[ -n $entry ]]; then break; fi
    sleep 0.05
  done
  [[ -n $entry ]] ||
    { echo "$id never appeared in the plugin list; enable it with: omarchy plugin enable $id" >&2; exit 1; }

  # Enabling what is already enabled is harmless, but saying so is more use than
  # a second "Enabled" on a re-run.
  if [[ $(jq -r '.enabled' <<<"$entry") == true ]]; then
    echo "  $id already enabled"
  else
    # No placement: the bar widget carries barWidget.defaultSection and lands
    # beside the tray on its own.
    omarchy-plugin-enable "$id" >/dev/null
    echo "  enabled $id"
  fi
done

echo "Plugins installed. Undo with: ${here/#$HOME/\~}/uninstall.sh"
