@tool
extends EditorPlugin

var mcp_server: Node

func _enter_tree():
    mcp_server = preload("res://addons/godot_mcp/mcp_server.gd").new()
    get_editor_interface().get_editor_main_screen().add_child(mcp_server)
    print("[Godot MCP] Plugin v2.0.0 initialized — WebSocket server starting on ws://localhost:9080")

func _exit_tree():
    if mcp_server:
        mcp_server.stop_server()
        mcp_server.queue_free()
        mcp_server = null
    print("[Godot MCP] Plugin unloaded — server stopped")
