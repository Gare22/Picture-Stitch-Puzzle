extends Node

## Central registry of all available puzzle images.
## Drag textures into level_images in the inspector.

## Puzzle images — drag textures here in the editor.
@export var level_images: Array[Texture2D] = []

## Built at runtime from the exported array.
var levels: Array[Dictionary] = []

## Index of the currently-selected level (set by LevelSelect).
var current_index: int = 0


func _ready() -> void:
	_build_levels()


## Converts the exported array into a levels array with auto-numbered names.
func _build_levels() -> void:
	levels.clear()
	for i in range(level_images.size()):
		var tex: Texture2D = level_images[i]
		levels.append({
			"name": "Level %d" % (i + 1),
			"path": tex.resource_path,
		})
	print("LevelManager: built %d levels" % levels.size())


## Returns the Dictionary for the current level.
func get_current_level() -> Dictionary:
	if levels.is_empty():
		return {}
	return levels[current_index]


## Returns the total number of levels.
func get_level_count() -> int:
	return levels.size()


## Advance to the next level (wraps around). Returns true if wrapped.
func advance_level() -> bool:
	var wrapped := false
	current_index += 1
	if current_index >= levels.size():
		current_index = 0
		wrapped = true
	return wrapped


## Jump to a specific level index.
func set_level(index: int) -> void:
	current_index = clampi(index, 0, levels.size() - 1)
