<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# Installing, upgrading and uninstalling OpenMila

This page is about getting OpenMila onto and off a machine. For what to do once
it is running (models, dictation, diarization, the MCP server), see
[docs/openmila/INSTALL.md](../openmila/INSTALL.md).

Every release publishes four downloads and a `SHA256SUMS` file:

| File | System | What it is |
|---|---|---|
| `OpenMila-<version>-win64-setup.exe` | Windows | Installer. Per user, no administrator needed. |
| `OpenMila-<version>-win64.zip` | Windows | Portable. Unzip and run, installs nothing. |
| `openmila_<version>_amd64.deb` | Debian, Ubuntu | A real package: `apt` installs and removes it. |
| `OpenMila-<version>-x86_64.AppImage` | Any current Linux desktop | Portable. One file, runs with no install step. |

Check what you downloaded before you run it. Each file has a `.sha256` beside
it:

```bash
sha256sum -c OpenMila-<version>-x86_64.AppImage.sha256
```

```powershell
(Get-FileHash OpenMila-<version>-win64-setup.exe -Algorithm SHA256).Hash
```

## The short version

Your recordings, transcripts, models and settings are **never** removed by an
uninstall. They live outside the application, they survive removing it, and
reinstalling picks them up exactly where they were. Deleting them is a separate,
explicit request: the `--purge` option on Linux, and answering Yes to the
uninstaller's question on Windows.

## Windows

### Install

Run `OpenMila-<version>-win64-setup.exe`. It installs into
`%LOCALAPPDATA%\Programs\OpenMila` for your account only, so there is no
administrator prompt and no elevation, which also means it works on a machine
where you are not an administrator. It adds:

- a Start menu entry (and a desktop shortcut, if you tick the box),
- an entry in **Settings > Apps > Installed apps**, with a working Uninstall,
- a `.milaconfig` file association, so a team configuration file opens OpenMila.

Windows may show a SmartScreen warning the first time: the installer is not
signed with a code-signing certificate yet. Choose **More info > Run anyway**
after checking the SHA-256 above.

The portable zip still ships and still works: unblock it, extract it anywhere,
run `openmila.exe`. It writes no registry keys, creates no shortcuts and has
nothing to uninstall - deleting the folder is the uninstall.

### What the installer sets up besides the app

The user interface is built on WinUI, which needs Microsoft's **Windows App
Runtime** on the machine. The installer carries that redistributable and runs
it for your user, so there is still no administrator prompt, and it does
nothing on a machine that already has it.

If you use the portable zip instead, run `WindowsAppRuntimeInstall-x64.exe`
from the zip once before starting `openmila.exe`. Without it the app starts and
exits again immediately. `openmila-cli.exe` does not need it.

### Upgrade

Run the new installer. It replaces the installed version in place, keeps your
shortcuts, the association and all of your data, and does not need the old
version to be uninstalled first. Close OpenMila first if it is running; the
installer will otherwise ask to close it for you.

For the portable zip, extract the new one over the old folder, or beside it.

### Uninstall

**Settings > Apps > Installed apps > OpenMila > Uninstall**, or the entry in
the Start menu's context menu. It removes the program, both shortcuts, the
`.milaconfig` association, the autostart entry (if one existed) and the
regenerable cache at `%LOCALAPPDATA%\OpenMila\cache`.

It then asks one question: whether to delete your data as well. The default is
No, and No is the right answer unless you are certain. Yes permanently deletes
`%APPDATA%\Mila` and `%LOCALAPPDATA%\OpenMila`: every recording, transcript and
downloaded model you have, and the settings stored beside them. The small
preferences file Foundation writes for the app elsewhere under `%LOCALAPPDATA%`
is left alone, which is the conservative choice and costs you nothing: it holds
preferences, not content.

To purge without being asked, for example from a management script:

```powershell
& "$env:LOCALAPPDATA\Programs\OpenMila\unins000.exe" /SILENT /PURGEDATA=yes
```

A silent uninstall with no `/PURGEDATA=yes` always keeps your data: a question
nobody can see is never allowed to delete anything.

### Where your data lives on Windows

