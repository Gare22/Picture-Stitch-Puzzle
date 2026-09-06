extends Control

## Album-selection screen. Shows a scrollable grid of album thumbnails
## that the player can tap to load that album's puzzles into level select.

@onready var grid: GridContainer = $ScrollContainer/MarginContainer/VBox/GridContainer
@onready var back_button: Button = $BackButton
@onready var purchase_overlay: Control = $PurchaseOverlay
@onready var purchase_info_label: Label = $PurchaseOverlay/Panel/VBox/InfoLabel
@onready var purchase_confirm_button: Button = $PurchaseOverlay/Panel/VBox/ConfirmButton
@onready var purchase_cancel_button: Button = $PurchaseOverlay/Panel/VBox/CancelButton
@onready var purchase_message_label: Label = $PurchaseOverlay/Panel/VBox/MessageLabel
@onready var options_button: Button = $OptionsButton
@onready var options_overlay: Control = $OptionsOverlay
@onready var options_reset_button: Button = $OptionsOverlay/Panel/VBox/ResetButton
@onready var options_confirm_label: Label = $OptionsOverlay/Panel/VBox/ConfirmLabel
@onready var options_confirm_reset_button: Button = $OptionsOverlay/Panel/VBox/ConfirmResetButton
@onready var options_cancel_reset_button: Button = $OptionsOverlay/Panel/VBox/CancelResetButton
@onready var options_close_button: Button = $OptionsOverlay/Panel/VBox/CloseButton
@onready var restore_iap_button: Button = $OptionsOverlay/Panel/VBox/RestoreIapButton
@onready var remove_iap_button: Button = $OptionsOverlay/Panel/VBox/RemoveIapButton
@onready var iap_message_label: Label = $OptionsOverlay/Panel/VBox/IapMessageLabel
@onready var identity_status_label: Label = $OptionsOverlay/Panel/VBox/IdentityStatusLabel
@onready var identity_sign_in_button: Button = $OptionsOverlay/Panel/VBox/IdentitySignInButton
@onready var identity_sign_out_button: Button = $OptionsOverlay/Panel/VBox/IdentitySignOutButton
@onready var account_prompt_overlay: Control = $AccountPromptOverlay
@onready var account_prompt_sign_in_button: Button = $AccountPromptOverlay/Panel/VBox/SignInButton
@onready var account_prompt_continue_button: Button = $AccountPromptOverlay/Panel/VBox/ContinueButton
@onready var account_prompt_cancel_button: Button = $AccountPromptOverlay/Panel/VBox/CancelButton
@onready var oauth_token_overlay: Control = $OAuthTokenOverlay
@onready var oauth_token_open_button: Button = $OAuthTokenOverlay/Panel/VBox/OpenLoginButton
@onready var oauth_token_cancel_button: Button = $OAuthTokenOverlay/Panel/VBox/CancelButton
@onready var payment_overlay: Control = $PaymentOverlay
@onready var payment_info_label: Label = $PaymentOverlay/Panel/VBox/InfoLabel
@onready var payment_confirm_button: Button = $PaymentOverlay/Panel/VBox/ConfirmButton
@onready var payment_cancel_button: Button = $PaymentOverlay/Panel/VBox/CancelButton
@onready var iap_banner: Button = $IapBanner

## Index of the album whose purchase dialog is currently open (-1 = none).
var _pending_purchase_index: int = -1

## When true, proceed to checkout automatically after a sign-in succeeds
## (set when the player chose "Sign in" from the purchase account prompt).
var _purchase_after_sign_in: bool = false

## True while a payment confirmation is being server-verified: the result of
## the next restore_finished belongs to the payment overlay, not the restore
## button in Options.
var _confirm_verify_pending: bool = false

const STYLE := preload("res://assets/app_style.tres") as AppStyle

const ROUNDED_SHADER := preload("res://assets/rounded_corners.gdshader")

