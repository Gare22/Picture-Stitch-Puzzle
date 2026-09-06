class_name IapProvider
extends Node

## Base interface for in-app-purchase providers. IapManager injects the active
## provider (Google Play Billing, a web payment link, or a dev mock) via a
## scene instantiation, so the rest of the game never touches a platform
## directly — swap platforms by changing which provider is injected.

## Emitted once the localized price string is known ("$2.99", "2,99 €", ...).
signal price_loaded(price: String)

## Emitted when the unlock-all entitlement becomes active (purchased or restored).
signal purchase_completed

## Emitted when the purchase flow could not be started/finished. Reason is a
## debug string, safe to log.
signal purchase_failed(reason: String)

## Emitted when this provider is known to be unusable on the device.
signal became_unavailable

## Emitted when a user-initiated restore finishes.
signal restore_finished(result: RestoreResult)

## Emitted when a hosted checkout page was opened (web providers), so the UI
## can prompt the player to confirm once they complete payment. Other providers
## never emit this.
signal payment_flow_started

## Outcome of a user-initiated restore_purchases() call.
enum RestoreResult {
	RESTORED,     # entitlement is active (already owned or re-granted)
	NOT_FOUND,    # no previous purchase found
	UNAVAILABLE,  # provider not connected / query failed
}

## True when this provider can be used on the current platform.
func is_supported() -> bool:
	return false

## True when the provider is known to be unusable on this device.
func is_unavailable() -> bool:
	return false

## Localized price string, or "" until known.
func get_price() -> String:
	return ""

## Starts the purchase flow for the product.
func purchase() -> void:
	push_error("IapProvider.purchase() not implemented by %s" % get_script().resource_path)

## Re-checks entitlements with the provider.
func restore_purchases() -> void:
	push_error("IapProvider.restore_purchases() not implemented by %s" % get_script().resource_path)

## Confirms a payment completed through a hosted checkout (web providers only).
## No-op for every other provider.
func confirm_payment() -> void:
	pass

## Returns the provider's customer / restore identifier, or "" when the
## provider has no such concept. Used by the Options "restore code" UI.
func get_app_user_id() -> String:
	return ""

## Sets the provider's customer / restore identifier (e.g. a user-entered
## restore code). No-op for providers without identity.
func set_app_user_id(_id: String) -> void:
	pass