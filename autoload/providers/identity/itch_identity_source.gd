class_name ItchIdentitySource
extends IdentitySource

## itch.io OAuth identity source — Implicit Flow (response_type=token), no
## client secret — safe for a client-only game. This is the only OAuth flow
## itch.io exposes for third-party OAuth applications (see
## https://itch.io/docs/api/oauth); there is no token-exchange endpoint and no
## refresh token. The granted credential is a long-lived API key the user can
## revoke from their itch.io settings.
##
##   Android: the game opens the itch authorize page in the default browser
##     and the token comes back through the custom URI scheme
##     picturepuzzle://callback (identity/itch_android_redirect_uri). The
##     scheme is registered in the game's AndroidManifest intent-filter and
##     GodotApp.java forwards the URI into the game via
##     user://deep_link_uri.txt (user:// == app files dir on 4.6 Android).
##     There is no loopback listener: the browser is a separate app and
##     localhost cleartext is blocked by default. The hosted callback page
##     (web/itch_oauth_callback.html) re-emits the token as a *query* string —
##     a fragment would never reach the intent.
##   Desktop: the game opens the itch authorize page in the browser and
##     catches the loopback redirect on http://127.0.0.1:<port>/callback with
##     a local TCPServer (no native code, no manifest changes). The token
##     travels in the URL *hash*, which browsers never send to the server, so
##     the listener serves a tiny page whose JavaScript reads the hash and
##     POSTs it back to the loopback address — same machine, so the token
##     never leaves the device.
##   Web: itch.io game pages always embed the game in a cross-origin iframe,
##     where in-frame redirects are blocked (X-Frame-Options: sameorigin) and
##     the token hash would land on the parent page the iframe cannot read.
##     The authorize page therefore opens in a NEW TAB (popups from iframes are
##     allowed, in-frame navigations are not) and the token comes back one of
##     two ways:
##       * AUTO (recommended): identity/itch_web_callback_url points at a tiny
##         relay page we host (web/itch_oauth_callback.html, e.g. on GitHub
##         Pages — HTTPS required, must be registered as this OAuth app's
##         callback URL). itch redirects the popup there, the page reads the
##         hash and postMessages the token back to the game window — the player
##         never copies anything.
##       * FALLBACK: without a callback URL the out-of-band (oob) flow is used
##         (redirect_uri=urn:ietf:wg:oauth:2.0:oob): itch shows the API key and
##         the player pastes it into the game (manual_token_required ->
##         submit_manual_token). The paste dialog doubles as the fallback UI
##         for the auto flow (blocked popup, expired state, etc.).
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
## Where GodotApp.java drops the incoming custom-scheme URI (Android only).
## Godot 4.6 maps user:// to the app files dir (getFilesDir()), which is
## exactly where the Java side writes (GodotIO.getDataDir() ignores the
## project-name subdirectory).
const DEEP_LINK_PATH := "user://deep_link_uri.txt"

var _client_id: String = ""
var _redirect_uri: String = ""
var _port: int = 39201
var _is_web: bool = false
var _is_android: bool = false

var _state: String = ""
var _signing_in: bool = false
var _sign_in_started_at: float = 0.0
var _listener: TCPServer = null
var _pending_conn: StreamPeerTCP = null

var _access_token: String = ""
var _user_id: String = ""
var _user_name: String = ""
## The login URL for the currently-pending web flow ("" when none).
var _oob_login_url: String = ""
## Hosted relay page (identity/itch_web_callback_url); "" = oob fallback.
var _callback_url: String = ""
## Kept referenced so the JS->GDScript message bridge isn't garbage collected.
var _web_msg_callback: JavaScriptObject = null

