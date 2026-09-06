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
## Identity comes from the IdentityManager autoload: when the player is signed
## in (itch.io OAuth), the RevenueCat App User ID is the namespaced account id
## ("itch:12345") so purchases follow the account on any device. When not signed
## in, an anonymous per-install id is used — the purchase is then tied to the
## device and cannot be recovered elsewhere (the UI warns about this).
##
## Flow: purchase() opens the identified purchase link
##   <checkout_url>/<app_user_id>
## and the provider checks entitlements server-side via
##   GET https://api.revenuecat.com/v1/subscribers/<app_user_id>
## (the same call RevenueCat's own web SDK makes). Signing in on a device that
## previously purchased anonymously migrates that purchase onto the account via
##   POST /v1/subscribers/identify
##
## Sandbox: test purchases made through a sandbox checkout
## (https://pay.rev.cat/sandbox/...) are only returned by the API when the
## request carries X-Is-Sandbox: true — sending false makes every restore come
## back empty. The sandbox flag is derived from BOTH the key prefix (rcb_sb_)
## and the checkout URL, so a production-key + sandbox-checkout test setup
## still restores correctly.

const API_BASE := "https://api.revenuecat.com/v1"
const IDENTITY_PATH := "user://iap_identity.cfg"

var _price: String = ""
var _app_user_id: String = ""
var _restore_in_progress: bool = false
var _request_in_flight: bool = false
## Whether the customer record has been ensured server-side (the first GET
## creates it). Used so the identified checkout link never hits an unknown
## customer (which RevenueCat answers with 404).
var _initial_check_done: bool = false

## Anonymous install identity (always persisted; used when not signed in).
var _anon_id: String = ""

## True when the anonymous id owns the entitlement — only then is a sign-in
## worth migrating (identify would otherwise POST a customer with no record).
var _anon_owned: bool = false

## Set when a sign-in lands while the boot-time anonymous check is still in
## flight: the migration decision is made when that response arrives.
var _migration_pending: bool = false

## The app_user_id the in-flight customer-info check queried (its response
## arrives after _app_user_id may have changed, e.g. mid sign-in).
var _checked_user_id: String = ""

@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	_load_identity()
	_recompute_app_user_id()
	_price = str(ProjectSettings.get_setting("iap/web_price_label", ""))
	if not _price.is_empty():
		price_loaded.emit(_price)
	_http.request_completed.connect(_on_http_completed)
	$IdentifyHttp.request_completed.connect(_on_identify_completed)
	IdentityManager.signed_in.connect(_on_identity_signed_in)
	IdentityManager.signed_out.connect(_on_identity_signed_out)
	# Startup restore: if this identity owns the entitlement, grant it.
	_fetch_customer_info()
	print("RevenueCatIapProvider: environment=%s" % ["sandbox" if _is_sandbox() else "production"])


func is_supported() -> bool:
	return true


func is_unavailable() -> bool:
	return false


func get_price() -> String:
	return _price


## Opens the identified RevenueCat Web Purchase Link in a new tab.
## Identified links take the App User ID on the URL PATH (per RevenueCat docs):
##   <checkout_url>/<app_user_id>
## Before opening, the customer record is ensured server-side (the first GET
## creates it) so the link doesn't hit an unknown-customer 404.
func purchase() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	var base: String = str(ProjectSettings.get_setting("iap/web_checkout_url", "")).trim_suffix("/")
	if base.is_empty():
		purchase_failed.emit("iap/web_checkout_url is not configured")
		return
	if str(ProjectSettings.get_setting("iap/revenuecat_public_key", "")).is_empty():
		purchase_failed.emit("iap/revenuecat_public_key is not configured")
		return
	if not _initial_check_done:
		_initial_check_done = true
		if _fetch_customer_info():
			await _http.request_completed
	var url := "%s/%s" % [base, _app_user_id.uri_encode()]
	OS.shell_open(url)
	payment_flow_started.emit()


## Called from the "I've completed payment" overlay. NEVER grants on trust —
## only a server-backed check confirms the purchase. The check runs through the
## restore path: when the purchase is found, _on_http_completed grants the
## entitlement and reports RESTORED; otherwise the UI keeps the player waiting
## and lets them retry (payments can take a few seconds to propagate).
func confirm_payment() -> void:
	if LevelManager.all_puzzles_unlocked:
		return
	_fetch_customer_info(true)


## Server-backed restore: queries RevenueCat for the current identity's
## entitlements and grants if owned. Outcome arrives on restore_finished.
func restore_purchases() -> void:
	_fetch_customer_info(true)


## ── Identity composition (IdentityManager autoload) ────────────────────────


## The RevenueCat App User ID: the account id ("itch:12345") when signed in,
## otherwise the anonymous install id. Logs changes so a run log shows exactly
## which customer the provider is querying (e.g. after an OAuth sign-in).
func _recompute_app_user_id() -> void:
	var new_id: String = IdentityManager.get_prefixed_user_id() if IdentityManager.is_signed_in() else _anon_id
	if new_id != _app_user_id:
		_app_user_id = new_id
		print("RevenueCatIapProvider: app_user_id -> %s" % _app_user_id)


func _on_identity_signed_in(_user_id: String, _user_name: String) -> void:
	var previous := _app_user_id
	_recompute_app_user_id()
	_initial_check_done = false
	if previous == _anon_id and _app_user_id != _anon_id:
		if _request_in_flight:
			# The boot-time anonymous check is still running — it decides
			# whether there is anything to migrate.
			_migration_pending = true
		elif _anon_owned:
			# First sign-in on this device with an anonymous purchase: migrate it
			# onto the account so it follows the user (RevenueCat identify
			# aliases/merges the customers).
			_identify_customer(previous, _app_user_id)
		else:
			_fetch_customer_info()
	else:
		_fetch_customer_info()


