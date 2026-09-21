<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# What is left

The port's goal is one thing: every Mila feature, working on Linux and on
Windows, and staying that way as Mila moves. `PARITY.md` is the measure. This
page is the ordered list of what still stands between the current build and
that goal, and what "done" means for each item. It is not a wish list; a new
feature that Mila does not have does not belong here.

Status legend: **now** is in progress or next up, **next** is queued behind
it, **later** is agreed but not scheduled.

## 1. Windows verified by hand - now

Every Windows row in `PARITY.md` says *written*, not *done*, because until
today nothing had been run on a Windows desktop. The +port.3 build is the
first that starts there. Turning *written* into *done* is a beta pass on a
real machine, row by row, with the same evidence standard Linux had.

Done when: each Windows row has evidence from a Windows desktop, and the two
open faults from the first hands-on run are closed - the window not filling
its content, and the caption bar not following the app's theme (a fix for the
second is in `main`, unverified).

## 2. Per-application audio on Windows - now

WASAPI process loopback is written and compiles; it has never captured a
byte. Meeting mode on Windows records the whole system until it does.

Done when: `openmila-cli app-audio` captures from one chosen process on a
Windows desktop and the mixed meeting WAV carries both sides.

## 3. Diarization runtime on Windows - now

The bundle script exists and CI can build it; it has never been loaded by the
app on Windows.

Done when: enabling speakers on Windows downloads torch, and a recording
comes back with speaker labels.

## 4. Packaged for a package manager - next

Downloads from a release page are the floor. The two channels users expect:

- **winget**: `packaging/winget/make-manifest.sh` writes the manifest from a
  published release; what remains is the pull request to `microsoft/winget-pkgs`
  and its bot validation. Pre-releases are reachable with `--version` only.
- **apt**: an apt repository, so `apt install openmila` and `apt upgrade` work
  and the deb's dependency line is checked by apt rather than by the reader.
  The workable shape is a static repository (`reprepro` or `aptly`) published
  from the release workflow to GitHub Pages under `apt.openmila.nx1xlab.dev`,
  signed with a GPG key kept as an Actions secret and printed on the download
  page. A Launchpad PPA is not workable: its builders would have to build a
  Swift toolchain. Needs a decision on who holds the signing key.

Done when: both commands install the current release on a clean machine.

## 5. Signed builds - next

The Windows installer is unsigned, so SmartScreen warns on first run; the
Linux packages carry checksums and build provenance but no signature.

Done when: the installer is Authenticode-signed (a certificate is a purchase
and a decision), and the deb and AppImage are signed with the same key as the
apt repository.

## 6. Wayland tab-meeting detection for Firefox - next

The accessibility bus reads Wayland-native window titles, but Firefox and
Chromium only publish theirs once the desktop's accessibility switch is on.
Settings names the command; nothing turns it on for the user.

Done when: a Meet or Proton Meet tab in Firefox on a GNOME Wayland session is
detected without the user editing a gsettings key, or the app offers to make
that change with one click and explains what it does.

## 7. GPU measured - next

Vulkan is built, probed, selectable and wired on both systems, and no
transcription has been timed on real GPU hardware.

Done when: `HARDWARE.md` carries measured times for both shipped models on at
least one NVIDIA, one AMD and one Intel machine, on each system.

## 8. In-place updates - later

The update check finds a newer release and opens its page. Mila installs the
update itself.

Done when: the app downloads the matching package, verifies it against
`SHA256SUMS`, and hands off to the installer (Windows) or replaces the AppImage
or invokes apt (Linux), with the user's confirmation.

## 9. CUDA - later

Faster than Vulkan on NVIDIA, at the price of a second build and a large
toolkit. Worth doing only once Vulkan is measured (item 7) and the gain is
known to matter.

## 10. Upstream cadence - always

Mila releases roughly weekly. The port merges upstream on stable tags,
re-runs the parity audit, and re-ports any view that changed. The
`upstream-watch` workflow flags a new tag; the work is the merge.

## Housekeeping that is not a feature

- Linux CI has no cross-run cache, so every run rebuilds whisper.cpp and
  every Swift target (about 15 minutes flat). Fix: a cache backend for the
  Dagger volumes, or a host directory `actions/cache` restores around them.
- App screenshots for the website, taken by a person on each system.
- An end-to-end run of the managed Claude install on Windows.
- Proton Meet's badge: the prompt names it, but a saved recording gets the
  generic badge until `MeetingApp` upstream gains a case for it (an upstream
  pull request).
