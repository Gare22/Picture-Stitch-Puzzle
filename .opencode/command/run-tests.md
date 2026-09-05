---
description: Runs the project's GdUnit4 test suite headlessly and hands the results to godot-build to fix any failures.
agent: godot-build
---

Run the GdUnit4 test suite for this project, then fix anything that fails.

1. Run the suite headless:
   `& "C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests -c -rd ./reports`
   (`C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe` is the absolute path to this machine's Godot binary, baked in by the bootstrap script.)
2. Judge pass/fail from the exit code and the report in `./reports` (`index.htm` / JUnit `results.xml`) — NEVER from console `ERROR:` lines, which can appear even on a clean pass. Exit codes: 0 = all tests pass, 100 = test failures, 101 = warnings.
3. If there are failures, diagnose each one. Fix production-code bugs directly. If a test itself is wrong, fix the test. Then re-run the suite until it passes.
4. Report back: overall pass/fail, tests run, what you fixed, and the names of any tests still failing. Keep it short.