extends Node

## Autoload singleton for the "Unlock All Puzzles" Google Play in-app purchase.
## Wraps the GodotGooglePlayBilling plugin (addons/GodotGooglePlayBilling).
## The billing flow is entirely Play-managed; this node only:
##   1. connects to Play Billing at startup,
##   2. fetches the product's localized price,
##   3. restores existing purchases (query_purchases),
##   4. launches the purchase flow and acknowledges the result,
##   5. grants the entitlement through LevelManager.unlock_all_albums().

## Emitted once the localized price string is known ("$2.99", "2,99 €", ...).
signal price_loaded(price: String)

## Emitted when the unlock-all entitlement becomes active (purchased or restored).
signal purchase_completed

## Emitted when the purchase flow could not be started/finished. Reason is a
## debug string, safe to log; the UI stays silent to remain non-intrusive.
signal purchase_failed(reason: String)

## Emitted when billing cannot be used on this device (connect error).
signal became_unavailable

## Result of a user-initiated restore_purchases() call.
enum RestoreResult {
	RESTORED,     # entitlement is active (already owned or re-granted)
	NOT_FOUND,    # no previous purchases found for this account
	UNAVAILABLE,  # billing not connected / query failed
}

## Emitted when a user-initiated purchase restore finishes.
signal restore_finished(result: RestoreResult)

## Product ID configured in the Google Play Console. Must match EXACTLY.
const PRODUCT_ID: String = "unlock_all_puzzles"

## Placeholder price shown by the simulated dev flow (TEST_MODE only).
const TEST_PRICE: String = "$1.99 (test)"

## How many times a lost billing connection is re-established before giving
## up and emitting became_unavailable.
const MAX_RECONNECT_ATTEMPTS: int = 3

## Simulates the whole flow on non-Android dev machines so the banner and the
## unlock path can be tested without the Play Billing plugin. MUST be set to
## false for release builds (same discipline as AdMobManager.TEST_MODE).
const TEST_MODE: bool = true

var _price: String = ""
var _unavailable: bool = false
var _reconnect_attempts: int = 0
var _restore_in_progress: bool = false

@onready var billing_client: BillingClient = $BillingClient


func _ready() -> void:
	if not is_supported():
		print("IapManager: Play Billing not supported on this platform — IAP disabled.")
		_unavailable = true
		return
	if TEST_MODE:
		_simulate_product_load()
		return
	billing_client.connected.connect(_on_billing_connected)
	billing_client.disconnected.connect(_on_billing_disconnected)
	billing_client.connect_error.connect(_on_billing_connect_error)
	billing_client.query_product_details_response.connect(_on_product_details_response)
	billing_client.query_purchases_response.connect(_on_purchases_response)
	billing_client.on_purchase_updated.connect(_on_purchase_updated)
	billing_client.acknowledge_purchase_response.connect(_on_acknowledge_response)
	billing_client.start_connection()


## True when the purchase banner should be offered on this platform.
func is_supported() -> bool:
	if TEST_MODE:
		return true
	return OS.get_name() == "Android"


## True when billing is known to be unusable on this device.
func is_unavailable() -> bool:
	return _unavailable


## Localized price string from Play, or "" until the product details arrive.
func get_price_display() -> String:
	return _price


## Launches the Google Play purchase flow for the unlock-all product.
func purchase_unlock_all() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	if TEST_MODE:
		_simulate_purchase()
		return
	if _unavailable or not billing_client.is_ready():
		purchase_failed.emit("Billing is not connected yet")
		return
	var result: Dictionary = billing_client.purchase(PRODUCT_ID)
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		var reason: String = str(result.get("debug_message", ""))
		printerr("IapManager: purchase flow failed: ", reason)
		purchase_failed.emit(reason)


## Re-checks the player's purchases against Google Play and re-grants any
## owned entitlements (the "Restore Purchases" button). Safe to call anytime;
## the outcome arrives on restore_finished.
func restore_purchases() -> void:
	if TEST_MODE:
		_simulate_restore()
		return
	if _unavailable or not billing_client.is_ready():
		restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	_restore_in_progress = true
	billing_client.query_purchases(BillingClient.ProductType.INAPP)


