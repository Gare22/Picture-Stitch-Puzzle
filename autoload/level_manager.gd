extends Node

## Central registry of all available puzzle images.
## Images are auto-discovered from res://assets/ (excluding the old/ subfolder).
## best.png is always Level 1; the rest are sorted alphabetically.

## Built at runtime by scanning the assets folder.
var levels: Array[Dictionary] = []

## Index of the currently-selected level (set by LevelSelect).
var current_index: int = 0

## Grid size (columns = rows) for the currently-selected difficulty. Defaults to Easy (4x4).
var current_grid_size: int = 4


func _ready() -> void:
	_build_levels()


## Scans the assets folder and builds the levels list.
## best.png is pinned as Level 1; everything else is sorted alphabetically.
func _build_levels() -> void:
	levels.clear()

	# --- Diagnostic logging for Android debugging ---
	var dir := DirAccess.open("res://assets/")
	if dir == null:
		push_error("LevelManager: DirAccess.open returned null for res://assets/")
	else:
		print("LevelManager: DirAccess.open succeeded")

	# Try multiple path variations and log results
	var paths_to_try: Array[String] = [
		"res://assets/",
		"res://assets",
		"res://",
	]
	for p: String in paths_to_try:
		var files: PackedStringArray = DirAccess.get_files_at(p)
		print("LevelManager: get_files_at(\"%s\") => %d files" % [p, files.size()])
		for f: String in files:
			print("  - %s" % f)
	# --- End diagnostics ---

	if dir == null:
		return

	# Collect puzzle images via .png.import files, which exist in both editor
	# and export builds. Raw .png files only exist in the editor, so we skip
	# them to avoid double-counting.
	var images: Array[String] = []
	var all_files: PackedStringArray = DirAccess.get_files_at("res://assets/")
	for file_name: String in all_files:
		if file_name.ends_with(".png.import"):
			images.append(file_name.trim_suffix(".import"))

	# Sort alphabetically for consistent ordering
	images.sort()

	# Pin best.png as Level 1 (move it to the front if present)
	var best_idx := images.find("best.png")
	if best_idx >= 0:
		images.remove_at(best_idx)
		images.insert(0, "best.png")

	# Build levels array
	for i: int in range(images.size()):
		var path: String = "res://assets/%s" % images[i]
		levels.append({
			"name": "Level %d" % (i + 1),
			"path": path,
		})

	print("LevelManager: built %d levels" % levels.size())


## Returns the Dictionary for the current level.
func get_current_level() -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[current_index]


## Returns the total number of levels.
func get_level_count() -> int:
	return levels.size()


## Advance to the next level (wraps around). Returns true if wrapped.
func advance_level() -> bool:
	var wrapped := false
	current_index += 1
	if current_index >= levels.size():
		current_index = 0
		wrapped = true
	return wrapped


## Jump to a specific level index.
func set_level(index: int) -> void:
	current_index = clampi(index, 0, levels.size() - 1)


## Sets the grid size for the next puzzle (difficulty).
func set_grid_size(size: int) -> void:
	current_grid_size = size
