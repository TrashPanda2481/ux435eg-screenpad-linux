# ux435eg-screenpad-linux

A userspace shim that turns on the ScreenPad 2.0 (secondary 5.65" touchscreen in the touchpad area) on the ASUS ZenBook UX435EG under Linux.

On BIOS `UX435EG.315` (2022-04-22), the mainline `asus-wmi` driver creates the sysfs backlight surface at `/sys/class/backlight/asus_screenpad` but doesn't bind to the ATK WMI GUID. Writes to `brightness` succeed silently and the panel stays dark. This repo calls `\_SB.ATKD.WMNB` directly via [`acpi_call`](https://github.com/nix-community/acpi_call), bypassing the broken WMI binding.

Scope: UX435EG, kernel 7.0.12+deb13-amd64, Debian trixie. Compatibility with other UX4xx models is untested. See the [matrix](#compatibility).

## Requirements

- ASUS ZenBook UX435EG (or a UX4xx sibling with the same ATK DSDT layout. Untested)
- Linux kernel with the [`acpi_call`](https://github.com/nix-community/acpi_call) module available
- X11 session for the display piece (Wayland untested. The WMI power tool works either way)
- Python 3 (stdlib only)

## Install

### Debian / Ubuntu

```sh
git clone https://github.com/TrashPanda2481/ux435eg-screenpad-linux.git
cd ux435eg-screenpad-linux
sudo bash scripts/install.sh
```

That command:

1. Installs `acpi-call-dkms` and pulls kernel headers.
2. Places the CLI at `/usr/local/bin/ux435-screenpad`.
3. Installs `/etc/systemd/system/ux435-screenpad-boot.service` and enables it (boot-time WMI power).
4. Installs the udev rule so members of the `video` group can write `/proc/acpi/call` without sudo.
5. Installs the user-session display piece: `/usr/local/bin/screenpad-display` + `/usr/lib/systemd/user/ux435-screenpad-display.service`.
6. Loads `acpi_call` now and adds it to `/etc/modules-load.d/` for boot.

Dry-run first if you want to see what it will change:

```sh
sudo bash scripts/install.sh --dry-run
```

Post-install steps:

```sh
# add yourself to the video group so brightness writes don't need sudo
sudo usermod -aG video $USER          # then log out and back in

# enable the user-session xrandr rotate/position piece
systemctl --user daemon-reload
systemctl --user enable --now ux435-screenpad-display.service
```

Reboot to confirm the full chain fires automatically.

### Other distros

Install `acpi_call`:

- Fedora: `acpi_call-kmod` from RPM Fusion
- Arch: `acpi_call-dkms` from the AUR
- NixOS: `boot.extraModulePackages = [ config.boot.kernelPackages.acpi_call ]`

Then install the binaries and units by hand:

```sh
sudo install -m 0755 src/ux435-screenpad /usr/local/bin/
sudo install -m 0755 scripts/screenpad-display.sh /usr/local/bin/screenpad-display
sudo install -m 0755 scripts/screenpad-reapply.sh /usr/local/bin/screenpad-reapply
sudo install -m 0644 systemd/ux435-screenpad-boot.service /etc/systemd/system/
sudo install -Dm 0644 systemd/user/ux435-screenpad-display.service \
    /usr/lib/systemd/user/ux435-screenpad-display.service
sudo install -m 0644 udev/99-ux435-screenpad.rules /etc/udev/rules.d/
```

## Usage

### CLI

```sh
ux435-screenpad power on             # turn the panel on
ux435-screenpad power off            # turn the panel off
ux435-screenpad brightness 128       # 0-255
ux435-screenpad get                  # print current power + brightness
ux435-screenpad toggle               # flip power based on current state
```

Add `--debug` to any invocation to see the raw WMNB call and response.

### Display piece

`screenpad-display` runs `xrandr` to bring the ScreenPad up as a rotated secondary display:

- Off/on cycle on `HDMI-2` (i915 connector name for the ScreenPad)
- Mode `1080x2160`, rotated right → effective `2160x1080` landscape
- Positioned below the primary `eDP-1` at `0x1080`

The bundled user-session systemd unit runs this after login. To run manually:

```sh
screenpad-display
```

### Recovery from KDE display changes

Changing the primary output's resolution in KDE's Display settings sometimes drops the ScreenPad. Kscreen's re-apply pass doesn't cleanly re-enable the connector on this hardware. The recovery script re-fires WMI power and re-runs `screenpad-display` in one shot:

```sh
screenpad-reapply
```

Bind it to a keyboard shortcut in **System Settings → Keyboard → Shortcuts → Custom Shortcut**. `Meta+Shift+P` works well.

## How the fix works

Mainline `asus-wmi` has the correct constants for the ScreenPad DEVIDs. On the `UX435EG.315` BIOS the WMI subsystem's binding between the ATK GUID and the DSDT `WMNB` dispatch method doesn't come up the way the driver expects, so `wmi_evaluate_method` returns success without executing anything.

`acpi_call` bypasses `wmi_evaluate_method` and calls `\_SB.ATKD.WMNB` directly with the three arguments the WMI subsystem would have constructed:

- `Arg0` = instance = `0`
- `Arg1` = method_id = `0x53564544` (`'DEVS'` as LE u32) for SET, or `0x53545344` (`'DSTS'`) for GET
- `Arg2` = input buffer with `dev_id` and `ctrl_param` as the first two little-endian DWORDs

DEVIDs:

- ScreenPad power: `0x00050031`, `ctrl_param` `0` or `1`
- ScreenPad brightness: `0x00050032`, `ctrl_param` `0..255`

The buffer is `__packed` on the kernel side. Current mainline uses 24 bytes (six `u32`s). WMNB on non-ROG UX-series ZenBooks only reads the first two DWORDs, so any padded length ≥ 8 works. The CLI uses the full 24-byte form for parity with the kernel driver.

Byte-level walkthrough and DSDT excerpts in [`docs/wmi-encoding.md`](docs/wmi-encoding.md) and [`docs/dsdt-analysis.md`](docs/dsdt-analysis.md).

## Kernel patch

[`patches/`](patches/) contains a work-in-progress DMI-quirk patch that forces the correct WMI binding at the driver level. It has been tested locally against 7.0.12 and works, but has not been submitted to `linux-platform-drivers-x86` pending a second-machine test and confirmation of the root-cause diagnosis.

This repo is a stopgap. When the upstream driver handles this BIOS correctly, the repo can archive with a pointer to the kernel commit.

## Compatibility

| Model | BIOS | Kernel | Status | Reporter | Notes |
|---|---|---|---|---|---|
| UX435EG | UX435EG.315 (2022-04-22) | 7.0.12+deb13-amd64 | Working | @TrashPanda2481 | Debian trixie, KDE Plasma 6 on X11 |

Open a PR to add your row. `scripts/diagnose.sh` prints exactly the info that goes in the "Notes" column.

## Related work

- [**Plippo/asus-wmi-screenpad**](https://github.com/Plippo/asus-wmi-screenpad). Out-of-tree kernel patch that adds an LED class device at `/sys/class/leds/asus::screenpad`. This project is the reference for the DEVID mapping and the WMNB dispatch structure; on 6.x kernels this is the module to use.
- [**SinanAkkoyun/ScreenpadLinux**](https://github.com/SinanAkkoyun/ScreenpadLinux). Userspace shim for the UX580GE (ScreenPad *Plus*). Different DEVIDs and geometry, same general approach. Origin of the xrandr rotation pattern used here.
- **Denis Benato's mainline commits** [130d29c5627c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=130d29c5627cd50e786e926ad7ef66322c5a0c09) and [8d95d1f4aa5c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=8d95d1f4aa5c76202b0833a70998769384612488). Landed in `drivers/platform/x86/asus-wmi.c` in early 2026, fixing the power-sequencing / `bl_power` inversion for ScreenPad Plus / Duo. These do not rescue the UX435EG binding on `UX435EG.315`, but they're the code path any real upstream fix will touch.
- [**nix-community/acpi_call**](https://github.com/nix-community/acpi_call) (formerly `mkottman/acpi_call`). The kernel module this shim relies on. Debian packages it as [`acpi-call-dkms`](https://packages.debian.org/trixie/acpi-call-dkms).
- [**asus-linux.org**](https://asus-linux.org). ROG-family focus ([`asusctl`](https://gitlab.com/asus-linux/asusctl), [`supergfxctl`](https://gitlab.com/asus-linux/supergfxctl)). Different scope from this repo; the reference community for ASUS-on-Linux more broadly.

Kernel-source reading:

- [`drivers/platform/x86/asus-wmi.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/platform/x86/asus-wmi.c). Mainline driver
- [`include/linux/platform_data/x86/asus-wmi.h`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/platform_data/x86/asus-wmi.h). The DEVID and method-id constants

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). New matrix rows welcome; bug reports should include the output of `scripts/diagnose.sh`.

## License

GPL-2.0. See [LICENSE](LICENSE).

## Credits

- [**Plippo**](https://github.com/Plippo). [asus-wmi-screenpad](https://github.com/Plippo/asus-wmi-screenpad), original DEVID archaeology
- [**Sinan Akkoyun**](https://github.com/SinanAkkoyun). [ScreenpadLinux](https://github.com/SinanAkkoyun/ScreenpadLinux), userspace-WMI approach
- [**Denis Benato**](https://github.com/nero-tux). Mainline `asus-wmi` power-sequencing work
- The [**linux-platform-drivers-x86**](https://lore.kernel.org/platform-driver-x86/) maintainers
- [**mkottman**](https://github.com/mkottman) and the [**nix-community**](https://github.com/nix-community) maintainers. `acpi_call`
