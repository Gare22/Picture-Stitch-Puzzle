class_name ItchIdentitySource
extends IdentitySource

## itch.io OAuth identity source (PKCE authorization-code flow, no client
## secret — safe for a client-only game).
##
##   Android / desktop: the game opens the itch authorize page in the browser
##     and catches the loopback redirect on http://127.0.0.1:<port>/callback
##     with a local TCPServer (no native code, no manifest changes).
##   Web: same-window redirect — the game navigates to itch and, on return, the
##     authorization code is read from window.location.search at boot via
##     JavaScriptBridge (state + PKCE verifier survive the navigation in
##     sessionStorage).
##
## Session (access token + rotating refresh token + profile) persists in
## user://itch_session.cfg. On boot the access token is refreshed if needed and
## the profile re-fetched, so the user stays signed in across restarts.

const AUTHORIZE_URL := "https://itch.io/user/oauth"
const TOKEN_URL := "https://api.itch.io/oauth/token"
const PROFILE_URL := "https://api.itch.io/profile"
const SESSION_PATH := "user://itch_session.cfg"
const SCOPE := "profile:me"
const SIGN_IN_TIMEOUT_SEC := 300.0

enum _HttpMode { NONE, EXCHANGE, REFRESH, PROFILE }

var _client_id: String = ""
var _redirect_uri: String = ""
var _port: int = 39201
var _is_web: bool = false

var _code_verifier: String = ""
var _state: String = ""
var _signing_in: bool = false
var _sign_in_started_at: float = 0.0
var _listener: TCPServer = null
var _pending_conn: StreamPeerTCP = null

var _access_token: String = ""
var _refresh_token: String = ""
var _expires_at: int = 0  # unix seconds; 0 = unknown/non-expiring
var _user_id: String = ""
var _user_name: String = ""

var _http_mode: int = _HttpMode.NONE

@onready var _http: HTTPRequest = $HTTPRequest


func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	_client_id = str(ProjectSettings.get_setting("identity/itch_client_id", ""))
	if _is_web:
		_redirect_uri = str(ProjectSettings.get_setting("identity/itch_web_redirect_uri", ""))
	else:
		_redirect_uri = str(ProjectSettings.get_setting(
			"identity/itch_loopback_redirect_uri", "http://127.0.0.1:39201/callback"))
		_port = int(str(ProjectSettings.get_setting("identity/itch_loopback_port", 39201)))
	_http.request_completed.connect(_on_http_completed)
	if _is_web and _maybe_consume_web_callback():
		return
	_load_session()
	if not _refresh_token.is_empty():
		_restore_session()


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
		sign_in_failed.emit("identity/itch_client_id is not configured")
		return
	_sign_in_started_at = Time.get_ticks_msec() / 1000.0
	_signing_in = true
	_code_verifier = _generate_code_verifier()
	_state = _generate_state()
	var url := _build_authorize_url()
	if _is_web:
		# Persist state + verifier across the same-window navigation so the
		# returning boot can verify and exchange the code.
		JavaScriptBridge.eval("sessionStorage.setItem('itch_oauth_state', '%s')" % _state)
		JavaScriptBridge.eval("sessionStorage.setItem('itch_oauth_verifier', '%s')" % _code_verifier)
		JavaScriptBridge.eval("window.location = '%s'" % url)
	else:
		if not _start_loopback_listener():
			return  # failure already reported via sign_in_failed
		OS.shell_open(url)


func sign_out() -> void:
	_signing_in = false
	_stop_listener()
	# Cancel any in-flight exchange/profile so a late response can't re-sign the
	# user in after a sign-out.
	_http.cancel_request()
	_http_mode = _HttpMode.NONE
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
			var accepted := _handle_callback_connection(_pending_conn)
			_pending_conn = null
			if accepted:
				_stop_listener()


## ── OAuth plumbing ──────────────────────────────────────────────────────────


func _build_authorize_url() -> String:
	var parts := PackedStringArray([
		"client_id=%s" % _client_id.uri_encode(),
		"scope=%s" % SCOPE.uri_encode(),
		"redirect_uri=%s" % _redirect_uri.uri_encode(),
		"response_type=code",
		"code_challenge=%s" % _code_challenge().uri_encode(),
		"code_challenge_method=S256",
		"state=%s" % _state.uri_encode(),
	])
	return AUTHORIZE_URL + "?" + "&".join(parts)


