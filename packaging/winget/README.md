<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# winget

`winget install NX1X.OpenMila` needs a manifest in Microsoft's
[winget-pkgs](https://github.com/microsoft/winget-pkgs) repository, one per
version. `make-manifest.sh <version>` writes the three files that make up one
from a published release, with the installer's SHA-256 taken from the
release's own `SHA256SUMS`, never typed by hand.

Submitting is a pull request to winget-pkgs, and Microsoft's bot validates the
installer (it downloads it, checks the hash, runs it silently in a VM and
expects the package to appear in Installed Apps). The first submission is
reviewed by a human; later versions usually go through on the bot alone.

    packaging/winget/make-manifest.sh 1.9.5-beta.2+port.3
    # then copy out/manifests/n/NX1X/OpenMila/<version>/ into a winget-pkgs fork
    # under manifests/n/NX1X/OpenMila/<version>/ and open the pull request

winget's version field cannot carry `+`, so the manifest's `PackageVersion`
is the release version with `+` turned into `.`, which still sorts the way
the releases do. Pre-releases are not offered by default:
`winget install NX1X.OpenMila --version <version>` reaches one explicitly
until the first non-beta build.

The silent switches the installer accepts are Inno Setup's standard ones
(`/VERYSILENT /NORESTART`), which is what the manifest declares.