## DEV-ONLY: clears the local unlock-all entitlement so the purchase flow can
## be re-tested. A real Google Play purchase is untouched — the next
## query_purchases (app start or manual restore) re-grants it automatically.
func remove_all_unlock_entitlement() -> void:
	LevelManager.remove_unlock_all()


## ── Billing signal handlers (real flow, TEST_MODE = false) ─────────────────


func _on_billing_connected() -> void:
	_reconnect_attempts = 0
	# Fetch the localized price and restore any prior purchase in one go.
	billing_client.query_product_details(
		PackedStringArray([PRODUCT_ID]), BillingClient.ProductType.INAPP
	)
	billing_client.query_purchases(BillingClient.ProductType.INAPP)


func _on_billing_disconnected() -> void:
	# Retry a bounded number of times; connect_error handles the
	# permanently-unavailable case.
	if _unavailable:
		return
	_reconnect_attempts += 1
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		printerr("IapManager: billing disconnected %d times — giving up." % _reconnect_attempts)
		_unavailable = true
		became_unavailable.emit()
		return
	billing_client.start_connection()


func _on_billing_connect_error(response_code: int, debug_message: String) -> void:
	printerr("IapManager: billing connect failed (%d): %s" % [response_code, debug_message])
	_unavailable = true
	became_unavailable.emit()


func _on_product_details_response(response: Dictionary) -> void:
	if response.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		printerr("IapManager: product query failed: ", response.get("debug_message", ""))
		return
	for details: Dictionary in response.get("product_details", []):
		if details.get("product_id", "") != PRODUCT_ID:
			continue
		var offers: Array = details.get("one_time_purchase_offer_details_list", [])
		if offers.size() > 0:
			var offer: Dictionary = offers[0]
			var price: String = str(offer.get("formatted_price", ""))
			if not price.is_empty() and _price != price:
				_price = price
				price_loaded.emit(_price)
		break


func _on_purchases_response(response: Dictionary) -> void:
	if response.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		printerr("IapManager: purchase query failed: ", response.get("debug_message", ""))
		if _restore_in_progress:
			_restore_in_progress = false
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	_process_purchases(response.get("purchases", []))
	if _restore_in_progress:
		_restore_in_progress = false
		restore_finished.emit(
			RestoreResult.RESTORED if LevelManager.all_puzzles_unlocked else RestoreResult.NOT_FOUND
		)


func _on_purchase_updated(response: Dictionary) -> void:
	if response.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		var reason: String = str(response.get("debug_message", ""))
		printerr("IapManager: purchase update error: ", reason)
		purchase_failed.emit(reason)
		return
	_process_purchases(response.get("purchases", []))


## Grants the entitlement for every completed unlock-all purchase and
## acknowledges it (required by Google — unacknowledged purchases are refunded).
## Called for both startup restores and live purchase updates.
func _process_purchases(purchases: Array) -> void:
	for purchase: Dictionary in purchases:
		if not (PRODUCT_ID in purchase.get("product_ids", [])):
			continue
		# PENDING payments must wait until Google marks them PURCHASED.
		if int(purchase.get("purchase_state", -1)) != BillingClient.PurchaseState.PURCHASED:
			continue
		LevelManager.unlock_all_albums()
		if not purchase.get("is_acknowledged", false):
			billing_client.acknowledge_purchase(str(purchase.get("purchase_token", "")))
		purchase_completed.emit()


func _on_acknowledge_response(response: Dictionary) -> void:
	if response.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		# Not fatal: the entitlement is already granted locally, and the next
		# launch's query_purchases finds the purchase again to re-acknowledge.
		printerr("IapManager: acknowledge failed: ", response.get("debug_message", ""))


## ── TEST_MODE simulation (dev machines without the billing plugin) ─────────


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
