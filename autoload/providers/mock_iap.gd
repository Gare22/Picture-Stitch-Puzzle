class_name MockIapProvider
extends IapProvider

## Dev-only provider that simulates the full purchase flow on any platform, so
## the UI and the entitlement logic can be tested without a real store.

const TEST_PRICE: String = "$1.99 (test)"

var _price: String = ""


func _ready() -> void:
	_simulate_product_load()


func is_supported() -> bool:
	return true


func get_price() -> String:
	return _price


func purchase() -> void:
	_simulate_purchase()


func restore_purchases() -> void:
	_simulate_restore()


func _simulate_product_load() -> void:
	await get_tree().create_timer(0.8).timeout
	_price = TEST_PRICE
	price_loaded.emit(_price)


func _simulate_purchase() -> void:
	await get_tree().create_timer(1.0).timeout
	LevelManager.unlock_all_albums()
	purchase_completed.emit()


func _simulate_restore() -> void:
	await get_tree().create_timer(0.6).timeout
	restore_finished.emit(
		RestoreResult.RESTORED if LevelManager.all_puzzles_unlocked else RestoreResult.NOT_FOUND
	)