const ALBUM_BUTTON_SCENE := preload("res://album_button.tscn")

## Seconds between album-cover changes. Applied to every album button.
@export var cover_interval: float = 6.0
## Seconds of offset between albums so covers never change simultaneously.
@export var cover_stagger: float = 2.0
## Crossfade duration in seconds (old cover fades out as new fades in).
@export var cover_fade_time: float = 0.8


func _cell_size() -> Vector2:
	var vp_w: float = get_viewport_rect().size.x
	var col_w := (vp_w - STYLE.grid_edge_gap * 2.0 - STYLE.album_grid_separation * (STYLE.grid_columns - 1)) / STYLE.grid_columns
	return Vector2(col_w, col_w)


func _make_rounded_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_SHADER
	mat.set_shader_parameter("corner_radius", STYLE.album_corner_radius)
	mat.set_shader_parameter("control_size", _cell_size())
	return mat


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	purchase_confirm_button.pressed.connect(_on_purchase_confirmed)
	purchase_cancel_button.pressed.connect(_on_purchase_canceled)
	options_button.pressed.connect(_on_options_pressed)
	options_reset_button.pressed.connect(_on_reset_pressed)
	options_confirm_reset_button.pressed.connect(_on_confirm_reset_pressed)
	options_cancel_reset_button.pressed.connect(_on_cancel_reset_pressed)
	options_close_button.pressed.connect(_on_close_options_pressed)
	restore_iap_button.pressed.connect(_on_restore_iap_pressed)
	remove_iap_button.pressed.connect(_on_remove_iap_pressed)
	identity_sign_in_button.pressed.connect(_on_identity_sign_in_pressed)
	identity_sign_out_button.pressed.connect(_on_identity_sign_out_pressed)
	account_prompt_sign_in_button.pressed.connect(_on_account_prompt_sign_in)
	account_prompt_continue_button.pressed.connect(_on_account_prompt_continue)
	account_prompt_cancel_button.pressed.connect(_on_account_prompt_cancel)
	oauth_token_cancel_button.pressed.connect(_on_oauth_token_canceled)
	oauth_token_open_button.pressed.connect(_on_oauth_token_open_pressed)
	IdentityManager.signed_in.connect(_on_identity_signed_in)
	IdentityManager.signed_out.connect(_on_identity_signed_out)
	IdentityManager.sign_in_failed.connect(_on_identity_sign_in_failed)
	IdentityManager.manual_token_required.connect(_on_manual_token_required)
	iap_banner.pressed.connect(_on_iap_banner_pressed)
	IapManager.price_loaded.connect(_on_iap_price_loaded)
	IapManager.purchase_completed.connect(_on_iap_purchase_completed)
	IapManager.became_unavailable.connect(_on_iap_became_unavailable)
	IapManager.restore_finished.connect(_on_iap_restore_finished)
	IapManager.payment_flow_started.connect(_on_iap_payment_flow_started)
	payment_confirm_button.pressed.connect(_on_payment_confirmed)
	payment_cancel_button.pressed.connect(_on_payment_canceled)
	# Restore is only meaningful where billing exists; Remove-IAP is a dev-only
	# test tool (IapManager.TEST_MODE is the same flag that simulates purchases).
	restore_iap_button.visible = IapManager.is_supported()
	remove_iap_button.visible = IapManager.TEST_MODE
	_update_identity_ui()
	_update_iap_banner()
	_build_grid()
	LevelManager.albums_changed.connect(_on_albums_changed)
	LevelManager.downloading_changed.connect(_on_downloading_changed)
	$DownloadLabel.visible = LevelManager.is_downloading()


