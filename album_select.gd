extends Control

## Album-selection screen. Shows a scrollable grid of album thumbnails
## that the player can tap to load that album's puzzles into level select.

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

	var count := LevelManager.get_album_count()
	for i in range(count):
		var album: Dictionary = LevelManager.albums[i]
		var btn := Button.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.mouse_force_pass_scroll_events = true

		# Load album thumbnail texture
		var tex = load(album["thumbnail_path"]) as Texture2D
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

		btn.text = album["name"]

		var idx := i
		btn.pressed.connect(func() -> void: _on_album_pressed(idx))
		grid.add_child(btn)


func _on_album_pressed(index: int) -> void:
	LevelManager.set_album(index)
	get_tree().change_scene_to_file("res://level_select.tscn")


func _on_back_pressed() -> void:
	get_tree().reload_current_scene()
