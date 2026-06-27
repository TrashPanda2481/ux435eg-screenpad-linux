# DSDT analysis. UX435EG.315

Notes from decompiling the DSDT on my UX435EG (BIOS UX435EG.315, 2022-04-22).
The point of this file is to save the next person from repeating the same
grep sessions I did.

## How I got here

```
sudo cp /sys/firmware/acpi/tables/DSDT /tmp/DSDT.dat
iasl -d /tmp/DSDT.dat
# writes /tmp/DSDT.dsl next to it
```

`acpica-tools` on Debian, `pacman -S acpica` on Arch. `iasl -d` prints a small
mountain of "unresolved external references". Ignore those, they're normal for
a DSDT that references other tables (SSDT, etc.). The file we want is the
`.dsl`.

## What's actually in there

Three things matter for the ScreenPad path.

### 1. The ATK WMI GUID is declared

```
grep -n "97845ED0" /tmp/DSDT.dsl
```

Returns one hit inside a `_WDG` buffer. So the firmware *does* advertise the
ATK management GUID (`97845ED0-4E6D-11DE-8A39-0800200C9A66`, the value that
`ASUS_WMI_MGMT_GUID` in `include/linux/platform_data/x86/asus-wmi.h` resolves
to). This is the part that made me think everything was fine for a while. The
DSDT is not the problem.

### 2. WMNB exists at the expected path

```
grep -n "WMNB" /tmp/DSDT.dsl
```

Two hits: the method definition itself and one call site. The definition is a
`Serialized` method under `\_SB.ATKD` taking three arguments. Instance,
method_id, input buffer. Which matches the WMI-ACPI mapping convention exactly.

Full path: `\_SB.ATKD.WMNB`.

### 3. DEVS/DSTS dispatch on method_id and DEVID

The body of `WMNB` is a big `Switch` (well, chained `If`s. This is ASL) on the
method_id argument. For `'DEVS'` (`0x53564544` as an LE u32) it decodes the
input buffer as `{ u32 dev_id; u32 ctrl_param; ... }` and dispatches again on
`dev_id`.

The ScreenPad DEVIDs are exactly what asus-wmi.h claims:

- `0x00050031`. POWER on/off (ctrl_param `0` or `1`)
- `0x00050032`. LIGHT brightness (ctrl_param `0..255`)

For `'DSTS'` (`0x53545344`) the same DEVID lookup runs, but the return package
is a `{ present_bit, value }` pair. The `0x00010000` bit signals "this DEVID
is supported on this board" and the low bits are the current value. That's the
same shape mainline `asus-wmi` expects.

## Why the kernel driver fails on this BIOS anyway

Best guess, and I want to be clear this is a guess:

The GUID is in `_WDG` (so the DSDT knows about it) but the WMI bus in
`drivers/platform/x86/wmi.c` doesn't advertise it early enough for the
`asus-wmi` `wmi_driver` match to fire at probe time. `wmi_evaluate_method()`
returns `AE_NOT_FOUND`, `asus_wmi_set_devstate()` bails, and the DEVS call
never reaches WMNB.

I can prove the DSDT side is fine because `acpi_call` with the exact same
argument buffer that `asus_wmi_evaluate_method3()` would have built (see
`docs/wmi-encoding.md`) does dispatch through WMNB and does light the panel.
So the failure is somewhere between the WMI bus enumeration and the driver's
probe, not in ACPI itself.

The kernel patch in `patches/` is a DMI-gated workaround that falls back to
`acpi_evaluate_object()` on the WMNB handle directly when the WMI bus match
misses. It's a hack, but it's the smallest hack I could come up with that
doesn't require changing the WMI bus code.

## Things I ruled out

- **Path typo.** The path is `\_SB.ATKD.WMNB` not `\_SB.PCI0.LPC.ATKD.WMNB`.
  Some older ASUS DSDTs have the second form. This one's the flat variant.
- **Instance != 0.** UX435EG uses WMI instance 0. Confirmed by trying
  `\_SB.ATKD.WMNB 1 0x53564544 ...`. WMNB returns nothing useful.
- **Byte order on method_id.** `'DEVS'` in memory is `44 45 56 53` (D,E,V,S).
  As a little-endian `u32` that reads back as `0x53564544`. Passing
  `0x44455653` (the naive "spell it out in hex" version) walks off the switch
  and returns an error status. I burned an hour on this.
- **Padding.** Modern kernel `bios_args` is 6×u32 = 24 bytes. WMNB only reads
  the first two DWORDs on this board, so 8 bytes work too. See
  `docs/wmi-encoding.md`. Padding zeros beyond that are ignored.

## What I'd still like to check

- Whether the same _WDG entry maps a different WM method identifier that the
  bus is looking for. If someone with a working UX435 or UX434 can dump their
  DSDT and share the WMNB block, I'd like to diff the `_WDG` structure.
- Whether `SSDT` overlays add anything (I have not decompiled those yet).
