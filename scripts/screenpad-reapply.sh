#!/bin/bash
# screenpad-reapply.sh. Re-apply the entire ScreenPad config in one shot.
#
# Useful when KDE (or anything else) reconfigures displays and the ScreenPad
# drops off. This re-fires the WMI power call and re-runs xrandr rotate/position.
#
# Bind it to a keyboard shortcut in your DE. E.g. Meta+Shift+P in KDE.

set -euo pipefail

: "${DISPLAY:=:0}"
export DISPLAY

# 1. WMI power on + brightness (needs root for /proc/acpi/call)
if command -v pkexec >/dev/null 2>&1; then
    pkexec ux435-screenpad power on
    pkexec ux435-screenpad brightness 128
else
    sudo ux435-screenpad power on
    sudo ux435-screenpad brightness 128
fi

# 2. Give i915 a beat to re-enumerate HDMI-2
sleep 1

# 3. Re-apply xrandr rotation + position
if command -v screenpad-display >/dev/null 2>&1; then
    screenpad-display
else
    # inline fallback if the display script isn't installed
    for cand in HDMI-2 HDMI-1; do
        if xrandr --query 2>/dev/null | grep -qE "^${cand} connected .* 66mm x 134mm"; then
            xrandr --output "$cand" --rotate right --pos 0x1080
            xrandr --output eDP-1 --pos 156x0
            break
        fi
    done
fi
