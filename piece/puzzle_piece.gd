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

## Stores the merged group pieces during a drag for cleanup on drag end.
var _drag_group_pieces: Array = []


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

	var board = get_parent()
	var my_grid_pos: int = board.get_grid_pos(self)
	var group: Array[int] = board.get_merged_group(my_grid_pos)

	# Make all merged pieces semi-transparent
	_drag_group_pieces = []
	for pos in group:
		var piece = board.get_pieces()[pos]
		if piece != null:
			piece.modulate = Color(1.0, 1.0, 1.0, 0.3)
			_drag_group_pieces.append(piece)

	# Build drag preview showing all merged pieces
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for pos in group:
		var piece = board.get_pieces()[pos]
		var col_diff: int = (pos % board.columns_count) - (my_grid_pos % board.columns_count)
		var row_diff: int = (pos / board.columns_count) - (my_grid_pos / board.columns_count)

		var preview := TextureRect.new()
		preview.texture = piece.texture
		preview.expand_mode = EXPAND_IGNORE_SIZE
		preview.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED
		preview.size = size
		preview.position = Vector2(col_diff * size.x, row_diff * size.y) - size * 0.5
		preview.modulate = Color(1.0, 1.0, 1.0, 1.0)

		wrapper.add_child(preview)

	set_drag_preview(wrapper)

	return {
		"anchor_piece": self,
		"group_positions": group,
		"anchor_grid_pos": my_grid_pos,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data == null or not data is Dictionary:
		return false
	if data.get("anchor_piece") == self:
		return false

	var board = get_parent()
	var drop_grid_pos: int = board.get_grid_pos(self)
	if drop_grid_pos < 0:
		return false

	return board.can_drop_group(data["group_positions"], data["anchor_grid_pos"], drop_grid_pos)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_play_blip(drop_sound)

	var board = get_parent()
	var drop_grid_pos: int = board.get_grid_pos(self)
	board.swap_group(data["group_positions"], data["anchor_grid_pos"], drop_grid_pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		for piece in _drag_group_pieces:
			if piece != null:
				piece.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_drag_group_pieces = []
