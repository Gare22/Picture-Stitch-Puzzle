extends Node

## Central registry of puzzle albums.
## Albums are auto-discovered from subfolders of res://assets/puzzles/.
## Each album holds its own level list, discovered from the folder's .png files.

## Optional URL of a remote album catalog JSON. When set, albums listed there
## are downloaded at runtime and merged with the local albums.
@export var album_catalog_url: String = ""

## Built at runtime by scanning res://assets/puzzles/ subfolders.
## Each entry: { "name": String, "path": String, "thumbnail_path": String, "levels": Array[Dictionary] }
var albums: Array[Dictionary] = []

## Index of the currently-selected album (set by AlbumSelect).
var current_album_index: int = 0

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

## True once the player has purchased (or had restored) the real-money
## "Unlock All Puzzles" Google Play IAP. Persisted across sessions.
var all_puzzles_unlocked: bool = false

## Emitted whenever currency changes. HUDs connect to this.
signal currency_changed(new_amount: int)

## Emitted when the album list changes (remote albums added or cache loaded).
signal albums_changed()

## Emitted when remote album downloading starts or stops.
signal downloading_changed(downloading: bool)

## Path where per-level star progress is persisted.
const SAVE_PATH := "user://star_progress.cfg"

## Star progress per level. Key format: "%d:%d" % [album_index, level_index],
## value: an Array of 3 bools [easy, medium, hard].
var stars: Dictionary = {}

## ── Remote album downloading ──────────────────────────────────────────────
## Remote albums are stored under user://albums/ and cached in cache.json.
const REMOTE_DIR := "user://albums/"
const CACHE_PATH := "user://albums/cache.json"

## HTTP request mode: what the current request is fetching.
enum _MetaMode { IDLE, CATALOG }

var _http: HTTPRequest
var _http_full: HTTPRequest
var _http_preview: HTTPRequest
var _meta_mode: int = _MetaMode.IDLE
var _new_album_queue: Array = []
var _full_queue: Array = []
var _full_album_index: int = -1
var _current_image_index: int = 0
var _current_image_dest: String = ""
var _preview_queue: Array = []
var _preview_album_index: int = -1
var _current_preview_index: int = 0
var _current_preview_dest: String = ""
var _cache: Dictionary = {}
var _downloading: bool = false

## Album registry loaded from res://assets/puzzles/albums.json.
## Maps folder name -> { "price": int, "unlocked_by_default": bool }.
var album_registry: Dictionary = {}

## Folder names of albums the player has purchased (persisted across sessions).
var purchased_albums: Dictionary = {}

## Path to the central album registry JSON.
const ALBUM_REGISTRY_PATH := "res://assets/puzzles/albums.json"

## Path to the puzzle-image manifest (lists image filenames per album folder).
## Used so album discovery works in exported builds (e.g. Android) where the
## raw image source files are replaced by imported resources and are not
## discoverable via the file system.
const PUZZLE_MANIFEST_PATH := "res://assets/puzzles/manifest.json"


## Levels of the current album only (built by set_album()).
var levels: Array = []


func _ready() -> void:
	# Local albums are built first, before any remote work, so the built-in
	# puzzles are always available even if the network is slow or offline.
	_load_album_registry()
	_build_albums()
	set_album(0)
	load_progress()
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_meta_completed)
	_http_full = HTTPRequest.new()
	add_child(_http_full)
	_http_full.request_completed.connect(_on_content_completed)
	_http_preview = HTTPRequest.new()
	add_child(_http_preview)
	_http_preview.request_completed.connect(_on_preview_completed)
	_load_cache()
	# Defer the remote catalog fetch to the next frame so the scene tree is
	# fully settled and local albums are displayed before any async network
	# work begins.
	call_deferred("_fetch_remote_catalog")


## Scans res://assets/puzzles/ subfolders and builds the albums list.
## Folders with no puzzle images are skipped.
func _build_albums() -> void:
	albums.clear()

	var root_dir := DirAccess.open("res://assets/puzzles/")
	if root_dir == null:
		push_error("LevelManager: DirAccess.open returned null for res://assets/puzzles/")
		return

	var folders: PackedStringArray = DirAccess.get_directories_at("res://assets/puzzles/")
	folders.sort()

	var manifest := _load_puzzle_manifest()

	for folder: String in folders:
		var folder_path: String = "res://assets/puzzles/%s/" % folder

		# Collect puzzle images. ResourceLoader.list_directory() is remap-aware
		# and works in exported builds; the manifest is a fallback for any
		# platform where directory listing is unavailable.
		var images: Array[String] = _discover_images(folder_path)
		if images.is_empty() and manifest.has(folder):
			for img in manifest[folder]:
				images.append(img)
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


