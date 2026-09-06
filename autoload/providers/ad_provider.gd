class_name AdProvider
extends Node

## Base interface for rewarded-ad providers. AdsManager injects the active
## provider (AdMob, a web placeholder, or a dev mock) via a scene
## instantiation, so the rest of the game never touches an ad platform
## directly — swap platforms by changing which provider is injected.

## Emitted when a rewarded ad was watched to completion.
signal rewarded_earned

## Emitted when the ad could not be shown or was not completed.
signal ad_failed

## True when this provider can serve ads on the current platform.
func is_supported() -> bool:
	return false

## Starts the rewarded-ad flow. Emits EXACTLY ONE of rewarded_earned /
## ad_failed per call.
func show_rewarded() -> void:
	push_error("AdProvider.show_rewarded() not implemented by %s" % get_script().resource_path)