func _begin_exchange(code: String) -> void:
	_http_mode = _HttpMode.EXCHANGE
	var body := "grant_type=authorization_code&code=%s&code_verifier=%s&redirect_uri=%s&client_id=%s" % [
		code.uri_encode(), _code_verifier.uri_encode(), _redirect_uri.uri_encode(), _client_id.uri_encode()]
	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
	])
	_http.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body)


func _refresh_access_token() -> void:
	_http_mode = _HttpMode.REFRESH
	var body := "grant_type=refresh_token&refresh_token=%s&client_id=%s" % [
		_refresh_token.uri_encode(), _client_id.uri_encode()]
	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
	])
	_http.request(TOKEN_URL, headers, HTTPClient.METHOD_POST, body)


func _fetch_profile() -> void:
	_http_mode = _HttpMode.PROFILE
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _access_token,
		"Accept: application/json",
	])
	_http.request(PROFILE_URL, headers, HTTPClient.METHOD_GET)


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var mode: int = _http_mode
	_http_mode = _HttpMode.NONE
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		printerr("ItchIdentitySource: request failed (mode=%d result=%d code=%d)" % [mode, result, response_code])
		match mode:
			_HttpMode.EXCHANGE:
				_sign_in_fail("itch.io sign-in failed (HTTP %d)" % response_code)
			_HttpMode.PROFILE:
				if _signing_in:
					# Interactive sign-in: the exchange succeeded but the profile
					# lookup failed — report so the UI isn't stuck.
					_sign_in_fail("itch.io sign-in failed (profile lookup)")
				else:
					_clear_session()
			_:
				# Refresh failure means the session is gone — sign out quietly.
				_clear_session()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		printerr("ItchIdentitySource: malformed response")
		if mode == _HttpMode.EXCHANGE:
			_sign_in_fail("itch.io returned an unexpected response")
		else:
			_clear_session()
		return
	match mode:
		_HttpMode.EXCHANGE:
			# itch returns camelCase per its Go binding; read both casings to be
			# robust either way.
			_access_token = str(parsed.get("accessToken", parsed.get("access_token", "")))
			_refresh_token = str(parsed.get("refreshToken", parsed.get("refresh_token", "")))
			_expires_at = int(Time.get_unix_time_from_system()) + int(parsed.get("expiresIn", parsed.get("expires_in", 0)))
			if _access_token.is_empty():
				_sign_in_fail("itch.io sign-in returned no token")
				return
			_save_session()
			_fetch_profile()
		_HttpMode.REFRESH:
			_access_token = str(parsed.get("accessToken", parsed.get("access_token", "")))
			_refresh_token = str(parsed.get("refreshToken", parsed.get("refresh_token", _refresh_token)))  # tokens rotate
			_expires_at = int(Time.get_unix_time_from_system()) + int(parsed.get("expiresIn", parsed.get("expires_in", 0)))
			if _access_token.is_empty():
				_clear_session()
				return
			_save_session()
			_fetch_profile()
		_HttpMode.PROFILE:
			var user: Dictionary = parsed.get("user", {})
			_user_id = str(user.get("id", ""))
			_user_name = str(user.get("username", ""))
			if _user_id.is_empty():
				printerr("ItchIdentitySource: profile response had no user id")
				_clear_session()
				return
			_save_session()
			signed_in.emit(_user_id, _user_name)


func _restore_session() -> void:
	if _access_token.is_empty() or _is_expired():
		_refresh_access_token()
	else:
		_fetch_profile()


func _is_expired() -> bool:
	return _expires_at > 0 and Time.get_unix_time_from_system() >= _expires_at


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


