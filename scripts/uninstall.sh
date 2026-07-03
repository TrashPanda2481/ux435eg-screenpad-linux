#!/usr/bin/env bash
# uninstall.sh - remove ux435eg-screenpad from the system
#
# Usage: sudo ./scripts/uninstall.sh
#
# Does NOT purge acpi-call-dkms - other stuff might be using it. Remove that
# by hand if you want:
#   sudo apt-get purge acpi-call-dkms

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "error: must run as root. try: sudo $0" >&2
    exit 1
fi

BIN_DST="/usr/local/bin/ux435-screenpad"
UNIT_DST="/etc/systemd/system/ux435-screenpad-boot.service"
UDEV_DST="/etc/udev/rules.d/99-ux435-screenpad.rules"
MODLOAD="/etc/modules-load.d/acpi_call.conf"

echo "==> disabling + stopping boot service"
if systemctl list-unit-files | grep -q '^ux435-screenpad-boot\.service'; then
    systemctl disable --now ux435-screenpad-boot.service || true
fi

echo "==> removing installed files"
for f in "${UNIT_DST}" "${UDEV_DST}" "${BIN_DST}" "${MODLOAD}"; do
    if [[ -e "${f}" ]]; then
        echo "  - ${f}"
        rm -f "${f}"
    fi
done

echo "==> reloading systemd + udev"
systemctl daemon-reload
udevadm control --reload-rules

echo
echo "uninstall complete."
echo "acpi-call-dkms was left installed. remove with:"
echo "  sudo apt-get purge acpi-call-dkms"

# --- user-session xrandr piece ---
rm -f /usr/local/bin/screenpad-display
rm -f /usr/lib/systemd/user/ux435-screenpad-display.service