## Loads the puzzle-image manifest (folder -> array of image filenames).
## Returns {} if the file is missing or invalid.
func _load_puzzle_manifest() -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(PUZZLE_MANIFEST_PATH):
		return result
	var f := FileAccess.open(PUZZLE_MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return result
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		result = parsed
	return result


## Discovers image filenames in a folder by extension.
## Uses ResourceLoader.list_directory(), which is remap-aware and works in
## exported builds (unlike DirAccess, which only sees physical files and
## misses imported resources on Android/exported builds).
func _discover_images(folder_path: String) -> Array[String]:
	var images: Array[String] = []
	var entries := ResourceLoader.list_directory(folder_path)
	for entry in entries:
		if entry.ends_with("/"):
			continue  # subdirectory
		var base := entry
		if base.ends_with(".import"):
			base = base.trim_suffix(".import")
		var ext := base.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "avif", "bmp"]:
			if not images.has(base):
				images.append(base)
	return images


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
	levels = albums[current_album_index]["levels"]
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


## Returns true if the album at index is unlocked (free, purchased, or the
## player owns the "Unlock All Puzzles" IAP).
func is_album_unlocked(index: int) -> bool:
	if all_puzzles_unlocked:
		return true
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
	return albums[index].get("folder", albums[index].get("id", ""))


## Returns a stable star-key prefix for an album (source + id), so stars stay
## associated with the correct album even if album ordering changes.
func _album_star_key(album_index: int) -> String:
	if albums.is_empty() or album_index < 0 or album_index >= albums.size():
		return ""
	var a: Dictionary = albums[album_index]
	var source: String = a.get("source", "local")
	var id: String = a.get("folder", a.get("id", ""))
	return "%s:%s" % [source, id]


## Finds the index of a remote album by its ID.
func _find_remote_album_index(id: String) -> int:
	for i in range(albums.size()):
		if albums[i].get("id") == id and albums[i].get("source") == "remote":
			return i
	return -1


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
	if albums[index].get("source") == "remote" and not albums[index].get("downloaded", false):
		_start_full_download(index)
	return true


## Grants the "Unlock All Puzzles" entitlement (every current AND future
## album becomes unlocked, since is_album_unlocked() checks the flag first).
## Emits albums_changed so open menus rebuild with the unlocked state.
## Idempotent: repeated calls (e.g. purchase restores) do nothing.
func unlock_all_albums() -> void:
	if all_puzzles_unlocked:
		return
	all_puzzles_unlocked = true
	save_progress()
	# Start fetching the full images of any remote albums that were previously
	# locked (mirrors what purchase_album() does for coin purchases).
	for i in range(albums.size()):
		var a: Dictionary = albums[i]
		if a.get("source") == "remote" and not a.get("downloaded", false):
			_start_full_download(i)
	# Emit last, after all state changes, so rebuilt UI sees the final state.
	albums_changed.emit()


## DEV/TEST-ONLY: clears the local "Unlock All Puzzles" entitlement flag so the
## purchase flow can be tested again. The real Google Play purchase is NOT
## affected — the next query_purchases (app start or manual restore) re-grants
## it automatically. Emits albums_changed so open menus re-lock the albums.
func remove_unlock_all() -> void:
	if not all_puzzles_unlocked:
		return
	all_puzzles_unlocked = false
	save_progress()
	albums_changed.emit()


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


## Adds a specific amount of coins to the player's currency and persists it.
func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	currency += amount
	save_progress()
	currency_changed.emit(currency)


## Returns the 3-star earned array for a level (all false if none earned).
## Keyed by the album's stable ID (source + folder/id), not its array index,
## so stars stay with the correct album even when album ordering changes.
func get_level_stars(album_index: int, level_index: int) -> Array:
	var key := "%s:%d" % [_album_star_key(album_index), level_index]
	if stars.has(key):
		return stars[key]
	return [false, false, false]


## Marks a star earned for a level+difficulty and persists it.
func mark_star_earned(album_index: int, level_index: int, difficulty_index: int) -> void:
	var key := "%s:%d" % [_album_star_key(album_index), level_index]
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
	all_puzzles_unlocked = cfg.get_value("progress", "all_puzzles_unlocked", false)


