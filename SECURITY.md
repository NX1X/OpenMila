# Security Policy

OpenMila runs on your own machine: it records audio, keeps transcripts and
voice profiles on disk, and can paste text into other applications. Security
reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/NX1X/OpenMila/security/advisories/new).
Reports are acknowledged within a few days.

Please include:
- what the issue is and what an attacker could do with it;
- steps to reproduce, your OpenMila version (`openmila --version`) and your
  operating system;
- a proof of concept, if you have one.

If the problem is in code OpenMila shares with Mila (anything under `Mila/`
or `Packages/`), it probably affects Mila on macOS too. Say so in the report;
it will be passed on to Mila's maintainers through their own reporting
channel once a fix is coordinated.

## Supported versions

Fixes go into the newest release. Update before reporting.

## Good to know

- Local transcription never sends audio anywhere. The optional remote
  backend uploads audio only to the server you configure, and the app says
  so while it is active.
- AI features run a command-line tool or an OpenAI-compatible endpoint that
  **you** configure. OpenMila ships no API keys.
- Secrets you enter (API keys, tokens) are stored in files readable only by
  your user account.
- The MCP helper is off until you turn it on in Settings, and turning it off
  takes effect immediately. It is a consent switch, not a sandbox: it runs as
  your user, like the rest of the app.
- Updates are checked against this repository's GitHub releases and are
  never installed without you.
