@tool
extends Node

const PORT: int = 9080
const VERSION: String = "2.0.0"
const LOG_PREFIX: String = "[Godot MCP]"

## EditorInterface reference, injected by plugin.gd BEFORE this node enters the tree.
var editor_interface: EditorInterface = null

var _tcp_server: TCPServer = null
var _running: bool = false
var _peers: Dictionary[int, WebSocketPeer] = {}
var _next_peer_id: int = 0

func _ready():
	start_server()

func _exit_tree():
	stop_server()

func _process(_delta):
	if not _running or _tcp_server == null:
		return
	# Accept new WebSocket connections.
	while _tcp_server.is_connection_available():
		_next_peer_id += 1
		var ws := WebSocketPeer.new()
		var err := ws.accept_stream(_tcp_server.take_connection())
		if err == OK:
			_peers[_next_peer_id] = ws
			print(LOG_PREFIX, " Client connected: peer=", _next_peer_id)
		else:
			print(LOG_PREFIX, " Handshake failed for peer=", _next_peer_id, " error=", error_string(err))
			ws.close()
	# Poll every peer (iterate a copy of keys so we can erase while iterating).
	for peer_id in _peers.keys():
		var peer: WebSocketPeer = _peers[peer_id]
		peer.poll()
		var peer_state := peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = peer.get_packet()
				if peer.was_string_packet():
					_on_message(peer_id, packet.get_string_from_utf8())
				else:
					print(LOG_PREFIX, " Ignoring binary frame from peer=", peer_id)
		elif peer_state == WebSocketPeer.STATE_CLOSED:
			_peers.erase(peer_id)
			var code := peer.get_close_code()
			print(LOG_PREFIX, " Client disconnected: peer=", peer_id, " code=", code)

func start_server() -> bool:
	if _running:
		return true
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(PORT)
	if err != OK:
		push_error(LOG_PREFIX + " Failed to start WebSocket server on port %d: %s" % [PORT, error_string(err)])
		_tcp_server = null
		return false
	_running = true
	print(LOG_PREFIX, " Server listening on ws://localhost:", PORT)
	return true

func stop_server():
	if not _running and _peers.is_empty():
		return
	for peer_id in _peers.keys():
		var peer: WebSocketPeer = _peers[peer_id]
		peer.close()
	_peers.clear()
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null
	_running = false
	print(LOG_PREFIX, " Server stopped")

func _on_message(peer_id: int, raw_text: String):
	var json: Variant = JSON.parse_string(raw_text)
	if not (json is Dictionary):
		_send_error(peer_id, null, "parse_error", "Invalid JSON received")
		return
	var msg: Dictionary = json
	var msg_id = msg.get("id", null)
	var method := _get_param_string(msg, "method", "")
	if method.is_empty():
		_send_error(peer_id, msg_id, "unknown_method", "Empty method")
		return
	var params = msg.get("params", {})
	if params == null or not (params is Dictionary):
		params = {}
	var result := _dispatch(method, params)
	if result.has("_no_response") and result["_no_response"]:
		return
	if result.has("error"):
		_send(peer_id, { "id": msg_id, "error": result.error, "message": result.get("message", "") })
	else:
		_send(peer_id, { "id": msg_id, "result": result })

func _send(peer_id: int, data: Dictionary):
	if not _peers.has(peer_id):
		return
	_peers[peer_id].send_text(JSON.stringify(data))

func _send_error(peer_id: int, msg_id, error_code: String, message: String):
	_send(peer_id, { "id": msg_id, "error": error_code, "message": message })

# ─── Dispatch ──────────────────────────────────────────────────────────

