---
name: godot-scene-architecture
description: Worked examples of the runtime-node-soup anti-pattern vs. the scene-based fix for Rule 1. Load before writing any code that creates nodes at runtime.
---

## The anti-pattern (never write this)

```gdscript
func spawn_enemy(pos: Vector2) -> void:
    var enemy = CharacterBody2D.new()
    var sprite = Sprite2D.new()
    var collision = CollisionShape2D.new()
    enemy.add_child(sprite)
    enemy.add_child(collision)
    add_child(enemy)
    enemy.global_position = pos
```

## The fix

1. Build the enemy as a scene once in the editor: `enemy.tscn`.
2. Instantiate it at runtime:

```gdscript
const EnemyScene := preload("res://entities/enemy.tscn")

func spawn_enemy(pos: Vector2) -> void:
    var enemy := EnemyScene.instantiate()
    add_child(enemy)
    enemy.global_position = pos
```

## What's still allowed

A single node with no children, as long as it's an instanced scene:

```gdscript
const BulletScene := preload("res://entities/bullet.tscn")

func fire() -> void:
    add_child(BulletScene.instantiate())
```

## Rule of thumb

If you're about to write a second `add_child()` for the same feature, stop and make a `.tscn` first.
