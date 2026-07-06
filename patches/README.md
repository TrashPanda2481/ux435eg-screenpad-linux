# asus-wmi UX435EG ScreenPad quirk

## What this is

A small out-of-tree patch against `drivers/platform/x86/asus-wmi.c`
(plus a one-line struct addition in `asus-wmi.h` and a DMI entry in
`asus-nb-wmi.c`) that gets the ScreenPad 2.0 working on the ASUS
ZenBook UX435EG.

## The bug

On UX435EG shipping with BIOS `UX435EG.315` (2022-04-22), mainline
`asus_wmi` will happily create `/sys/class/backlight/asus_screenpad`
but writes to it are silent no-ops. The panel never lights up.

Root cause: the ATK management WMI GUID
`97845ED0-4E6D-11DE-8A39-0800200C9A66` is declared in the DSDT `_WDG`
table, but on this BIOS the WMI bus does not advertise it in time for
`asus_wmi`'s `wmi_driver` match to fire at probe. `wmi_evaluate_method()`
therefore returns `AE_NOT_FOUND`, `asus_wmi_set_devstate()` bails, and
none of the `DEVS`/`DSTS` calls ever reach `\_SB.ATKD.WMNB`.

You can prove this from userspace: `acpi_call` with the exact same
argument buffer that `asus_wmi_evaluate_method3()` would have built
does light the panel. So the DSDT side is fine. It's purely that the
kernel driver's WMI probe path doesn't fire on this SKU/BIOS.

## What the patch does

1. Adds a `wmi_force_mgmt_attach` bool to `struct quirk_entry`.
2. Adds a DMI match for the UX435EG in `asus-nb-wmi.c`'s `asus_quirks[]`
   table, wired to that flag.
3. In `asus_wmi_add()`, if the quirk is set and `\_SB.ATKD.WMNB`
   resolves via `acpi_get_handle()`, sets a driver-global
   `asus_wmi_mgmt_forced` flag.
4. In `asus_wmi_evaluate_method3()`, if that flag is set, skips
   `wmi_evaluate_method()` and calls `acpi_evaluate_object()` on
   `\_SB.ATKD.WMNB` directly with the same 3-arg convention
   (instance, method_id, input buffer).

The fallback path is essentially a shortcut around the WMI bus. The
DSDT method it lands on is the same one `wmi_evaluate_method()` would
have dispatched to, so DEVS/DSTS semantics are unchanged.

## Confirmed working

- Kernel 7.0.12+deb13-amd64 (Debian trixie)
- Hardware: ASUS ZenBook UX435EG, Tiger Lake, MX450, ScreenPad 2.0
  (2160x1080)
- BIOS: UX435EG.315

After patch:

```
$ dmesg | grep asus_wmi
asus_wmi: Detected ATK management GUID (fallback), binding
asus_wmi: ScreenPad backlight registered

$ echo 200 | sudo tee /sys/class/backlight/asus_screenpad/brightness
```

Panel lights up, brightness sweeps 0..255 correctly, POWER off drops
the panel and back on wakes it. Fn-key hotkeys and the primary panel
backlight are unaffected. Been running with this ~two weeks daily, no
regressions I've noticed.

## Not yet submitted upstream

I want to test on at least one more BIOS revision before sending it
to `platform-driver-x86@vger.kernel.org` and Cc'ing Corentin Chary and
Luke Jones. The DMI match is intentionally narrow (exact
`DMI_PRODUCT_NAME`) so it shouldn't affect other SKUs, but I'd rather
not spam LKML with a one-user quirk if it turns out a broader fix
(e.g. probing WMNB by handle when the GUID match misses, without any
DMI gate) is the right shape.

If you're on the same laptop and want to try it: `checkpatch.pl`
clean, applies against 7.0.12, builds as a module. Standard
`make -C /lib/modules/$(uname -r)/build M=$PWD/drivers/platform/x86
modules` from a source tree with the patch applied.

## Files

- `0001-platform-x86-asus-wmi-add-UX435EG-quirk.patch`. The patch
  itself, in `git format-patch` form.
