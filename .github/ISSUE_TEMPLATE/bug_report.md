---
name: Bug report
about: The tool doesn't work on hardware it should work on, or does something unexpected
title: '<model> <BIOS>: <one-line symptom>'
labels: bug
---

## Symptom

<what actually happens vs what you expected>

## Hardware

- Model:
- BIOS version (`sudo dmidecode -s bios-version`):
- Kernel (`uname -r`):
- Distro (`cat /etc/os-release | head -3`):

## Reproduction

Steps to reproduce, verbatim commands. If you ran `ux435-screenpad --debug ...`,
paste the exact command and full output.

```
$ sudo ux435-screenpad --debug power on
[debug] buffer     : ...
[debug] acpi_call  : ...
[debug] reply text : ...
```

## Diagnostic bundle

Please run:

```
sudo bash scripts/diagnose.sh
```

and paste the resulting `/tmp/ux435-diagnose-*.log`. It's long but every field
is there for a reason. The BIOS version and the WMI GUID binding status are
the two I'll look at first.

If you can also decompile the DSDT and re-run diagnose.sh, the DSDT greps will
be populated too:

```
sudo cp /sys/firmware/acpi/tables/DSDT /tmp/DSDT.dat
iasl -d /tmp/DSDT.dat
```

## Anything else

Notes, guesses, links to related upstream reports, etc.
