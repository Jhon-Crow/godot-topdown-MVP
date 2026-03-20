extends Node
## NavMeshMonitor - Toggles NavigationServer2D debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - nav_mesh_visible_enabled: show navigation mesh overlay (default: off)
##
## When enabled, the AI navigation mesh polygon is drawn on screen so level
## designers can see where enemies can walk and verify the mesh is correct.
##
## Issue #1187: Added as part of AI navigation debugging tools.


func _ready() -> void:
	# Sync debug rendering with current settings
	_apply_settings()
	# Connect to settings changes so toggle takes effect immediately
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	# Re-apply on scene change (Godot resets NavigationServer2D debug state on scene reload)
	get_tree().node_added.connect(_on_node_added)


## Apply current nav mesh debug visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_nav_mesh: bool = experimental_settings.has_method("is_nav_mesh_visible_enabled") and \
		experimental_settings.is_nav_mesh_visible_enabled()
	NavigationServer2D.set_debug_enabled(show_nav_mesh)


## Re-apply after a new NavigationRegion2D is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node is NavigationRegion2D:
		_apply_settings()
