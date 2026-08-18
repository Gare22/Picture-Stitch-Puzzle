extends Control

## Album-selection screen. Shows a scrollable grid of album thumbnails
## that the player can tap to load that album's puzzles into level select.

@onready var grid: GridContainer = $ScrollContainer/GridContainer
@onready var back_button: Button = $BackButton

const THUMB_SIZE := Vector2(160, 160)

## Seconds between cover changes per album.
const COVER_INTERVAL := 15.0
## Seconds of offset between albums so covers never change simultaneously.
const COVER_STAGGER := 5.0
## Crossfade duration in seconds (old cover fades out as new fades in).
const COVER_FADE_TIME := 1.0


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
		var cell: Control = _build_cover_cell(album, i)
		grid.add_child(cell)


func _build_cover_cell(album: Dictionary, index: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = THUMB_SIZE
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var cover_old := TextureRect.new()
	cover_old.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_old.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_old.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_old.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_old.texture = load(album["thumbnail_path"]) as Texture2D
	cell.add_child(cover_old)

	var cover_new := TextureRect.new()
	cover_new.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_new.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_new.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_new.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_new.modulate.a = 0.0
	cell.add_child(cover_new)

	var name_label := Label.new()
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = album["name"]
	cell.add_child(name_label)

	var click_button := Button.new()
	click_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_button.flat = true
	click_button.focus_mode = Control.FOCUS_NONE
	click_button.mouse_filter = Control.MOUSE_FILTER_STOP
	click_button.mouse_force_pass_scroll_events = true
	var idx := index
	click_button.pressed.connect(func() -> void: _on_album_pressed(idx))
	cell.add_child(click_button)

	var levels: Array = album["levels"]
	if levels.size() > 1:
		var cover_timer := Timer.new()
		cover_timer.wait_time = COVER_INTERVAL + float(index) * COVER_STAGGER
		cover_timer.one_shot = false
		cover_timer.autostart = true
		cover_timer.timeout.connect(_on_cover_timeout.bind(cell, cover_old, cover_new, levels))
		cover_timer.name = "CoverTimer"
		cell.add_child(cover_timer)

	return cell


func _on_cover_timeout(cell: Control, cover_old: TextureRect, cover_new: TextureRect, levels: Array) -> void:
	var idx: int = cell.get_meta("cover_index", 0)
	idx = (idx + 1) % levels.size()
	cell.set_meta("cover_index", idx)

	var next_tex = load(levels[idx]["path"]) as Texture2D
	if next_tex == null:
		return
	cover_new.texture = next_tex

	var tween := cell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(cover_new, "modulate:a", 1.0, COVER_FADE_TIME)
	tween.tween_property(cover_old, "modulate:a", 0.0, COVER_FADE_TIME)
	tween.chain().tween_callback(func() -> void:
		cover_old.texture = cover_new.texture
		cover_old.modulate.a = 1.0
		cover_new.modulate.a = 0.0
	)

	var timer: Timer = cell.get_node("CoverTimer")
	timer.wait_time = COVER_INTERVAL


func _on_album_pressed(index: int) -> void:
	LevelManager.set_album(index)
	get_tree().change_scene_to_file("res://level_select.tscn")


func _on_back_pressed() -> void:
	get_tree().reload_current_scene()
