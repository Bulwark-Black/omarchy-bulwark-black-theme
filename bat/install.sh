#!/usr/bin/env bash
# Install the Bulwark Black syntax theme for bat.
#
# Omarchy themes alacritty, ghostty, btop, helix, neovim and vscode, but has no
# template for bat — so bat stays on Monokai regardless of your theme. This puts
# the palette in bat too.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/bat"

mkdir -p "$dest/themes"
cp "$here/Bulwark Black.tmTheme" "$dest/themes/"
bat cache --build >/dev/null

conf="$dest/config"
touch "$conf"
if grep -q '^--theme=' "$conf"; then
  sed -i 's|^--theme=.*|--theme="Bulwark Black"|' "$conf"
else
  printf '%s\n' '--theme="Bulwark Black"' >>"$conf"
fi
echo "bat is now using Bulwark Black. Undo with: sed -i '/^--theme=/d' $conf"
