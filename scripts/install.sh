#!/usr/bin/env bash
# install.sh - system-wide install of ux435eg-screenpad
#
# Usage: sudo ./scripts/install.sh [--dry-run]
#
# Idempotent. Safe to re-run.

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "[dry-run] no changes will be made"
fi

# resolve repo root regardless of where the script is invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_SRC="${REPO_ROOT}/src/ux435-screenpad"
UNIT_SRC="${REPO_ROOT}/systemd/ux435-screenpad-boot.service"
UDEV_SRC="${REPO_ROOT}/udev/99-ux435-screenpad.rules"
DISPLAY_SH_SRC="${REPO_ROOT}/scripts/screenpad-display.sh"
DISPLAY_UNIT_SRC="${REPO_ROOT}/systemd/user/ux435-screenpad-display.service"

BIN_DST="/usr/local/bin/ux435-screenpad"
UNIT_DST="/etc/systemd/system/ux435-screenpad-boot.service"
UDEV_DST="/etc/udev/rules.d/99-ux435-screenpad.rules"
DISPLAY_SH_DST="/usr/local/bin/screenpad-display"
DISPLAY_UNIT_DST="/usr/lib/systemd/user/ux435-screenpad-display.service"

# --- sanity ---

for f in "${BIN_SRC}" "${UNIT_SRC}" "${UDEV_SRC}" "${DISPLAY_SH_SRC}" "${DISPLAY_UNIT_SRC}"; do
    if [[ ! -f "${f}" ]]; then
        echo "error: missing source file: ${f}" >&2
        exit 1
    fi
done

if [[ ${DRY_RUN} -eq 0 && "${EUID}" -ne 0 ]]; then
    echo "error: must run as root (or --dry-run). try: sudo $0" >&2
    exit 1
fi

run() {
    if [[ ${DRY_RUN} -eq 1 ]]; then
        printf '  [dry-run] %s\n' "$*"
    else
        printf '  + %s\n' "$*"
        "$@"
    fi
}

# --- 1. dependencies ---

echo "==> installing acpi-call-dkms (needed for /proc/acpi/call)"
if command -v apt-get >/dev/null 2>&1; then
    if [[ ${DRY_RUN} -eq 1 ]]; then
        echo "  [dry-run] apt-get install -y acpi-call-dkms dkms"
    else
        # DEBIAN_FRONTEND avoids the debconf tty prompt from dkms
        DEBIAN_FRONTEND=noninteractive apt-get install -y acpi-call-dkms dkms
    fi
else
    echo "  warning: apt-get not found; make sure acpi_call is available some other way"
fi

# --- 2. install files ---

echo "==> installing binary"
run install -m 0755 "${BIN_SRC}" "${BIN_DST}"

echo "==> installing systemd unit"
run install -m 0644 "${UNIT_SRC}" "${UNIT_DST}"

echo "==> installing udev rule"
run install -m 0644 "${UDEV_SRC}" "${UDEV_DST}"

# --- 3. load acpi_call ---

echo "==> loading acpi_call module"
if [[ ${DRY_RUN} -eq 0 ]]; then
    # DKMS may still be building on a fresh install; retry a couple times
    for i in 1 2 3; do
        if modprobe acpi_call 2>/dev/null; then
            break
        fi
        echo "  modprobe attempt ${i} failed, waiting..."
        sleep 2
    done
    if ! lsmod | grep -q '^acpi_call'; then
        echo "  warning: acpi_call not loaded. run 'sudo modprobe acpi_call' manually after DKMS finishes building."
    fi
else
    echo "  [dry-run] modprobe acpi_call"
fi

# make it load at boot
echo "==> ensuring acpi_call loads at boot"
run bash -c 'echo acpi_call > /etc/modules-load.d/acpi_call.conf'

# --- 4. udev + systemd reload ---

echo "==> reloading udev"
run udevadm control --reload-rules
run udevadm trigger --subsystem-match=backlight

echo "==> reloading systemd + enabling boot service"
run systemctl daemon-reload
run systemctl enable --now ux435-screenpad-boot.service

# --- 5. done ---

echo
echo "install complete."
if [[ ${DRY_RUN} -eq 0 ]]; then
    echo
    echo "test with:"
    echo "  sudo ux435-screenpad power on"
    echo "  sudo ux435-screenpad brightness 128"
    echo
    echo "if the panel doesn't come up, run scripts/diagnose.sh"
fi

# --- 6. user-session xrandr piece ---

echo "==> installing user-session display piece"
run install -m 0755 "${DISPLAY_SH_SRC}" "${DISPLAY_SH_DST}"
run install -Dm 0644 "${DISPLAY_UNIT_SRC}" "${DISPLAY_UNIT_DST}"

if [[ ${DRY_RUN} -eq 0 ]]; then
    echo
    echo "enable the display piece in your session (as your user, not root):"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable --now ux435-screenpad-display.service"
fi
