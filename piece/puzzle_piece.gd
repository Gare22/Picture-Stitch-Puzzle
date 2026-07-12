class_name PuzzlePiece
extends TextureRect

## Stores the grid position this piece SHOULD be at when the puzzle is solved.
## Determines which texture region from the source image belongs here.
var correct_index: int

## Flags for which borders to draw.
## When true, a line is rendered on that edge (meaning the neighbor doesn't belong there).
var draw_top := true
var draw_bottom := true
var draw_left := true
var draw_right := true

## Reference to the label shown in test mode.
@onready var piece_label: Label = $PieceLabel

## Audio players with randomized pitch for variety.
@onready var pickup_sound: AudioStreamPlayer = $PickupSound
@onready var drop_sound: AudioStreamPlayer = $DropSound



## Returns the piece label, resolving it lazily if @onready hasn't fired yet.
func get_piece_label() -> Label:
	if piece_label == null:
		piece_label = $PieceLabel
	return piece_label


## Play a sound with slight random pitch variation.
func _play_blip(player: AudioStreamPlayer) -> void:
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()


## Update border flags and trigger a redraw.
func set_borders(top: bool, bottom: bool, left: bool, right: bool) -> void:
	draw_top = top
	draw_bottom = bottom
	draw_left = left
	draw_right = right
	queue_redraw()


func _draw() -> void:
	var border_color = Color(0.15, 0.15, 0.15, 1.0)
	var w = size.x
	var h = size.y

	if draw_top:
		draw_line(Vector2(0.0, 0.0), Vector2(w, 0.0), border_color, 4.0)
	if draw_bottom:
		draw_line(Vector2(0.0, h), Vector2(w, h), border_color, 4.0)
	if draw_left:
		draw_line(Vector2(0.0, 0.0), Vector2(0.0, h), border_color, 4.0)
	if draw_right:
		draw_line(Vector2(w, 0.0), Vector2(w, h), border_color, 4.0)


func _get_drag_data(at_position: Vector2) -> Variant:
	_play_blip(pickup_sound)

	# Hide the original piece while dragging
	modulate = Color(1.0, 1.0, 1.0, 0.3)

	# Godot positions the drag preview's top-left at the mouse cursor
	# and overrides its position every frame. To visually center the
	# piece on the cursor, we offset the TextureRect *inside* a wrapper.
	var wrapper = Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview = TextureRect.new()
	preview.texture = texture
	preview.expand_mode = EXPAND_IGNORE_SIZE
	preview.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	preview.size = size
	preview.position = -size * 0.5   # center within wrapper → center on cursor
	preview.modulate = Color(1.0, 1.0, 1.0, 1.0)

	wrapper.add_child(preview)
	set_drag_preview(wrapper)

	return self


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data != null and data != self


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_play_blip(drop_sound)

	# Restore opacity on both pieces
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	data.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var board = get_parent()
	if board != null and board.has_method(&"swap_pieces"):
		board.swap_pieces(data, self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Only play the drop sound here if _drop_data didn't already handle it
		#_play_blip(drop_sound)
		modulate = Color(1.0, 1.0, 1.0, 1.0)
