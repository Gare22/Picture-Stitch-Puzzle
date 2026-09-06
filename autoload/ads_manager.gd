extends Node

## Autoload facade for rewarded ads. Injects one ad provider at startup
## (AdMob, a web placeholder, or a dev mock) and forwards calls, so the rest of
## the game never talks to an ad platform directly. Swap platforms by changing
## which provider gets injected.
##
## Provider selection (Project Settings -> ads/provider_id):
##   "auto"  — web everywhere (Google ads are not used in this project);
##             TEST_MODE falls back to the mock dev simulation
##   "admob" — force AdMob (godot-admob plugin)
##   "web"   — force the web placeholder provider (no Google account)
##   "mock"  — force the dev simulation
## An explicit provider_id is always honored; with "auto", TEST_MODE picks the
## mock provider on dev machines, otherwise the web provider is used everywhere.

## Simulates rewarded ads on dev machines via the mock provider. MUST be set to
## false for release builds.
@export var TEST_MODE: bool = true

## Emitted when a rewarded ad was watched to completion.
signal rewarded_earned

## Emitted when the ad could not be shown or was not completed.
signal ad_failed

var _provider: AdProvider = null

const PROVIDER_SCENES := {
	"admob": "res://autoload/providers/admob_provider.tscn",
	"web": "res://autoload/providers/web_ad_provider.tscn",
	"mock": "res://autoload/providers/mock_ad_provider.tscn",
}


func _ready() -> void:
	var provider_id := _resolve_provider_id()
	var scene_path: String = PROVIDER_SCENES.get(provider_id, "")
	if scene_path.is_empty():
		push_error("AdsManager: unknown provider_id '%s'" % provider_id)
		return
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("AdsManager: failed to load provider scene '%s'" % scene_path)
		return
	_provider = scene.instantiate() as AdProvider
	if _provider == null:
		push_error("AdsManager: provider scene '%s' did not produce an AdProvider" % scene_path)
		return
	# Connect BEFORE add_child: add_child() runs the provider's _ready()
	# synchronously; a signal emitted there must not be lost.
	_provider.rewarded_earned.connect(_on_provider_rewarded)
	_provider.ad_failed.connect(_on_provider_failed)
	add_child(_provider)


## Maps the configured provider_id to an actual provider for this run.
func _resolve_provider_id() -> String:
	var id: String = str(ProjectSettings.get_setting("ads/provider_id", "auto"))
	if id != "auto":
		return id
	if TEST_MODE:
		return "mock"
	# Google ads aren't used in this project — route every platform through the
	# web provider. "admob" stays available via explicit config.
	return "web"


## True when the active provider can serve ads on this platform.
func is_supported() -> bool:
	return _provider != null and _provider.is_supported()


## Starts the rewarded-ad flow. Emits EXACTLY ONE of rewarded_earned /
## ad_failed per call.
func show_rewarded() -> void:
	if _provider == null:
		ad_failed.emit()
		return
	_provider.show_rewarded()


## ── Provider signal passthroughs ───────────────────────────────────────────


func _on_provider_rewarded() -> void:
	rewarded_earned.emit()


func _on_provider_failed() -> void:
	ad_failed.emit()