## Saves star + currency progress to disk.
func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "currency", currency)
	cfg.set_value("progress", "purchased_albums", purchased_albums)
	cfg.set_value("progress", "all_puzzles_unlocked", all_puzzles_unlocked)
	cfg.save(SAVE_PATH)


## Resets ALL player progress: stars, currency, purchases, and downloaded albums.
## Rebuilds the local album list and re-fetches the remote catalog from scratch.
## NOTE: the real-money "Unlock All Puzzles" IAP entitlement is deliberately
## preserved — a paid Google Play entitlement is tied to the player's account
## and must not be revoked by an in-game reset.
func reset_all_progress() -> void:
	stars = {}
	currency = 0
	purchased_albums = {}
	save_progress()
	currency_changed.emit(currency)
	_delete_remote_cache()
	albums.clear()
	_build_albums()
	set_album(0)
	_cache = {}
	_fetch_remote_catalog()
	albums_changed.emit()


## Recursively deletes a directory and all its contents.
## DirAccess.remove() handles both files and empty directories; rmdir() and
## remove_dir_recursive() do not exist as instance methods in Godot 4.6.
func _delete_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for f in da.get_files():
		da.remove(f)
	for d in da.get_directories():
		_delete_dir_recursive(path.path_join(d))
	da.remove(path)


## Deletes the entire remote-album cache directory (user://albums/).
func _delete_remote_cache() -> void:
	_delete_dir_recursive("user://albums")
	_cache = {}


## Returns true while remote albums are being downloaded.
func is_downloading() -> bool:
	return _downloading

func is_album_downloaded(index: int) -> bool:
	if albums.is_empty():
		return true
	return albums[index].get("downloaded", true)

func _update_downloading() -> void:
	var busy := _new_album_queue.size() > 0 or _full_album_index != -1 or _full_queue.size() > 0 or _preview_album_index != -1 or _preview_queue.size() > 0
	if _downloading != busy:
		_downloading = busy
		downloading_changed.emit(busy)

func _load_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CACHE_PATH) == OK:
		_cache = cfg.get_value("cache", "albums", {})
		for id in _cache.keys():
			albums.append(_cache[id])
		if not _cache.is_empty():
			albums_changed.emit()
	for i in range(albums.size()):
		var a: Dictionary = albums[i]
		if a.get("source") != "remote":
			continue
		if not a.get("downloaded", false):
			if is_album_unlocked(i):
				_start_full_download(i)
			elif not a.get("preview_downloaded", false):
				_start_preview_download(i)

func _save_cache() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cache", "albums", _cache)
	cfg.save(CACHE_PATH)

func _fetch_remote_catalog() -> void:
	if album_catalog_url.is_empty():
		return
	_meta_mode = _MetaMode.CATALOG
	var err := _http.request(album_catalog_url)
	if err != OK:
		push_error("LevelManager: catalog request failed: %d" % err)

func _on_meta_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	match _meta_mode:
		_MetaMode.CATALOG:
			_handle_catalog(result, response_code, body)

func _handle_catalog(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		push_error("LevelManager: catalog fetch failed result=%d code=%d" % [result, response_code])
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Array or parsed is Dictionary):
		push_error("LevelManager: invalid catalog JSON")
		return
	var list: Array = parsed if parsed is Array else parsed.get("albums", [])
	var catalog_ids := {}
	for entry in list:
		if not (entry is Dictionary):
			continue
		var id: String = entry.get("id", "")
		if id.is_empty():
			continue
		catalog_ids[id] = entry
		if _cache.has(id):
			# Album already cached — sync it (check for updates, resume incomplete downloads)
			_sync_existing_album(id, entry)
		else:
			# New album — queue for download
			var name: String = entry.get("name", id)
			print("LevelManager: catalog album '%s' (id=%s)" % [name, id])
			_new_album_queue.append(entry)
	# Delete outdated albums (in cache but no longer in catalog)
	for id in _cache.keys():
		if not catalog_ids.has(id):
			_delete_outdated_album(id)
	_process_new_album_queue()


