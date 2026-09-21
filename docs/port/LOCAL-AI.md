<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# Local AI, set up from inside the app

The AI features (titles, summaries, action items, Live AI) need a language
model. Mila leaves finding one to the user. OpenMila can do it: **Settings ->
AI Provider -> Set up local AI** installs a model server on the machine,
downloads an open model, and selects it as the provider. From then on nothing
the AI features do leaves the computer.

This is a port-only feature; Mila has no equivalent.

## What the button does

1. Downloads [Ollama](https://github.com/ollama/ollama) at a pinned release
   (`OllamaRelease.pinned` in `Port/LocalAI/ManagedOllama.swift`) into the
   app's cache directory, and checks the download against the digest the
   vendor publishes for that release before anything is unpacked or run. A
   mismatch deletes the download and stops.
2. Unpacks it and marks it verified. Files alone are not trusted: without the
   stamp written after a verified unpack, the app will not start the server.
3. Starts `ollama serve` as a child of the app, bound to `127.0.0.1:11434`,
   with its model store under the same cache directory. If something already
   answers on that port (a user's own Ollama), that is used instead.
4. Pulls the chosen model through the server, showing progress.
5. Sets the provider to Ollama (local), the base URL, the model name, and
   turns automatic summaries on.

Each step skips what is already done, so pressing the button again with a
different model only pulls that model.

## Models offered

Western, open-licensed, in sizes that fit the machines the port targets.
The first is what "just set it up" picks. `LocalModel.catalogue` is the
list, and a test pins the rule.

| Model | Publisher | Licence | Size | Memory |
|---|---|---|---|---|
| Mistral 7B (default) | Mistral AI, France | Apache-2.0 | 4.4 GB | 8 GB |
| Mistral NeMo 12B | Mistral AI and NVIDIA | Apache-2.0 | 7.1 GB | 16 GB |
| OLMo 2 7B | Allen Institute for AI, USA | Apache-2.0 | 4.5 GB | 8 GB |
| Gemma 3 4B | Google, USA | Gemma terms | 3.3 GB | 8 GB |
| Llama 3.1 8B | Meta, USA | Llama 3.1 community licence | 4.9 GB | 8 GB |
| SmolLM2 1.7B | Hugging Face | Apache-2.0 | 1.8 GB | 4 GB |

Any other model Ollama can pull works too: pull it by hand with the managed
runtime (`<cache>/local-ai/runtime/bin/ollama pull <name>`) and type its name
in the Model field.

## Where it lives, and how it goes away

| | Linux | Windows |
|---|---|---|
| Runtime | `~/.cache/openmila/local-ai/runtime/` | `%LOCALAPPDATA%\OpenMila\cache\local-ai\runtime\` |
| Models | `~/.cache/openmila/local-ai/models/` | `%LOCALAPPDATA%\OpenMila\cache\local-ai\models\` |

Nothing is installed system-wide and no administrator is involved. The
server runs only while the app runs. Uninstalling the app keeps the models,
like every other piece of user data; an uninstall purge removes the whole
`local-ai` directory, and its size is stated before the question is asked.

## Headless

`openmila-selftest local-ai [--model name] [--cache dir]` runs the whole path
from a terminal and ends with one prompt through the summariser's own entry
point. It is how the feature was verified on Linux before it had a button.
