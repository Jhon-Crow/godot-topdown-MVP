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
## Issue #1392: Replaced Node2D._draw() with Line2D/Label scene nodes to fix
##              invisible overlays in gl_compatibility exported builds.

## Number of segments for circle approximations.
const CIRCLE_SEGMENTS := 16
## Radius of waypoint circles.
const WAYPOINT_RADIUS := 12.0

## The overlay node used for rendering.
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
	get_tree().root.add_child(_overlay)


## Re-apply after a new Marker2D is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node is Marker2D:
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Generate circle outline points as a PackedVector2Array for use with Line2D.
static func _circle_points(center: Vector2, radius: float, segments: int = CIRCLE_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (TAU * i) / segments
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Inner class: a CanvasLayer that renders waypoint markers using Line2D and Label nodes.
## Issue #1392: Node2D._draw() is unreliable in gl_compatibility exported builds;
## Line2D and Label scene nodes use Godot's built-in rendering pipeline reliably.
class _WaypointOverlay extends CanvasLayer:
	## Container node for all child nodes.
	var _container: Node2D = null

	func _init() -> void:
		# Render above game world (layer 11, just above NavMeshMonitor at 10)
		layer = 11
		# Follow the viewport camera so world-space coordinates align correctly
		follow_viewport_enabled = true
		_container = Node2D.new()
		_container.name = "WaypointContainer"
		add_child(_container)

	## Collect all waypoint positions from both groups and create Line2D/Label nodes.
	func refresh() -> void:
		if _container == null:
			return
		# Clear previous nodes
		for child in _container.get_children():
			child.queue_free()

		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return

		# Collect waypoints from both groups
		var waypoints: Array = []
		for wp in tree.get_nodes_in_group("passage_waypoints"):
			if wp is Node2D:
				waypoints.append({"pos": wp.global_position, "name": wp.name,
						"color": Color(0.2, 1.0, 0.3, 0.85)})
		for wp in tree.get_nodes_in_group("search_path_waypoints"):
			if wp is Node2D:
				waypoints.append({"pos": wp.global_position, "name": wp.name,
						"color": Color(1.0, 0.85, 0.1, 0.85)})

		for wp in waypoints:
			var pos: Vector2 = wp["pos"]
			var color: Color = wp["color"]

			# Filled circle (thick Line2D circle)
			var fill_circle := Line2D.new()
			fill_circle.points = WaypointMonitor._circle_points(pos, WaypointMonitor.WAYPOINT_RADIUS)
			fill_circle.default_color = color
			fill_circle.width = WaypointMonitor.WAYPOINT_RADIUS
			_container.add_child(fill_circle)

			# Label with waypoint name
			var label := Label.new()
			label.text = wp["name"]
			label.position = pos + Vector2(14, -6)
			label.add_theme_font_size_override("font_size", 11)
			label.add_theme_color_override("font_color", Color.WHITE)
			_container.add_child(label)
