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

## Index of the album whose purchase dialog is currently open (-1 = none).
var _pending_purchase_index: int = -1

const STYLE := preload("res://assets/app_style.tres") as AppStyle

const ROUNDED_SHADER := preload("res://assets/rounded_corners.gdshader")

const ALBUM_BUTTON_SCENE := preload("res://album_button.tscn")


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
	_build_grid()


func _build_grid() -> void:
	# Clear any existing children
	for child in grid.get_children():
		child.queue_free()

	var count := LevelManager.get_album_count()
	for i in range(count):
		var album: Dictionary = LevelManager.albums[i]
		var cell := ALBUM_BUTTON_SCENE.instantiate() as AlbumButton
		grid.add_child(cell)
		cell.setup(album, i, _cell_size(), LevelManager.is_album_unlocked(i), LevelManager.get_album_price(i))
		cell.album_selected.connect(_on_album_pressed)


func _on_album_pressed(index: int) -> void:
	if LevelManager.is_album_unlocked(index):
		LevelManager.set_album(index)
		get_tree().change_scene_to_file("res://level_select.tscn")
	else:
		_open_purchase_dialog(index)


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


func _exit_tree() -> void:
	if back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.disconnect(_on_back_pressed)
	if purchase_confirm_button.pressed.is_connected(_on_purchase_confirmed):
		purchase_confirm_button.pressed.disconnect(_on_purchase_confirmed)
	if purchase_cancel_button.pressed.is_connected(_on_purchase_canceled):
		purchase_cancel_button.pressed.disconnect(_on_purchase_canceled)