| What | Where | Removed by uninstall? |
|---|---|---|
| Recordings, transcripts, models, MCP contracts | `%APPDATA%\Mila\` | No. Only with the purge. |
| Settings | sidecars in `%APPDATA%\Mila\`, plus a preferences file the app writes under `%LOCALAPPDATA%` | The sidecars go with the purge; the preferences file is always kept. |
| Logs | `%LOCALAPPDATA%\OpenMila\logs\` | No: they are what a bug report attaches. |
| Cache | `%LOCALAPPDATA%\OpenMila\cache\` | Yes. It is regenerable. |
| The program | `%LOCALAPPDATA%\Programs\OpenMila\` | Yes. |
| Shortcuts, association, Installed Apps entry | Start menu, desktop, `HKCU\Software\Classes` | Yes. |

## Linux

### The .deb (Debian, Ubuntu)

```bash
sudo apt install ./openmila_<version>_amd64.deb
```

It installs to `/opt/openmila` with `openmila`, `openmila-cli`, `openmila-mcp`
and `openmila-uninstall` on `PATH`, a launcher entry, the icons and the
`.milaconfig` MIME type. Upgrading is the same command with a newer file.

To remove it:

```bash
openmila-uninstall     # your own per-user leftovers; apt cannot reach these
sudo apt remove openmila
```

`apt remove` takes the program away and leaves `~/.local/share/Mila` and
`~/.config` alone, which is deliberate: those are yours. So does `apt purge` -
dpkg's purge means "remove the package's own configuration", and a maintainer
script running as root has no business deciding that every account on the
machine is finished with its recordings, nor any safe way to enumerate them.
`apt purge` therefore prints where the data is and names the command that
removes it. That command is `openmila-uninstall --purge`, run by the person
whose recordings they are.

`openmila-uninstall` is the part apt cannot do: it clears the per-user
leftovers (autostart entry, MCP registration, cache, per-user launcher entry).
Run it before `apt remove`, while it is still installed.

### The AppImage

```bash
chmod +x OpenMila-<version>-x86_64.AppImage
./OpenMila-<version>-x86_64.AppImage
```

That is the whole install: one file, no root, nothing written outside your home.
If it complains about FUSE, run it with `--appimage-extract-and-run`, or install
`libfuse2t64`.

**Optional desktop integration.** The AppImage is not second class: one command
puts it in the launcher with its icon and makes `.milaconfig` files open it.

```bash
./OpenMila-<version>-x86_64.AppImage --install
```

That writes three things, all under `~/.local/share`, none of them system-wide:
a `.desktop` entry pointing at this AppImage, the icons at every size, and the
`application/x-milaconfig` MIME type. It does not copy, move or modify the
AppImage, so **keep the file where it was when you ran `--install`**; the
launcher entry names that path. Run it again after moving the file.

**Upgrading** an AppImage is replacing the file. If you integrated it and the
new file has a different name (it will: the version is in the name), run
`--install` again on the new one and delete the old file. Run
`--uninstall --keep-appimage` first if you want the old entry cleaned up
explicitly; running `--install` on the new file simply overwrites the entry.

**Uninstall:**

```bash
./OpenMila-<version>-x86_64.AppImage --uninstall
```

It removes the launcher entry, the icons, the MIME type and its association, the
autostart entry, the MCP registration, the cache, and the AppImage file itself.
Pass `--keep-appimage` to keep the file. Pass `--dry-run` to see what it would
do and have it do nothing.

### Deleting your data on Linux

Nothing above touches your recordings. When you do want them gone, ask in
increasing order of regret:

```bash
openmila-uninstall --purge-models   # models and the diarization packages only
openmila-uninstall --purge          # settings, logs, AND recordings
```

`--purge-models` deletes several GB that can be downloaded again. `--purge`
deletes the settings, the logs and, after a separate confirmation that asks you
to type `delete my recordings`, the whole of `~/.local/share/Mila`. There is no
undo and no backup. In a script, `--yes` answers both prompts, and that is the
one combination that can destroy recordings without a question, so write it
deliberately.

Without a terminal to ask on, both prompts answer themselves with "keep".

### Where your data lives on Linux

| What | Where | Removed by uninstall? |
|---|---|---|
| Recordings, transcripts, models, MCP contracts | `~/.local/share/Mila/` | No. `--purge` only. |
| Settings | sidecars in `~/.local/share/Mila/`, plus a plist the app writes under `~/.config/` | No. `--purge` removes both. |
| Logs | `~/.local/state/openmila/logs/` | No. `--purge` only. |
| Cache | `~/.cache/openmila/` | Yes. It is regenerable. |
| Secrets (API keys, tokens) | your desktop keyring, or `~/.local/share/Mila/secrets/` where no keyring runs | No. `--purge` only. |
| Launcher entry, icons, MIME type | `~/.local/share/applications`, `icons`, `mime` | Yes. |
| The program | the AppImage file, or `/opt/openmila` from the .deb | Yes (the .deb's part through `apt remove`). |

The data directory is named `Mila`, not `openmila`, on purpose: the MCP helper
and the rest of the shared upstream code resolve it by that name.

## The MCP registration

If you registered the MCP helper with an AI client, that registration lives in
the client's own configuration, not in OpenMila's. The Linux uninstall asks
Claude Code to remove it (`claude mcp remove openmila`) when the `claude`
command is present, and prints the command when it is not. On Windows, remove it
yourself:

```powershell
claude mcp remove openmila
```

`mcp-access.json`, the consent file inside your data directory, stays with your
data. It grants nothing on its own once the helper is gone, and the gate it
feeds fails closed.

## What an uninstall never removes

Stated once more, because it is the rule the whole page is built on: removing
OpenMila removes OpenMila. Recordings, transcripts, downloaded models and
settings are kept unless you explicitly ask for them to go, on both systems.
That is upstream Mila's own uninstall rule, and the port keeps it.
