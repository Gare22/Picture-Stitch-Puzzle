class_name DifficultyMenu
extends Control

## The difficulty selection overlay shown when a level is tapped.
## Emits difficulty_selected(grid_size) when a difficulty is chosen, and back_pressed to close.

signal difficulty_selected(grid_size: int)
signal back_pressed

@onready var easy_button: Button = $ContentVBox/Panel/VBox/EasyButton
@onready var medium_button: Button = $ContentVBox/Panel/VBox/MediumButton
@onready var hard_button: Button = $ContentVBox/Panel/VBox/HardButton
@onready var back_button: Button = $ContentVBox/Panel/VBox/BackButton
@onready var easy_star: TextureRect = $ContentVBox/Panel/VBox/EasyButton/Star
@onready var medium_star: TextureRect = $ContentVBox/Panel/VBox/MediumButton/Star
@onready var hard_star: TextureRect = $ContentVBox/Panel/VBox/HardButton/Star
@onready var puzzle_texture: TextureRect = $ContentVBox/PanelContainer/PuzzleTexture

## Scene-default modulates for each star, captured once in _ready.
var _star_defaults: Array[Color] = []


func _ready() -> void:
	easy_button.pressed.connect(func() -> void: difficulty_selected.emit(4))
	medium_button.pressed.connect(func() -> void: difficulty_selected.emit(5))
	hard_button.pressed.connect(func() -> void: difficulty_selected.emit(6))
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	_star_defaults = [easy_star.modulate, medium_star.modulate, hard_star.modulate]


## Initializer: passes the puzzle image (shown as a preview) and the star statuses.
func setup(image: Texture2D, earned: Array) -> void:
	puzzle_texture.texture = image
	set_stars(earned)


## Updates the star statuses next to each difficulty. `earned` is an Array of 3 bools (easy, medium, hard).
## Lit stars use full white modulate; unlit stars keep their scene-defined dim default.
func set_stars(earned: Array) -> void:
	var stars: Array[TextureRect] = [easy_star, medium_star, hard_star]
	for s in range(stars.size()):
		var lit: bool = s < earned.size() and earned[s]
		stars[s].modulate = Color.WHITE if lit else _star_defaults[s]
