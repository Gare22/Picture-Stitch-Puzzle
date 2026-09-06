extends Control

## Wheel-of-fortune reward overlay. Spins a pre-drawn wheel texture and reports
## the final coin total via reward_ready when the player presses Collect.
##
## The wheel texture must have ONE segment per entry in `rewards`, with segment
## 0 centered at the TOP (12 o'clock) and segments going clockwise. Duplicate
## values in `rewards` create duplicate segments (increasing that value's odds).

signal reward_ready(final_coins: int)

## Multipliers shown on the wheel. One segment per entry; each entry has equal
## probability (duplicates add extra segments). Keep the entry count in sync
## with the wheel texture's segment count.
@export var rewards: Array[float] = [2.0, 3.0, 4.0, 10.0]

@onready var wheel_texture: TextureRect = $WheelHolder/WheelTexture
@onready var result_label: Label = $ResultLabel
@onready var collect_button: Button = $CollectButton

var _session_rng := RandomNumberGenerator.new()
var _base_coins: int = 0
var _final_coins: int = 0
var _last_multiplier: float = 1.0
var _spinning: bool = false


func _ready() -> void:
	_session_rng.randomize()
	hide()
	result_label.visible = false
	collect_button.visible = false
	collect_button.pressed.connect(_on_collect_pressed)
	# Rotate around the wheel's center, not its top-left corner.
	_update_wheel_pivot()
	wheel_texture.resized.connect(_update_wheel_pivot)


## Keeps the rotation pivot at the wheel's center so it spins around its own
## axis instead of the texture's top-left corner.
func _update_wheel_pivot() -> void:
	wheel_texture.pivot_offset = wheel_texture.size / 2.0


func spin(base_coins: int) -> void:
	if _spinning:
		return
	if rewards.is_empty():
		push_error("RewardWheel: rewards list is empty — add multipliers in the inspector")
		return
	_spinning = true
	_base_coins = base_coins
	_update_wheel_pivot()
	wheel_texture.rotation = 0.0
	result_label.visible = false
	collect_button.visible = false
	show()

	var idx := _session_rng.randi_range(0, rewards.size() - 1)
	_last_multiplier = rewards[idx]
	_final_coins = int(round(float(_base_coins) * _last_multiplier))

	var seg := TAU / rewards.size()
	var turns := _session_rng.randi_range(3, 6)
	# Segment 0 is centered at the top; rotate clockwise so segment idx lands
	# under the fixed top pointer, plus random full turns.
	var target := fposmod(-idx * seg, TAU) + turns * TAU

	var tween := create_tween()
	tween.tween_property(wheel_texture, "rotation", target, 2.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_spin_complete)


func _on_spin_complete() -> void:
	_spinning = false
	result_label.text = "You won %s!\n+%d coins" % [_mult_text(_last_multiplier), _final_coins]
	result_label.visible = true
	collect_button.visible = true


func _on_collect_pressed() -> void:
	hide()
	reward_ready.emit(_final_coins)


func _mult_text(mult: float) -> String:
	if mult == floor(mult):
		return "%dx" % int(mult)
	return "%.1fx" % mult