## Shows the "Unlock All Puzzles" banner only when the platform supports
## Play Billing (or the dev TEST_MODE simulation) and the player has not
## purchased it yet. Two lines: hook question + price.
func _update_iap_banner() -> void:
	if LevelManager.all_puzzles_unlocked or IapManager.is_unavailable():
		iap_banner.visible = false
		return
	iap_banner.visible = IapManager.is_supported()
	var price: String = IapManager.get_price_display()
	if price.is_empty():
		iap_banner.text = "Enjoy the game?\nUnlock all puzzles"
	else:
		iap_banner.text = "Enjoy the game?\nUnlock all puzzles for %s" % price


func _build_grid() -> void:
	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	var count := LevelManager.get_album_count()
	for i in range(count):
		var album: Dictionary = LevelManager.albums[i]
		var cell := ALBUM_BUTTON_SCENE.instantiate() as AlbumButton
		# Apply the exported cover-timer settings so they're tweakable from
		# the album_select scene inspector.
		cell.cover_interval = cover_interval
		cell.cover_stagger = cover_stagger
		cell.cover_fade_time = cover_fade_time
		grid.add_child(cell)
		cell.setup(album, i, _cell_size(), LevelManager.is_album_unlocked(i), LevelManager.get_album_price(i), LevelManager.is_album_downloaded(i), LevelManager.get_album_stars_earned(i), LevelManager.get_album_star_total(i))
		cell.album_selected.connect(_on_album_pressed)


func _on_albums_changed() -> void:
	_build_grid()
	# The album list also changes when the IAP entitlement is granted/removed
	# (unlock_all_albums / remove_unlock_all), so keep the banner in sync.
	_update_iap_banner()


func _on_downloading_changed(downloading: bool) -> void:
	$DownloadLabel.visible = downloading


func _on_album_pressed(index: int) -> void:
	if not LevelManager.is_album_unlocked(index):
		_open_purchase_dialog(index)
		return
	if not LevelManager.is_album_downloaded(index):
		LevelManager.ensure_album_downloaded(index)
		return
	LevelManager.set_album(index)
	get_tree().change_scene_to_file("res://level_select.tscn")


func _open_purchase_dialog(index: int) -> void:
	_pending_purchase_index = index
	var price: int = LevelManager.get_album_price(index)
	var name: String = LevelManager.albums[index]["name"]
	var cur: int = LevelManager.currency
	purchase_info_label.text = "Buy %s?\nCost: %d coins\nYou have: %d" % [name, price, cur]
	if cur < price:
		purchase_confirm_button.disabled = true
		purchase_message_label.text = "Need %d more coins" % (price - cur)
		purchase_message_label.visible = true
	else:
		purchase_confirm_button.disabled = false
		purchase_message_label.visible = false
	purchase_overlay.visible = true


func _on_purchase_confirmed() -> void:
	var ok := LevelManager.purchase_album(_pending_purchase_index)
	purchase_overlay.visible = false
	if ok:
		_build_grid()


func _on_purchase_canceled() -> void:
	purchase_overlay.visible = false


func _on_back_pressed() -> void:
	get_tree().reload_current_scene()


## Opens the options overlay (reset UI hidden initially).
func _on_options_pressed() -> void:
	options_confirm_label.visible = false
	options_confirm_reset_button.visible = false
	options_cancel_reset_button.visible = false
	options_reset_button.visible = true
	iap_message_label.visible = false
	_update_identity_ui()
	options_overlay.visible = true


## Shows the itch.io account section only when an identity source is
## configured. Signed-in players see their username + a sign-out button;
## otherwise a sign-in button.
func _update_identity_ui() -> void:
	var supported: bool = IdentityManager.is_supported()
	identity_status_label.visible = supported
	identity_sign_in_button.visible = supported and not IdentityManager.is_signed_in()
	identity_sign_out_button.visible = supported and IdentityManager.is_signed_in()
	if supported:
		if IdentityManager.is_signed_in():
			identity_status_label.text = "itch.io account: %s" % IdentityManager.get_user_name()
		else:
			identity_status_label.text = "Not signed in"


func _on_identity_sign_in_pressed() -> void:
	identity_status_label.text = "Signing in..."
	IdentityManager.sign_in()


