# WMI encoding. What actually goes into /proc/acpi/call

This is the byte-level story for calling `\_SB.ATKD.WMNB` from userspace via
`acpi_call`. It's what I'd have wanted to read before I started. If you just
want to use the tool, you don't need any of this. `ux435-screenpad power on`
does the right thing. If you want to port it to a different ASUS model, or
just understand what the kernel driver would have sent, read on.

## The moving parts

Four things you have to get right, in order:

1. The ACPI method path (`\_SB.ATKD.WMNB`).
2. The instance argument (`0` on UX435EG).
3. The method_id argument. A 32-bit fourCC, little-endian.
4. The input buffer. A packed `{ u32 dev_id; u32 ctrl_param; ... }`, also
   little-endian.

`acpi_call` takes a single space-separated line: `PATH INSTANCE METHOD_ID
BUFFER`. Integer args go as plain integers (`0` or `0x53564544`). Buffers go
as `bXXXX...`. A lowercase `b` followed by hex nibbles, no `0x`, no spaces.

## Constants (from mainline)

All of these are lifted verbatim from
`include/linux/platform_data/x86/asus-wmi.h`. If mainline changes them, this
tool needs to change too. I don't invent any of them.

| Name | Value | Meaning |
|---|---|---|
| `ASUS_WMI_MGMT_GUID` | `97845ED0-4E6D-11DE-8A39-0800200C9A66` | the GUID WMNB is bound to |
| `ASUS_WMI_METHODID_DEVS` | `0x53564544` (`'DEVS'` LE) | set devstate |
| `ASUS_WMI_METHODID_DSTS` | `0x53545344` (`'DSTS'` LE) | get devstate |
| `ASUS_WMI_DEVID_SCREENPAD_POWER` | `0x00050031` | ScreenPad on/off |
| `ASUS_WMI_DEVID_SCREENPAD_LIGHT` | `0x00050032` | ScreenPad brightness 0..255 |

## The fourCC endian gotcha

`'DEVS'` as ASCII bytes in memory is `44 45 56 53` (D, E, V, S). As a little-
endian `u32` that reads back as `0x53564544`. You pass the little-endian
integer to `acpi_call`, not the spelled-out one. Passing `0x44455653` will
look up a nonexistent method and WMNB returns an error status.

I burned an embarrassing amount of time on this. If you take one thing away
from this doc, take that.

## The input buffer

The kernel struct is:

```c
struct bios_args {
    u32 arg0;   // dev_id
    u32 arg1;   // ctrl_param
    u32 arg2;   // reserved (zero on non-ROG)
    u32 arg3;   // reserved
    u32 arg4;   // reserved
    u32 arg5;   // reserved
} __packed;   // sizeof == 24 on current mainline
```

`__packed` means no alignment padding. Offsets are exactly 0, 4, 8, 12, 16, 20.

The struct has grown over the years. Old kernels had 2 u32s (8 bytes). Then 5
(20 bytes). Now 6 (24 bytes). See commits `130d29c5627c` and `8d95d1f4aa5c`.
WMNB on non-ROG ZenBooks. Including the UX435EG. Only inspects `arg0` and
`arg1`, so **any padded length ≥ 8 bytes works**. The default in this tool is
24 to match current mainline; `--short` flips it to 8 as a fallback.

## Worked example: turn the ScreenPad on

DEVID `0x00050031`, ctrl_param `0x00000001`:

```
offset  field       value          bytes (LE)
0x00    arg0        0x00050031     31 00 05 00
0x04    arg1        0x00000001     01 00 00 00
0x08    arg2        0x00000000     00 00 00 00
0x0C    arg3        0x00000000     00 00 00 00
0x10    arg4        0x00000000     00 00 00 00
0x14    arg5        0x00000000     00 00 00 00
```

Hex string (48 nibbles): `310005000100000000000000000000000000000000000000`

Full `acpi_call` invocation:

```sh
echo '\_SB.ATKD.WMNB 0 0x53564544 b310005000100000000000000000000000000000000000000' \
  | sudo tee /proc/acpi/call
```

That single backslash before `_SB` is load-bearing. In a single-quoted bash
string it's fine; in a double-quoted string escape it (`"\\_SB..."`).

## Worked example: brightness = 128

DEVID `0x00050032`, ctrl_param `0x00000080`:

```
offset  field       value          bytes (LE)
0x00    arg0        0x00050032     32 00 05 00
0x04    arg1        0x00000080     80 00 00 00
0x08..0x14                         00 00 00 00 × 4
```

Hex string: `320005008000000000000000000000000000000000000000`

```sh
echo '\_SB.ATKD.WMNB 0 0x53564544 b320005008000000000000000000000000000000000000000' \
  | sudo tee /proc/acpi/call
```

## The 8-byte short form

If the 24-byte form returns `Error:` or `not called` on your board, try 8 bytes
first. That's what most third-party projects (Plippo's patch, older AUR
scripts) use, and it's what old kernels wrote.

```sh
# power on (8-byte bios_args)
echo '\_SB.ATKD.WMNB 0 0x53564544 b3100050001000000' | sudo tee /proc/acpi/call

# brightness 128
echo '\_SB.ATKD.WMNB 0 0x53564544 b3200050080000000' | sudo tee /proc/acpi/call
```

The Python tool exposes this as `--short`; the C tool too. If both forms fail
on your BIOS but the WMNB path resolves in DSDT, it's most likely a wrong
instance number (try 1) or a DSDT that dispatches on a different set of DEVIDs
for your model. Open an issue with the DSDT snippet.

## Reading back the reply

`sudo cat /proc/acpi/call` after a write returns the last invocation's status
as a NUL-terminated ASCII string. Typical replies:

- `0x0` / `0x1`. Succeeded, WMNB returned that status word.
- `0x00010001`. DSTS reply: `0x00010000` (present bit) OR'd with the current
  value. `0x0001` means "on".
- `not called`. WMNB didn't dispatch. Either the path is wrong for your BIOS,
  or `acpi_call` refused for some other reason. Check with
  `grep -i WMNB /tmp/DSDT.dsl`.
- `Error: ...`. ACPI evaluation ran but WMNB returned an error status (bad
  method_id, unsupported DEVID, malformed buffer, etc.).

## What happens on the kernel side (for the curious)

When `asus-wmi` calls `asus_wmi_set_devstate(SCREENPAD_LIGHT, 128, &retval)`:

1. `asus_wmi_evaluate_method(DEVS, dev_id, ctrl_param, retval)` in
   `drivers/platform/x86/asus-wmi.c` builds a `struct bios_args` on the stack.
2. That calls `wmi_evaluate_method(ASUS_WMI_MGMT_GUID, 0, DEVS, &input, &output)`.
3. `wmi.c` finds the ACPI device carrying that GUID in its `_WDG` table,
   picks the "WM" method slot, and calls `WMNB(instance, method_id, buffer)`.
4. Inside DSDT, WMNB switches on `method_id`, then on `dev_id`, and hands
   `ctrl_param` to the hardware side.

Skipping the driver via `acpi_call` reproduces step 3 exactly. WMNB doesn't
care who called it, it just wants the right three ACPI args. That's why this
works.

## Why not just use `/sys/class/leds/asus::screenpad`?

That node only exists if Plippo's out-of-tree kernel patch is loaded. On a
stock kernel (7.x, Debian trixie) it isn't. If you have Plippo's module
working on your kernel, absolutely use the LED node. It's the right
interface. This tool is what you use when the module doesn't build.

If a future mainline kernel starts creating that node itself (which is the
whole point of the WIP patch in `patches/`), this tool becomes obsolete and I
will archive the repo with a pointer to the kernel commit.
