# Contributing

Thanks for even reading this. This is a small single-purpose repo and I'd rather have a few real reports than a lot of noise, so please read the relevant section before opening an issue or PR.

## Adding a compatibility matrix row

This is the most useful thing you can do. Even a "does not work" row is valuable. It tells the next person not to burn a weekend on the same setup.

1. Fork the repo and edit the "Compatibility matrix" table in `README.md`.
2. Add one row with: model, BIOS version (from `sudo dmidecode -s bios-version`), kernel (`uname -r`), status (Working / Partial / Not working), your GitHub handle, and a short notes column.
3. If you'd like the notes column to be genuinely useful, paste the one-line summary that `docs/how-to-diagnose.sh` prints at the end.
4. Open a PR. Keep the diff to just that one row unless you're also fixing something else.

## Reporting new hardware that doesn't work

Open an issue titled `<model> <BIOS>: <one-line symptom>`. In the body, paste the full output of:

```sh
sudo ./docs/how-to-diagnose.sh
```

That script dumps: kernel version, BIOS version, loaded `asus_*` modules, presence of `/sys/class/backlight/asus_screenpad`, whether `acpi_call` is loaded, the result of a probe DEVS call, and the relevant lines from your DSDT. Please don't redact the BIOS version. That's the single most useful field for triaging.

If you can attach a `iasl -d` decompiled DSDT (from `/sys/firmware/acpi/tables/DSDT`), even better. It's fine to gzip it and attach; GitHub accepts up to 25 MB.

## Sending a PR

- Keep commit messages short, present tense, no ticket refs. `add UX481FA row to compatibility matrix` is the shape I want.
- One logical change per commit. If you're touching the script and the docs, that's two commits.
- Don't rewrite history on someone else's PR review just to squash; I'll squash on merge if it matters.
- No CI hooks yet, but please run `shellcheck bin/screenpad` before pushing script changes.

## Helping upstream the kernel patch

The real fix for this problem lives in `drivers/platform/x86/asus-wmi.c`. The patch in `patches/` is my best guess but I'm not confident enough in the diagnosis to send it to the list on my own. If you're a kernel developer or have kernel-list experience, I'd love the help.

- Mailing list: `platform-driver-x86@vger.kernel.org`, cc `linux-kernel@vger.kernel.org` and the `asus-wmi.c` maintainers from `scripts/get_maintainer.pl`
- The relevant recent history is Denis Benato's 130d29c5627c and 8d95d1f4aa5c. Read those first
- Please loop me in (cc `c.skeens065@gmail.com` or ping in the PR) so I can test any revised patch on my UX435EG before it lands

If you want to just take over the patch and land it under your own name, that's completely fine too. I care about the fix existing, not about credit.
