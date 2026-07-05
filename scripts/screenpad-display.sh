#!/bin/bash
# screenpad-display.sh. Position and rotate the ScreenPad after login.
# Assumes ux435-screenpad power on has already run (from the system boot unit)
# and that i915 has enumerated the panel as HDMI-2 (or HDMI-1 on some models , 
# we handle both).
#
# UX435EG native panel: 1080x2160 portrait. Rotated right for landscape use
# below the main display.

set -euo pipefail

: "${DISPLAY:=:0}"
export DISPLAY

# Find the ScreenPad output. UX435EG uses HDMI-2; some older UX4xx may be HDMI-1.
# We identify by the 66mm x 134mm physical size in the xrandr line.
#
# There is a timing race at boot: the system unit fires the WMI power call,
# but i915 takes a moment to enumerate HDMI-2 as connected and populate its
# EDID. If we probe too early we see "no output" and exit. Poll for up to
# ~15 seconds before giving up.
SP_OUTPUT=""
for attempt in $(seq 1 15); do
    for cand in HDMI-2 HDMI-1; do
        if xrandr --query 2>/dev/null | grep -qE "^${cand} connected .* 66mm x 134mm"; then
            SP_OUTPUT="$cand"
            break 2
        fi
    done
    sleep 1
done

if [ -z "$SP_OUTPUT" ]; then
    echo "screenpad-display: no ScreenPad-sized output on HDMI-1 or HDMI-2 after 15s" >&2
    echo "screenpad-display: check that the boot unit ran (ux435-screenpad power on)" >&2
    exit 1
fi

# Full pipe cycle. Just re-applying --rotate/--pos on an already-enabled
# HDMI-2 leaves the connector in a state where the framebuffer says
# "enabled at 2160x1080+0+1080 rotated right" but no scanout actually
# reaches the panel (backlight on, screen dark). Explicit --off then
# --mode + --rotate + --pos gives i915 a clean pipe re-setup.
xrandr --output "$SP_OUTPUT" --off
sleep 1
xrandr --output "$SP_OUTPUT" --mode 1080x2160 --rotate right --pos 0x1080

# Nudge the primary so it sits sensibly above the wider ScreenPad. Optional , 
# comment this out if you like the main screen locked at 0,0.
xrandr --output eDP-1 --pos 156x0