@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_is_android = OS.get_name() == "Android"
	if _is_web:
		_client_id = str(ProjectSettings.get_setting("identity/itch_web_client_id", ""))
		_redirect_uri = str(ProjectSettings.get_setting("identity/itch_web_redirect_uri", ""))
		_callback_url = str(ProjectSettings.get_setting("identity/itch_web_callback_url", "")).strip_edges()
		if not _callback_url.is_empty():
			_install_web_message_listener()
	elif _is_android:
		_client_id = str(ProjectSettings.get_setting("identity/itch_android_client_id", ""))
		_redirect_uri = str(ProjectSettings.get_setting(
			"identity/itch_android_redirect_uri", "picturepuzzle://callback"))
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
		elif _is_android:
			sign_in_failed.emit("identity/itch_android_client_id is not configured")
		else:
			sign_in_failed.emit("identity/itch_loopback_client_id is not configured")
		return
	_sign_in_started_at = Time.get_ticks_msec() / 1000.0
	_signing_in = true
	_state = _generate_state()
	if _is_android:
		# A stale deep-link file from a previous aborted attempt would fail the
		# state check of the new attempt — clear it up front.
		if FileAccess.file_exists(DEEP_LINK_PATH):
			DirAccess.remove_absolute(DEEP_LINK_PATH)
	if _is_web:
		# Web is always the popup flow (see header doc): itch game pages embed
		# the game in a cross-origin iframe where in-frame redirects are
		# blocked. With a hosted callback URL the token relays back
		# automatically; without one the player pastes it (oob).
		_begin_web_flow()
	elif _is_android:
		# Android: open the authorize page in the default browser and wait for
		# the custom-scheme redirect. The browser is a separate app, so no
		# localhost listener exists; GodotApp.java forwards the returned URI
		# into user://deep_link_uri.txt and _process() consumes it below.
		OS.shell_open(_build_authorize_url())
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
	if FileAccess.file_exists(DEEP_LINK_PATH):
		DirAccess.remove_absolute(DEEP_LINK_PATH)
	_clear_session()
	signed_out.emit()


func _process(_delta: float) -> void:
	if not _signing_in:
		return
	if Time.get_ticks_msec() / 1000.0 - _sign_in_started_at > SIGN_IN_TIMEOUT_SEC:
		printerr("ItchIdentitySource: sign-in timed out")
		_signing_in = false
		_stop_listener()
		sign_in_failed.emit("Sign-in timed out")
		return
	if _is_android:
		_check_deep_link_file()
		return
	if _is_web:
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


## ── Android custom-scheme callback ─────────────────────────────────────────


## Android only, called from _process() while a sign-in is pending. Polls the
## deep-link file that GodotApp.java writes when the browser hands the
## picturepuzzle://callback URI back to the app (both cold start via onCreate
## and warm start via onNewIntent). The file is consumed and deleted so an
## unrelated later launch of the scheme can't replay stale OAuth data.
func _check_deep_link_file() -> void:
	if not FileAccess.file_exists(DEEP_LINK_PATH):
		return
	var file := FileAccess.open(DEEP_LINK_PATH, FileAccess.READ)
	if file == null:
		return
	var uri := file.get_as_text().strip_edges()
	file.close()
	DirAccess.remove_absolute(DEEP_LINK_PATH)
	if uri.is_empty():
		return
	if not uri.begins_with("picturepuzzle://callback"):
		printerr("ItchIdentitySource: unexpected deep link uri: %s" % uri)
		return
	_handle_callback_uri(uri)


## Parses the custom-scheme callback (query string, because a fragment never
## leaves the browser — the hosted relay page re-emits it as query), validates
## the OAuth state, then completes sign-in exactly like every other flow.
func _handle_callback_uri(uri: String) -> void:
	var query_start := uri.find("?")
	if query_start == -1:
		printerr("ItchIdentitySource: callback uri had no query string")
		sign_in_failed.emit("itch.io sign-in failed (token missing from callback)")
		return
	var params := {}
	for pair in uri.substr(query_start + 1).split("&"):
		if not pair.contains("="):
			continue
		var kv := pair.split("=", true, 1)
		params[kv[0]] = kv[1].uri_decode()
	var token: String = str(params.get("access_token", ""))
	var state: String = str(params.get("state", ""))
	if state != _state:
		printerr("ItchIdentitySource: OAuth state mismatch — ignoring")
		sign_in_failed.emit("OAuth state mismatch")
		return
	if token.is_empty():
		printerr("ItchIdentitySource: callback had no access_token")
		sign_in_failed.emit("itch.io sign-in failed (missing access token)")
		return
	_signing_in = false
	_access_token = token
	_save_session()
	_fetch_profile()


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


