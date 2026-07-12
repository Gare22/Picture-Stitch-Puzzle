extends Control

## Level-selection screen. Shows a scrollable grid of puzzle thumbnails
## that the player can tap to start.

@onready var grid: GridContainer = $ScrollContainer/GridContainer
@onready var back_button: Button = $BackButton

const THUMB_SIZE := Vector2(160, 160)


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build_grid()


func _build_grid() -> void:
	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	var count := LevelManager.get_level_count()
	for i in range(count):
		var level: Dictionary = LevelManager.levels[i]
		var btn := Button.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Load thumbnail texture
		var tex = load(level["path"]) as Texture2D
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

		btn.text = level["name"]

		var idx := i
		btn.pressed.connect(func() -> void: _on_level_pressed(idx))
		grid.add_child(btn)


func _on_level_pressed(index: int) -> void:
	LevelManager.set_level(index)
	get_tree().change_scene_to_file("res://puzzle_game.tscn")


func _on_back_pressed() -> void:
	# If there's nowhere to go "back" to, just restart the selection
	get_tree().reload_current_scene()
