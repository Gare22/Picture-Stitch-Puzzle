extends Node

## Editor-only helper for mobile testing: sizes each run instance to a mobile
## profile so the UI can be checked across phone/tablet sizes.
##
## Setup: Debug > Customize Run Instances... in the editor. Enable multiple
## instances, set the count, and in each instance row's "Launch Arguments"
## column enter --profile=1, --profile=2, --profile=3, --profile=4 (one per
## instance). Leave "Override Main Run Args" unchecked so the shared Main Run
## Args still apply. The script reads --profile from the command line and
## sizes the window accordingly. Runs without a --profile arg keep the
## project's default resolution. Does nothing in exported builds (the editor
## feature flag is absent there).

const MOBILE_PROFILES := {
	1: Vector2i(390, 844),   # Profile 1: iPhone 13/14 (non-Pro)
	2: Vector2i(412, 915),   # Profile 2: Google Pixel 7/8
	3: Vector2i(360, 800),   # Profile 3: Standard Samsung Galaxy
	4: Vector2i(768, 1024),  # Profile 4: iPad Mini / Tablet
}

func _ready() -> void:
	if OS.has_feature("editor"):
		_adjust_window_size_for_debug_instance()


func _adjust_window_size_for_debug_instance() -> void:
	var profile_index: int = _find_profile_index()
	if MOBILE_PROFILES.has(profile_index):
		var target_size: Vector2i = MOBILE_PROFILES[profile_index]
		DisplayServer.window_set_size(target_size)
		print("DebugWindow: profile %d -> %dx%d" % [profile_index, target_size.x, target_size.y])

		# Stagger positions so instances don't stack on top of each other
		var screen_offset := Vector2i((profile_index - 1) * 450, 100)
		DisplayServer.window_set_position(screen_offset)


## Reads --profile=N (or --profile N) from the command line, checking both the
## regular args and the user args (after --). Returns -1 if absent.
func _find_profile_index() -> int:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for i in range(args.size()):
		var arg: String = args[i]
		if arg == "--profile" and i + 1 < args.size():
			return args[i + 1].to_int()
		elif arg.begins_with("--profile="):
			return arg.get_slice("=", 1).to_int()
	return -1
