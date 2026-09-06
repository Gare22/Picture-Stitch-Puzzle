class_name MockAdProvider
extends AdProvider

## Dev-only: simulates a rewarded ad on any platform so the wheel flow can be
## tested without a real ad network. Emits exactly one outcome per call.

func is_supported() -> bool:
	return true


func show_rewarded() -> void:
	await get_tree().create_timer(1.5).timeout
	rewarded_earned.emit()