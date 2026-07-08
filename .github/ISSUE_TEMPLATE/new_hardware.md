---
name: New hardware report
about: You tried this on a model that isn't in the compatibility matrix yet
title: '<model> <BIOS>: works / partial / doesn''t work'
labels: hardware
---

## Result

- [ ] Works fully
- [ ] Works partially (describe below)
- [ ] Does not work

## Hardware

- Model (exact. `sudo dmidecode -s system-product-name`):
- BIOS version (`sudo dmidecode -s bios-version`):
- BIOS date (`sudo dmidecode -s bios-release-date`):
- Kernel (`uname -r`):
- Distro:

## What I did

Verbatim commands, from install through first successful (or failed) call.

## Diagnostic bundle

Paste the output of `sudo bash scripts/diagnose.sh` (or attach the log file).
Even for a "works fine" report this is useful. It's how the next person with
your model confirms they're starting from the same place.

## Suggested matrix row

Copy the header from README.md and drop your row here so I can just paste it in
if we're all good:

```
| <Model> | <BIOS> | <Kernel> | Working | @<yourhandle> | <one-line note> |
```

If you'd rather send a PR directly, that's welcome too. See CONTRIBUTING.md.
