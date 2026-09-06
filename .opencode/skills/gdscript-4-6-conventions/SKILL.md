---
name: gdscript-4-6-conventions
description: Godot 4.6 GDScript syntax — typed variables, signal connections, exports, autoloads. Load before writing or reviewing any GDScript, to avoid 3.x patterns.
---

## Signals

3.x (never write): `button.connect("pressed", self, "_on_button_pressed")`
4.6: `button.pressed.connect(_on_button_pressed)`

## Async waits

3.x: `yield(get_tree().create_timer(1.0), "timeout")`
4.6: `await get_tree().create_timer(1.0).timeout`

## Exports and onready

```gdscript
@export var speed: float = 200.0
@onready var sprite: Sprite2D = $Sprite
```

## Typed function signatures (project convention)

```gdscript
func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        die()
```

## Autoload access

Reference by registered name directly, no `get_node()` needed: `GameState.add_score(10)`

If unsure whether a method or signal exists in 4.6, query the `godot-docs` MCP tool before using it.