## Syncs an existing cached album with the catalog entry.
## Checks puzzle_count for new puzzles, resumes incomplete downloads.
func _sync_existing_album(id: String, catalog_entry: Dictionary) -> void:
	var album_idx := _find_remote_album_index(id)
	if album_idx == -1:
		return
	var a: Dictionary = albums[album_idx]
	var new_images: Array = catalog_entry.get("images", [])
	var new_previews: Array = catalog_entry.get("previews", [])
	var puzzle_count: int = catalog_entry.get("puzzle_count", new_images.size())
	var cached_level_count: int = a.get("levels", []).size()
	
	# Update metadata from catalog
	a["name"] = catalog_entry.get("name", a.get("name", id))
	a["price"] = catalog_entry.get("price", a.get("price", 0))
	a["images"] = new_images
	a["previews"] = new_previews
	a["puzzle_count"] = puzzle_count
	
	if not a.get("downloaded", false):
		# Full images not downloaded yet.
		if is_album_unlocked(album_idx):
			print("LevelManager: resuming download for '%s' (%d/%d images)" % [id, cached_level_count, puzzle_count])
			_start_full_download(album_idx)
		elif not a.get("preview_downloaded", false):
			print("LevelManager: downloading previews for '%s'" % id)
			_start_preview_download(album_idx)
		return
	
	if puzzle_count != cached_level_count:
		# Puzzle count changed — update (download missing, re-register all)
		print("LevelManager: updating '%s' (%d -> %d puzzles)" % [id, cached_level_count, puzzle_count])
		a["downloaded"] = false
		a["levels"] = []
		_start_full_download(album_idx)
	else:
		print("LevelManager: '%s' up to date (%d puzzles)" % [id, cached_level_count])


func _process_new_album_queue() -> void:
	_update_downloading()
	if _new_album_queue.is_empty():
		return
	var listing: Dictionary = _new_album_queue.pop_front()
	var id: String = listing.get("id", "")
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists(REMOTE_DIR + id):
		dir.make_dir_recursive(REMOTE_DIR + id)
	_finalize_listing(id, listing)

func _delete_outdated_album(id: String) -> void:
	var album_idx := _find_remote_album_index(id)
	if album_idx == -1:
		return
	albums.remove_at(album_idx)
	_cache.erase(id)
	_save_cache()
	# Delete the album folder
	_delete_dir_recursive(REMOTE_DIR + id)
	print("LevelManager: deleted outdated album '%s'" % id)
	albums_changed.emit()

func _finalize_listing(id: String, listing: Dictionary) -> void:
	var new_listing := {
		"id": id,
		"name": listing.get("name", id),
		"path": REMOTE_DIR + id + "/",
		"images": listing.get("images", []),
		"previews": listing.get("previews", []),
		"puzzle_count": listing.get("puzzle_count", listing.get("images", []).size()),
		"levels": [],
		"preview_paths": [],
		"price": listing.get("price", 0),
		"unlocked_by_default": listing.get("unlocked_by_default", false),
		"source": "remote",
		"downloaded": false,
		"preview_downloaded": false,
	}
	var idx := albums.size()
	albums.append(new_listing)
	_cache[id] = new_listing
	_save_cache()
	albums_changed.emit()
	# Free albums download full images immediately. Paid albums download
	# lower-res previews (or the full images if no previews are provided) so
	# the locked cover can show grayed-out previews before purchase.
	if new_listing["price"] <= 0 or new_listing.get("unlocked_by_default", false):
		_start_full_download(idx)
	else:
		_start_preview_download(idx)
	_process_new_album_queue()

func _start_full_download(index: int) -> void:
	if _full_queue.has(index) or _full_album_index == index:
		return
	_full_queue.append(index)
	_process_full_queue()

func _process_full_queue() -> void:
	_update_downloading()
	if _full_album_index != -1 or _full_queue.is_empty():
		return
	_full_album_index = _full_queue.pop_front()
	_current_image_index = 0
	_download_next_full_image()

func _download_next_full_image() -> void:
	if _full_album_index == -1:
		return
	var a: Dictionary = albums[_full_album_index]
	var images: Array = a.get("images", [])
	if _current_image_index >= images.size():
		_finalize_full_download()
		return
	var url: String = images[_current_image_index]
	var file_name := url.get_file()
	if file_name.is_empty():
		file_name = "img_%d.png" % _current_image_index
	_current_image_dest = a["path"] + file_name
	if FileAccess.file_exists(_current_image_dest):
		_register_full_image(_current_image_dest)
		_current_image_index += 1
		_download_next_full_image()
		return
	print("LevelManager: downloading image '%s' for album '%s'" % [file_name, a["name"]])
	_http_full.download_file = _current_image_dest
	var err := _http_full.request(url)
	if err != OK:
		push_error("LevelManager: image request failed: %d" % err)
		_current_image_index += 1
		_download_next_full_image()

