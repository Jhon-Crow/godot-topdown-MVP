extends Node
## WaypointMonitor - Draws a debug overlay for passage and search-path waypoints.
##
## Controlled by ExperimentalSettings:
##   - passage_waypoints_visible_enabled: show waypoint overlay (default: off)
##
## When enabled, draws colored circles and labels at every Marker2D in:
##   - "passage_waypoints" group  → green circles  (BuildingLevel doorway waypoints)
##   - "search_path_waypoints" group → yellow circles (all-levels search path waypoints)
##
## Uses a CanvasLayer with follow_viewport_enabled so world-space positions track
## the camera correctly — same pattern as NavMeshMonitor (Issue #1187).
##
## Issue #1255: Added as a dedicated debug toggle in the Experimental menu.

## The overlay node used for custom drawing.
var _overlay: _WaypointOverlay = null


func _ready() -> void:
	_apply_settings()
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	# Re-apply when scene changes (waypoint nodes change between levels)
	get_tree().node_added.connect(_on_node_added)


## Apply current waypoint visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show: bool = experimental_settings.has_method("is_passage_waypoints_visible_enabled") and \
		experimental_settings.is_passage_waypoints_visible_enabled()
	_set_overlay_visible(show)


## Show or hide the waypoint overlay.
func _set_overlay_visible(visible: bool) -> void:
	if visible:
		_ensure_overlay()
		if _overlay != null:
			_overlay.refresh()
			_overlay.show()
	else:
		if _overlay != null:
			_overlay.hide()


## Create the overlay node if it does not exist yet.
func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _WaypointOverlay.new()
	add_child(_overlay)


## Re-apply after a new Marker2D is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node is Marker2D:
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Inner class: a CanvasLayer that draws all waypoint circles each frame.
class _WaypointOverlay extends CanvasLayer:
	## The Node2D child that performs the actual draw calls.
	## Initialized in _init() so it is available immediately after .new(),
	## before _ready() fires (which is deferred to the next frame by add_child).
	var _draw_node: _WaypointDrawNode = null

	func _init() -> void:
		# Issue #1392: raised above visual effects (layers 97-103) to remain visible.
		layer = 150
		# Follow the viewport camera so world-space coordinates align correctly
		follow_viewport_enabled = true
		# IMPORTANT: _draw_node must be created here in _init(), NOT in _ready().
		# _ready() is deferred to the next frame after add_child(), so if refresh()
		# is called immediately after _WaypointOverlay.new() + add_child(), _draw_node
		# would still be null and the overlay would silently draw nothing.
		_draw_node = _WaypointDrawNode.new()
		add_child(_draw_node)

	## Collect all waypoint positions from both groups and pass them to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var waypoints: Array = []
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		for wp in tree.get_nodes_in_group("passage_waypoints"):
			if wp is Node2D:
				waypoints.append({"pos": wp.global_position, "name": wp.name,
						"color": Color(0.2, 1.0, 0.3, 0.85)})
		for wp in tree.get_nodes_in_group("search_path_waypoints"):
			if wp is Node2D:
				waypoints.append({"pos": wp.global_position, "name": wp.name,
						"color": Color(1.0, 0.85, 0.1, 0.85)})
		_draw_node.set_waypoints(waypoints)


## Inner draw node: performs the actual draw calls each frame.
class _WaypointDrawNode extends Node2D:
	var _waypoints: Array = []

	func set_waypoints(waypoints: Array) -> void:
		_waypoints = waypoints
		queue_redraw()

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		for wp in _waypoints:
			var pos: Vector2 = wp["pos"]
			draw_circle(pos, 12.0, wp["color"])
			draw_string(font, pos + Vector2(14, 4), wp["name"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
