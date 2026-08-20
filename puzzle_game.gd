extends Node

## Orchestrates the puzzle game: timer, board setup, win detection, and menu navigation.

@onready var timer_label: Label = $TimerLabel
@onready var restart_button: Button = $RestartButton
@onready var currency_hud: HBoxContainer = $CurrencyHUD
@onready var win_panel: Control = $GameLayout/WinPanel

var elapsed_time: float = 0.0
var is_complete: bool = false

## When true, cycles through all grid sizes 3×3→6×6 for testing.
@export var test_grid_cycle: bool = false

## Test-mode puzzle dimensions: cycles through all 3×3 to 6×6 combos.
static var _test_cols: int = 3
static var _test_rows: int = 3

var puzzle_columns: int
var puzzle_rows: int


func _ready() -> void:
	if test_grid_cycle:
		puzzle_columns = _test_cols
		puzzle_rows = _test_rows
	else:
		puzzle_columns = LevelManager.current_grid_size
		puzzle_rows = LevelManager.current_grid_size

	var level: Dictionary = LevelManager.get_current_level()
	if level.is_empty():
		push_error("Picture Puzzle: No level selected")
		return

	var image = load(level["path"]) as Texture2D
	if image == null:
		push_error("Picture Puzzle: Could not load image at ", level["path"])
		return

	# Locate the PuzzleBoard — it's inside the CenterContainer in the GameLayout VBox
	var board = $GameLayout/BoardCenter/PuzzleBoard
	if board == null:
		push_error("Picture Puzzle: PuzzleBoard node not found")
		return

	# Set to true to show numbered labels on each piece (for debugging)
	board.test_mode = false
	board.setup(image, puzzle_columns, puzzle_rows)

	# Advance test grid size for next puzzle
	if test_grid_cycle:
		_test_cols += 1
		if _test_cols > 6:
			_test_cols = 3
			_test_rows += 1
			if _test_rows > 6:
				_test_rows = 3

	restart_button.pressed.connect(_on_restart_pressed)


func _process(delta: float) -> void:
	if is_complete:
		return
	elapsed_time += delta
	timer_label.text = _format_time(elapsed_time)


## Returns a time string showing only the relevant units:
##   < 1 minute → "SS"
##   < 1 hour   → "MM:SS"
##   >= 1 hour  → "HH:MM:SS"
static func _format_time(total_seconds: float) -> String:
	var total_sec = int(total_seconds)
	var seconds = total_sec % 60
	var minutes = int(total_sec / 60.0) % 60
	var hours = int(total_sec / 3600.0)

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	elif minutes > 0:
		return "%02d:%02d" % [minutes, seconds]
	else:
		return "%02d" % [seconds]


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Called by PuzzleBoard when all pieces are in their correct positions.
func on_puzzle_complete() -> void:
	is_complete = true
	var diff_idx := LevelManager.grid_size_to_difficulty_index(LevelManager.current_grid_size)
	LevelManager.mark_star_earned(LevelManager.current_album_index, LevelManager.current_index, diff_idx)
	var coins_earned := LevelManager.earn_currency(diff_idx)

	# Show the currency HUD
	currency_hud.visible = true

	# Configure and show the win panel (VBox layout handles the shift automatically)
	var is_max := LevelManager.current_grid_size >= 6
	win_panel.setup(coins_earned, is_max)
	win_panel.visible = true
	win_panel.next_difficulty_pressed.connect(_on_next_difficulty)
	win_panel.play_again_pressed.connect(_on_restart_pressed)
	win_panel.back_to_album_pressed.connect(_on_back_to_album)
	win_panel.ad_button_pressed.connect(_on_ad_button)


func _on_next_difficulty() -> void:
	# Advance to the next difficulty level
	LevelManager.current_grid_size = mini(LevelManager.current_grid_size + 1, 6)
	get_tree().reload_current_scene()


func _on_back_to_album() -> void:
	get_tree().change_scene_to_file("res://album_select.tscn")


func _on_ad_button() -> void:
	# Placeholder for ad integration — doubles the coins earned this completion.
	var diff_idx := LevelManager.grid_size_to_difficulty_index(LevelManager.current_grid_size)
	LevelManager.earn_currency(diff_idx)
