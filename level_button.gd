class_name LevelButton
extends Button

## A single puzzle button in the level select grid.
## Shows the puzzle image with 3 star indicators (easy/medium/hard) at the bottom.

signal level_selected(level_index: int)

## Index of the level this button represents (within the current album).
var level_index: int = -1


## Initializer: sets the puzzle image, star status, and level index.
## Sizes the button to fill target_width while preserving the image's aspect ratio.
func setup(image: Texture2D, earned: Array, index: int, target_width: float) -> void:
	level_index = index
	if image != null:
		icon = image
		expand_icon = true
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		var tex_size := image.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var fit_scale := target_width / tex_size.x
			custom_minimum_size = Vector2(target_width, tex_size.y * fit_scale)
		else:
			custom_minimum_size = Vector2(target_width, target_width)
	else:
		custom_minimum_size = Vector2(target_width, target_width)
	set_stars(earned)


## Updates the button size after a viewport resize, preserving the image's
## aspect ratio (mirrors the size math from setup(), without touching the icon).
func resize_to(target_width: float) -> void:
	var image: Texture2D = icon
	if image != null:
		var tex_size := image.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var fit_scale := target_width / tex_size.x
			custom_minimum_size = Vector2(target_width, tex_size.y * fit_scale)
			return
	custom_minimum_size = Vector2(target_width, target_width)


## Scene-default modulates for each star, captured once in _ready.
var _star_defaults: Array[Color] = []


func _ready() -> void:
	pressed.connect(_on_pressed)
	for child in $StarRow.get_children():
		_star_defaults.append(child.modulate)


## Updates the star statuses. `earned` is an Array of 3 bools (easy, medium, hard).
## Lit stars use full white modulate; unlit stars reset to their scene-defined default.
func set_stars(earned: Array) -> void:
	var stars := $StarRow.get_children()
	for s in range(stars.size()):
		var lit: bool = s < earned.size() and earned[s]
		stars[s].modulate = Color.WHITE if lit else _star_defaults[s]


func _on_pressed() -> void:
	level_selected.emit(level_index)
