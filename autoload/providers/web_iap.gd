class_name WebIapProvider
extends IapProvider

## Web implementation using a hosted checkout / payment link — no Google account
## required. Configure in Project Settings:
##   iap/web_checkout_url  — hosted checkout (Stripe Payment Link, LemonSqueezy,
##                           Gumroad, ...) opened in a new tab on purchase
##   iap/web_price_label   — display price for the banner, e.g. "$4.99"
##
## Flow: purchase() opens the checkout tab and emits payment_flow_started; the
## UI prompts the player to confirm once the payment is done, then
## confirm_payment() grants the entitlement. There is no server-side
## verification in this build — for production, point the checkout at a backend
## that verifies the payment via webhook before confirming.

var _price: String = ""


func _ready() -> void:
	var price: String = str(ProjectSettings.get_setting("iap/web_price_label", ""))
	if price.is_empty():
		print("WebIapProvider: iap/web_price_label is empty — banner will show no price.")
		return
	_price = price
	price_loaded.emit(_price)


func is_supported() -> bool:
	return true


func is_unavailable() -> bool:
	return false


func get_price() -> String:
	return _price


## Opens the hosted checkout in a new tab. The player returns to the game tab
## and confirms via confirm_payment() (prompted by payment_flow_started).
func purchase() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	var url: String = str(ProjectSettings.get_setting("iap/web_checkout_url", ""))
	if url.is_empty():
		purchase_failed.emit("iap/web_checkout_url is not configured")
		return
	OS.shell_open(url)
	payment_flow_started.emit()


## Grants the entitlement after the player completes the hosted checkout.
func confirm_payment() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	LevelManager.unlock_all_albums()
	purchase_completed.emit()


## No server to re-verify against: the entitlement is local-only, so a restore
## simply reports the current local state.
func restore_purchases() -> void:
	restore_finished.emit(
		RestoreResult.RESTORED if LevelManager.all_puzzles_unlocked else RestoreResult.NOT_FOUND
	)