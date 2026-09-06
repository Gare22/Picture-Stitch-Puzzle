class_name ItchIdentitySource
extends IdentitySource

## itch.io OAuth identity source — Implicit Flow (response_type=token), no
## client secret — safe for a client-only game. This is the only OAuth flow
## itch.io exposes for third-party OAuth applications (see
## https://itch.io/docs/api/oauth); there is no token-exchange endpoint and no
## refresh token. The granted credential is a long-lived API key the user can
## revoke from their itch.io settings.
##
##   Android / desktop: the game opens the itch authorize page in the browser
##     and catches the loopback redirect on http://127.0.0.1:<port>/callback
##     with a local TCPServer (no native code, no manifest changes). The token
##     travels in the URL *hash*, which browsers never send to the server, so
##     the listener serves a tiny page whose JavaScript reads the hash and
##     POSTs it back to the loopback address — same machine, so the token
##     never leaves the device.
##   Web: itch.io game pages always embed the game in a cross-origin iframe,
##     where in-frame redirects are blocked (X-Frame-Options: sameorigin) and
##     the token hash would land on the parent page the iframe cannot read. The
##     out-of-band (oob) flow is used instead: the authorize page
##     (redirect_uri=urn:ietf:wg:oauth:2.0:oob — register this as the web
##     OAuth app's callback) opens in a NEW TAB and shows the API key; the
##     player copies it and pastes it back into the game
##     (manual_token_required -> submit_manual_token).
##
## Session (access token + profile) persists in user://itch_session.cfg. On
## boot the profile is re-fetched to validate the token, so the user stays
## signed in across restarts until they revoke the token or sign out.

const AUTHORIZE_URL := "https://itch.io/user/oauth"
const PROFILE_URL := "https://api.itch.io/profile"
const SESSION_PATH := "user://itch_session.cfg"
const SCOPE := "profile:me"
const OOB_REDIRECT_URI := "urn:ietf:wg:oauth:2.0:oob"
const SIGN_IN_TIMEOUT_SEC := 300.0

var _client_id: String = ""
var _redirect_uri: String = ""
var _port: int = 39201
var _is_web: bool = false

var _state: String = ""
var _signing_in: bool = false
var _sign_in_started_at: float = 0.0
var _listener: TCPServer = null
var _pending_conn: StreamPeerTCP = null

var _access_token: String = ""
var _user_id: String = ""
var _user_name: String = ""
## The login URL for the currently-pending oob flow ("" when none).
var _oob_login_url: String = ""

@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	if _is_web:
		_client_id = str(ProjectSettings.get_setting("identity/itch_web_client_id", ""))
		_redirect_uri = str(ProjectSettings.get_setting("identity/itch_web_redirect_uri", ""))
	else:
		_client_id = str(ProjectSettings.get_setting("identity/itch_loopback_client_id", ""))
		_redirect_uri = str(ProjectSettings.get_setting(
			"identity/itch_loopback_redirect_uri", "http://127.0.0.1:39201/callback"))
		_port = int(str(ProjectSettings.get_setting("identity/itch_loopback_port", 39201)))
	_http.request_completed.connect(_on_http_completed)
	_load_session()
	if not _access_token.is_empty():
		# Validate the persisted token and refresh the cached profile.
		_fetch_profile()


func is_supported() -> bool:
	return not _client_id.is_empty()


func is_signed_in() -> bool:
	return not _user_id.is_empty()


func get_user_id() -> String:
	return _user_id


func get_user_name() -> String:
	return _user_name


func get_id_prefix() -> String:
	return "itch"


func sign_in() -> void:
	if _signing_in or is_signed_in():
		return
	if _client_id.is_empty():
		if _is_web:
			sign_in_failed.emit("identity/itch_web_client_id is not configured")
		else:
			sign_in_failed.emit("identity/itch_loopback_client_id is not configured")
		return
	_sign_in_started_at = Time.get_ticks_msec() / 1000.0
	_signing_in = true
	_state = _generate_state()
	if _is_web:
		# Web is always oob (see header doc): itch game pages embed the game in
		# a cross-origin iframe where in-frame redirects are blocked.
		_begin_oob_flow()
	else:
		if not _start_loopback_listener():
			return  # failure already reported via sign_in_failed
		OS.shell_open(_build_authorize_url())


func sign_out() -> void:
	_signing_in = false
	_stop_listener()
	# Cancel any in-flight profile fetch so a late response can't re-sign the
	# user in after a sign-out.
	_http.cancel_request()
	_clear_session()
	signed_out.emit()


