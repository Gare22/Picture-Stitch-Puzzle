extends Control

## Bottom panel shown on puzzle completion. Offers next-difficulty / replay / back-to-album.

signal next_difficulty_pressed
signal play_again_pressed
signal back_to_album_pressed
signal coins_claimed(coins: int)

@onready var reward_phase: VBoxContainer = $Panel/VBox/RewardPhase
@onready var nav_phase: VBoxContainer = $Panel/VBox/NavPhase
@onready var coin_label: Label = $Panel/VBox/RewardPhase/RewardRow/CoinLabel
@onready var ad_button: Button = $Panel/VBox/RewardPhase/RewardRow/AdButton
@onready var claim_button: Button = $Panel/VBox/RewardPhase/ClaimButton
@onready var next_button: Button = $Panel/VBox/NavPhase/NextButton
@onready var back_button: Button = $Panel/VBox/NavPhase/BackButton

var _coins_earned: int = 0


func setup(coins_earned: int, is_max_difficulty: bool) -> void:
	_coins_earned = coins_earned
	coin_label.text = "You earned %d coins" % _coins_earned

	if is_max_difficulty:
		next_button.text = "Play Again?"
	else:
		next_button.text = "Next Difficulty?"

	# Reset ad button state
	ad_button.disabled = false
	ad_button.text = "2x?"

	# Show reward phase, hide nav phase until claimed
	reward_phase.visible = true
	nav_phase.visible = false

	# Wire signals
	ad_button.pressed.connect(_on_ad_pressed)
	claim_button.pressed.connect(_on_claim_pressed)
	next_button.pressed.connect(_on_next_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_ad_pressed() -> void:
	ad_button.disabled = true
	ad_button.text = "Loading ad..."

	await get_tree().create_timer(1.5).timeout
	ad_button.text = "Playing ad..."

	await get_tree().create_timer(2.0).timeout
	_coins_earned *= 2
	coin_label.text = "You earned %d coins" % _coins_earned
	ad_button.text = "Claimed"


func _on_claim_pressed() -> void:
	coins_claimed.emit(_coins_earned)
	reward_phase.visible = false
	nav_phase.visible = true


func _on_next_pressed() -> void:
	if next_button.text == "Play Again?":
		play_again_pressed.emit()
	else:
		next_difficulty_pressed.emit()


func _on_back_pressed() -> void:
	back_to_album_pressed.emit()
