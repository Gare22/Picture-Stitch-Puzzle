class_name IdentitySource
extends Node

## Base interface for player-identity providers (itch.io OAuth today, Firebase
## etc. later). IdentityManager injects the active source, so game code and the
## IAP layer never talk to an identity provider directly.

## Emitted when the user is signed in. user_id is the stable provider user id
## (e.g. itch's numeric id); user_name is a display name (e.g. itch username).
signal signed_in(user_id: String, user_name: String)

## Emitted when the session ends (sign-out, revocation, refresh failure).
signal signed_out

## Emitted when an interactive sign-in attempt fails. Reason is a debug string.
signal sign_in_failed(reason: String)

## True when this source is configured and can be used on this platform.
func is_supported() -> bool:
	return false

## True when a session is currently active.
func is_signed_in() -> bool:
	return false

## Stable provider user id ("" when signed out).
func get_user_id() -> String:
	return ""

## Display name ("" when signed out).
func get_user_name() -> String:
	return ""

## Short prefix used to namespace RevenueCat App User IDs per source
## (e.g. "itch" -> "itch:12345") so ids never collide across sources.
func get_id_prefix() -> String:
	return ""

## Starts the interactive sign-in flow (async; result via signals).
func sign_in() -> void:
	pass

## Ends the current session.
func sign_out() -> void:
	pass