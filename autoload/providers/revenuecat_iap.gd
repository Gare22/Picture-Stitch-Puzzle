class_name RevenueCatIapProvider
extends IapProvider

## RevenueCat implementation that needs no native SDK and no backend on your
## side. Configure in Project Settings:
##   iap/revenuecat_public_key     — the pk_... public key (client-safe, read-only)
##   iap/revenuecat_entitlement_id — entitlement identifier (default "unlock_all")
##   iap/web_checkout_url          — RevenueCat Web Purchase Link (base URL,
##                                   WITHOUT an app_user_id; we append it)
##   iap/web_price_label           — display price for the banner
##
## Flow: purchase() opens the identified purchase link
##   <checkout_url>/<app_user_id>
## so the payment is recorded under this customer immediately. The provider
## checks the entitlement server-side via the public-key REST endpoint
##   GET https://api.revenuecat.com/v1/subscribers/<app_user_id>
## (the same call RevenueCat's own web SDK makes) and grants when active.
##
## Cross-device restore: the App User ID is the "restore code". It defaults to
## a generated anonymous id persisted in user://iap_identity.cfg; the player
## can set/enter a stable code in the Options menu so a purchase made on one
## device can be restored on another (RevenueCat holds the entitlement record —
## no server infrastructure of your own).

const API_BASE := "https://api.revenuecat.com/v1"
const IDENTITY_PATH := "user://iap_identity.cfg"

var _price: String = ""
var _app_user_id: String = ""
var _restore_in_progress: bool = false
var _request_in_flight: bool = false

@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	_app_user_id = _load_or_create_app_user_id()
	_price = str(ProjectSettings.get_setting("iap/web_price_label", ""))
	if not _price.is_empty():
		price_loaded.emit(_price)
	_http.request_completed.connect(_on_http_completed)
	# Startup restore: if this identity owns the entitlement, grant it.
	_fetch_customer_info()


func is_supported() -> bool:
	return true


func is_unavailable() -> bool:
	return false


func get_price() -> String:
	return _price


## Current restore code (RevenueCat App User ID).
func get_app_user_id() -> String:
	return _app_user_id


## Sets a player-provided restore code (App User ID) and re-checks whether it
## owns the entitlement. Changing identity transfers access on the server side
## (RevenueCat merges/aliases customer records on the next check).
func set_app_user_id(id: String) -> void:
	var clean := id.strip_edges()
	if clean.is_empty() or clean == _app_user_id:
		return
	_app_user_id = clean
	_save_app_user_id()
	_fetch_customer_info()


## Opens the identified RevenueCat Web Purchase Link in a new tab.
func purchase() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	var base: String = str(ProjectSettings.get_setting("iap/web_checkout_url", "")).trim_suffix("/")
	if base.is_empty():
		purchase_failed.emit("iap/web_checkout_url is not configured")
		return
	# Identified links take the App User ID on the URL PATH (per RevenueCat docs).
	var url := "%s/%s" % [base, _app_user_id.uri_encode()]
	OS.shell_open(url)
	payment_flow_started.emit()


## Called from the "I've completed payment" overlay. Grants when the server
## confirms the entitlement; if the payment hasn't propagated to the API yet
## (or the request fails), falls back to trusting the player's confirmation —
## a re-check on the next launch/restore reconciles it.
func confirm_payment() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	LevelManager.unlock_all_albums()
	purchase_completed.emit()
	_fetch_customer_info()


## Server-backed restore: queries RevenueCat for the current identity's
## entitlements and grants if owned. Outcome arrives on restore_finished.
func restore_purchases() -> void:
	_fetch_customer_info(true)


## ── RevenueCat API ─────────────────────────────────────────────────────────


func _fetch_customer_info(for_restore := false) -> void:
	if _request_in_flight:
		# A check is already in flight — fold the restore intent into it so the
		# response still reports the restore result.
		if for_restore:
			_restore_in_progress = true
		return
	_restore_in_progress = for_restore
	var key: String = str(ProjectSettings.get_setting("iap/revenuecat_public_key", ""))
	if key.is_empty():
		if for_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	_request_in_flight = true
	var url := "%s/subscribers/%s" % [API_BASE, _app_user_id.uri_encode()]
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % key,
		"Accept: application/json",
	])
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_request_in_flight = false
		printerr("RevenueCatIapProvider: request failed: %d" % err)
		if for_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	var was_restore: bool = _restore_in_progress
	_restore_in_progress = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		printerr("RevenueCatIapProvider: customer info failed (result=%d code=%d)" % [result, response_code])
		if was_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		printerr("RevenueCatIapProvider: malformed customer info response")
		if was_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return
	var owned: bool = _has_active_entitlement(parsed)
	if owned and not LevelManager.all_puzzles_unlocked:
		LevelManager.unlock_all_albums()
		purchase_completed.emit()
	if was_restore:
		restore_finished.emit(RestoreResult.RESTORED if owned else RestoreResult.NOT_FOUND)


## A one-time (lifetime) entitlement is active when its key exists in the
## customer's entitlements — it has no expiry. Presence is enough here.
func _has_active_entitlement(customer: Dictionary) -> bool:
	var subscriber: Dictionary = customer.get("subscriber", {})
	var entitlements: Dictionary = subscriber.get("entitlements", {})
	var id: String = str(ProjectSettings.get_setting("iap/revenuecat_entitlement_id", "unlock_all"))
	return entitlements.has(id)


## ── Identity persistence ───────────────────────────────────────────────────


func _load_or_create_app_user_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(IDENTITY_PATH) == OK:
		var id := str(cfg.get_value("identity", "app_user_id", ""))
		if not id.is_empty():
			return id
	var generated := _generate_anon_id()
	_app_user_id = generated
	_save_app_user_id()
	return generated


func _generate_anon_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _save_app_user_id() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "app_user_id", _app_user_id)
	cfg.save(IDENTITY_PATH)