func _process(_delta: float) -> void:
	if not _signing_in or _is_web:
		return
	if Time.get_ticks_msec() / 1000.0 - _sign_in_started_at > SIGN_IN_TIMEOUT_SEC:
		printerr("ItchIdentitySource: sign-in timed out")
		_signing_in = false
		_stop_listener()
		sign_in_failed.emit("Sign-in timed out")
		return
	if _listener != null:
		if _listener.is_connection_available() and _pending_conn == null:
			_pending_conn = _listener.take_connection()
	if _pending_conn != null:
		_pending_conn.poll()
		if _pending_conn.get_available_bytes() > 0:
			var result := _handle_connection(_pending_conn)
			if result != -1:
				_pending_conn.disconnect_from_host()
				_pending_conn = null
				if result == 1:
					_stop_listener()


## ── OAuth plumbing ──────────────────────────────────────────────────────────


func _build_authorize_url(p_redirect_uri := "", p_include_state := true) -> String:
	var parts := PackedStringArray([
		"client_id=%s" % _client_id.uri_encode(),
		"scope=%s" % SCOPE.uri_encode(),
		"redirect_uri=%s" % (p_redirect_uri if not p_redirect_uri.is_empty() else _redirect_uri).uri_encode(),
		"response_type=token",
	])
	if p_include_state:
		parts.append("state=%s" % _state.uri_encode())
	return AUTHORIZE_URL + "?" + "&".join(parts)


## Embedded-web (iframe) sign-in: open the oob authorize page in a NEW TAB —
## popups from iframes are allowed, in-frame navigations are not. itch shows
## the API key; the player copies it and pastes it back via submit_manual_token.
func _begin_oob_flow() -> void:
	_oob_login_url = _build_authorize_url(OOB_REDIRECT_URI, false)
	# This runs from the rAF game loop, not the DOM event call stack, so a
	# browser popup blocker may refuse it; the paste dialog then offers a
	# direct button (real user gesture) plus the URL itself as a fallback.
	JavaScriptBridge.eval("window.open('%s', '_blank')" % _oob_login_url)
	manual_token_required.emit(_oob_login_url)


## Re-opens the oob login page — called from a direct button click, which is a
## real user gesture that popup blockers allow even when the auto-open above
## was refused.
func request_oob_login_page() -> void:
	if _is_web and not _oob_login_url.is_empty():
		JavaScriptBridge.eval("window.open('%s', '_blank')" % _oob_login_url)


## Feeds a manually pasted oob token back and validates it with the profile
## fetch (the token is the credential — no state round-trip in oob).
func submit_manual_token(token: String) -> void:
	var trimmed := token.strip_edges()
	if trimmed.is_empty():
		sign_in_failed.emit("No token entered")
		return
	_access_token = trimmed
	_save_session()
	_fetch_profile()


func _fetch_profile() -> void:
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _access_token,
		"Accept: application/json",
	])
	_http.request(PROFILE_URL, headers, HTTPClient.METHOD_GET)


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		printerr("ItchIdentitySource: profile request failed (result=%d code=%d)" % [result, response_code])
		if _signing_in:
			_sign_in_fail("itch.io sign-in failed (HTTP %d)" % response_code)
		else:
			# A restored session whose token was revoked/expired — sign out.
			var was_signed_in := not _user_id.is_empty()
			_clear_session()
			if was_signed_in:
				signed_out.emit()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		printerr("ItchIdentitySource: malformed profile response")
		if _signing_in:
			_sign_in_fail("itch.io returned an unexpected response")
		else:
			_clear_session()
		return
	var user: Dictionary = parsed.get("user", {})
	var raw_id: Variant = user.get("id", null)
	if raw_id == null:
		printerr("ItchIdentitySource: profile response had no user id")
		_clear_session()
		return
	# Godot's JSON parser returns every number as a float, so str() of a raw id
	# would produce "2289629.0" — normalize to int to keep the account id
	# stable ("itch:2289629") across parses and session round-trips.
	var user_id: String = str(int(raw_id))
	_user_id = user_id
	_user_name = str(user.get("username", user.get("display_name", "")))
	_save_session()
	_signing_in = false
	signed_in.emit(_user_id, _user_name)


func _sign_in_fail(reason: String) -> void:
	_signing_in = false
	_stop_listener()
	sign_in_failed.emit(reason)


## ── Loopback listener (Android / desktop) ──────────────────────────────────


## Starts the loopback listener. Returns false (and emits sign_in_failed) when
## the port can't be bound — callers should not open the browser in that case.
func _start_loopback_listener() -> bool:
	_stop_listener()
	_listener = TCPServer.new()
	var err := _listener.listen(_port, "127.0.0.1")
	if err != OK:
		printerr("ItchIdentitySource: loopback listen failed: %d" % err)
		_signing_in = false
		sign_in_failed.emit("Could not start the local OAuth listener (port %d in use?)" % _port)
		return false
	return true


