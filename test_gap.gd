extends Node

## Test scene for debugging 1-pixel gaps between puzzle pieces.
## Hardcoded to Level 2 (gradient_fire.png) with a 3×4 grid.

@onready var board: GridContainer = $PuzzleBoard
@onready var debug_label: Label = $DebugLabel

const TEST_IMAGE_PATH: String = "res://assets/gradient_fire.png"
const TEST_COLUMNS: int = 4
const TEST_ROWS: int = 3


func _ready() -> void:
	# Bright background so any gap is immediately visible
	RenderingServer.set_default_clear_color(Color.MAGENTA)

	var image: Texture2D = load(TEST_IMAGE_PATH) as Texture2D
	if image == null:
		push_error("TestGap: Could not load image")
		return

	board.test_mode = true
	board.setup(image, TEST_COLUMNS, TEST_ROWS)

	# Wait one frame so GridContainer computes layout
	await get_tree().process_frame

	# Now read actual positions after layout
	var pieces: Array = board.get_pieces()
	print("=== After layout ===")
	print("Board pos=(%.2f, %.2f) size=(%.2f, %.2f)" % [
		board.position.x, board.position.y,
		board.size.x, board.size.y,
	])

	var prev_right: float = -1.0
	for i in range(pieces.size()):
		var p: PuzzlePiece = pieces[i] as PuzzlePiece
		var col: int = i % board.columns_count
		var row: int = i / board.columns_count

		# Compute gaps from previous piece in same row
		var h_gap: float = 0.0
		if col > 0:
			h_gap = p.global_position.x - prev_right
		prev_right = p.global_position.x + p.size.x

		print("  [%2d] r%d c%d  pos=(%7.2f, %7.2f)  size=(%5.2f, %5.2f)  h_gap=%.4f  borders=[T:%s B:%s L:%s R:%s] correct=%d" % [
			i, row, col,
			p.global_position.x, p.global_position.y,
			p.size.x, p.size.y,
			h_gap,
			p.draw_top, p.draw_bottom, p.draw_left, p.draw_right,
			board.get_correct_index(i),
		])

		# Reset prev_right at row start
		if col == board.columns_count - 1:
			prev_right = -1.0

	# Update label
	var info: String = "Board: %dx%d at (%.0f,%.0f) | Cell: %.0fx%.0f" % [
		int(board.size.x), int(board.size.y),
		board.position.x, board.position.y,
		board.cell_display_w, board.cell_display_h,
	]
	debug_label.text = info
