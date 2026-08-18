extends Node

## Central registry of puzzle albums.
## Albums are auto-discovered from subfolders of res://assets/puzzles/.
## Each album holds its own level list, discovered from the folder's .png files.

## Built at runtime by scanning res://assets/puzzles/ subfolders.
## Each entry: { "name": String, "path": String, "thumbnail_path": String, "levels": Array[Dictionary] }
var albums: Array[Dictionary] = []

## Index of the currently-selected album (set by AlbumSelect).
var current_album_index: int = 0

## Levels of the current album only (built by set_album()).
var levels: Array[Dictionary] = []

## Index of the currently-selected level within the current album (set by LevelSelect).
var current_index: int = 0

## Grid size (columns = rows) for the currently-selected difficulty. Defaults to Easy (4x4).
var current_grid_size: int = 4


func _ready() -> void:
	_build_albums()
	set_album(0)


## Scans res://assets/puzzles/ subfolders and builds the albums list.
## Folders with no .png files are skipped.
func _build_albums() -> void:
	albums.clear()

	var root_dir := DirAccess.open("res://assets/puzzles/")
	if root_dir == null:
		push_error("LevelManager: DirAccess.open returned null for res://assets/puzzles/")
		return

	var folders: PackedStringArray = DirAccess.get_directories_at("res://assets/puzzles/")
	folders.sort()

	for folder: String in folders:
		var folder_path: String = "res://assets/puzzles/%s/" % folder

		# Collect puzzle images via .png.import files, which exist in both editor
		# and export builds. Raw .png files only exist in the editor, so we skip
		# them to avoid double-counting.
		var images: Array[String] = []
		var all_files: PackedStringArray = DirAccess.get_files_at(folder_path)
		for file_name: String in all_files:
			if file_name.ends_with(".png.import"):
				images.append(file_name.trim_suffix(".import"))
		images.sort()

		# Skip folders that contain no puzzle images.
		if images.is_empty():
			continue

		var album_levels: Array[Dictionary] = []
		for i: int in range(images.size()):
			album_levels.append({
				"name": "Level %d" % (i + 1),
				"path": "%s%s" % [folder_path, images[i]],
			})

		albums.append({
			"name": folder.capitalize(),
			"path": folder_path,
			"thumbnail_path": album_levels[0]["path"],
			"levels": album_levels,
		})

	print("LevelManager: built %d albums" % albums.size())


## Selects an album and loads its levels as the current level set.
## Resets the in-album level index to 0.
func set_album(index: int) -> void:
	if albums.is_empty():
		return
	current_album_index = clampi(index, 0, albums.size() - 1)
	levels = albums[current_album_index]["levels"] as Array[Dictionary]
	current_index = 0


## Returns the total number of albums.
func get_album_count() -> int:
	return albums.size()


## Returns the currently-selected album Dictionary, or {} if none.
func get_current_album() -> Dictionary:
	if albums.is_empty():
		return {}
	return albums[current_album_index]


## Returns the Dictionary for the current level.
func get_current_level() -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[current_index]


## Returns the total number of levels in the current album.
func get_level_count() -> int:
	return levels.size()


## Advance to the next level (wraps around within the current album). Returns true if wrapped.
func advance_level() -> bool:
	var wrapped := false
	current_index += 1
	if current_index >= levels.size():
		current_index = 0
		wrapped = true
	return wrapped


## Jump to a specific level index within the current album.
func set_level(index: int) -> void:
	current_index = clampi(index, 0, levels.size() - 1)


## Sets the grid size for the next puzzle (difficulty).
func set_grid_size(size: int) -> void:
	current_grid_size = size
