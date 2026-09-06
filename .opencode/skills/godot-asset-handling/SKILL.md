---
name: godot-asset-handling
description: Exact commands for inspecting binary asset metadata and safely relocating scripts/shaders with their .uid sidecars, without reading binary content directly.
---

## Inspecting binary assets (never `cat` these)

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/Garrett Tallent/.config/opencode/scripts/asset_info.ps1" path/to/sprite.png
```

The inspector reads only file headers and prints plain-text metadata: image dimensions (png/jpeg/gif/bmp/webp) and audio duration (wav/flac). ogg/mp3 durations are unsupported by the inspector.

## Moving or renaming a script/shader

Move the file and its `.uid` sidecar together - never regenerate the `.uid`:

```bash
mv scripts/player.gd scripts/entities/player.gd
mv scripts/player.gd.uid scripts/entities/player.gd.uid
```

## Never do this

- `cat path/to/sprite.png` - forbidden by Rule 4.
- Deleting a `.uid` file or adding `*.uid` to `.gitignore` - breaks scene links for every other clone.
- Hand-editing `.uid` file contents.
