extends GridContainer

## When true, pieces show a numbered label for debugging.
@export var test_mode: bool = false

var columns_count: int = 4
var rows_count: int = 4

## Tracks which correct_index each grid position currently holds.
## Indexed by grid position (row * columns + col), value is the correct_index
## of the piece currently at that position.
var grid_indices: Array[int] = []

const SIDE_PADDING: float = 16.0
const TOP_PADDING: float = 50.0   # room for timer
const BOTTOM_PADDING: float = 50.0 # room for menu button


## Called by GameManager after instantiation.
## Slices the source image into a grid, creates pieces, shuffles them, and draws borders.
func setup(source_image: Texture2D, p_columns: int, p_rows: int) -> void:
	columns_count = p_columns
	rows_count = p_rows
	columns = columns_count

	# Cell dimensions in image-space
	var cell_w = source_image.get_width() / float(columns_count)
	var cell_h = source_image.get_height() / float(rows_count)

	# Available screen area
	var viewport_size = get_viewport_rect().size
	var avail_w = viewport_size.x - SIDE_PADDING * 2.0
	var avail_h = viewport_size.y - TOP_PADDING - BOTTOM_PADDING

	# Board natural dimensions (at 1:1 scale)
	var board_w = cell_w * columns_count
	var board_h = cell_h * rows_count

	# Scale the board to fit within available area (maintain aspect ratio)
	var board_scale = minf(avail_w / board_w, avail_h / board_h)

	# Determine the final display cell size
	var cell_display_w = cell_w * board_scale
	var cell_display_h = cell_h * board_scale

	# ---- Create pieces ----
	var piece_scene = preload("res://piece/puzzle_piece.tscn")
	var pieces = []
	pieces.resize(columns_count * rows_count)

	var img_w := source_image.get_width()
	var img_h := source_image.get_height()

	for row in range(rows_count):
		for col in range(columns_count):
			var idx = row * columns_count + col
			var piece = piece_scene.instantiate()
			piece.name = "Piece_%d" % idx

			# Compute integer pixel boundaries so every pixel is covered
			# with no gaps or overlaps (handles non-divisible dimensions).
			var x_start := col * img_w / columns_count
			var x_end := (col + 1) * img_w / columns_count
			var y_start := row * img_h / rows_count
			var y_end := (row + 1) * img_h / rows_count
			var region_w := x_end - x_start
			var region_h := y_end - y_start

			# Slice with AtlasTexture
			var atlas = AtlasTexture.new()
			atlas.atlas = source_image
			atlas.region = Rect2(x_start, y_start, region_w, region_h)
			piece.texture = atlas
			piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			piece.custom_minimum_size = Vector2(cell_display_w, cell_display_h)
			piece.size = piece.custom_minimum_size
			piece.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			piece.size_flags_vertical = Control.SIZE_SHRINK_CENTER

			# Test-mode label
			if test_mode:
				piece.get_piece_label().visible = true
				piece.get_piece_label().text = str(idx + 1)

			pieces[idx] = piece

	# Initialize grid_indices: position i holds correct_index i
	grid_indices = []
	for k in range(pieces.size()):
		grid_indices.append(k)

	# Fisher-Yates shuffle on grid_indices (shuffle what's where).
	# Keep shuffling until we get a non-solved state.
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var is_solved := true
	while is_solved:
		for i in range(pieces.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var tmp = grid_indices[i]
			grid_indices[i] = grid_indices[j]
			grid_indices[j] = tmp
		# Check if the shuffle produced the solved state
		is_solved = false
		for k in range(grid_indices.size()):
			if grid_indices[k] != k:
				break
			if k == grid_indices.size() - 1:
				is_solved = true

	# Add children to grid in shuffled order.
	# Child at index i is the piece whose correct_index = grid_indices[i].
	for i in range(pieces.size()):
		var piece = pieces[grid_indices[i]]
		add_child(piece)

	# Set size explicitly from calculated dimensions (don't rely on
	# get_minimum_size() which can differ due to GridContainer internals).
	var total_board_w = cell_display_w * columns_count
	var total_board_h = cell_display_h * rows_count
	custom_minimum_size = Vector2(total_board_w, total_board_h)
	size = custom_minimum_size

	# Center the board in the available area
	position = Vector2(
		(viewport_size.x - total_board_w) * 0.5,
		TOP_PADDING + (avail_h - total_board_h) * 0.5
	)

	update_borders()


## Returns the correct_index of the piece at the given grid position.
func get_correct_index(grid_pos: int) -> int:
	if grid_pos < 0 or grid_pos >= grid_indices.size():
		return -1
	return grid_indices[grid_pos]


## Returns only PuzzlePiece children (filters out drag previews, etc.)
func get_pieces() -> Array:
	var result: Array = []
	for child in get_children():
		if child is PuzzlePiece:
			result.append(child)
	return result


## Re-evaluates which borders should be drawn for every piece.
## A border is hidden only when a piece's correctly-adjacent neighbor is beside it.
func update_borders() -> void:
	var all_pieces = get_pieces()
	for i in range(all_pieces.size()):
		var piece = all_pieces[i]
		var col = i % columns_count
		var row = int(float(i) / columns_count)
		var my_idx = get_correct_index(i)

		var draw_top = true
		var draw_bottom = true
		var draw_left = true
		var draw_right = true

		# Above
		if row > 0:
			var neighbor_idx = get_correct_index(i - columns_count)
			if neighbor_idx == my_idx - columns_count:
				draw_top = false

		# Below
		if row < rows_count - 1:
			var neighbor_idx = get_correct_index(i + columns_count)
			if neighbor_idx == my_idx + columns_count:
				draw_bottom = false

		# Left — only hide if the piece's correct position isn't at the left edge
		if col > 0 and my_idx % columns_count > 0:
			var neighbor_idx = get_correct_index(i - 1)
			if neighbor_idx == my_idx - 1:
				draw_left = false

		# Right — only hide if the piece's correct position isn't at the right edge
		if col < columns_count - 1 and my_idx % columns_count < columns_count - 1:
			var neighbor_idx = get_correct_index(i + 1)
			if neighbor_idx == my_idx + 1:
				draw_right = false

		piece.set_borders(draw_top, draw_bottom, draw_left, draw_right)


## Swap two pieces: exchange their textures and grid_indices, then re-evaluate borders.
func swap_pieces(piece_a, piece_b) -> void:
	# Find grid positions of both pieces
	var pieces = get_pieces()
	var pos_a = -1
	var pos_b = -1
	for i in range(pieces.size()):
		if pieces[i] == piece_a:
			pos_a = i
		if pieces[i] == piece_b:
			pos_b = i

	if pos_a < 0 or pos_b < 0:
		return

	# Swap textures
	var temp_tex = piece_a.texture
	piece_a.texture = piece_b.texture
	piece_b.texture = temp_tex

	# Swap grid_indices
	var temp_idx = grid_indices[pos_a]
	grid_indices[pos_a] = grid_indices[pos_b]
	grid_indices[pos_b] = temp_idx

	# Also swap test-mode labels if visible
	if test_mode:
		var temp_label = piece_a.get_piece_label().text
		piece_a.get_piece_label().text = piece_b.get_piece_label().text
		piece_b.get_piece_label().text = temp_label

	update_borders()
	check_win()


## Called after every swap to see if the puzzle is solved.
func check_win() -> void:
	for i in range(grid_indices.size()):
		if grid_indices[i] != i:
			return

	# All pieces match — puzzle complete
	var game_manager = get_parent()
	if game_manager != null and game_manager.has_method(&"on_puzzle_complete"):
		game_manager.on_puzzle_complete()
