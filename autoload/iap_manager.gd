extends Node

## Autoload facade for in-app purchases. Injects one IAP provider at startup
## (Google Play Billing, a web payment link, or a dev mock) and forwards its
## signals and calls, so the rest of the game never talks to a store platform
## directly. Swap platforms by changing which provider gets injected.
##
## Provider selection (Project Settings -> iap/provider_id):
##   "auto"        — web everywhere (Google Play is not used in this project);
##                   TEST_MODE falls back to the mock dev simulation
##   "google_play" — force Google Play Billing (GodotGooglePlayBilling plugin)
##   "web"         — force the web payment-link provider (no Google account)
##   "revenuecat"  — force the RevenueCat provider (hosted web checkout +
##                   server-backed entitlements; cross-device restore codes)
##   "mock"        — force the dev simulation
## An explicit provider_id is always honored; with "auto", TEST_MODE picks the
## mock provider on dev machines, otherwise the web provider is used on every
## platform.

## Simulates the whole flow on non-mobile dev machines via the mock provider.
## MUST be set to false for release builds.
@export var TEST_MODE: bool = true

signal price_loaded(price: String)
signal purchase_completed
signal purchase_failed(reason: String)
signal became_unavailable
signal restore_finished(result: IapProvider.RestoreResult)
signal payment_flow_started

var _provider: IapProvider = null
var _unavailable: bool = false

const PROVIDER_SCENES := {
	"google_play": "res://autoload/providers/google_play_iap.tscn",
	"web": "res://autoload/providers/web_iap.tscn",
	"revenuecat": "res://autoload/providers/revenuecat_iap.tscn",
	"mock": "res://autoload/providers/mock_iap.tscn",
}


func _ready() -> void:
	var provider_id := _resolve_provider_id()
	var scene_path: String = PROVIDER_SCENES.get(provider_id, "")
	if scene_path.is_empty():
		push_error("IapManager: unknown provider_id '%s'" % provider_id)
		_unavailable = true
		return
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("IapManager: failed to load provider scene '%s'" % scene_path)
		_unavailable = true
		return
	_provider = scene.instantiate() as IapProvider
	if _provider == null:
		push_error("IapManager: provider scene '%s' did not produce an IapProvider" % scene_path)
		_unavailable = true
		return
	# Connect BEFORE add_child: add_child() runs the provider's _ready()
	# synchronously, and a signal emitted there (e.g. price_loaded) must not be
	# lost. Connecting an instantiated-but-not-in-tree node is legal.
	_provider.price_loaded.connect(_on_provider_price_loaded)
	_provider.purchase_completed.connect(_on_provider_purchase_completed)
	_provider.purchase_failed.connect(_on_provider_purchase_failed)
	_provider.became_unavailable.connect(_on_provider_became_unavailable)
	_provider.restore_finished.connect(_on_provider_restore_finished)
	_provider.payment_flow_started.connect(_on_provider_payment_flow_started)
	add_child(_provider)


## Maps the configured provider_id to an actual provider for this run.
func _resolve_provider_id() -> String:
	var id: String = str(ProjectSettings.get_setting("iap/provider_id", "auto"))
	if id != "auto":
		return id
	if TEST_MODE:
		return "mock"
	# Google Play isn't used in this project — route every platform through the
	# web payment-link provider. "google_play" stays available via explicit config.
	return "web"


## True when the purchase banner should be offered on this platform.
func is_supported() -> bool:
	return _provider != null and _provider.is_supported()


## True when billing is known to be unusable on this device.
func is_unavailable() -> bool:
	return _unavailable or (_provider != null and _provider.is_unavailable())


## Localized price string from the active provider, or "" until known.
func get_price_display() -> String:
	if _provider == null:
		return ""
	return _provider.get_price()


## Launches the purchase flow for the unlock-all product.
func purchase_unlock_all() -> void:
	if _provider != null:
		_provider.purchase()


## Re-checks entitlements with the active provider.
func restore_purchases() -> void:
	if _provider != null:
		_provider.restore_purchases()


## Confirms a payment completed through a hosted checkout (web provider only).
func confirm_payment() -> void:
	if _provider != null:
		_provider.confirm_payment()


## DEV-ONLY: clears the local unlock-all entitlement so the purchase flow can
## be re-tested. A real store purchase is untouched — providers that can
## re-verify (e.g. Google Play) restore it on the next query.
func remove_all_unlock_entitlement() -> void:
	LevelManager.remove_unlock_all()


## Clears provider-local purchase state (files/caches) as part of a full
## data wipe. LevelManager.reset_all_data() clears the entitlement flag;
## this clears what the provider itself persisted (e.g. the anonymous
## RevenueCat identity). Server-side purchases are not deleted.
func reset_all_data() -> void:
	if _provider != null:
		_provider.reset_all_data()


## ── Provider signal passthroughs ───────────────────────────────────────────


func _on_provider_price_loaded(price: String) -> void:
	price_loaded.emit(price)


func _on_provider_purchase_completed() -> void:
	purchase_completed.emit()


func _on_provider_purchase_failed(reason: String) -> void:
	purchase_failed.emit(reason)


func _on_provider_became_unavailable() -> void:
	_unavailable = true
	became_unavailable.emit()


func _on_provider_restore_finished(result: IapProvider.RestoreResult) -> void:
	restore_finished.emit(result)


func _on_provider_payment_flow_started() -> void:
	payment_flow_started.emit()
