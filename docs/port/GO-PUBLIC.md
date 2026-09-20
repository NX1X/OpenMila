# Going public

OpenMila stays private until the port is finished and privately tested. This
is what must be true before the repository is flipped, and in what order.

## Code and release

- [ ] `dagger call check` green on Linux; the Windows workflow green.
- [ ] A private beta on the maintainer's own machines (Linux and Windows 11),
      with the log file from a real session reviewed.
- [ ] `RELEASE_NOTES/v<version>.md` written for the first release.
- [ ] `UPSTREAM_VERSION` matches the Mila release the port follows.
- [ ] A tag pushed and the release workflow's draft release checked: AppImage,
      .deb, Windows zip, `SHA256SUMS`, SBOM, build provenance.

## Legal and attribution (Apache-2.0 section 4)

- [ ] `LICENSE` unchanged; `NOTICE` keeps Mila's paragraph and adds OpenMila's.
- [ ] `CHANGES.md` lists every modified upstream file.
- [ ] README, About screen, installer and release notes carry the
      non-affiliation disclaimer.
- [ ] `THIRD_PARTY_NOTICES.md` matches what the packages actually ship.
- [ ] No Island artwork anywhere; no `io.island.*` identifiers in the port.

## Repository settings (the maintainer applies these)

`scripts/port/apply-repo-rules.sh` applies the first three with `gh`; the
rest are toggles in the web interface.

- [ ] Branch ruleset on `main`: pull request required, one approval, required
      status checks (OpenMila Linux), linear history, signed commits, no force
      push, no deletion.
- [ ] Tag ruleset on `v*`: creation restricted to maintainers, no update, no
      deletion, so a published version can never move.
- [ ] Actions policy: GitHub-owned and verified creators only, plus the
      allowlist; full-length commit SHA required; workflow token read-only.
- [ ] Secret scanning and push protection on.
- [ ] Private vulnerability reporting on.
- [ ] Dependabot alerts on, Dependabot version updates off (Renovate owns them).
- [ ] Discussions on, for the contact route the README promises.

## The flip

- [ ] Settings > General > Change visibility > Public.
- [ ] Repository description and topics, including `dagger`.
- [ ] Publish the drafted release.
- [ ] Open an issue on Mila introducing the port, so upstream hears it from
      the maintainer rather than from someone else.
