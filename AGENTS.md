# Godot 4.6 Project Rules

Follow every rule below without exception. These are hard constraints, not suggestions. If a request conflicts with a rule, say so and stop instead of working around it.

## Rule 1: Scene-based architecture only

- NEVER write code that calls `add_child()` more than once at runtime to build up the same feature.
- If a feature needs more than one node, create a `.tscn` scene file for it and instantiate that scene: `preload("res://path/to/thing.tscn").instantiate()`.
- A single dynamically spawned node (e.g. one bullet) is allowed ONLY if it is itself an instanced scene, not a node built by hand in code.
- Before writing any runtime node-creation code, check: does this touch more than one node? If yes, stop and create the scene file first instead of writing the loop.

## Rule 2: Godot 4.6 only — verify, never assume

- This project targets Godot 4.6 exclusively.
- NEVER use Godot 3.x patterns:
  - `yield` (use `await` instead)
  - string-based signal connections: `.connect("signal_name", self, "_on_thing")` (use `signal.connect(_on_thing)`)
  - `onready var` without the `@onready` annotation
  - `export var` without the `@export` annotation
- Before calling any API you are not certain shipped in Godot 4.6, query the `godot-docs` MCP tool or the official class reference. Do not guess from memory — Godot 4.6 went stable January 27, 2026, recent enough that your training data may be wrong, outdated, or missing it entirely.

## Rule 3: UIDs are opaque — hands off, with one exception

- NEVER read, generate, or hand-edit `uid://` values or `.uid` file contents. Treat them as editor-managed state you do not touch.
- EXCEPTION: if you move or rename a `.gd` or `.gdshader` file, move its matching `.uid` sidecar in the SAME operation using `mv` — never regenerate or rewrite it. Example: `mv scripts/player.gd scripts/entities/player.gd && mv scripts/player.gd.uid scripts/entities/player.gd.uid`
- NEVER add `*.uid` to `.gitignore`. These files are committed project state. Ignoring them breaks scene-to-script links for every other collaborator's clone.

## Rule 4: Never read raw binary asset contents

- NEVER open, `cat`, or otherwise read the raw bytes of: `.png .jpg .jpeg .webp .wav .ogg .mp3 .ttf .otf .bin`
- To inspect a binary asset's properties, use the system header-only inspector (reads only file headers, prints plain-text metadata):
  `powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/Garrett Tallent/.config/opencode/scripts/asset_info.ps1" path/to/file.png`
  Images print dimensions (png/jpeg/gif/bmp/webp), wav/flac print duration. ogg/mp3 durations are unsupported by the inspector.
- `.import` files are plain text metadata and safe to read normally.

## Testing

- Testing is manual. Write tests with `@godot-tester` (tab-visible agent, invoked by the user). Run the suite with the `/run-tests` command, which hands results to godot-build to fix any failures.
- The test suite is GdUnit4 (v6.x). Run it headless with this machine's Godot binary (the bootstrap bakes its absolute path below; re-run the bootstrap if the binary moves or upgrades):
  `& "C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests -c -rd ./reports`
- Judge pass/fail from the exit code and the report file in `./reports` (`index.htm`, JUnit `results.xml`), NEVER from console text alone. Exit codes: 0 = all tests pass, 100 = test failures, 101 = warnings.
- Godot can print alarming `ERROR:` lines to console on a completely clean test run.
- Use MCP scene/runtime tools (screenshots, live scene-tree inspection) only for exploratory or visual checks. Use GdUnit4 for anything that needs to be a repeatable regression test.

## Bootstrap (first access in a new project)

If `AGENTS.md`, `opencode.json`, `.opencode/`, or `addons/gdUnit4` are missing, this harness is not installed in this project yet. Before doing anything else, run the system bootstrap once:

    powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/Garrett Tallent/.config/opencode/scripts/godot46_bootstrap.ps1" -ProjectDir <project root>

The script copies this harness into the project, prepares the godot-docs MCP server (uv venv + one-time godot-docs download/conversion, all cached system-wide), clones/builds the godot-control MCP server and patches `opencode.json` with its real path, and drops the GdUnit4 addon into `addons/gdUnit4`. No Docker is required at any step. Report any step that needs manual attention.

## Delegation

- Before committing any change that creates nodes at runtime, delegate review to `@scene-reviewer`.
- Before finalizing code that uses an API you're not fully certain about, delegate to `@api-auditor`.
