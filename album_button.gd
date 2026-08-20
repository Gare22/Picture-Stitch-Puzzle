class_name AlbumButton
extends Control

## A single album cover cell in the album select grid.
## Shows a crossfading cover image, the album name, and a click button.

signal album_selected(album_index: int)

const STYLE := preload("res://assets/app_style.tres") as AppStyle
const ROUNDED_SHADER := preload("res://assets/rounded_corners.gdshader")

## Seconds between cover changes per album.
const COVER_INTERVAL := 15.0
## Seconds of offset between albums so covers never change simultaneously.
const COVER_STAGGER := 5.0
## Crossfade duration in seconds (old cover fades out as new fades in).
const COVER_FADE_TIME := 1.0

## Index of the album this cell represents.
var album_index: int = -1
var _levels: Array = []

@onready var name_label = $ClickButton/NameLabel

## Initializer: sets the cover image, name, rounded material, and starts the cover timer.
## Locked albums show the lock overlay with the purchase price instead.
func setup(album: Dictionary, index: int, cell_size: Vector2, unlocked: bool, price: int) -> void:
	album_index = index
	custom_minimum_size = cell_size
	_levels = album["levels"]
	var cover_old: TextureRect = $CoverOld
	var cover_new: TextureRect = $CoverNew
	cover_old.texture = load(album["thumbnail_path"]) as Texture2D
	cover_old.material = _make_rounded_material(cell_size)
	cover_new.material = _make_rounded_material(cell_size)
	name_label.text = album["name"]
	if unlocked:
		$LockOverlay.visible = false
		if _levels.size() > 1:
			$CoverTimer.wait_time = COVER_INTERVAL + float(index) * COVER_STAGGER
			$CoverTimer.start()
	else:
		$LockOverlay.visible = true
		$LockOverlay/PriceLabel.text = "%d" % price
	$ClickButton.pressed.connect(_on_click_pressed)


func _make_rounded_material(cell_size: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_SHADER
	mat.set_shader_parameter("corner_radius", STYLE.album_corner_radius)
	mat.set_shader_parameter("control_size", cell_size)
	return mat


func _on_click_pressed() -> void:
	album_selected.emit(album_index)


func _on_cover_timeout() -> void:
	var idx: int = get_meta("cover_index", 0)
	idx = (idx + 1) % _levels.size()
	set_meta("cover_index", idx)

	var next_tex = load(_levels[idx]["path"]) as Texture2D
	if next_tex == null:
		return
	var cover_old: TextureRect = $CoverOld
	var cover_new: TextureRect = $CoverNew
	cover_new.texture = next_tex

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cover_new, "modulate:a", 1.0, COVER_FADE_TIME)
	tween.tween_property(cover_old, "modulate:a", 0.0, COVER_FADE_TIME)
	tween.chain().tween_callback(func() -> void:
		cover_old.texture = cover_new.texture
		cover_old.modulate.a = 1.0
		cover_new.modulate.a = 0.0
	)

	$CoverTimer.wait_time = COVER_INTERVAL


func _ready() -> void:
	$CoverTimer.timeout.connect(_on_cover_timeout)


func _exit_tree() -> void:
	if $ClickButton.pressed.is_connected(_on_click_pressed):
		$ClickButton.pressed.disconnect(_on_click_pressed)