func _stop_listener() -> void:
	if _listener != null:
		_listener.stop()
		_listener = null
	_pending_conn = null


## Handles one browser connection to the loopback listener.
##
## Returns:
##   1 — an OAuth callback was consumed (stop the listener),
##   0 — the connection was handled and can be closed,
##   -1 — need more data (keep the connection for the next poll).
func _handle_connection(conn: StreamPeerTCP) -> int:
	var read: Array = conn.get_partial_data(conn.get_available_bytes())
	var raw := PackedByteArray()
	if read[0] == OK:
		raw = read[1] as PackedByteArray
	var text := raw.get_string_from_utf8()
	if not text.contains("\r\n\r\n"):
		return -1  # headers not fully arrived yet
	var header_part := text.split("\r\n\r\n")[0]
	var body: String = text.split("\r\n\r\n", true, 1)[1] if text.contains("\r\n\r\n") else ""
	var lines := header_part.split("\r\n")
	if lines.is_empty():
		return 0
	var tokens := lines[0].split(" ")
	if tokens.size() < 2:
		return 0
	var method := tokens[0]
	var path := tokens[1]
	if method == "GET":
		if path.begins_with("/callback"):
			# The token is in the URL hash, which the browser never sends to the
			# server — serve a page whose JS reads it and POSTs it back to us.
			var page := _callback_page_html()
			conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
				+ "Content-Length: %d\r\nConnection: close\r\n\r\n%s" % [page.length(), page]).to_utf8_buffer())
		# Any other GET (favicon probes etc.) is ignored so the flow isn't
		# aborted by noise.
		return 0
	if method == "POST":
		if body.is_empty():
			return -1  # body may arrive in a second packet
		var parsed: Variant = JSON.parse_string(body)
		if not (parsed is Dictionary):
			printerr("ItchIdentitySource: loopback POST was not JSON")
			return 0
		var token: String = str(parsed.get("access_token", ""))
		if token.is_empty():
			printerr("ItchIdentitySource: loopback POST had no access_token")
			return 0
		if str(parsed.get("state", "")) != _state:
			printerr("ItchIdentitySource: OAuth state mismatch")
			_signing_in = false
			conn.put_data(("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").to_utf8_buffer())
			sign_in_failed.emit("OAuth state mismatch")
			return 1
		var msg := "Signed in! You can close this window."
		conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
			+ "Content-Length: %d\r\nConnection: close\r\n\r\n%s" % [msg.length(), msg]).to_utf8_buffer())
		_signing_in = false
		_access_token = token
		_save_session()
		_fetch_profile()
		return 1
	return 0


## The page served at /callback: reads access_token + state out of the URL hash
## and POSTs them back to the loopback listener (same machine — the token never
## leaves the device).
func _callback_page_html() -> String:
	return """<!DOCTYPE html><html><head><meta charset="utf-8"><title>Sign-in</title></head>
<body><p>Signing you in... You can close this window when it says done.</p>
<script>
var params = new URLSearchParams(window.location.hash.slice(1));
fetch('http://127.0.0.1:%d/', {
  method: 'POST',
  body: JSON.stringify({ access_token: params.get('access_token'), state: params.get('state') })
}).then(function (r) { return r.text(); }).then(function (t) {
  document.body.innerHTML = '<p>' + t + '</p>';
});
</script></body></html>""" % _port


## ── Web callback (same-window redirect) ────────────────────────────────────


## ── Helpers ────────────────────────────────────────────────────────────────


func _generate_state() -> String:
	return _base64url(Crypto.new().generate_random_bytes(16))


func _base64url(bytes: PackedByteArray) -> String:
	var s := Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_")
	# RFC 4648 base64url omits all padding ("=" × 1 or 2).
	return s.trim_suffix("==").trim_suffix("=")


## ── Session persistence ────────────────────────────────────────────────────


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "access_token", _access_token)
	cfg.set_value("session", "user_id", _user_id)
	cfg.set_value("session", "user_name", _user_name)
	cfg.save(SESSION_PATH)


func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	_access_token = str(cfg.get_value("session", "access_token", ""))
	# Normalize a session saved before the float-id fix ("2289629.0" -> int) so
	# a stale cfg can't produce a wrong RevenueCat App User ID.
	var loaded_id: String = str(cfg.get_value("session", "user_id", ""))
	_user_id = str(int(loaded_id)) if not loaded_id.is_empty() else ""
	_user_name = str(cfg.get_value("session", "user_name", ""))


func _clear_session() -> void:
	_access_token = ""
	_user_id = ""
	_user_name = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)