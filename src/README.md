# ScreenPad userspace tool

Small helper for driving the ASUS ScreenPad backlight from userspace. Pokes `\_SB.ATKD.WMNB` through the `acpi_call` kernel module.

Right now this is just a Python CLI sketch. Nothing is wired up properly yet.

## TODO

- C fallback for when python is not around
- actual docs (usage, flags, examples)
- install script + Makefile
- figure out permissions story (suid? udev? group?)
- test on more than one machine
