extends Control

## Screen-space coin display. Stays in the top-right corner across scenes.
## Connects to LevelManager.currency_changed to auto-refresh.

@onready var coin_label: Label = $MarginContainer/HBoxContainer/CoinLabel



func _ready() -> void:
	# Snap to current value immediately.
	_refresh(LevelManager.currency)
	LevelManager.currency_changed.connect(_refresh)


func _refresh(new_amount: int) -> void:
	coin_label.text = str(new_amount)
