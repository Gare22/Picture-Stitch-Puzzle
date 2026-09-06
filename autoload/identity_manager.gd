extends Node

## Autoload facade for player identity. Injects one IdentitySource at startup
## (itch.io OAuth today; Firebase etc. later) so game code and the IAP layer
## never talk to an identity provider directly — swap platforms by changing
## which source gets injected.
##
## Source selection (Project Settings -> identity/provider_id):
##   "none" — no account layer (anonymous play only)
##   "itch" — itch.io OAuth (implicit flow, loopback/Web same-window flows)

signal signed_in(user_id: String, user_name: String)
signal signed_out
signal sign_in_failed(reason: String)
signal manual_token_required(url: String)

const SOURCE_SCENES := {
	"itch": "res://autoload/providers/identity/itch_identity_source.tscn",
}

var _source: IdentitySource = null


func _ready() -> void:
	var provider_id := str(ProjectSettings.get_setting("identity/provider_id", "none"))
	if provider_id == "none":
		return
	var scene_path: String = SOURCE_SCENES.get(provider_id, "")
	if scene_path.is_empty():
		push_error("IdentityManager: unknown provider_id '%s'" % provider_id)
		return
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("IdentityManager: failed to load identity source '%s'" % scene_path)
		return
	_source = scene.instantiate() as IdentitySource
	if _source == null:
		push_error("IdentityManager: '%s' did not produce an IdentitySource" % scene_path)
		return
	# Connect BEFORE add_child so synchronous _ready emissions are not lost.
	_source.signed_in.connect(_on_source_signed_in)
	_source.signed_out.connect(_on_source_signed_out)
	_source.sign_in_failed.connect(_on_source_sign_in_failed)
	_source.manual_token_required.connect(_on_source_manual_token_required)
	add_child(_source)


## True when an identity source is configured for this platform.
func is_supported() -> bool:
	return _source != null and _source.is_supported()


## True when the player is signed in.
func is_signed_in() -> bool:
	return _source != null and _source.is_signed_in()


## Stable provider user id ("" when signed out).
func get_user_id() -> String:
	if _source == null:
		return ""
	return _source.get_user_id()


## Display name ("" when signed out).
func get_user_name() -> String:
	if _source == null:
		return ""
	return _source.get_user_name()


## Namespaced App User ID for RevenueCat (e.g. "itch:12345"), or "" when signed
## out. Prefixing prevents ID collisions between identity sources.
func get_prefixed_user_id() -> String:
	if _source == null or not _source.is_signed_in():
		return ""
	return "%s:%s" % [_source.get_id_prefix(), _source.get_user_id()]


## Starts the interactive sign-in flow (result arrives via signals).
func sign_in() -> void:
	if _source != null:
		_source.sign_in()


## Ends the current session.
func sign_out() -> void:
	if _source != null:
		_source.sign_out()


## Feeds a manually pasted token back to the source (oob web-embed flow).
func submit_manual_token(token: String) -> void:
	if _source != null:
		_source.submit_manual_token(token)


## Re-opens the oob login page in a new tab (call from a direct button click
## so the browser treats it as a user gesture).
func request_oob_login_page() -> void:
	if _source != null:
		_source.request_oob_login_page()


## ── Source signal passthroughs ─────────────────────────────────────────────


func _on_source_signed_in(user_id: String, user_name: String) -> void:
	signed_in.emit(user_id, user_name)


func _on_source_signed_out() -> void:
	signed_out.emit()


func _on_source_sign_in_failed(reason: String) -> void:
	sign_in_failed.emit(reason)


func _on_source_manual_token_required(url: String) -> void:
	manual_token_required.emit(url)