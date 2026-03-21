extends Node
## SearchPathMonitor - Toggles search path waypoints debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - search_path_visible_enabled: show search path overlay (default: off)
##
## When enabled, all SearchPathWaypoints positions and connecting lines are drawn
## on screen so level designers can verify predefined enemy search routes.
##
## The overlay draws:
##   - A circle at each waypoint position
##   - Lines connecting consecutive waypoints (forming the patrol loop)
##   - A small index number near each waypoint
##
## Issue #1251: Added as part of AI search path debugging tools.

## Color for waypoint circles and path lines.
const SEARCH_PATH_COLOR := Color(0.0, 1.0, 0.8, 0.9)
## Color for the waypoint fill.
const SEARCH_PATH_FILL_COLOR := Color(0.0, 1.0, 0.8, 0.25)
## Radius of each waypoint circle in world pixels.
const WAYPOINT_RADIUS := 10.0

## The overlay node used for custom drawing.
var _overlay: _SearchPathOverlay = null


func _ready() -> void:
	# Sync debug rendering with current settings
	_apply_settings()
	# Connect to settings changes so toggle takes effect immediately
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	# Re-apply on scene change (waypoints change between levels)
	get_tree().node_added.connect(_on_node_added)


## Apply current search path visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_paths: bool = experimental_settings.has_method("is_search_path_visible_enabled") and \
		experimental_settings.is_search_path_visible_enabled()
	_set_overlay_visible(show_paths)


## Show or hide the custom search path overlay.
func _set_overlay_visible(visible: bool) -> void:
	if visible:
		_ensure_overlay()
		if _overlay != null:
			_overlay.refresh()
			_overlay.show()
	else:
		if _overlay != null:
			_overlay.hide()


## Create the overlay node if it doesn't exist yet.
func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = _SearchPathOverlay.new()
	_overlay.path_color = SEARCH_PATH_COLOR
	_overlay.fill_color = SEARCH_PATH_FILL_COLOR
	_overlay.waypoint_radius = WAYPOINT_RADIUS
	get_tree().root.add_child(_overlay)


## Re-apply after a new SearchPathWaypoints node is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node.is_in_group("search_path_waypoints"):
		# Defer refresh so all Marker2D children are fully populated
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Inner class: a CanvasLayer that draws all SearchPathWaypoints nodes.
## Using a CanvasLayer ensures the overlay renders above the game world
## and is not affected by the camera transform.
class _SearchPathOverlay extends CanvasLayer:
	var path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var waypoint_radius: float = 10.0
	## The Node2D child that does the actual drawing.
	var _draw_node: _SearchPathDrawNode = null

	func _ready() -> void:
		# Render above game world (layer 10) but below UI (layer 100+)
		layer = 10
		# Follow the viewport camera so world-space coordinates in _draw() align correctly
		follow_viewport_enabled = true
		_draw_node = _SearchPathDrawNode.new()
		_draw_node.path_color = path_color
		_draw_node.fill_color = fill_color
		_draw_node.waypoint_radius = waypoint_radius
		add_child(_draw_node)

	## Collect all SearchPathWaypoints nodes and pass their waypoints to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var waypoint_sets: Array = []
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		# Find all nodes in the search_path_waypoints group
		var path_nodes: Array = tree.get_nodes_in_group("search_path_waypoints")
		for path_node in path_nodes:
			if not is_instance_valid(path_node):
				continue
			var positions: Array[Vector2] = []
			for child in path_node.get_children():
				if child is Marker2D:
					positions.append(child.global_position)
			if positions.size() > 0:
				waypoint_sets.append(positions)
		_draw_node.set_waypoint_sets(waypoint_sets)


## Inner draw node: performs the actual draw calls each frame.
class _SearchPathDrawNode extends Node2D:
	var path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var waypoint_radius: float = 10.0
	var _waypoint_sets: Array = []

	func set_waypoint_sets(waypoint_sets: Array) -> void:
		_waypoint_sets = waypoint_sets
		queue_redraw()

	func _draw() -> void:
		for waypoints in _waypoint_sets:
			if waypoints.size() == 0:
				continue
			# Draw connecting lines between consecutive waypoints (closing the loop)
			for i in range(waypoints.size()):
				var from: Vector2 = waypoints[i]
				var to: Vector2 = waypoints[(i + 1) % waypoints.size()]
				draw_line(from, to, path_color, 2.0)
			# Draw waypoint circles and index numbers on top of lines
			for i in range(waypoints.size()):
				var pos: Vector2 = waypoints[i]
				# Filled circle background
				draw_circle(pos, waypoint_radius, fill_color)
				# Outline circle
				_draw_circle_outline(pos, waypoint_radius, path_color, 2.0)

	## Draw a circle outline using line segments.
	func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
		const SEGMENTS := 16
		for i in range(SEGMENTS):
			var angle_a := (TAU * i) / SEGMENTS
			var angle_b := (TAU * (i + 1)) / SEGMENTS
			var p1 := center + Vector2(cos(angle_a), sin(angle_a)) * radius
			var p2 := center + Vector2(cos(angle_b), sin(angle_b)) * radius
			draw_line(p1, p2, color, width)