## Web (iframe) sign-in: open the authorize page in a NEW TAB — popups from
## iframes are allowed, in-frame navigations are not. The redirect target is
## the hosted relay page (auto, token comes back via postMessage) or the oob
## urn (the player pastes the API key). The paste dialog is shown either way —
## it doubles as the fallback when the auto relay is blocked or times out.
func _begin_web_flow() -> void:
	var use_auto := not _callback_url.is_empty()
	_oob_login_url = _build_authorize_url(_callback_url if use_auto else OOB_REDIRECT_URI, use_auto)
	# This runs from the rAF game loop, not the DOM event call stack, so a
	# browser popup blocker may refuse it; the dialog then offers a direct
	# button (real user gesture) plus the URL itself as a fallback.
	JavaScriptBridge.eval("window.open('%s', '_blank')" % _oob_login_url)
	manual_token_required.emit(_oob_login_url)


## Re-opens the web login page — called from a direct button click, which is a
## real user gesture that popup blockers allow even when the auto-open above
## was refused.
func request_oob_login_page() -> void:
	if _is_web and not _oob_login_url.is_empty():
		JavaScriptBridge.eval("window.open('%s', '_blank')" % _oob_login_url)


## Installs the popup -> game message bridge (web only, auto flow). The relay
## page postMessages {type:"itch_oauth", access_token, state} to this window;
## the JS wrapper filters for that payload and hands clean strings to GDScript.
func _install_web_message_listener() -> void:
	if not _is_web:
		return
	_web_msg_callback = JavaScriptBridge.create_callback(_on_web_oauth_message)
	var window_obj: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window_obj.__itchOauthHandler = _web_msg_callback
	JavaScriptBridge.eval("""
		window.addEventListener('message', function (e) {
			var d = e.data;
			if (d && d.type === 'itch_oauth' && d.access_token) {
				window.__itchOauthHandler(d.access_token, d.state || '');
			}
		});
	""")


## The relay page's token arrives here. State is validated when present (the
## auto flow always sends it); the token is then persisted and profile-fetched
## exactly like every other flow.
func _on_web_oauth_message(args: Array) -> void:
	var token: String = str(args[0] if args.size() > 0 else "")
	var state: String = str(args[1] if args.size() > 1 else "")
	if not _signing_in:
		return
	if not state.is_empty() and state != _state:
		printerr("ItchIdentitySource: web OAuth state mismatch — ignoring")
		sign_in_failed.emit("OAuth state mismatch")
		return
	if token.is_empty():
		return
	_signing_in = false
	_access_token = token
	_save_session()
	_fetch_profile()


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


## The itch.io API sends NO CORS headers (verified on every response type),
## so browser builds cannot call api.itch.io directly — the fetch is blocked
## before any data returns. identity/itch_api_proxy_url points at a tiny
## pass-through proxy (see tools/itch_api_proxy_worker.js) that forwards the
## Authorization header and adds Access-Control-Allow-Origin. Desktop/Android
## use the API directly (native HTTP has no CORS).
func _fetch_profile() -> void:
	if _is_web:
		var proxy: String = str(ProjectSettings.get_setting("identity/itch_api_proxy_url", "")).strip_edges()
		if proxy.is_empty():
			printerr("ItchIdentitySource: web profile fetch blocked by CORS — set identity/itch_api_proxy_url")
			if _signing_in:
				_sign_in_fail("Sign-in requires identity/itch_api_proxy_url on web (itch.io API has no CORS)")
			return
		var headers := PackedStringArray([
			"Authorization: Bearer %s" % _access_token,
			"Accept: application/json",
		])
		_http.request(proxy, headers, HTTPClient.METHOD_GET)
		return
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