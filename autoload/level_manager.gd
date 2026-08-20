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

## ── Currency ──────────────────────────────────────────────────────────────
## Coins awarded per difficulty on puzzle completion. Easily configurable.
const EASY_REWARD: int = 10
const MEDIUM_REWARD: int = 25
const HARD_REWARD: int = 50

## Total coins the player owns (persisted across sessions).
var currency: int = 0

## Emitted whenever currency changes. HUDs connect to this.
signal currency_changed(new_amount: int)

## Path where per-level star progress is persisted.
const SAVE_PATH := "user://star_progress.cfg"

## Star progress per level. Key format: "%d:%d" % [album_index, level_index],
## value: an Array of 3 bools [easy, medium, hard].
var stars: Dictionary = {}

## Album registry loaded from res://assets/puzzles/albums.json.
## Maps folder name -> { "price": int, "unlocked_by_default": bool }.
var album_registry: Dictionary = {}

## Folder names of albums the player has purchased (persisted across sessions).
var purchased_albums: Dictionary = {}

## Path to the central album registry JSON.
const ALBUM_REGISTRY_PATH := "res://assets/puzzles/albums.json"


func _ready() -> void:
	_load_album_registry()
	_build_albums()
	set_album(0)
	load_progress()


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

		# Look up purchase metadata for this folder in the album registry.
		var entry: Dictionary = album_registry.get(folder, {})
		var price: int = entry.get("price", 0)
		var unlocked_by_default: bool = entry.get("unlocked_by_default", false)

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
			"folder": folder,
			"price": price,
			"unlocked_by_default": unlocked_by_default,
		})

	print("LevelManager: built %d albums" % albums.size())


## Loads the album registry (folder -> price/unlocked_by_default) from albums.json.
## A missing file or a missing folder entry means the album is free/unlocked.
func _load_album_registry() -> void:
	album_registry = {}
	if not FileAccess.file_exists(ALBUM_REGISTRY_PATH):
		return
	var f := FileAccess.open(ALBUM_REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_error("LevelManager: could not open %s" % ALBUM_REGISTRY_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("LevelManager: invalid albums.json at %s" % ALBUM_REGISTRY_PATH)
		return
	album_registry = parsed


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


## Returns true if the album at index is free (no price or unlocked by default).
func is_album_free(index: int) -> bool:
	if albums.is_empty():
		return true
	var a: Dictionary = albums[index]
	return a.get("price", 0) <= 0 or a.get("unlocked_by_default", false)


## Returns true if the album at index is unlocked (free or purchased).
func is_album_unlocked(index: int) -> bool:
	if is_album_free(index):
		return true
	return purchased_albums.has(_album_key(index))


## Returns the purchase price of the album at index (0 = free).
func get_album_price(index: int) -> int:
	if albums.is_empty():
		return 0
	return albums[index].get("price", 0)


## Returns the registry key (folder name) for the album at index.
func _album_key(index: int) -> String:
	if albums.is_empty():
		return ""
	return albums[index].get("folder", "")


## Attempts to purchase the album at index. Deducts currency, persists the
## purchase, and emits currency_changed on success. Returns true if purchased.
func purchase_album(index: int) -> bool:
	if is_album_unlocked(index):
		return false
	var price := get_album_price(index)
	if price <= 0:
		return false
	if currency < price:
		return false
	currency -= price
	purchased_albums[_album_key(index)] = true
	save_progress()
	currency_changed.emit(currency)
	return true


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


## Maps a grid size to a difficulty index (0=easy, 1=medium, 2=hard). 4->0, 5->1, 6->2.
func grid_size_to_difficulty_index(size: int) -> int:
	return clampi(size - 4, 0, 2)


## Returns the coin reward for a difficulty index (0=easy, 1=medium, 2=hard).
func reward_for_difficulty(difficulty_index: int) -> int:
	match difficulty_index:
		0: return EASY_REWARD
		1: return MEDIUM_REWARD
		2: return HARD_REWARD
		_: return 0


## Awards coins for completing a puzzle at the given difficulty. Returns the amount earned.
func earn_currency(difficulty_index: int) -> int:
	var amount := reward_for_difficulty(difficulty_index)
	if amount <= 0:
		return 0
	currency += amount
	save_progress()
	currency_changed.emit(currency)
	return amount


## Returns the 3-star earned array for a level (all false if none earned).
func get_level_stars(album_index: int, level_index: int) -> Array:
	var key := "%d:%d" % [album_index, level_index]
	if stars.has(key):
		return stars[key]
	return [false, false, false]


## Marks a star earned for a level+difficulty and persists it.
func mark_star_earned(album_index: int, level_index: int, difficulty_index: int) -> void:
	var key := "%d:%d" % [album_index, level_index]
	var arr: Array = get_level_stars(album_index, level_index)
	if difficulty_index >= 0 and difficulty_index < arr.size():
		arr[difficulty_index] = true
	stars[key] = arr
	save_progress()


## Loads star + currency progress from disk.
func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	stars = cfg.get_value("progress", "stars", {})
	currency = cfg.get_value("progress", "currency", 0)
	purchased_albums = cfg.get_value("progress", "purchased_albums", {})


## Saves star + currency progress to disk.
func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "currency", currency)
	cfg.set_value("progress", "purchased_albums", purchased_albums)
	cfg.save(SAVE_PATH)
