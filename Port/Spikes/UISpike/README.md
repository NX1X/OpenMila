# UI spike: SwiftCrossUI 0.9.0 (GTK4 backend)

Question: can SwiftCrossUI carry OpenMila's UI with Mila's layout and theme?

Build and run (Linux):

```bash
export PATH=$HOME/.local/swift-6.4.0/usr/bin:$PATH
cd Port/Spikes/UISpike
swift build --build-system native --product UISpike
.build/debug/UISpike
```

`--product` matters: Swift 6.4's default build system tries to compile every
target in the dependency, including the Windows-only `WinUIInterop`, and fails
on Linux.

## Checklist (Ubuntu 26.04, GTK 4.22)

| Item | Result | Notes |
|---|---|---|
| Sidebar / list / detail (`NavigationSplitView`, `List` selection) | Works | Same structure as Mila's `ContentView` |
| Mila's type scale | Works | `.caption`, `.callout`, `.title3`, `.title2`, `.headline`, `.body` exist under the same names |
| Settings with a section sidebar, `Toggle`, `Picker`, `Slider`, `TextField` | Works | |
| Sheets (`.sheet(isPresented:)`) | Works | Rename sheet and Settings |
| Light / dark (`.preferredColorScheme`) | Works | |
| App menu (`.commands`, `CommandMenu`) | Works | |
| Actions menu (`Menu`) | Works | Stands in for the context menu |
| Playback bar with a speed `Picker` | Works | |
| Multi-line editor (`TextEditor`) | Works | Undo comes from GTK's text view |
| Hebrew transcript | Needs eyes | Pango picks the base direction per paragraph; alignment is set per block. Visual check by a Hebrew reader pending |
| Right-click `contextMenu` | Missing | No modifier in 0.9.0. Options: `Menu` button per row (used here), or a GTK gesture through the backend |
| Drag a recording onto a folder | Missing | No drag-and-drop API in 0.9.0. Fallback: "Move to folder" menu, which Mila also has |
| `layoutDirection` environment | Missing | Per-block alignment covers transcripts; a fully mirrored RTL layout is not available |
| Borderless always-on-top overlay (dictation pill) | Missing | No window-level API. Needs a small GTK window outside SwiftCrossUI (gtk4-layer-shell on Wayland) |

## Verdict

Go, with three items built beside the framework rather than in it: the
context menu, drag-and-drop filing, and the dictation overlay window. None of
them blocks the main window, Settings, or the recording flow. WinUI backend
still to be checked on Windows.
