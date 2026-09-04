#!/usr/bin/env bash
# Called when make-wallpaper.py refuses a logo.
#
# Tries the mechanical repairs first, because they are deterministic and cost
# nothing. Only when a rejection needs judgement — usually "too small", which
# no amount of processing can fix — does it offer to hand the job to whichever
# coding agent the user has configured. Clicking the notification is the
# consent; nothing is sent to an agent without it.
set -uo pipefail

# Same derivation as set-logo.sh, which is what launches this: this file lives
# in the theme's tools/, so ".." is the theme. A hardcoded bulwark-black sent a
# fork at a doctor and a skill it does not have, and set-logo.sh runs this in
# the background with its output thrown away, so nothing would have said so.
THEME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$THEME/tools/logo-doctor.py"
SKILL="$THEME/agents/skills/prepare-logo/SKILL.md"
logo=${1:?usage: rescue-logo.sh <image>}

fixed="${logo%.*}-fixed.png"
if python3 "$DOCTOR" "$logo" --fix -o "$fixed" 2>/dev/null | grep -q "passes every check"; then
  python3 - "$HOME/.config/omarchy/bulwark-comets.json" "$fixed" <<'PY'
import json, sys
p, logo = sys.argv[1], sys.argv[2]
try: d = json.load(open(p))
except Exception: d = {}
d["logoPath"] = logo
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
PY
  "$THEME/tools/set-logo.sh" --rebuild >/dev/null 2>&1
  notify-send "Bulwark Black" "That logo needed repairing — done, and applied."
  exit 0
fi

why=$(python3 "$DOCTOR" "$logo" 2>/dev/null | sed -n 's/^  \[manual\] *//p' | head -1)
[[ -n $why ]] || why="It needs preparing before it can be used."

# The click is the permission. Until then nothing leaves this machine.
omarchy-notification-send -u critical \
  "Logo needs work" \
  "$why  Click to hand it to your coding agent." \
  --exec bash -c "omarchy-agent --prompt \"\$(cat <<'P'
I picked an image to use as the logo on my Bulwark Black wallpaper, but the
theme's generator will not accept it, and the mechanical repairs did not fix it.

  image: $logo

$(python3 "$DOCTOR" "$logo" 2>/dev/null | sed -n 's/^  \[[a-z]*\] *//p' | sed 's/^/  - /')

Please use the prepare-logo skill. If your harness has no skill mechanism, read
it directly and follow it:

  $SKILL
P
)\""
