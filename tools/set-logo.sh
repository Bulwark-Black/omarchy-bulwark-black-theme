#!/usr/bin/env bash
# Rebuild the wallpaper around a logo.
#
#   set-logo.sh             pick an image, then build
#   set-logo.sh --rebuild   rebuild with the logo already chosen (e.g. new size)
#   set-logo.sh --defaults  back to the shipped Bulwark Black logo and settings
#
# Output goes to ~/.config/omarchy/backgrounds/bulwark-black/, Omarchy's place
# for extra per-theme backgrounds, so the shipped branded wallpaper is never
# overwritten. The name keeps "circuit" in it because the background plugin
# gates its live comets on that substring.
set -uo pipefail

# The theme root is wherever this script is sitting — this file lives in the
# theme's tools/, so ".." is the theme. Spelling the name out instead meant a
# fork installed as themes/acme kept looking in themes/bulwark-black, and the
# Comets buttons that launch this script discard stderr, so it failed in total
# silence.
THEME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$THEME/tools/make-wallpaper.py"
PICK="$THEME/tools/pick-image.py"
CFG="$HOME/.config/omarchy/bulwark-comets.json"
# Omarchy keys a theme's extra backgrounds on its installed directory name, so
# that comes off the theme root too: a fork's rebuilds then land in the one
# directory omarchy-theme-bg-next will index for it.
OUTDIR="$HOME/.config/omarchy/backgrounds/$(basename "$THEME")"
# The wallpaper --defaults goes back to. It has to be the STAGED copy, not the
# one under themes/: omarchy-theme-bg-next builds its candidate list out of
# ~/.local/state/omarchy/current/theme/backgrounds/ and OUTDIR only, so a
# symlink into themes/ matches nothing it knows about and the first "next
# background" press after a reset lands straight back on this same image. When
# some other theme is staged this path does not exist, and the reset then
# leaves that theme's wallpaper alone rather than hijacking it.
SHIPPED_BG="$HOME/.local/state/omarchy/current/theme/backgrounds/01-circuit-4k.png"
# Each rebuild gets a fresh filename. Writing the same path again is invisible
# twice over: Background.qml returns early when the new path equals the current
# one, and its base Image has cache:true so QML would serve the old bytes for an
# unchanged URL. That is why a resize appeared to work once and never again.
OUT="$OUTDIR/00-custom-circuit-$(date +%s%N).png"

# Remove every custom wallpaper except the one named, after the switch.
sweep_customs() {
  local keep="${1:-}"
  shopt -s nullglob
  local f
  for f in "$OUTDIR"/00-custom-circuit*.png; do
    [[ $f == "$keep" ]] || rm -f "$f"
  done
}

note()  { notify-send "Bulwark Black" "$1"; }
fail()  { notify-send -u critical "Bulwark Black" "$1"; exit 1; }

command -v magick >/dev/null || fail "ImageMagick (magick) is not installed."
[[ -f $GEN ]] || fail "Generator missing: $GEN"
mkdir -p "$OUTDIR"

read -r size stored <<<"$(python3 - "$CFG" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(int(d.get("logoSize", 880)), d.get("logoPath", "") or "-")
PY
)"
[[ -n ${size:-} ]] || size=880

case "${1:-}" in
  ""|--defaults|--rebuild) ;;
  -h|--help)
    # Everything from line 2 down to the first line that is not a comment. A
    # fixed line range went stale the moment the header changed length and
    # printed "set -uo pipefail" as if it were help.
    sed -n '2,${ /^#/!q; s/^# \?//p; }' "$0"
    exit 0 ;;
  *)
    # Previously anything unrecognised fell through to the picker, so a typo
    # silently opened a fullscreen file dialog instead of reporting itself.
    echo "unknown option: $1" >&2
    echo "usage: set-logo.sh [--rebuild | --defaults]" >&2
    exit 2 ;;
esac

if [[ ${1:-} == --defaults ]]; then
  # Restore everything shipped: the branded wallpaper, the original emblem as
  # the stored logo, and the default slider values. The custom wallpaper is
  # removed rather than left behind, so the background cycler stops offering it.
  # Switch away first, then delete: the shell crossfades from the outgoing
  # wallpaper, and removing it first makes that load a file that is gone.
  omarchy-theme-bg-set "$SHIPPED_BG" >/dev/null 2>&1
  sleep 1
  sweep_customs
  python3 - "$CFG" "$THEME/tools/assets/logo.png" <<'PY'
import json, sys
p, logo = sys.argv[1], sys.argv[2]
json.dump({"version": 1, "count": 6, "speed": 0.55, "thickness": 0.6,
           "logoSize": 880, "logoPath": logo}, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
  note "Restored the Bulwark Black defaults."
  exit 0
fi

if [[ ${1:-} == --rebuild ]]; then
  logo="$stored"
  [[ $logo != "-" && -f $logo ]] || fail "No logo chosen yet — use “Choose an image…” first."
else
  if logo=$(python3 "$PICK" 2>/dev/null); then :; else
    exit 0   # cancelled
  fi
  [[ -n $logo && -f $logo ]] || exit 0
fi

# Render at the actual screen size, not always 4K: on a 1080p monitor that is
# four times the pixels for no visible gain, and it dominates the rebuild time.
res=$(hyprctl monitors -j 2>/dev/null | python3 -c "
import json,sys
try:
    ms=json.load(sys.stdin)
    w=max(m['width'] for m in ms); h=max(m['height'] for m in ms)
    print(f'{w}x{h}' if w>=1280 else '3840x2160')
except Exception:
    print('3840x2160')" 2>/dev/null)
[[ -n ${res:-} ]] || res=3840x2160

# The panel's Size slider runs to 1600, but the generator caps the logo at the
# short edge of the canvas. On a 1080p screen anything above 1080 would be
# refused, which read as "resizing stopped working". Clamp instead of failing.
short=${res#*x}
if (( size > short )); then
  size=$short
  note "Logo size capped to ${short}px — the height of this screen."
fi

note "Building wallpaper at ${size}px…"
if err=$(python3 "$GEN" --logo "$logo" --logo-size "$size" --size "$res" -o "$OUT.tmp" 2>&1); then
  mv -f "$OUT.tmp" "$OUT"
  python3 - "$CFG" "$logo" <<'PY'
import json, sys
p, logo = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["logoPath"] = logo
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
  omarchy-theme-bg-set "$OUT" >/dev/null 2>&1
  sleep 1
  sweep_customs "$OUT"   # drop the previous rebuild, now that we switched off it
  note "Wallpaper rebuilt with $(basename "$logo")"
else
  rm -f "$OUT.tmp"
  # Rejection is not a dead end: try the mechanical repairs, and offer the
  # rest to the user's agent. See tools/rescue-logo.sh.
  "$THEME/tools/rescue-logo.sh" "$logo" &
  disown
fi