func _on_identity_sign_out_pressed() -> void:
	IdentityManager.sign_out()
	_update_identity_ui()


func _on_identity_signed_in(_user_id: String, _user_name: String) -> void:
	# An auto-relay sign-in may have completed while the paste dialog was up —
	# dismiss it.
	oauth_token_overlay.visible = false
	_update_identity_ui()
	# If the player chose "Sign in" from the purchase prompt, continue to
	# checkout now that the account is active (Android/desktop only — on web the
	# same-window redirect reloads the game, so the player taps the banner again).
	if _purchase_after_sign_in:
		_purchase_after_sign_in = false
		IapManager.purchase_unlock_all()


func _on_identity_signed_out() -> void:
	_update_identity_ui()


func _on_identity_sign_in_failed(reason: String) -> void:
	_update_identity_ui()
	identity_status_label.text = "Sign-in failed: %s" % reason


## The identity source opened an out-of-band authorize page (web iframe
## embeds): show the sign-in dialog. The tab is opened automatically; the
## button below re-opens it if a popup blocker swallowed the auto-open.
func _on_manual_token_required(_url: String) -> void:
	oauth_token_overlay.visible = true


## Re-opens the itch.io login page in a new tab. Called from a direct button
## click so the browser treats it as a real user gesture (the auto-open from
## sign_in can be refused by popup blockers).
func _on_oauth_token_open_pressed() -> void:
	IdentityManager.request_oob_login_page()


func _on_oauth_token_canceled() -> void:
	oauth_token_overlay.visible = false


## Shows the reset confirmation step.
func _on_reset_pressed() -> void:
	options_reset_button.visible = false
	options_confirm_label.visible = true
	options_confirm_reset_button.visible = true
	options_cancel_reset_button.visible = true


## Performs the full progress reset and closes the overlay.
func _on_confirm_reset_pressed() -> void:
	LevelManager.reset_all_progress()
	options_overlay.visible = false
	_build_grid()


## Cancels the reset confirmation, returning to the options list.
func _on_cancel_reset_pressed() -> void:
	options_confirm_label.visible = false
	options_confirm_reset_button.visible = false
	options_cancel_reset_button.visible = false
	options_reset_button.visible = true


func _on_close_options_pressed() -> void:
	options_overlay.visible = false


## ── "Unlock All Puzzles" IAP banner ───────────────────────────────────────


## Re-renders the banner once the localized price arrives from Play.
func _on_iap_price_loaded(_price: String) -> void:
	_update_iap_banner()


## The entitlement became active — hide the banner. The grid itself refreshes
## via LevelManager.albums_changed, which unlock_all_albums() emits.
func _on_iap_purchase_completed() -> void:
	_update_iap_banner()


## Billing is unusable on this device (e.g. no Play Store) — hide the banner.
func _on_iap_became_unavailable() -> void:
	_update_iap_banner()


## The web IAP provider opened a hosted checkout tab — prompt the player to
## confirm once the payment is complete.
func _on_iap_payment_flow_started() -> void:
	payment_overlay.visible = true


## Player confirmed they finished the hosted checkout. The entitlement is NOT
## granted on trust: the provider re-checks with the store server and only then
## grants; this overlay stays up (with status text) until that result arrives.
func _on_payment_confirmed() -> void:
	if LevelManager.all_puzzles_unlocked:
		payment_overlay.visible = false
		return
	_confirm_verify_pending = true
	payment_confirm_button.disabled = true
	payment_info_label.text = "Checking payment..."
	IapManager.confirm_payment()


## Player cancelled the hosted-checkout confirmation.
func _on_payment_canceled() -> void:
	_confirm_verify_pending = false
	payment_confirm_button.disabled = false
	payment_info_label.text = "Complete your payment in the opened tab.\nTap Confirm once it's done."
	payment_overlay.visible = false


