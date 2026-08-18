extends Node

## Editor-only helper for mobile testing: sizes each multi-instance run to a
## different mobile profile so the UI can be checked across phone/tablet sizes.
## Enabled via Debug > Run Multiple Instances in the editor.
## Does nothing in exported builds (the editor feature flag is absent there).

const MOBILE_PROFILES := {
	1: Vector2i(390, 844),   # Instance 1: iPhone 13/14 Pro
	2: Vector2i(412, 915),   # Instance 2: Google Pixel 7/8
	3: Vector2i(360, 800),   # Instance 3: Standard Samsung Galaxy
	4: Vector2i(768, 1024),  # Instance 4: iPad Mini / Tablet
}

func _ready() -> void:
	if OS.has_feature("editor"):
		_adjust_window_size_for_debug_instance()


func _adjust_window_size_for_debug_instance() -> void:
	# Godot passes --multirun-index starting from 0; +1 maps to MOBILE_PROFILES.
	var instance_index: int = -1  # -1 = not a multi-instance run; keep the project's default resolution

	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		var arg: String = args[i]
		if arg == "--multirun-index" and i + 1 < args.size():
			instance_index = args[i + 1].to_int() + 1
			break
		elif arg.begins_with("--multirun-index="):
			instance_index = arg.get_slice("=", 1).to_int() + 1
			break

	if MOBILE_PROFILES.has(instance_index):
		var target_size: Vector2i = MOBILE_PROFILES[instance_index]
		DisplayServer.window_set_size(target_size)
		print("DebugWindow: instance %d -> %dx%d" % [instance_index, target_size.x, target_size.y])

		# Stagger positions so instances don't stack on top of each other
		var screen_offset := Vector2i((instance_index - 1) * 450, 100)
		DisplayServer.window_set_position(screen_offset)