func _on_identity_signed_out() -> void:
	_recompute_app_user_id()
	_initial_check_done = false
	_fetch_customer_info()


## POST /v1/subscribers/identify — client-safe (same endpoint their web SDK
## uses with the public key). Moves purchases recorded under old_id to new_id.
func _identify_customer(old_id: String, new_id: String) -> void:
	var key: String = str(ProjectSettings.get_setting("iap/revenuecat_public_key", ""))
	if key.is_empty():
		_fetch_customer_info()
		return
	var body := JSON.stringify({"app_user_id": old_id, "new_app_user_id": new_id})
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % key,
		"Content-Type: application/json",
		"Accept: application/json",
		"X-Platform: web",
		"X-Is-Sandbox: %s" % _is_sandbox(),
	])
	$IdentifyHttp.request("%s/subscribers/identify" % API_BASE, headers, HTTPClient.METHOD_POST, body)


func _on_identify_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		printerr("RevenueCatIapProvider: identify failed (result=%d code=%d)" % [result, response_code])
	# Migration done (or failed) — now check entitlements under the account id.
	_fetch_customer_info()


## ── RevenueCat API ─────────────────────────────────────────────────────────


## Fetches the customer's entitlements from RevenueCat. Returns true when a
## request was dispatched (the caller may await its completion).
func _fetch_customer_info(for_restore := false) -> bool:
	if _request_in_flight:
		# A check is already in flight — fold the restore intent into it so the
		# response still reports the restore result.
		if for_restore:
			_restore_in_progress = true
		return true
	_restore_in_progress = for_restore
	var key: String = str(ProjectSettings.get_setting("iap/revenuecat_public_key", ""))
	if key.is_empty():
		if for_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return false
	_request_in_flight = true
	_checked_user_id = _app_user_id
	var url := "%s/subscribers/%s" % [API_BASE, _app_user_id.uri_encode()]
	# Mirror the headers RevenueCat's own web SDK sends (same base URL for
	# sandbox and production; the key prefix signals the environment).
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % key,
		"Content-Type: application/json",
		"Accept: application/json",
		"X-Platform: web",
		"X-Is-Sandbox: %s" % _is_sandbox(),
	])
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_request_in_flight = false
		printerr("RevenueCatIapProvider: request failed: %d" % err)
		if for_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		return false
	return true


## True when this build talks to the RevenueCat sandbox environment. The API
## only returns sandbox/test purchases when the request carries
## X-Is-Sandbox: true — sending false makes every restore come back empty.
## Derived from BOTH the key prefix (rcb_sb_) and the checkout URL, so a
## production-key + sandbox-checkout test setup is still detected as sandbox.
func _is_sandbox() -> bool:
	var key: String = str(ProjectSettings.get_setting("iap/revenuecat_public_key", ""))
	if key.begins_with("rcb_sb_"):
		return true
	var checkout: String = str(ProjectSettings.get_setting("iap/web_checkout_url", ""))
	return checkout.contains("/sandbox/")


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	var was_restore: bool = _restore_in_progress
	_restore_in_progress = false
	# 200 for an existing customer, 201 when the GET created it — both success.
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		printerr("RevenueCatIapProvider: customer info failed (result=%d code=%d)" % [result, response_code])
		if was_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		if _migration_pending:
			_migration_pending = false
			# Can't tell whether the anonymous id owned anything — check the
			# account id directly instead of migrating blindly.
			_fetch_customer_info()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		printerr("RevenueCatIapProvider: malformed customer info response")
		if was_restore:
			restore_finished.emit(RestoreResult.UNAVAILABLE)
		if _migration_pending:
			_migration_pending = false
			_fetch_customer_info()
		return
	var owned: bool = _has_active_entitlement(parsed)
	if _checked_user_id == _anon_id and owned:
		_anon_owned = true
	if owned and not LevelManager.all_puzzles_unlocked:
		LevelManager.unlock_all_albums()
		purchase_completed.emit()
	if was_restore:
		restore_finished.emit(RestoreResult.RESTORED if owned else RestoreResult.NOT_FOUND)
	if _migration_pending:
		_migration_pending = false
		if _anon_owned and _app_user_id != _anon_id:
			_identify_customer(_anon_id, _app_user_id)
		else:
			_fetch_customer_info()


## True when the customer owns the unlock. Checks the mapped entitlement first
## (dashboard product -> entitlement mapping); falls back to the purchased
## non-subscription product, which is where checkout purchases land when the
## product is NOT mapped to an entitlement in the dashboard. Matches the
## configured product id (iap/revenuecat_product_id), or any non-subscription
## when unset (this project has exactly one purchasable product).
func _has_active_entitlement(customer: Dictionary) -> bool:
	var subscriber: Dictionary = customer.get("subscriber", {})
	var id: String = str(ProjectSettings.get_setting("iap/revenuecat_entitlement_id", "unlock_all"))
	if (subscriber.get("entitlements", {}) as Dictionary).has(id):
		return true
	var product_id: String = str(ProjectSettings.get_setting("iap/revenuecat_product_id", ""))
	var non_subs: Dictionary = subscriber.get("non_subscriptions", {})
	if product_id.is_empty():
		return not non_subs.is_empty()
	var purchases: Array = non_subs.get(product_id, [])
	return purchases.size() > 0


## ── Identity persistence ───────────────────────────────────────────────────


func _load_identity() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(IDENTITY_PATH) == OK:
		_anon_id = str(cfg.get_value("identity", "anon_id", ""))
	if _anon_id.is_empty():
		_anon_id = _generate_anon_id()
		_save_identity()


func _save_identity() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "anon_id", _anon_id)
	cfg.save(IDENTITY_PATH)


func _generate_anon_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()