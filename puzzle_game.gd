extends Node

## Orchestrates the puzzle game: timer, board setup, win detection, and menu navigation.

@onready var timer_label: Label = $TimerLabel
@onready var menu_button: Button = $MenuButton
@onready var restart_button: Button = $RestartButton
@onready var win_message: Label = $WinMessage
@onready var win_button: Button = $WinButton
@onready var level_select_button: Button = $LevelSelectButton

var elapsed_time: float = 0.0
var is_complete: bool = false

## Default puzzle dimensions.
const DEFAULT_COLUMNS: int = 4
const DEFAULT_ROWS: int = 4

## The "New Puzzle" button on the win overlay — reused as "Next Puzzle".
@onready var next_button: Button = $WinButton


func _ready() -> void:
	var level: Dictionary = LevelManager.get_current_level()
	if level.is_empty():
		push_error("Picture Puzzle: No level selected")
		return

	var image = load(level["path"]) as Texture2D
	if image == null:
		push_error("Picture Puzzle: Could not load image at ", level["path"])
		return

	# Update the title / win message to show which puzzle this is
	win_message.text = "Complete!  (%s)" % level["name"]

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
	win_button.pressed.connect(_on_next_pressed)
	level_select_button.pressed.connect(_on_level_select_pressed)

	win_message.visible = false
	win_button.visible = false
	level_select_button.visible = false


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
	get_tree().change_scene_to_file("res://level_select.tscn")


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Advance to the next puzzle image.
func _on_next_pressed() -> void:
	LevelManager.advance_level()
	get_tree().reload_current_scene()


## Return to the level selection screen.
func _on_level_select_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")


## Called by PuzzleBoard when all pieces are in their correct positions.
func on_puzzle_complete() -> void:
	is_complete = true
	win_message.visible = true
	win_button.visible = true
	level_select_button.visible = true