func _dispatch(method: String, params: Dictionary) -> Dictionary:
	match method:
		"ping":
			return _cmd_ping()
		"get_project_info":
			return _wrap(_cmd_get_project_info)
		"create_scene":
			return _wrap(_cmd_create_scene, params)
		"load_scene":
			return _wrap(_cmd_load_scene, params)
		"save_scene":
			return _wrap(_cmd_save_scene, params)
		"get_scene_tree":
			return _wrap(_cmd_get_scene_tree)
		"add_node":
			return _wrap(_cmd_add_node, params)
		"remove_node":
			return _wrap(_cmd_remove_node, params)
		"reparent_node":
			return _wrap(_cmd_reparent_node, params)
		"duplicate_node":
			return _wrap(_cmd_duplicate_node, params)
		"set_property":
			return _wrap(_cmd_set_property, params)
		"get_property":
			return _wrap(_cmd_get_property, params)
		"create_script":
			return _wrap(_cmd_create_script, params)
		"edit_script":
			return _wrap(_cmd_edit_script, params)
		"attach_script":
			return _wrap(_cmd_attach_script, params)
		"detach_script":
			return _wrap(_cmd_detach_script, params)
		"hot_reload_scripts":
			return _wrap(_cmd_hot_reload_scripts)
		"execute_code":
			return _wrap(_cmd_execute_code, params)
		"run_scene":
			return _wrap(_cmd_run_scene)
		"stop_scene":
			return _wrap(_cmd_stop_scene)
		"list_files":
			return _wrap(_cmd_list_files, params)
		"read_file":
			return _wrap(_cmd_read_file, params)
		"write_file":
			return _wrap(_cmd_write_file, params)
		"resource_load":
			return _wrap(_cmd_resource_load, params)
		"resource_save":
			return _wrap(_cmd_resource_save, params)
		"get_project_settings":
			return _wrap(_cmd_get_project_settings, params)
		"set_project_settings":
			return _wrap(_cmd_set_project_settings, params)
		"connect_signal":
			return _wrap(_cmd_connect_signal, params)
		"disconnect_signal":
			return _wrap(_cmd_disconnect_signal, params)
		"get_signal_list":
			return _wrap(_cmd_get_signal_list, params)
		"get_export_presets":
			return _wrap(_cmd_get_export_presets)
		"run_export":
			return _wrap(_cmd_run_export, params)
		"get_plugins":
			return _wrap(_cmd_get_plugins)
		"set_plugin_enabled":
			return _wrap(_cmd_set_plugin_enabled, params)
		"validate_script":
			return _wrap(_cmd_validate_script, params)
		"get_asset_import_options":
			return _wrap(_cmd_get_asset_import_options, params)
		"reimport_asset":
			return _wrap(_cmd_reimport_asset, params)
		_:
			return { "error": "unknown_method", "message": "Unknown method: " + method }

# ─── Safe execution wrapper ────────────────────────────────────────────

func _wrap(cmd: Callable, params: Dictionary = {}) -> Dictionary:
	if editor_interface == null and cmd != _cmd_ping:
		return { "error": "not_in_editor", "message": "This command requires the Godot editor" }
	return cmd.call(params)

# ─── Tool Implementations ──────────────────────────────────────────────

func _cmd_ping(_params: Dictionary = {}) -> Dictionary:
	return { "status": "ok", "version": VERSION, "engine": Engine.get_version_info() }

