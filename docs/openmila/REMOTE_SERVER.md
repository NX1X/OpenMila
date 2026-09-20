# Remote transcription in OpenMila

OpenMila can send audio to your own transcription server instead of
transcribing on the machine, exactly as Mila can. Setting up the server is
covered by Mila's guides, which apply to OpenMila as they are:

- [One server with Docker](../REMOTE_TRANSCRIPTION_SERVER.md)
- [A shared team server on Kubernetes](../self-hosted-server/README.md)

The server does not know or care which app sends the audio. What differs is
only on the app side:

| Mila's guide says | In OpenMila |
|---|---|
| Settings → Models → Backend → Remote API | Settings > Models > Backend > Remote API (same place) |
| The API key is stored in the macOS Keychain | Stored in a file readable only by your user, under `~/.local/share/Mila/secrets/` on Linux |
| Double-click a `.milaconfig` file to apply it | Settings > General > Import a .milaconfig file, or open the file with OpenMila (`openmila team.milaconfig`). Double-click works once the desktop file association is installed. |
| Lower-powered Macs benefit most | Any machine without a GPU benefits: OpenMila transcribes on the CPU until GPU support ships, so a team server makes long recordings much faster |

Everything else in the guides (the Docker image, the ivrit.ai Hebrew model,
the separate English model, the Kubernetes manifests, the `.milaconfig`
format) is the same, and a `.milaconfig` made for Mila works in OpenMila and
the other way round.
