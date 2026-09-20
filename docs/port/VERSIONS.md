<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# How OpenMila is numbered, and how that relates to Mila

OpenMila does not have a version of its own. It carries the version of the
Mila release it is a port of, plus a port number:

```
<upstream version>+port.<N>
```

`1.9.5-beta.2+port.0` is the zeroth port of Mila v1.9.5-beta.2. The next
OpenMila release of the same upstream version is `+port.1`; when the port
follows Mila v1.9.6, it becomes `1.9.6+port.0`.

## Why this shape

- **A user can tell what they have.** "Which Mila is this?" is answered by
  reading the version, not by cross-referencing a table.
- **Upstream's own numbering is untouched.** OpenMila never invents a Mila
  version that Island did not publish, and never claims to be one: the `+port`
  suffix is always there, even for the first release.
- **It is valid semver.** The part before `+` is upstream's version, including
  its pre-release identifiers; the `+port.N` is build metadata. So
  `1.9.5-beta.2+port.0` sorts before `1.9.5+port.0`, which is right: Mila's
  1.9.5 final is later than its beta.
- **The beta channel comes for free.** Upstream ships `-beta.N` versions; a
  port of one keeps that marker, so the updater's beta channel offers it only
  to people who asked for betas. A port of a stable Mila has no `-` in it and
  goes to everyone.

## The one place it needed code

Semver says build metadata is ignored when comparing versions, which would
make every port of one upstream version compare equal, and the updater would
never offer an upgrade from `+port.0` to `+port.1`. The port's comparison
therefore uses build metadata as the final tiebreaker, numerically
(`+port.9` before `+port.10`). `VersionOrderTests` pins that.

## Rules

- `UPSTREAM_VERSION` at the repository root names the Mila tag the port is
  measured against, and the version string must start with exactly that.
- The port number resets to 0 on every upstream bump and increases by one for
  every OpenMila release in between, whatever the change was.
- A port release never changes what a Mila version means. If OpenMila needs a
  fix that upstream does not have, that is still `+port.N`, and `CHANGES.md`
  records the difference.
- Tags are `v<version>`: `v1.9.5-beta.2+port.0`. The `+` is legal in a git tag
  and in a GitHub release. The Debian package replaces it with `~`
  (`1.9.5-beta.2~port.0`), which is what `dpkg` orders correctly.
- Release notes live at `RELEASE_NOTES/v<version>.md` and the release workflow
  refuses to build without them, which is upstream's rule kept.

## What this means when Mila moves

A new Mila release is not automatically a new OpenMila release. The sync
routine merges upstream, re-measures `docs/port/PARITY.md`, and only then is
there a version to cut. If upstream ships a feature the port cannot do yet,
the port still takes the version number, and PARITY.md records the feature as
missing rather than pretending otherwise.
