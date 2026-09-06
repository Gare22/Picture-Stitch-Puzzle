class_name AlbumButton
extends Control

## A single album cover cell in the album select grid.
## Shows a crossfading cover image, the album name, and a click button.

signal album_selected(album_index: int)

const STYLE := preload("res://assets/app_style.tres") as AppStyle
const ROUNDED_SHADER := preload("res://assets/rounded_corners.gdshader")

## Seconds between cover changes per album.
@export var cover_interval: float = 6.0
## Seconds of offset between albums so covers never change simultaneously.
@export var cover_stagger: float = 2.0
## Crossfade duration in seconds (old cover fades out as new fades in).
@export var cover_fade_time: float = 0.8

## Index of the album this cell represents.
var album_index: int = -1
var _levels: Array = []
## True when this album is locked; covers are shown grayed out.
var _grayed: bool = false

@onready var name_label = $ClickButton/NameLabel
@onready var star_hud = $StarHud
@onready var star_count_label = $StarHud/StarCountLabel

## Initializer: sets the cover image, name, rounded material, and starts the cover timer.
## Locked albums show the lock overlay with the purchase price, and their covers
## are grayed out (the images are downloaded so the player can preview them).
## stars_earned/stars_total feed the "earned/total" star badge shown top-right.
func setup(album: Dictionary, index: int, cell_size: Vector2, unlocked: bool, price: int, downloaded: bool, stars_earned: int = 0, stars_total: int = 0) -> void:
	album_index = index
	custom_minimum_size = cell_size
	_grayed = not unlocked
	# Locked albums use the lower-res previews for the cover (falling back to
	# the full images when the catalog provides no previews); unlocked albums
	# always use the full images.
	if not unlocked:
		var previews: Array = album.get("preview_paths", [])
		if previews.size() > 0:
			_levels = previews
		else:
			_levels = album["levels"]
	else:
		_levels = album["levels"]
	var cover_old: TextureRect = $CoverOld
	var cover_new: TextureRect = $CoverNew
	# Use the first puzzle image as the cover (rotates through all images)
	var cover_path: String = ""
	if _levels.size() > 0:
		cover_path = _levels[0]["path"]
	cover_old.texture = _load_texture(cover_path)
	cover_old.modulate = Color(0.55, 0.55, 0.55, 1.0) if _grayed else Color.WHITE
	cover_old.material = _make_rounded_material(cell_size)
	cover_new.material = _make_rounded_material(cell_size)
	name_label.text = album["name"]
	# Star badge: only meaningful once the album is unlocked and has puzzles.
	star_count_label.text = "%d/%d" % [stars_earned, stars_total]
	star_hud.visible = unlocked and stars_total > 0
	if not unlocked:
		$LockOverlay.visible = true
		$LockOverlay/LockLabel.text = "Locked"
		$LockOverlay/PriceLabel.text = "%d" % price
		# Locked covers still rotate through the (grayed) images
		if _levels.size() > 1:
			$CoverTimer.wait_time = cover_interval + float(index) * cover_stagger
			$CoverTimer.start()
	elif not downloaded:
		$LockOverlay.visible = true
		$LockOverlay/LockLabel.text = "Downloading..."
		$LockOverlay/PriceLabel.text = ""
	else:
		$LockOverlay.visible = false
		if _levels.size() > 1:
			$CoverTimer.wait_time = cover_interval + float(index) * cover_stagger
			$CoverTimer.start()
	$ClickButton.pressed.connect(_on_click_pressed)


func _make_rounded_material(cell_size: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_SHADER
	mat.set_shader_parameter("corner_radius", STYLE.album_corner_radius)
	mat.set_shader_parameter("control_size", cell_size)
	return mat


## Updates the cell size after a viewport resize: fixes the minimum size and
## the rounded-corner shader's control_size, without reloading any textures.
func resize_to(cell_size: Vector2) -> void:
	custom_minimum_size = cell_size
	if $CoverOld.material != null:
		$CoverOld.material.set_shader_parameter("control_size", cell_size)
	if $CoverNew.material != null:
		$CoverNew.material.set_shader_parameter("control_size", cell_size)


## Loads a texture from a path, handling both res:// (imported) and user:// (runtime) paths.
## Uses ResourceLoader for res:// paths because FileAccess.file_exists() fails
## on exported builds (imported resources are remapped to .ctex and the raw
## source file is not present).
func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path) as Texture2D
	# user:// or absolute path — use Image API for runtime-downloaded images
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty() or img.get_width() == 0:
		return null
	# Generate mipmaps so downscaled rendering (album covers, puzzle pieces)
	# looks as smooth as imported res:// textures, which get mipmaps from the
	# import pipeline automatically.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _on_click_pressed() -> void:
	album_selected.emit(album_index)


func _on_cover_timeout() -> void:
	var idx: int = get_meta("cover_index", 0)
	idx = (idx + 1) % _levels.size()
	set_meta("cover_index", idx)

	var next_tex = _load_texture(_levels[idx]["path"])
	if next_tex == null:
		return
	var cover_old: TextureRect = $CoverOld
	var cover_new: TextureRect = $CoverNew
	cover_new.texture = next_tex
	# Keep locked covers grayed out during rotation
	if _grayed:
		cover_new.modulate = Color(0.55, 0.55, 0.55, 0.0)
	else:
		cover_new.modulate = Color(1, 1, 1, 0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(cover_new, "modulate:a", 1.0, cover_fade_time)
	tween.tween_property(cover_old, "modulate:a", 0.0, cover_fade_time)
	tween.chain().tween_callback(func() -> void:
		cover_old.texture = cover_new.texture
		cover_old.modulate.a = 1.0
		cover_new.modulate.a = 0.0
	)

	$CoverTimer.wait_time = cover_interval


func _ready() -> void:
	$CoverTimer.timeout.connect(_on_cover_timeout)


func _exit_tree() -> void:
	if $ClickButton.pressed.is_connected(_on_click_pressed):
		$ClickButton.pressed.disconnect(_on_click_pressed)
