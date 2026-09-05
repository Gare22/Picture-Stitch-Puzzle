---
name: godot-testing-gdunit4
description: How to write and run GdUnit4 tests headlessly and how to read the result without dumping raw console logs. Test authoring is @godot-tester; running is via the /run-tests command.
---

Test authoring is owned by `@godot-tester` (tab-visible agent). Running the full suite is done via the `/run-tests` command, which hands results to godot-build to fix. godot-build does not write or run tests on its own.

## Running the suite

```bash
& "C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests -c -rd ./reports
```

`C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe` is the absolute path to this machine's Godot binary, baked in by the bootstrap script (re-run the bootstrap if the binary moves or upgrades). `-a tests` adds the `tests/` directory to the execution pipeline, `-c` keeps running after a failure so the report is complete, `-rd ./reports` sets the report directory. Exit codes: 0 = all tests pass, 100 = test failures, 101 = warnings.

Judge pass/fail from the exit code and the report in `./reports` (`index.htm`, JUnit `results.xml`) — not console text. Godot can print `ERROR:` lines on a completely clean, all-passing run.

## Minimal test shape

```gdscript
extends GdUnitTestSuite

func test_player_takes_damage() -> void:
    var player := Player.new()
    player.take_damage(10)
    assert_int(player.health).is_equal(90)
```

Place tests under `tests/`, mirroring the source tree.
