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

## Index of the album whose purchase dialog is currently open (-1 = none).
var _pending_purchase_index: int = -1

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
	_build_grid()
	LevelManager.albums_changed.connect(_on_albums_changed)
	LevelManager.downloading_changed.connect(_on_downloading_changed)
	$DownloadLabel.visible = LevelManager.is_downloading()


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
		cell.setup(album, i, _cell_size(), LevelManager.is_album_unlocked(i), LevelManager.get_album_price(i), LevelManager.is_album_downloaded(i))
		cell.album_selected.connect(_on_album_pressed)


func _on_albums_changed() -> void:
	_build_grid()


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
	options_overlay.visible = true


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


func _exit_tree() -> void:
	if back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.disconnect(_on_back_pressed)
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
