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
		var tex = load(level["path"]) as Texture2D
		var earned := LevelManager.get_level_stars(LevelManager.current_album_index, i)
		var btn := LEVEL_BUTTON_SCENE.instantiate() as LevelButton
		btn.level_selected.connect(_on_level_pressed)
		grid.add_child(btn)
		btn.setup(tex, earned, i, _column_width())


func _on_level_pressed(index: int) -> void:
	_pending_level_index = index
	var tex = load(LevelManager.levels[index]["path"]) as Texture2D
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