## ── Purchase: optional account prompt (itch.io restore) ────────────────────


## Before opening the checkout, players who are not signed in are offered the
## itch.io account so the purchase can follow them to any device. They can
## continue anonymously, but the purchase is then device-tied (warned here).
func _on_iap_banner_pressed() -> void:
	if IdentityManager.is_supported() and not IdentityManager.is_signed_in():
		account_prompt_overlay.visible = true
		return
	IapManager.purchase_unlock_all()


func _on_account_prompt_sign_in() -> void:
	_purchase_after_sign_in = true
	account_prompt_overlay.visible = false
	IdentityManager.sign_in()


func _on_account_prompt_continue() -> void:
	_purchase_after_sign_in = false
	account_prompt_overlay.visible = false
	IapManager.purchase_unlock_all()


func _on_account_prompt_cancel() -> void:
	_purchase_after_sign_in = false
	account_prompt_overlay.visible = false


## ── Options: restore / remove IAP ─────────────────────────────────────────


## Re-checks the active IAP provider for previously purchased entitlements.
func _on_restore_iap_pressed() -> void:
	iap_message_label.text = "Checking purchases..."
	iap_message_label.visible = true
	IapManager.restore_purchases()


## DEV-ONLY test tool: clears the local unlock-all flag so the purchase flow
## can be tested again (button hidden unless IapManager.TEST_MODE is on).
func _on_remove_iap_pressed() -> void:
	IapManager.remove_all_unlock_entitlement()
	iap_message_label.text = "Unlock-all removed (local only)."
	iap_message_label.visible = true


## Shows the restore outcome. On a successful restore the entitlement is
## granted by the IAP provider (albums_changed refreshes the grid + banner).
## Also carries the payment-confirmation result (server-backed verify).
func _on_iap_restore_finished(result: int) -> void:
	if _confirm_verify_pending:
		_confirm_verify_pending = false
		payment_confirm_button.disabled = false
		payment_info_label.text = "Complete your payment in the opened tab.\nTap Confirm once it's done."
		match result:
			IapProvider.RestoreResult.RESTORED:
				payment_overlay.visible = false
			IapProvider.RestoreResult.NOT_FOUND:
				payment_info_label.text = "Payment not detected yet.\nComplete it in the opened tab, wait a moment, then tap Confirm again."
			IapProvider.RestoreResult.UNAVAILABLE:
				payment_info_label.text = "Could not reach the store.\nCheck your connection, then tap Confirm again."
		return
	match result:
		IapProvider.RestoreResult.RESTORED:
			iap_message_label.text = "Purchases restored!"
		IapProvider.RestoreResult.NOT_FOUND:
			iap_message_label.text = "No previous purchases found."
		IapProvider.RestoreResult.UNAVAILABLE:
			iap_message_label.text = "Could not reach the store."
	iap_message_label.visible = true


