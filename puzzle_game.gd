extends Node

## Orchestrates the puzzle game: timer, board setup, win detection, and menu navigation.

@onready var timer_label: Label = $TimerLabel
@onready var menu_button: Button = $MenuButton
@onready var restart_button: Button = $RestartButton
@onready var win_message: Label = $WinMessage
@onready var win_button: Button = $WinButton

var elapsed_time: float = 0.0
var is_complete: bool = false

## Default puzzle dimensions.
const DEFAULT_COLUMNS: int = 4
const DEFAULT_ROWS: int = 4
const SOURCE_IMAGE_PATH: String = "res://assets/puzzle_image.png"


func _ready() -> void:
	var image = load(SOURCE_IMAGE_PATH) as Texture2D
	if image == null:
		push_error("Picture Puzzle: Could not load source image at ", SOURCE_IMAGE_PATH)
		return

	# Locate the PuzzleBoard — it's a direct child
	var board = $PuzzleBoard
	if board == null:
		push_error("Picture Puzzle: PuzzleBoard node not found")
		return

	# Set to true to show numbered labels on each piece (for debugging)
	board.test_mode = false
	board.setup(image, DEFAULT_COLUMNS, DEFAULT_ROWS)

	menu_button.pressed.connect(_on_menu_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	win_button.pressed.connect(_on_menu_pressed)

	win_message.visible = false
	win_button.visible = false


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


func _on_menu_pressed() -> void:
	get_tree().reload_current_scene()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Called by PuzzleBoard when all pieces are in their correct positions.
func on_puzzle_complete() -> void:
	is_complete = true
	win_message.visible = true
	win_button.visible = true
