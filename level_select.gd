extends Control

## Level-selection screen. Shows a scrollable grid of puzzle thumbnails
## that the player can tap to start.

@onready var grid: GridContainer = $ScrollContainer/MarginContainer/VBox/GridContainer
@onready var back_button: Button = $BackButton
@onready var difficulty_overlay: DifficultyMenu = $DifficultyOverlay

const STYLE := preload("res://assets/app_style.tres") as AppStyle
const LEVEL_BUTTON_SCENE := preload("res://level_button.tscn")

## Index of the level the player tapped, held until a difficulty is chosen.
var _pending_level_index: int = -1


## Loads a texture from a path, handling both res:// (imported) and user:// (runtime) paths.
## Uses ResourceLoader for res:// paths because FileAccess.file_exists() fails
## on exported builds (imported resources are remapped to .ctex and the raw
## source file is not present).
func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path) as Texture2D
	# user:// or absolute path — use Image API for runtime-downloaded images
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty() or img.get_width() == 0:
		return null
	# Generate mipmaps so downscaled rendering (album covers, puzzle pieces)
	# looks as smooth as imported res:// textures, which get mipmaps from the
	# import pipeline automatically.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _column_width() -> float:
	var vp_w: float = get_viewport_rect().size.x
	return (vp_w - STYLE.grid_edge_gap * 2.0 - STYLE.level_grid_separation * (STYLE.grid_columns - 1)) / STYLE.grid_columns


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	difficulty_overlay.difficulty_selected.connect(_on_difficulty_pressed)
	difficulty_overlay.back_pressed.connect(_on_overlay_back_pressed)
	_build_grid()


func _build_grid() -> void:
	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	var count := LevelManager.get_level_count()
	for i in range(count):
		var level: Dictionary = LevelManager.levels[i]
		var tex = _load_texture(level["path"])
		var earned := LevelManager.get_level_stars(LevelManager.current_album_index, i)
		var btn := LEVEL_BUTTON_SCENE.instantiate() as LevelButton
		btn.level_selected.connect(_on_level_pressed)
		grid.add_child(btn)
		btn.setup(tex, earned, i, _column_width())


func _on_level_pressed(index: int) -> void:
	_pending_level_index = index
	var tex = _load_texture(LevelManager.levels[index]["path"])
	var earned := LevelManager.get_level_stars(LevelManager.current_album_index, index)
	difficulty_overlay.setup(tex, earned)
	difficulty_overlay.visible = true


func _on_difficulty_pressed(grid_size: int) -> void:
	LevelManager.set_level(_pending_level_index)
	LevelManager.set_grid_size(grid_size)
	get_tree().change_scene_to_file("res://puzzle_game.tscn")


func _on_overlay_back_pressed() -> void:
	difficulty_overlay.visible = false


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://album_select.tscn")