func _exit_tree() -> void:
	if back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.disconnect(_on_back_pressed)
	if iap_banner.pressed.is_connected(_on_iap_banner_pressed):
		iap_banner.pressed.disconnect(_on_iap_banner_pressed)
	if restore_iap_button.pressed.is_connected(_on_restore_iap_pressed):
		restore_iap_button.pressed.disconnect(_on_restore_iap_pressed)
	if remove_iap_button.pressed.is_connected(_on_remove_iap_pressed):
		remove_iap_button.pressed.disconnect(_on_remove_iap_pressed)
	if identity_sign_in_button.pressed.is_connected(_on_identity_sign_in_pressed):
		identity_sign_in_button.pressed.disconnect(_on_identity_sign_in_pressed)
	if identity_sign_out_button.pressed.is_connected(_on_identity_sign_out_pressed):
		identity_sign_out_button.pressed.disconnect(_on_identity_sign_out_pressed)
	if account_prompt_sign_in_button.pressed.is_connected(_on_account_prompt_sign_in):
		account_prompt_sign_in_button.pressed.disconnect(_on_account_prompt_sign_in)
	if account_prompt_continue_button.pressed.is_connected(_on_account_prompt_continue):
		account_prompt_continue_button.pressed.disconnect(_on_account_prompt_continue)
	if account_prompt_cancel_button.pressed.is_connected(_on_account_prompt_cancel):
		account_prompt_cancel_button.pressed.disconnect(_on_account_prompt_cancel)
	if IdentityManager.signed_in.is_connected(_on_identity_signed_in):
		IdentityManager.signed_in.disconnect(_on_identity_signed_in)
	if IdentityManager.signed_out.is_connected(_on_identity_signed_out):
		IdentityManager.signed_out.disconnect(_on_identity_signed_out)
	if IdentityManager.sign_in_failed.is_connected(_on_identity_sign_in_failed):
		IdentityManager.sign_in_failed.disconnect(_on_identity_sign_in_failed)
	if IdentityManager.manual_token_required.is_connected(_on_manual_token_required):
		IdentityManager.manual_token_required.disconnect(_on_manual_token_required)
	if oauth_token_cancel_button.pressed.is_connected(_on_oauth_token_canceled):
		oauth_token_cancel_button.pressed.disconnect(_on_oauth_token_canceled)
	if oauth_token_open_button.pressed.is_connected(_on_oauth_token_open_pressed):
		oauth_token_open_button.pressed.disconnect(_on_oauth_token_open_pressed)
	if IapManager.price_loaded.is_connected(_on_iap_price_loaded):
		IapManager.price_loaded.disconnect(_on_iap_price_loaded)
	if IapManager.purchase_completed.is_connected(_on_iap_purchase_completed):
		IapManager.purchase_completed.disconnect(_on_iap_purchase_completed)
	if IapManager.became_unavailable.is_connected(_on_iap_became_unavailable):
		IapManager.became_unavailable.disconnect(_on_iap_became_unavailable)
	if IapManager.restore_finished.is_connected(_on_iap_restore_finished):
		IapManager.restore_finished.disconnect(_on_iap_restore_finished)
	if IapManager.payment_flow_started.is_connected(_on_iap_payment_flow_started):
		IapManager.payment_flow_started.disconnect(_on_iap_payment_flow_started)
	if payment_confirm_button.pressed.is_connected(_on_payment_confirmed):
		payment_confirm_button.pressed.disconnect(_on_payment_confirmed)
	if payment_cancel_button.pressed.is_connected(_on_payment_canceled):
		payment_cancel_button.pressed.disconnect(_on_payment_canceled)
	if purchase_confirm_button.pressed.is_connected(_on_purchase_confirmed):
		purchase_confirm_button.pressed.disconnect(_on_purchase_confirmed)
	if purchase_cancel_button.pressed.is_connected(_on_purchase_canceled):
		purchase_cancel_button.pressed.disconnect(_on_purchase_canceled)
	if options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.disconnect(_on_options_pressed)
	if options_reset_button.pressed.is_connected(_on_reset_pressed):
		options_reset_button.pressed.disconnect(_on_reset_pressed)
	if options_confirm_reset_button.pressed.is_connected(_on_confirm_reset_pressed):
		options_confirm_reset_button.pressed.disconnect(_on_confirm_reset_pressed)
	if options_cancel_reset_button.pressed.is_connected(_on_cancel_reset_pressed):
		options_cancel_reset_button.pressed.disconnect(_on_cancel_reset_pressed)
	if options_close_button.pressed.is_connected(_on_close_options_pressed):
		options_close_button.pressed.disconnect(_on_close_options_pressed)
	if LevelManager.albums_changed.is_connected(_on_albums_changed):
		LevelManager.albums_changed.disconnect(_on_albums_changed)
	if LevelManager.downloading_changed.is_connected(_on_downloading_changed):
		LevelManager.downloading_changed.disconnect(_on_downloading_changed)
