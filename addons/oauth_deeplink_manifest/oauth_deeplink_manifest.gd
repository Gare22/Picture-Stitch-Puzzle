@tool
extends EditorPlugin

# Registers an EditorExportPlugin that re-injects the itch.io OAuth return
# intent-filter (picturepuzzle://callback) into the generated Android
# manifest on every export.
#
# This is the official, upgrade-safe mechanism for Android manifest
# customization in Godot 4.2+ (see EditorExportPlugin._get_android_manifest_activity_element_contents).
# Editing android/build/src/debug|release/AndroidManifest.xml directly does
# NOT work: the Android export regenerates those files on every export.

# A class member to hold the editor export plugin during its lifecycle.
var export_plugin: OauthDeepLinkManifestExportPlugin


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	export_plugin = OauthDeepLinkManifestExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	remove_export_plugin(export_plugin)
	export_plugin = null


class OauthDeepLinkManifestExportPlugin extends EditorExportPlugin:
	# The itch.io OAuth implicit flow delivers the token in the URL fragment
	# (scheme://callback#access_token=...&state=...). Android intents carry the
	# full URI including the fragment, so the app-side handler must parse the
	# fragment first (see itch_identity_source.gd). GodotApp.java forwards the
	# URI to the game via user://deep_link_uri.txt.
	const _ACTIVITY_MANIFEST_CONTENT := """\
<intent-filter>
	<action android:name="android.intent.action.VIEW" />
	<category android:name="android.intent.category.DEFAULT" />
	<category android:name="android.intent.category.BROWSABLE" />
	<data android:scheme="picturepuzzle" android:host="callback" />
</intent-filter>"""

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_manifest_activity_element_contents(platform, debug) -> String:
		return _ACTIVITY_MANIFEST_CONTENT

	func _get_name() -> String:
		return "OAuthDeepLinkManifest"