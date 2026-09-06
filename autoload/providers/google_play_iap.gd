class_name GooglePlayIapProvider
extends IapProvider

## Google Play Billing implementation (GodotGooglePlayBilling plugin v3.3.0).
## Only meaningful in Android builds distributed through Google Play; the
## BillingClient child no-ops gracefully elsewhere.

## Product ID configured in the Google Play Console. Must match EXACTLY.
const PRODUCT_ID: String = "unlock_all_puzzles"

## How many times a lost billing connection is re-established before giving up
## and emitting became_unavailable.
const MAX_RECONNECT_ATTEMPTS: int = 3

var _price: String = ""
var _unavailable: bool = false
var _reconnect_attempts: int = 0
var _restore_in_progress: bool = false

@onready var billing_client: BillingClient = $BillingClient


func _ready() -> void:
	if not is_supported():
		print("GooglePlayIapProvider: Play Billing not supported on this platform — IAP disabled.")
		_unavailable = true
		became_unavailable.emit()
		return
	billing_client.connected.connect(_on_billing_connected)
	billing_client.disconnected.connect(_on_billing_disconnected)
	billing_client.connect_error.connect(_on_billing_connect_error)
	billing_client.query_product_details_response.connect(_on_product_details_response)
	billing_client.query_purchases_response.connect(_on_purchases_response)
	billing_client.on_purchase_updated.connect(_on_purchase_updated)
	billing_client.acknowledge_purchase_response.connect(_on_acknowledge_response)
	billing_client.start_connection()


func is_supported() -> bool:
	return OS.get_name() == "Android"


func is_unavailable() -> bool:
	return _unavailable


func get_price() -> String:
	return _price


## Launches the Google Play purchase flow for the unlock-all product.
func purchase() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	if _unavailable or not billing_client.is_ready():
		purchase_failed.emit("Billing is not connected yet")
		return
	if _price.is_empty():
		# The product query returned nothing (no matching product in the Play
		# Console) or never arrived — surface that instead of the raw library
		# "productId not found" error.
		purchase_failed.emit("Product details unavailable — check the product ID in the Google Play Console")
		return
	var result: Dictionary = billing_client.purchase(PRODUCT_ID)
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		var reason: String = str(result.get("debug_message", ""))
		printerr("GooglePlayIapProvider: purchase flow failed: ", reason)
		purchase_failed.emit(reason)


## Re-checks the player's purchases against Google Play and re-grants any
## owned entitlements. Outcome arrives on restore_finished.
func restore_purchases() -> void:
	if _unavailable or not billing_client.is_ready():
		restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	_restore_in_progress = true
	billing_client.query_purchases(BillingClient.ProductType.INAPP)


## ── Billing signal handlers ────────────────────────────────────────────────


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
		printerr("GooglePlayIapProvider: billing disconnected %d times — giving up." % _reconnect_attempts)
		_unavailable = true
		became_unavailable.emit()
		return
	billing_client.start_connection()


func _on_billing_connect_error(response_code: int, debug_message: String) -> void:
	printerr("GooglePlayIapProvider: billing connect failed (%d): %s" % [response_code, debug_message])
	_unavailable = true
	became_unavailable.emit()


func _on_product_details_response(response: Dictionary) -> void:
	if response.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		printerr("GooglePlayIapProvider: product query failed: ", response.get("debug_message", ""))
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
		printerr("GooglePlayIapProvider: purchase query failed: ", response.get("debug_message", ""))
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
		printerr("GooglePlayIapProvider: purchase update error: ", reason)
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
		printerr("GooglePlayIapProvider: acknowledge failed: ", response.get("debug_message", ""))
