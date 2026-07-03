#!/usr/bin/env bash
# diagnose.sh - collect a diagnostic bundle for the UX435EG ScreenPad situation
#
# Writes everything to a single log file. No sudo required for most of it, but
# dmidecode and /proc/acpi/call need root - the script will note when they're
# skipped.

set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/ux435-diagnose-${STAMP}.log"

# little helpers -------------------------------------------------------------

section() {
    {
        echo
        echo "============================================================"
        echo "== $*"
        echo "============================================================"
    } >> "${LOG}"
}

run() {
    echo "\$ $*" >> "${LOG}"
    # capture stdout AND stderr, don't let a nonzero exit kill the script
    "$@" >> "${LOG}" 2>&1 || echo "  (exit $?)" >> "${LOG}"
}

# header ---------------------------------------------------------------------

: > "${LOG}"
{
    echo "ux435eg-screenpad diagnostic bundle"
    echo "generated: $(date -Iseconds)"
    echo "hostname:  $(hostname)"
    echo "user:      $(whoami) (uid=$(id -u))"
} >> "${LOG}"

# --- system ---
section "uname"
run uname -a

section "os-release"
run cat /etc/os-release

section "dmidecode - system + BIOS"
if [[ "${EUID}" -eq 0 ]] && command -v dmidecode >/dev/null 2>&1; then
    run dmidecode -s system-product-name
    run dmidecode -s system-manufacturer
    run dmidecode -s bios-version
    run dmidecode -s bios-release-date
else
    echo "(skipped: need root + dmidecode installed)" >> "${LOG}"
    # non-root fallbacks
    for f in /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor \
             /sys/class/dmi/id/bios_version /sys/class/dmi/id/bios_date; do
        if [[ -r "${f}" ]]; then
            echo "${f}: $(cat "${f}")" >> "${LOG}"
        fi
    done
fi

# --- kernel modules ---
section "lsmod - asus_wmi + acpi_call"
run bash -c "lsmod | grep -E 'asus|acpi_call|wmi' || echo '(no matches)'"

section "modinfo asus_wmi"
run modinfo asus_wmi

section "modinfo acpi_call"
run modinfo acpi_call

section "dkms status"
if command -v dkms >/dev/null 2>&1; then
    run dkms status
else
    echo "(dkms not installed)" >> "${LOG}"
fi

# --- backlight + LEDs ---
section "/sys/class/backlight"
run ls -la /sys/class/backlight/
for d in /sys/class/backlight/*/; do
    [[ -d "${d}" ]] || continue
    name="$(basename "${d}")"
    echo "--- ${name} ---" >> "${LOG}"
    for f in brightness max_brightness actual_brightness bl_power type; do
        if [[ -r "${d}${f}" ]]; then
            echo "${f}: $(cat "${d}${f}" 2>/dev/null)" >> "${LOG}"
        fi
    done
done

section "/sys/class/leds"
run ls -la /sys/class/leds/
for d in /sys/class/leds/asus*/; do
    [[ -d "${d}" ]] || continue
    name="$(basename "${d}")"
    echo "--- ${name} ---" >> "${LOG}"
    for f in brightness max_brightness; do
        if [[ -r "${d}${f}" ]]; then
            echo "${f}: $(cat "${d}${f}" 2>/dev/null)" >> "${LOG}"
        fi
    done
done

# --- WMI devices + driver bindings ---
section "/sys/bus/wmi/devices"
run ls -la /sys/bus/wmi/devices/
for d in /sys/bus/wmi/devices/*/; do
    [[ -d "${d}" ]] || continue
    guid="$(basename "${d}")"
    drv="(unbound)"
    if [[ -L "${d}driver" ]]; then
        drv="$(readlink -f "${d}driver" | xargs basename)"
    fi
    echo "  ${guid}  ->  ${drv}" >> "${LOG}"
done

section "target GUID check (97845ED0-4E6D-11DE-8A39-0800200C9A66)"
target="97845ED0-4E6D-11DE-8A39-0800200C9A66"
found=""
for d in /sys/bus/wmi/devices/*/; do
    if [[ "$(basename "${d}")" == "${target}" ]]; then
        found="${d}"
        break
    fi
done
if [[ -n "${found}" ]]; then
    echo "found: ${found}" >> "${LOG}"
    if [[ -L "${found}driver" ]]; then
        echo "driver: $(readlink -f "${found}driver")" >> "${LOG}"
    else
        echo "driver: UNBOUND (this is the bug)" >> "${LOG}"
    fi
else
    echo "NOT FOUND in /sys/bus/wmi/devices - _WDG never declared it?" >> "${LOG}"
fi

# --- DSDT bits ---
section "DSDT grep (needs /tmp/DSDT.dsl)"
if [[ -f /tmp/DSDT.dsl ]]; then
    echo "-- WMNB references --" >> "${LOG}"
    run grep -n "WMNB" /tmp/DSDT.dsl
    echo "-- ATKD block --" >> "${LOG}"
    run grep -n "ATKD" /tmp/DSDT.dsl
    echo "-- ScreenPad DEVID 0x50031 --" >> "${LOG}"
    run grep -n -i "0x00050031\|50031" /tmp/DSDT.dsl
    echo "-- ScreenPad DEVID 0x50032 --" >> "${LOG}"
    run grep -n -i "0x00050032\|50032" /tmp/DSDT.dsl
    echo "-- WMI mgmt GUID (partial match) --" >> "${LOG}"
    run grep -n -i "97845ED0" /tmp/DSDT.dsl
else
    echo "(/tmp/DSDT.dsl not present. get it with:" >> "${LOG}"
    echo "   sudo cp /sys/firmware/acpi/tables/DSDT /tmp/DSDT.dat" >> "${LOG}"
    echo "   iasl -d /tmp/DSDT.dat" >> "${LOG}"
    echo " which produces /tmp/DSDT.dsl. then re-run this script.)" >> "${LOG}"
fi

# --- acpi_call state ---
section "acpi_call presence"
if [[ -e /proc/acpi/call ]]; then
    echo "/proc/acpi/call EXISTS" >> "${LOG}"
    run stat /proc/acpi/call
else
    echo "/proc/acpi/call MISSING (module not loaded?)" >> "${LOG}"
fi

# --- dmesg tail (asus/wmi) ---
section "dmesg - asus/wmi/acpi lines"
if [[ "${EUID}" -eq 0 ]] || dmesg >/dev/null 2>&1; then
    run bash -c "dmesg | grep -iE 'asus|wmi|acpi_call|screenpad' | tail -100"
else
    echo "(dmesg needs CAP_SYSLOG on this kernel)" >> "${LOG}"
fi

# --- installed pieces of our own package ---
section "our installed files"
for f in /usr/local/bin/ux435-screenpad \
         /etc/systemd/system/ux435-screenpad-boot.service \
         /etc/udev/rules.d/99-ux435-screenpad.rules \
         /etc/modules-load.d/acpi_call.conf; do
    if [[ -e "${f}" ]]; then
        echo "  present: ${f}" >> "${LOG}"
    else
        echo "  missing: ${f}" >> "${LOG}"
    fi
done

section "systemctl status ux435-screenpad-boot"
run systemctl status --no-pager ux435-screenpad-boot.service

# --- done ---

echo
echo "diagnostic bundle written to: ${LOG}"
echo "attach it to bug reports, or paste with:"
echo "  cat ${LOG}"
