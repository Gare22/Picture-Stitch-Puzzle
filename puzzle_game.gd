extends Node

## Orchestrates the puzzle game: timer, board setup, win detection, and menu navigation.

@onready var timer_label: Label = $TimerLabel
@onready var restart_button: Button = $MarginContainer/HBoxContainer/RestartButton
@onready var back_button: Button = $MarginContainer/HBoxContainer/BackButton
@onready var back_dialog: ConfirmationDialog = $BackConfirmDialog
@onready var restart_dialog: ConfirmationDialog = $RestartConfirmDialog
@onready var currency_hud: PanelContainer = $MarginContainer/HBoxContainer/CurrencyHUD
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


## Loads a texture from a path, handling both res:// (imported) and user:// (runtime) paths.
## Uses ResourceLoader for res:// paths because FileAccess.file_exists() fails
## on exported builds (imported resources are remapped to .ctex and the raw
## source file is not present).
func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path) as Texture2D
	# user:// or absolute path — use Image API for runtime-downloaded images
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty() or img.get_width() == 0:
		return null
	# Generate mipmaps so downscaled rendering (album covers, puzzle pieces)
	# looks as smooth as imported res:// textures, which get mipmaps from the
	# import pipeline automatically.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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

	var image = _load_texture(level["path"])
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
	# The win/claim popup must never be wider than the puzzle image itself.
	win_panel.set_width_cap(board.custom_minimum_size.x)
	# Re-fit the board when the window/viewport resizes (web fullscreen toggles,
	# desktop window drags) so pieces keep filling the available area.
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Advance test grid size for next puzzle
	if test_grid_cycle:
		_test_cols += 1
		if _test_cols > 6:
			_test_cols = 3
			_test_rows += 1
			if _test_rows > 6:
				_test_rows = 3

	restart_button.pressed.connect(_on_restart_button_pressed)
	restart_dialog.get_ok_button().text = "Restart puzzle"
	restart_dialog.get_cancel_button().text = "Keep working on it"
	restart_dialog.confirmed.connect(_on_restart_pressed)

	back_button.pressed.connect(_on_back_pressed)
	back_dialog.get_ok_button().text = "Go back to menu"
	back_dialog.get_cancel_button().text = "Continue puzzle"
	back_dialog.confirmed.connect(_on_back_to_album)


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.disconnect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	var board: Node = $GameLayout/BoardCenter/PuzzleBoard
	if board != null and board.has_method("refit"):
		board.refit()
		# Keep the win/claim popup sized to the (possibly re-fitted) puzzle.
		win_panel.set_width_cap(board.custom_minimum_size.x)


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


func _on_restart_button_pressed() -> void:
	restart_dialog.popup_centered()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Called by PuzzleBoard when all pieces are in their correct positions.
func on_puzzle_complete() -> void:
	is_complete = true
	var diff_idx := LevelManager.grid_size_to_difficulty_index(LevelManager.current_grid_size)
	LevelManager.mark_star_earned(LevelManager.current_album_index, LevelManager.current_index, diff_idx)
	var coins_earned := LevelManager.reward_for_difficulty(diff_idx)

	# Show the currency HUD
	currency_hud.visible = true

	# Configure and show the win panel (VBox layout handles the shift automatically)
	var is_max := LevelManager.current_grid_size >= 6
	win_panel.setup(coins_earned, is_max)
	win_panel.set_reward_wheel($RewardWheel)
	win_panel.visible = true
	win_panel.next_difficulty_pressed.connect(_on_next_difficulty)
	win_panel.play_again_pressed.connect(_on_restart_pressed)
	win_panel.back_to_album_pressed.connect(_on_back_to_album)
	win_panel.coins_claimed.connect(_on_coins_claimed)


func _on_next_difficulty() -> void:
	# Advance to the next difficulty level
	LevelManager.current_grid_size = mini(LevelManager.current_grid_size + 1, 6)
	get_tree().reload_current_scene()


func _on_back_pressed() -> void:
	back_dialog.popup_centered()


func _on_back_to_album() -> void:
	get_tree().change_scene_to_file("res://album_select.tscn")


func _on_coins_claimed(amount: int) -> void:
	LevelManager.add_currency(amount)
