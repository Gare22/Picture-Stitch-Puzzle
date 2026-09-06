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


## Computes the level-card column width from a width budget and a height budget.
## The width budget fills the viewport; the height budget shrinks cards on wide
## viewports (stretch mode "expand" grows width while logical height stays fixed)
## so every grid row, sized by its tallest image, stays fully visible.
func _column_width(textures: Array[Texture2D]) -> float:
	var vp := get_viewport_rect().size
	var width_col := (vp.x - STYLE.grid_edge_gap * 2.0 - STYLE.level_grid_separation * (float(STYLE.grid_columns) - 1.0)) / float(STYLE.grid_columns)
	var rows := ceili(float(textures.size()) / float(STYLE.grid_columns))
	if rows <= 0:
		return width_col
	# Sum of per-row tallest-card aspects (image height / width) at column width 1.
	var aspect_sum := 0.0
	for row in range(rows):
		var row_aspect := 0.0
		for col in range(STYLE.grid_columns):
			var idx := row * STYLE.grid_columns + col
			if idx >= textures.size():
				break
			var tex := textures[idx]
			if tex != null and tex.get_size().x > 0.0:
				row_aspect = maxf(row_aspect, tex.get_size().y / tex.get_size().x)
		aspect_sum += row_aspect
	if aspect_sum <= 0.0:
		return width_col
	var avail_h := _grid_available_height() - float(rows - 1) * STYLE.level_grid_separation
	var height_col := avail_h / aspect_sum
	return maxf(minf(width_col, height_col), 1.0)


## Height available to the grid inside the scroll area: viewport height minus the
## ScrollContainer's vertical offsets and the MarginContainer's top/bottom margins.
func _grid_available_height() -> float:
	var scroll: ScrollContainer = $ScrollContainer
	var margins: MarginContainer = $ScrollContainer/MarginContainer
	var vp_h := get_viewport_rect().size.y
	var scroll_h := vp_h + scroll.offset_bottom - scroll.offset_top
	return scroll_h - float(margins.get_theme_constant("margin_top")) - float(margins.get_theme_constant("margin_bottom"))


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
	var textures: Array[Texture2D] = []
	for i in range(count):
		textures.append(_load_texture(LevelManager.levels[i]["path"]))

	var target_width := _column_width(textures)
	for i in range(count):
		var level: Dictionary = LevelManager.levels[i]
		var tex := textures[i]
		var earned := LevelManager.get_level_stars(LevelManager.current_album_index, i)
		var btn := LEVEL_BUTTON_SCENE.instantiate() as LevelButton
		btn.level_selected.connect(_on_level_pressed)
		grid.add_child(btn)
		btn.setup(tex, earned, i, target_width)


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
