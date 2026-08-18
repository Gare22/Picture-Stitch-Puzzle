extends Control

## Level-selection screen. Shows a scrollable grid of puzzle thumbnails
## that the player can tap to start.

@onready var grid: GridContainer = $ScrollContainer/VBox/GridContainer
@onready var back_button: Button = $BackButton
@onready var difficulty_overlay: Control = $DifficultyOverlay
@onready var easy_button: Button = $DifficultyOverlay/Panel/VBox/EasyButton
@onready var medium_button: Button = $DifficultyOverlay/Panel/VBox/MediumButton
@onready var hard_button: Button = $DifficultyOverlay/Panel/VBox/HardButton

const EDGE_GAP := 8.0
const COL_SEP := 5.0
const COLUMNS := 2

## Index of the level the player tapped, held until a difficulty is chosen.
var _pending_level_index: int = -1


func _column_width() -> float:
	var vp_w: float = get_viewport_rect().size.x
	return (vp_w - EDGE_GAP * 2.0 - COL_SEP * (COLUMNS - 1)) / COLUMNS


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	easy_button.pressed.connect(func() -> void: _on_difficulty_pressed(4))
	medium_button.pressed.connect(func() -> void: _on_difficulty_pressed(5))
	hard_button.pressed.connect(func() -> void: _on_difficulty_pressed(6))
	_build_grid()


func _build_grid() -> void:
	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	var count := LevelManager.get_level_count()
	for i in range(count):
		var level: Dictionary = LevelManager.levels[i]
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_force_pass_scroll_events = true

		# Load thumbnail texture
		var col_w := _column_width()
		var tex = load(level["path"]) as Texture2D
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

			# Size the button to fill the column width while preserving
			# the image's aspect ratio.
			var tex_size := tex.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				var fit_scale := col_w / tex_size.x
				btn.custom_minimum_size = Vector2(col_w, tex_size.y * fit_scale)
			else:
				btn.custom_minimum_size = Vector2(col_w, col_w)
		else:
			btn.custom_minimum_size = Vector2(col_w, col_w)

		var idx := i
		btn.pressed.connect(func() -> void: _on_level_pressed(idx))
		grid.add_child(btn)


func _on_level_pressed(index: int) -> void:
	_pending_level_index = index
	difficulty_overlay.visible = true


func _on_difficulty_pressed(grid_size: int) -> void:
	LevelManager.set_level(_pending_level_index)
	LevelManager.set_grid_size(grid_size)
	get_tree().change_scene_to_file("res://puzzle_game.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://album_select.tscn")