func _on_content_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _full_album_index == -1:
		return
	var a: Dictionary = albums[_full_album_index]
	var images: Array = a.get("images", [])
	if _current_image_index < images.size():
		if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
			push_error("LevelManager: image download failed: %s (result=%d code=%d)" % [_current_image_dest, result, response_code])
		else:
			print("LevelManager: image ready '%s' for album '%s'" % [_current_image_dest.get_file(), a["name"]])
			_register_full_image(_current_image_dest)
	_current_image_index += 1
	_download_next_full_image()

func _register_full_image(dest: String) -> void:
	var a: Dictionary = albums[_full_album_index]
	a["levels"].append({"name": "Level %d" % (a["levels"].size() + 1), "path": dest})

func _finalize_full_download() -> void:
	var a: Dictionary = albums[_full_album_index]
	a["downloaded"] = true
	_cache[a["id"]] = a
	_save_cache()
	albums_changed.emit()
	_full_album_index = -1
	_process_full_queue()

## Starts downloading lower-res previews for a locked (paid, unpurchased) album.
## If the catalog entry has no `previews` array, falls back to the full images.
func _start_preview_download(index: int) -> void:
	var a: Dictionary = albums[index]
	var previews: Array = a.get("previews", [])
	if previews.is_empty():
		# No previews in the catalog — fall back to the full images
		_start_full_download(index)
		return
	if _preview_queue.has(index) or _preview_album_index == index:
		return
	_preview_queue.append(index)
	_process_preview_queue()

func _process_preview_queue() -> void:
	_update_downloading()
	if _preview_album_index != -1 or _preview_queue.is_empty():
		return
	_preview_album_index = _preview_queue.pop_front()
	_current_preview_index = 0
	# Ensure the previews subdirectory exists
	var a: Dictionary = albums[_preview_album_index]
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists(a["path"] + "previews"):
		dir.make_dir_recursive(a["path"] + "previews")
	_download_next_preview()

func _download_next_preview() -> void:
	if _preview_album_index == -1:
		return
	var a: Dictionary = albums[_preview_album_index]
	var previews: Array = a.get("previews", [])
	if _current_preview_index >= previews.size():
		_finalize_preview_download()
		return
	var url: String = previews[_current_preview_index]
	var file_name := url.get_file()
	if file_name.is_empty():
		file_name = "preview_%d.png" % _current_preview_index
	_current_preview_dest = a["path"] + "previews/" + file_name
	if FileAccess.file_exists(_current_preview_dest):
		_register_preview(_current_preview_dest)
		_current_preview_index += 1
		_download_next_preview()
		return
	print("LevelManager: downloading preview '%s' for album '%s'" % [file_name, a["name"]])
	_http_preview.download_file = _current_preview_dest
	var err := _http_preview.request(url)
	if err != OK:
		push_error("LevelManager: preview request failed: %d" % err)
		_current_preview_index += 1
		_download_next_preview()

func _on_preview_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _preview_album_index == -1:
		return
	var a: Dictionary = albums[_preview_album_index]
	var previews: Array = a.get("previews", [])
	if _current_preview_index < previews.size():
		if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
			push_error("LevelManager: preview download failed: %s (result=%d code=%d)" % [_current_preview_dest, result, response_code])
		else:
			print("LevelManager: preview ready '%s' for album '%s'" % [_current_preview_dest.get_file(), a["name"]])
			_register_preview(_current_preview_dest)
	_current_preview_index += 1
	_download_next_preview()

func _register_preview(dest: String) -> void:
	var a: Dictionary = albums[_preview_album_index]
	a["preview_paths"].append({"name": "Preview %d" % (a["preview_paths"].size() + 1), "path": dest})

func _finalize_preview_download() -> void:
	var a: Dictionary = albums[_preview_album_index]
	a["preview_downloaded"] = true
	_cache[a["id"]] = a
	_save_cache()
	albums_changed.emit()
	_preview_album_index = -1
	_process_preview_queue()

func ensure_album_downloaded(index: int) -> void:
	if index < 0 or index >= albums.size():
		return
	var a: Dictionary = albums[index]
	if a.get("source") != "remote" or a.get("downloaded", false) or not is_album_unlocked(index):
		return
	_start_full_download(index)
