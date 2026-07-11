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
	# Hide the original piece while dragging
	modulate = Color(1.0, 1.0, 1.0, 0.3)

	# Create a full-opacity preview that looks exactly like the piece
	var preview = TextureRect.new()
	preview.texture = texture
	preview.expand_mode = EXPAND_IGNORE_SIZE
	preview.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
	preview.size = size
	preview.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Offset the preview so the cursor is at the center of the piece
	preview.position = -size * 0.5
	set_drag_preview(preview)

	return self


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data != null and data != self


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# Restore opacity on both pieces
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	data.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var board = get_parent()
	if board != null and board.has_method(&"swap_pieces"):
		board.swap_pieces(data, self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# Drag was cancelled (dropped outside a valid target) — restore opacity
		modulate = Color(1.0, 1.0, 1.0, 1.0)