## Reads the browser's HTTP request, extracts code+state, and kicks off the
## token exchange. Only a request to /callback (from the loopback redirect) is
## treated as an OAuth callback; other probes (favicons etc.) are ignored so a
## live flow is never aborted. Returns true when a callback was consumed.
func _handle_callback_connection(conn: StreamPeerTCP) -> bool:
	var read: Array = conn.get_partial_data(conn.get_available_bytes())
	var request := ""
	if read[0] == OK:
		request = (read[1] as PackedByteArray).get_string_from_utf8()
	var first_line: String = request.split("\r\n")[0] if request.contains("\r\n") else request
	var parts := first_line.split(" ")
	var accepted := false
	if parts.size() >= 2:
		var path := parts[1]
		if path.begins_with("/callback"):
			var q_index := path.find("?")
			if q_index != -1:
				var params := _parse_query(path.substr(q_index + 1))
				var code: String = str(params.get("code", ""))
				if not code.is_empty():
					if str(params.get("state", "")) == _state:
						# A tiny 200 so the browser tab closes cleanly.
						conn.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
							+ "Content-Length: 0\r\nConnection: close\r\n\r\n").to_utf8_buffer())
						_signing_in = false
						_begin_exchange(code)
						accepted = true
					else:
						printerr("ItchIdentitySource: OAuth state mismatch")
						_signing_in = false
						accepted = true
						sign_in_failed.emit("OAuth state mismatch")
	conn.disconnect_from_host()
	return accepted


## ── Web callback (same-window redirect) ────────────────────────────────────


## Called at boot on web: if we just returned from the itch authorize page,
## consume the code + state from window.location.search. Returns true when a
## callback was consumed (and the exchange started).
func _maybe_consume_web_callback() -> bool:
	if not _is_web:
		return false
	var search := str(JavaScriptBridge.eval("window.location.search"))
	if search.is_empty():
		return false
	var params := _parse_query(search.trim_prefix("?"))
	var code: String = str(params.get("code", ""))
	if code.is_empty():
		# Returned from itch without a callback (abandoned flow) — reset so a new
		# sign-in attempt can start fresh.
		_signing_in = false
		return false
	var expected_state: String = str(JavaScriptBridge.eval("sessionStorage.getItem('itch_oauth_state')"))
	if expected_state.is_empty() or expected_state == "<null>" or str(params.get("state", "")) != expected_state:
		printerr("ItchIdentitySource: web OAuth state mismatch — ignoring callback")
		return false
	_code_verifier = str(JavaScriptBridge.eval("sessionStorage.getItem('itch_oauth_verifier')"))
	JavaScriptBridge.eval("sessionStorage.removeItem('itch_oauth_state')")
	JavaScriptBridge.eval("sessionStorage.removeItem('itch_oauth_verifier')")
	# Strip the query so a reload doesn't re-consume a stale code.
	JavaScriptBridge.eval("history.replaceState({}, '', window.location.pathname)")
	_signing_in = false
	_begin_exchange(code)
	return true


## ── PKCE / helpers ─────────────────────────────────────────────────────────


func _generate_code_verifier() -> String:
	return _base64url(Crypto.new().generate_random_bytes(32))


func _generate_state() -> String:
	return _base64url(Crypto.new().generate_random_bytes(16))


func _code_challenge() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_code_verifier.to_utf8_buffer())
	return _base64url(ctx.finish())


func _base64url(bytes: PackedByteArray) -> String:
	var s := Marshalls.raw_to_base64(bytes)
	return s.replace("+", "-").replace("/", "_").trim_suffix("=")


func _parse_query(query: String) -> Dictionary:
	var result := {}
	for pair in query.split("&"):
		if pair.is_empty():
			continue
		var kv := pair.split("=", true, 1)
		if kv.size() == 2:
			result[kv[0]] = kv[1].uri_decode()
	return result


## ── Session persistence ────────────────────────────────────────────────────


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "access_token", _access_token)
	cfg.set_value("session", "refresh_token", _refresh_token)
	cfg.set_value("session", "expires_at", _expires_at)
	cfg.set_value("session", "user_id", _user_id)
	cfg.set_value("session", "user_name", _user_name)
	cfg.save(SESSION_PATH)


func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	_access_token = str(cfg.get_value("session", "access_token", ""))
	_refresh_token = str(cfg.get_value("session", "refresh_token", ""))
	_expires_at = int(cfg.get_value("session", "expires_at", 0))
	_user_id = str(cfg.get_value("session", "user_id", ""))
	_user_name = str(cfg.get_value("session", "user_name", ""))


func _clear_session() -> void:
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0
	_user_id = ""
	_user_name = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)