# ScreenPad userspace SET/GET (ASUS UX435EG)

Two tools that drive the ScreenPad on the ZenBook UX435EG directly via
`\_SB.ATKD.WMNB` in the DSDT, using the `acpi_call` kernel module as a
mailbox. Both do the same thing; use whichever the environment supports.

## Why this exists

Mainline `asus_wmi` on kernel 7.x on this laptop registers
`/sys/class/backlight/asus_screenpad`, but on my BIOS (`UX435EG.315`,
2022-04-22) it never actually binds to the ATK WMI GUID
`97845ED0-4E6D-11DE-8A39-0800200C9A66`, so writes to the sysfs node are silent
no-ops and the secondary panel stays dark. Plippo's out-of-tree
`asus-wmi-screenpad` DKMS module used to be the answer but it hasn't kept up
with newer kernels. So: skip the driver, talk to `WMNB` directly.

Under the hood we're just calling
`\_SB.ATKD.WMNB(0, methodId, buffer)` where `buffer` is the same packed
`struct bios_args` the in-kernel `asus_wmi` builds up before handing it to
`wmi_evaluate_method()`. See `wmi-set.c` and the top of `ux435-screenpad`
for the byte layout.

The confirmed WMI constants (all from
`include/linux/platform_data/x86/asus-wmi.h`):

| Name | Value |
|---|---|
| `METHODID_DEVS` (set) | `0x53564544` (`'DEVS'` LE) |
| `METHODID_DSTS` (get) | `0x53545344` (`'DSTS'` LE) |
| `DEVID_SCREENPAD_POWER` | `0x00050031` |
| `DEVID_SCREENPAD_LIGHT` | `0x00050032` |

## Files

- **`ux435-screenpad`**. The primary tool. Python 3, stdlib only. Ships in
  every distro that has Python. This is what should live in `/usr/local/bin`
  on installed systems.
- **`wmi-set.c`**. Same functionality as a small C program. For minimal
  environments (recovery initramfs, busybox shell) where Python isn't
  available. Build with `make` (dynamic) or `make static` (self-contained).
- **`Makefile`**. Builds `wmi-set` and installs both tools.

## Requirements

The `acpi_call` kernel module must be loaded so that `/proc/acpi/call` exists.

On Debian:

```sh
sudo apt install acpi-call-dkms
sudo modprobe acpi_call
echo acpi_call | sudo tee /etc/modules-load.d/acpi_call.conf   # persist
```

Verify:

```sh
ls /proc/acpi/call && echo ok
```

## Usage

Both tools take the same subcommands and both need root (writes to
`/proc/acpi/call`).

```sh
# Python
sudo ./ux435-screenpad power on
sudo ./ux435-screenpad brightness 128
sudo ./ux435-screenpad get
sudo ./ux435-screenpad toggle
sudo ./ux435-screenpad --debug brightness 200
sudo ./ux435-screenpad --short power on      # 8-byte bios_args fallback

# C. Same interface
sudo ./wmi-set power on
sudo ./wmi-set brightness 128
sudo ./wmi-set get
sudo ./wmi-set toggle
sudo ./wmi-set --debug --short brightness 64
```

`brightness` accepts decimal or `0x`-prefixed hex (`0..255`).

`get` prints both `POWER` and `LIGHT` DSTS values, decoded. The `supported`
column is the `0x00010000` present-bit that WMNB sets when the devstate is
implemented on this box. If it's `False` for a DEVID, the low bits are
meaningless.

## Build & install the C tool

```sh
make                # dynamic build -> ./wmi-set
make static         # -static (needs a static libc)
sudo make install   # installs both tools to /usr/local/bin
```

`PREFIX` and `DESTDIR` are honored the usual way:

```sh
sudo make install PREFIX=/usr
make install DESTDIR=/tmp/stage PREFIX=/usr
```

## Debugging

`--debug` prints the buffer hex and the exact command handed to
`/proc/acpi/call`, plus the raw reply. Expected replies from WMNB are things
like `0x1`, `0x0`, or `0x00010001` (present-bit + value). Anything starting
with `Error:` or the literal string `not called` means WMNB didn't dispatch , 
double-check the WMNB path with:

```sh
sudo cp /sys/firmware/acpi/tables/DSDT /tmp/DSDT.dat
iasl -d /tmp/DSDT.dat
grep -i WMNB /tmp/DSDT.dsl
```

## Known gotchas

- **Kernel driver races.** If `asus_wmi` or `asus_nb_wmi` is still bound to
  the ScreenPad LED (check for `/sys/class/leds/asus::screenpad`), the driver
  may re-issue its own `DEVS` on lid events, suspend/resume, or Fn keypresses
  and clobber your state. Options: `rmmod asus_nb_wmi asus_wmi` before use,
  or write to the sysfs LED node instead of using this tool.
- **`bios_args` size drift.** The kernel struct has grown from 2 to 5 to 6
  `u32`s over the years (commits `130d29c5627c`, `8d95d1f4aa5c`). WMNB on the
  UX435EG only inspects the first two DWORDs, so the default 24-byte form
  matches current mainline and the 8-byte `--short` form matches older
  drivers / third-party hacks. Try `--short` if the default gets rejected.
- **`method_id` endian.** `'DEVS'` in memory is `44 45 56 53` (D,E,V,S). As
  a little-endian `u32` that's `0x53564544`. That's what we pass. Passing
  `0x44455653` will look up a nonexistent method.
- **Instance = 0.** UX435EG uses WMI instance 0. Other ASUS boards may
  expose more than one; if `get` on a different model returns `0xFFFFFFFE`
  or similar, try instance 1 (edit `WMI_INSTANCE` in the source).

## Prior art

- **Plippo/asus-wmi-screenpad**. Out-of-tree kernel patch. Reference for the
  POWER-vs-LIGHT dispatch. Ages badly against newer kernels.
- **Plippo/screenpad-tools**. Thin userland wrappers around Plippo's sysfs LED.
- **lakinduakash/asus-screenpad-control**. GUI + bundled (stale) module.
- **Traciges/Ayuz**. Newer GTK4 control center, wider ASUS support.
- Sinan Akkoyun's earlier ScreenPad hack. Same idea, but predates the
  mainline `SCREENPAD_LIGHT` DEVID and hand-rolls its own WMI method IDs.
  Historical reference only.

## License

GPL-2.0. See [`LICENSE`](../LICENSE) at the repo root.