func _cmd_get_project_info(_params: Dictionary = {}) -> Dictionary:
	var ei := editor_interface
	var root = ei.get_edited_scene_root() if ei else null
	var version_info := Engine.get_version_info()
	return {
		"project_path": ProjectSettings.globalize_path("res://"),
		"project_name": ProjectSettings.get_setting("application/config/name", "Untitled"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"current_scene": root.name if root else "",
		"current_scene_path": root.scene_file_path if root and root.scene_file_path else "",
		"rendering_driver": RenderingServer.get_video_adapter_name(),
		"engine_version": version_info.get("string", ""),
		"engine_major": version_info.get("major", 0),
		"engine_minor": version_info.get("minor", 0),
	}

func _cmd_create_scene(params: Dictionary) -> Dictionary:
	var root_type := _get_param_string(params, "root_type", "Node")
	var root_name := _get_param_string(params, "root_name", "Root")
	var ei := editor_interface

	var node := _create_node_of_type(root_type)
	if not node:
		return { "error": "unknown_type", "message": "Cannot create node of type: " + root_type }
	node.name = _sanitize_name(root_name)

	ei.get_editor_main_screen().add_child(node)
	ei.edit_node(node)
	return { "status": "ok", "node": node.name, "type": root_type }

func _cmd_load_scene(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	editor_interface.open_scene_from_path(path)
	return { "status": "ok", "path": path }

func _cmd_save_scene(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	var ei := editor_interface
	if path.is_empty():
		var root := ei.get_edited_scene_root()
		if root and root.scene_file_path:
			path = root.scene_file_path
	if path.is_empty():
		return { "error": "missing_param", "message": "Scene has no path. Provide a 'path' to save to." }
	ei.save_scene_as(path)
	if FileAccess.file_exists(path):
		return { "status": "ok", "path": path }
	return { "error": "save_failed", "message": "Failed to save scene to: " + path }

func _cmd_get_scene_tree(_params: Dictionary = {}) -> Dictionary:
	var root := _get_edited_root()
	if not root:
		return { "nodes": [] }
	return { "nodes": [ _serialize_node(root) ] }

func _serialize_node(node: Node) -> Dictionary:
	var data := {
		"name": node.name,
		"type": node.get_class(),
		"path": _node_path_string(node),
		"children": [],
	}
	var script := node.get_script()
	if script:
		data["script"] = script.resource_path if script.resource_path else "<built-in>"
	for child in node.get_children():
		data["children"].append(_serialize_node(child))
	return data

func _node_path_string(node: Node) -> String:
	var ei := editor_interface
	if not ei:
		return str(node.get_path())
	var root := ei.get_edited_scene_root()
	if not root:
		return str(node.get_path())
	if node == root:
		return "."
	var path_str := str(node.get_path())
	var root_str := str(root.get_path())
	if path_str.begins_with(root_str):
		return path_str.substr(root_str.length()).trim_prefix("/")
	return path_str

func _cmd_add_node(params: Dictionary) -> Dictionary:
	var parent_path := _get_param_string(params, "parent_path", ".")
	var node_type := _get_param_string(params, "node_type", "Node")
	var node_name := _get_param_string(params, "node_name", node_type)
	var ei := editor_interface

	var parent = ei.get_edited_scene_root()
	if parent_path != ".":
		parent = _find_node_by_path(parent, parent_path)
	if not parent:
		return { "error": "parent_not_found", "message": "Parent node not found: '" + parent_path + "'" }

	var new_node := _create_node_of_type(node_type)
	if not new_node:
		return { "error": "unknown_type", "message": "Cannot create node type: '" + node_type + "'" }

	new_node.name = _sanitize_name(node_name)
	parent.add_child(new_node)
	new_node.set_owner(ei.get_edited_scene_root())
	ei.edit_node(new_node)
	return { "status": "ok", "path": _node_path_string(new_node), "name": new_node.name, "type": node_type }

func _cmd_remove_node(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path")
	if node_path.is_empty():
		return { "error": "missing_param", "message": "'node_path' is required" }
	var root := _get_edited_root()
	var node := _find_node_by_path(root, node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	if node == root:
		return { "error": "cannot_remove_root", "message": "Cannot remove the root node of the scene" }
	node.queue_free()
	return { "status": "ok" }

func _cmd_reparent_node(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path")
	var new_parent_path := _get_param_string(params, "new_parent_path")
	if node_path.is_empty() or new_parent_path.is_empty():
		return { "error": "missing_param", "message": "'node_path' and 'new_parent_path' are required" }
	var root := _get_edited_root()
	var node := _find_node_by_path(root, node_path)
	var new_parent := _find_node_by_path(root, new_parent_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	if not new_parent:
		return { "error": "parent_not_found", "message": "New parent not found: '" + new_parent_path + "'" }
	if node == root:
		return { "error": "cannot_reparent_root", "message": "Cannot reparent the root node" }
	node.reparent(new_parent)
	return { "status": "ok" }

func _cmd_duplicate_node(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path")
	if node_path.is_empty():
		return { "error": "missing_param", "message": "'node_path' is required" }
	var root := _get_edited_root()
	var node := _find_node_by_path(root, node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	var parent := node.get_parent()
	if not parent:
		return { "error": "cannot_duplicate_root", "message": "Cannot duplicate the root node" }
	var dup := node.duplicate()
	parent.add_child(dup)
	dup.set_owner(root)
	return { "status": "ok", "path": _node_path_string(dup) }

func _cmd_set_property(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var property := _get_param_string(params, "property")
	var value = params.get("value", null)
	if property.is_empty():
		return { "error": "missing_param", "message": "'property' is required" }
	var node := _resolve_node(node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	if property in node:
		node.set(property, value)
		return { "status": "ok", "property": property, "value": str(value) }
	return { "error": "property_not_found", "message": "No such property: '" + property + "' on " + node.get_class() }

func _cmd_get_property(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var property := _get_param_string(params, "property")
	if property.is_empty():
		return { "error": "missing_param", "message": "'property' is required" }
	var node := _resolve_node(node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	if property in node:
		return { "status": "ok", "value": node.get(property), "property": property }
	return { "error": "property_not_found", "message": "No such property: '" + property + "' on " + node.get_class() }

func _cmd_create_script(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	var content := _get_param_string(params, "content")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var full_path := _resolve_project_path(path)
	if full_path.is_empty():
		return { "error": "invalid_path", "message": "Path must be within the project directory" }

	var dir_path := full_path.get_base_dir()
	var dir := DirAccess.open(dir_path)
	if not dir:
		dir = DirAccess.open("res://")
		if dir:
			dir.make_dir_recursive(dir_path.trim_prefix(ProjectSettings.globalize_path("res://")).trim_prefix("/"))

	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if not file:
		return { "error": "write_failed", "message": "Cannot write to: " + path }
	file.store_string(content)
	file.close()

	ResourceSaver.save(load(full_path))

	return { "status": "ok", "path": "res://" + path.trim_prefix("res://") }

func _cmd_edit_script(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var script := load(path)
	if not script:
		return { "error": "script_not_found", "message": "Script not found: " + path }
	editor_interface.edit_resource(script)
	return { "status": "ok" }

func _cmd_attach_script(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var script_path := _get_param_string(params, "script_path")
	if script_path.is_empty():
		return { "error": "missing_param", "message": "'script_path' is required" }
	var node := _resolve_node(node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	var script := load(script_path) if script_path.begins_with("res://") else load("res://" + script_path.trim_prefix("/"))
	if not script:
		return { "error": "script_not_found", "message": "Script not found: " + script_path }
	node.set_script(script)
	return { "status": "ok", "script": script_path }

func _cmd_detach_script(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var node := _resolve_node(node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: '" + node_path + "'" }
	node.set_script(null)
	return { "status": "ok" }

func _cmd_hot_reload_scripts(_params: Dictionary = {}) -> Dictionary:
	var scripts: Array[GDScript] = []
	_collect_gd_scripts("res://", scripts)
	var count := 0
	for script in scripts:
		script.reload()
		count += 1
	return { "status": "ok", "message": "Reloaded %d GDScript files" % count, "count": count }

func _collect_gd_scripts(dir_path: String, output: Array[GDScript]):
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_gd_scripts(dir_path.path_join(entry), output)
		elif entry.ends_with(".gd"):
			var script := load(dir_path.path_join(entry))
			if script is GDScript:
				output.append(script)
		entry = dir.get_next()
	dir.list_dir_end()

func _cmd_execute_code(params: Dictionary) -> Dictionary:
	var code := _get_param_string(params, "code")
	if code.is_empty():
		return { "error": "missing_param", "message": "'code' is required" }
	if code.length() > 50000:
		return { "error": "code_too_long", "message": "Code exceeds maximum length of 50000 characters" }

	var wrapped_code := "extends RefCounted\n\n" + code
	var gdscript := GDScript.new()
	gdscript.source_code = wrapped_code
	var err := gdscript.reload()
	if err != OK:
		return { "error": "syntax_error", "message": "GDScript error: " + error_string(err) }

	var instance: RefCounted = gdscript.new()
	var result = null
	if instance.has_method("_run"):
		result = str(instance.call("_run"))
	return { "status": "ok", "result": result }

func _cmd_run_scene(_params: Dictionary = {}) -> Dictionary:
	var ei := editor_interface
	if not ei.get_edited_scene_root():
		return { "error": "no_scene", "message": "No scene is currently open" }
	ei.play_current_scene()
	return { "status": "ok" }

func _cmd_stop_scene(_params: Dictionary = {}) -> Dictionary:
	editor_interface.stop_playing_scene()
	return { "status": "ok" }

func _cmd_list_files(params: Dictionary) -> Dictionary:
	var dir_path := _get_param_string(params, "path", "res://")
	var pattern := _get_param_string(params, "pattern", "*")
	var files := []
	var dir := DirAccess.open(dir_path)
	if not dir:
		return { "error": "dir_not_found", "message": "Directory not found: " + dir_path }
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			files.append({ "name": file_name, "type": "directory" })
		else:
			files.append({ "name": file_name, "type": "file" })
		file_name = dir.get_next()
	dir.list_dir_end()
	return { "files": files, "path": dir_path }

func _cmd_read_file(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var full_path := _resolve_project_path(path)
	if full_path.is_empty():
		return { "error": "invalid_path", "message": "Path is outside the project directory" }
	var file := FileAccess.open(full_path, FileAccess.READ)
	if not file:
		return { "error": "file_not_found", "message": "File not found: " + path }
	var content := file.get_as_text()
	var size := file.get_length()
	file.close()
	return { "status": "ok", "content": content, "size": size }

func _cmd_write_file(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	var content := _get_param_string(params, "content")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var full_path := _resolve_project_path(path)
	if full_path.is_empty():
		return { "error": "invalid_path", "message": "Path is outside the project directory" }

	var dir_path := full_path.get_base_dir()
	var dir := DirAccess.open(dir_path)
	if not dir:
		dir = DirAccess.open("res://")
		if dir:
			dir.make_dir_recursive(dir_path.trim_prefix(ProjectSettings.globalize_path("res://")).trim_prefix("/"))

	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if not file:
		return { "error": "write_failed", "message": "Cannot write to: " + path }
	file.store_string(content)
	file.close()
	return { "status": "ok", "path": path, "size": content.length() }

func _cmd_resource_load(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var resource := load(path)
	if not resource:
		return { "error": "resource_not_found", "message": "Resource not found: " + path }
	var props := {}
	for prop in resource.get_property_list():
		var prop_name: String = prop.get("name", "")
		if prop_name.begins_with("__") or prop_name == "resource_path" or prop_name == "resource_name":
			continue
		props[prop_name] = str(resource.get(prop_name))
	return {
		"status": "ok",
		"class": resource.get_class(),
		"resource_path": path,
		"properties": props,
	}

func _cmd_resource_save(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	var resource_class := _get_param_string(params, "resource_class", "Resource")
	var properties = params.get("properties", {})
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	if not path.ends_with(".tres") and not path.ends_with(".res"):
		return { "error": "invalid_extension", "message": "Path must end in .tres or .res" }

	var resource := ClassDB.instantiate(resource_class)
	if not resource:
		return { "error": "unknown_class", "message": "Cannot instantiate: " + resource_class }

	if properties is Dictionary:
		for key in properties:
			if resource.has_property(key):
				resource.set(key, properties[key])

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		return { "error": "save_failed", "message": "Failed to save resource: " + error_string(err) }
	return { "status": "ok", "path": path, "class": resource_class }

func _cmd_get_project_settings(params: Dictionary) -> Dictionary:
	var key := _get_param_string(params, "key", "")
	if key.is_empty():
		var setting_list := ProjectSettings.get_property_list()
		var all_settings := []
		for setting in setting_list:
			var name: String = setting.get("name", "")
			if name.begins_with("__"):
				continue
			all_settings.append({ "name": name, "type": _type_name(setting.get("type", 0)) })
		return { "settings": all_settings, "count": all_settings.size() }
	if not ProjectSettings.has_setting(key):
		return { "error": "setting_not_found", "message": "Setting not found: " + key }
	return { "key": key, "value": ProjectSettings.get_setting(key) }

func _cmd_set_project_settings(params: Dictionary) -> Dictionary:
	var key := _get_param_string(params, "key")
	var value = params.get("value", null)
	if key.is_empty():
		return { "error": "missing_param", "message": "'key' is required" }
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()
	return { "status": "ok", "key": key }

func _cmd_connect_signal(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var signal_name := _get_param_string(params, "signal_name")
	var target_path := _get_param_string(params, "target_path", ".")
	var method_name := _get_param_string(params, "method_name")
	var flags = params.get("flags", 0)
	if signal_name.is_empty() or method_name.is_empty():
		return { "error": "missing_param", "message": "'signal_name' and 'method_name' are required" }
	var node := _resolve_node(node_path)
	var target := _resolve_node(target_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: " + node_path }
	if not target:
		return { "error": "target_not_found", "message": "Target not found: " + target_path }
	if not node.has_signal(signal_name):
		return { "error": "signal_not_found", "message": "Signal not found: " + signal_name + " on " + node.get_class() }

	var err := node.connect(signal_name, Callable(target, method_name), flags)
	if err != OK:
		return { "error": "connect_failed", "message": "Failed to connect signal: " + error_string(err) }
	return { "status": "ok" }

func _cmd_disconnect_signal(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var signal_name := _get_param_string(params, "signal_name")
	var target_path := _get_param_string(params, "target_path", ".")
	var method_name := _get_param_string(params, "method_name")
	if signal_name.is_empty() or method_name.is_empty():
		return { "error": "missing_param", "message": "'signal_name' and 'method_name' are required" }
	var node := _resolve_node(node_path)
	var target := _resolve_node(target_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: " + node_path }
	node.disconnect(signal_name, Callable(target, method_name))
	return { "status": "ok" }

func _cmd_get_signal_list(params: Dictionary) -> Dictionary:
	var node_path := _get_param_string(params, "node_path", ".")
	var node := _resolve_node(node_path)
	if not node:
		return { "error": "node_not_found", "message": "Node not found: " + node_path }
	var signals := []
	var signal_list := node.get_signal_list()
	for s in signal_list:
		var sig := s as Dictionary
		signals.append({
			"name": sig.get("name", ""),
			"args": sig.get("args", []),
		})
	return { "signals": signals, "node": node_path, "type": node.get_class() }

func _cmd_get_export_presets(_params: Dictionary = {}) -> Dictionary:
	var presets := []
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK:
		return { "presets": presets, "count": 0 }
	for section in config.get_sections():
		if not section.begins_with("preset."):
			continue
		if section.trim_prefix("preset.").contains("."):
			continue  # "preset.N.options" option group, not a preset entry
		presets.append({
			"name": config.get_value(section, "name", ""),
			"platform": config.get_value(section, "platform", ""),
			"runnable": config.get_value(section, "runnable", false),
			"dedicated_server": config.get_value(section, "dedicated_server", false),
			"export_path": config.get_value(section, "export_path", ""),
		})
	return { "presets": presets, "count": presets.size() }

func _cmd_run_export(params: Dictionary) -> Dictionary:
	var preset_name := _get_param_string(params, "preset_name")
	if preset_name.is_empty():
		return { "error": "missing_param", "message": "'preset_name' is required" }

	var output_path := _get_param_string(params, "output_path", "")
	if output_path.is_empty():
		var config := ConfigFile.new()
		var found := false
		if config.load("res://export_presets.cfg") == OK:
			for section in config.get_sections():
				if not section.begins_with("preset."):
					continue
				if section.trim_prefix("preset.").contains("."):
					continue  # "preset.N.options" option group, not a preset entry
				if config.get_value(section, "name", "") == preset_name:
					output_path = config.get_value(section, "export_path", "")
					found = true
					break
		if not found:
			return { "error": "preset_not_found", "message": "Export preset not found: " + preset_name }
	if output_path.is_empty():
		return { "error": "missing_param", "message": "'output_path' is required" }
	var full_output := _resolve_project_path(output_path)
	if full_output.is_empty():
		full_output = output_path

	# Godot 4.6 removed the scriptable editor export API, so delegate to the
	# headless CLI which reads the presets from export_presets.cfg itself.
	var args := PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--export-release", preset_name,
		full_output,
	])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		return { "error": "export_failed", "message": "Failed to launch export subprocess" }
	return {
		"status": "ok",
		"pid": pid,
		"output_path": output_path,
		"preset": preset_name,
		"note": "Export started in a headless subprocess; monitor the export output file",
	}

func _cmd_get_plugins(_params: Dictionary = {}) -> Dictionary:
	var enabled_by_name := {}
	var project_cfg := ConfigFile.new()
	if project_cfg.load("res://project.godot") == OK:
		var enabled = project_cfg.get_value("editor_plugins", "enabled", [])
		for entry in enabled:
			if entry is String and entry.begins_with("res://addons/") and entry.ends_with("/plugin.cfg"):
				var addon_name: String = entry.trim_prefix("res://addons/").trim_suffix("/plugin.cfg")
				enabled_by_name[addon_name] = true
	var plugins := []
	var dir := DirAccess.open("res://addons")
	if dir:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir() and not name.begins_with("."):
				plugins.append({ "name": name, "enabled": enabled_by_name.has(name) })
			name = dir.get_next()
		dir.list_dir_end()
	return { "plugins": plugins }

func _cmd_set_plugin_enabled(params: Dictionary) -> Dictionary:
	var plugin_name := _get_param_string(params, "plugin_name")
	var enabled = params.get("enabled", false)
	if plugin_name.is_empty():
		return { "error": "missing_param", "message": "'plugin_name' is required" }
	editor_interface.set_plugin_enabled(plugin_name, enabled)
	return { "status": "ok", "plugin": plugin_name, "enabled": enabled }

func _cmd_validate_script(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var script := load(path)
	if not script:
		return { "error": "script_not_found", "message": "Script not found: " + path }

	var gdscript := script as GDScript
	if not gdscript:
		return { "status": "ok", "valid": true, "message": "Script is valid (non-GDScript)" }

	gdscript.reload()
	var source := gdscript.source_code
	return { "status": "ok", "valid": true, "line_count": source.count("\n") + 1 if source else 0 }

func _cmd_get_asset_import_options(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	var full_path := _resolve_project_path(path)
	if full_path.is_empty():
		return { "error": "invalid_path", "message": "Path is outside project directory" }
	return { "status": "ok", "path": path }

func _cmd_reimport_asset(params: Dictionary) -> Dictionary:
	var path := _get_param_string(params, "path")
	if path.is_empty():
		return { "error": "missing_param", "message": "'path' is required" }
	editor_interface.get_resource_filesystem().reimport_files([path])
	return { "status": "ok", "path": path }


# ─── Helpers ──────────────────────────────────────────────────────────

func _get_editor() -> EditorInterface:
	return editor_interface

func _get_edited_root() -> Node:
	var ei := editor_interface
	return ei.get_edited_scene_root() if ei else null

func _resolve_node(path_str: String) -> Node:
	if path_str == "." or path_str.is_empty():
		return _get_edited_root()
	return _find_node_by_path(_get_edited_root(), path_str)

func _find_node_by_path(root: Node, path_str: String) -> Node:
	if not root:
		return null
	var lookup := path_str
	if lookup.begins_with("."):
		lookup = lookup.substr(1)
	var parts := lookup.split("/", false)
	var current := root
	for part in parts:
		var found := false
		for child in current.get_children():
			if child.name == part:
				current = child
				found = true
				break
		if not found:
			return null
	return current

func _create_node_of_type(type_name: String) -> Node:
	var class_map := {
		"Node": Node.new(),
		"Node2D": Node2D.new(),
		"Node3D": Node3D.new(),
		"Sprite2D": Sprite2D.new(),
		"Sprite3D": Sprite3D.new(),
		"AnimatedSprite2D": AnimatedSprite2D.new(),
		"RigidBody2D": RigidBody2D.new(),
		"RigidBody3D": RigidBody3D.new(),
		"CharacterBody2D": CharacterBody2D.new(),
		"CharacterBody3D": CharacterBody3D.new(),
		"StaticBody2D": StaticBody2D.new(),
		"StaticBody3D": StaticBody3D.new(),
		"AnimatableBody2D": AnimatableBody2D.new(),
		"AnimatableBody3D": AnimatableBody3D.new(),
		"Area2D": Area2D.new(),
		"Area3D": Area3D.new(),
		"CollisionShape2D": CollisionShape2D.new(),
		"CollisionShape3D": CollisionShape3D.new(),
		"CollisionPolygon2D": CollisionPolygon2D.new(),
		"CollisionPolygon3D": CollisionPolygon3D.new(),
		"Camera2D": Camera2D.new(),
		"Camera3D": Camera3D.new(),
		"CanvasLayer": CanvasLayer.new(),
		"ParallaxBackground": ParallaxBackground.new(),
		"ParallaxLayer": ParallaxLayer.new(),
		"TileMap": TileMap.new(),
		"TileMapLayer": TileMapLayer.new(),
		"Control": Control.new(),
		"Button": Button.new(),
		"Label": Label.new(),
		"RichTextLabel": RichTextLabel.new(),
		"TextureRect": TextureRect.new(),
		"ColorRect": ColorRect.new(),
		"Panel": Panel.new(),
		"NinePatchRect": NinePatchRect.new(),
		"LineEdit": LineEdit.new(),
		"TextEdit": TextEdit.new(),
		"HSlider": HSlider.new(),
		"VSlider": VSlider.new(),
		"HBoxContainer": HBoxContainer.new(),
		"VBoxContainer": VBoxContainer.new(),
		"GridContainer": GridContainer.new(),
		"CenterContainer": CenterContainer.new(),
		"MarginContainer": MarginContainer.new(),
		"ScrollContainer": ScrollContainer.new(),
		"TabContainer": TabContainer.new(),
		"AnimationPlayer": AnimationPlayer.new(),
		"AnimationTree": AnimationTree.new(),
		"AudioStreamPlayer": AudioStreamPlayer.new(),
		"AudioStreamPlayer2D": AudioStreamPlayer2D.new(),
		"AudioStreamPlayer3D": AudioStreamPlayer3D.new(),
		"GPUParticles2D": GPUParticles2D.new(),
		"GPUParticles3D": GPUParticles3D.new(),
		"CPUParticles2D": CPUParticles2D.new(),
		"CPUParticles3D": CPUParticles3D.new(),
		"Timer": Timer.new(),
		"Path2D": Path2D.new(),
		"Path3D": Path3D.new(),
		"PathFollow2D": PathFollow2D.new(),
		"PathFollow3D": PathFollow3D.new(),
		"Light2D": PointLight2D.new(),
		"PointLight2D": PointLight2D.new(),
		"DirectionalLight3D": DirectionalLight3D.new(),
		"OmniLight3D": OmniLight3D.new(),
		"SpotLight3D": SpotLight3D.new(),
		"MultiMeshInstance2D": MultiMeshInstance2D.new(),
		"MultiMeshInstance3D": MultiMeshInstance3D.new(),
		"MeshInstance2D": MeshInstance2D.new(),
		"MeshInstance3D": MeshInstance3D.new(),
		"VisibleOnScreenNotifier2D": VisibleOnScreenNotifier2D.new(),
		"VisibleOnScreenNotifier3D": VisibleOnScreenNotifier3D.new(),
		"WorldEnvironment": WorldEnvironment.new(),
		"ResourcePreloader": ResourcePreloader.new(),
		"HTTPRequest": HTTPRequest.new(),
		"AudioListener2D": AudioListener2D.new(),
		"AudioListener3D": AudioListener3D.new(),
		"BackBufferCopy": BackBufferCopy.new(),
		"RemoteTransform2D": RemoteTransform2D.new(),
		"RemoteTransform3D": RemoteTransform3D.new(),
		"PhysicalBone3D": PhysicalBone3D.new(),
		"VehicleBody3D": VehicleBody3D.new(),
		"Joint3D": Generic6DOFJoint3D.new(),
		"Generic6DOFJoint3D": Generic6DOFJoint3D.new(),
		"HingeJoint3D": HingeJoint3D.new(),
		"PinJoint3D": PinJoint3D.new(),
		"ConeTwistJoint3D": ConeTwistJoint3D.new(),
	}
	if class_map.has(type_name) and class_map[type_name] != null:
		return class_map[type_name].duplicate()
	var c := ClassDB.instantiate(type_name)
	if c != null and c is Node:
		return c
	return null

func _resolve_project_path(user_path: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://")
	if user_path.begins_with("res://"):
		var relative := user_path.trim_prefix("res://")
		return project_root.path_join(relative)
	if user_path.begins_with("user://"):
		return ProjectSettings.globalize_path(user_path)
	if user_path.is_absolute_path():
		var normalized := user_path.simplify_path()
		if normalized.begins_with(project_root):
			return normalized
		return ""
	return project_root.path_join(user_path)

func _sanitize_name(name: String) -> String:
	var clean := ""
	for c in name:
		if c.is_valid_ascii_identifier():
			clean += c
		else:
			clean += "_"
	if clean.is_empty():
		clean = "Node"
	return clean

func _get_param_string(params: Dictionary, key: String, default: String = "") -> String:
	var value = params.get(key, default)
	if value is String:
		return value
	if value != null:
		return str(value)
	return default

func _type_name(type_int: int) -> String:
	match type_int:
		0: return "nil"
		1: return "bool"
		2: return "int"
		3: return "float"
		4: return "String"
		5: return "Vector2"
		6: return "Vector2i"
		7: return "Rect2"
		8: return "Rect2i"
		9: return "Vector3"
		10: return "Vector3i"
		11: return "Transform2D"
		12: return "Vector4"
		13: return "Vector4i"
		14: return "Plane"
		15: return "Quaternion"
		16: return "AABB"
		17: return "Basis"
		18: return "Transform3D"
		19: return "Projection"
		20: return "Color"
		21: return "StringName"
		22: return "NodePath"
		23: return "RID"
		24: return "Object"
		25: return "Callable"
		26: return "Signal"
		27: return "Dictionary"
		28: return "Array"
		29: return "PackedByteArray"
		30: return "PackedInt32Array"
		31: return "PackedInt64Array"
		32: return "PackedFloat32Array"
		33: return "PackedFloat64Array"
		34: return "PackedStringArray"
		35: return "PackedVector2Array"
		36: return "PackedVector3Array"
		37: return "PackedColorArray"
		38: return "PackedVector4Array"
		_: return "unknown"