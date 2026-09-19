# Using OpenMila with Claude (MCP)

OpenMila includes the same MCP server Mila has, built from the same source:
it lets a Claude session search and read your transcripts, including the live
transcript of a meeting in progress. Nothing leaves your machine unless you
ask Claude to do something with it.

## Turn it on

Access is **off by default**. Enable it in **Settings > Storage > Allow MCP
access to transcriptions**. While it is off, every call is refused, and
turning it off stops an already-running session at once.

This switch is about consent, not isolation: the helper runs as your user and
reads the same files you can.

## Register it with Claude Code

The helper ships inside the AppImage. Register it once:

```bash
claude mcp add openmila -- /path/to/OpenMila-<version>-x86_64.AppImage --mcp
```

When running from a source build, point at the binary instead:

```bash
claude mcp add openmila -- /path/to/OpenMila/.build/debug/openmila-mcp
```

## What it offers

`list_recordings`, `get_transcript`, `search_transcripts` and
`get_live_transcript`. They behave as described in Mila's documentation,
[docs/mcp.md](../mcp.md); only the paths differ (OpenMila's data lives in
`~/.local/share/Mila/`).
