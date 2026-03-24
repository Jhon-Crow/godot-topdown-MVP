extends Node
## SearchPathMonitor - Toggles search path waypoints debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - search_path_visible_enabled: show search path overlay (default: off)
##
## When enabled, two types of search paths are drawn on screen:
##   1. Predefined SearchPathWaypoints (static scene nodes in group "search_path_waypoints"):
##      Drawn in cyan — lets level designers verify pre-planned enemy patrol loops.
##   2. Active enemy search paths (dynamic spiral waypoints currently used by enemies in
##      SEARCHING state): Drawn in orange — shows where enemies are actively searching
##      right now, including spiral-search levels like LabyrinthLevel.
##
## The overlay draws per type:
##   - A circle at each waypoint position
##   - Lines connecting consecutive waypoints
##   - For active paths: highlights the current target waypoint in yellow
##
## Issue #1251: Added as part of AI search path debugging tools.
##   Fix: Added active enemy search path visualization so paths are visible in all levels,
##   not just levels with predefined SearchPathWaypoints nodes.
## Issue #1392: Replaced Node2D._draw() with Line2D scene nodes to fix
##              invisible overlays in gl_compatibility exported builds.

## Color for predefined waypoint circles and path lines (cyan).
const PREDEFINED_PATH_COLOR := Color(0.0, 1.0, 0.8, 0.9)
## Fill color for predefined waypoint circles.
const PREDEFINED_FILL_COLOR := Color(0.0, 1.0, 0.8, 0.25)
## Color for active enemy search path lines and circles (orange).
const ACTIVE_PATH_COLOR := Color(1.0, 0.55, 0.0, 0.9)
## Fill color for active enemy search path circles.
const ACTIVE_FILL_COLOR := Color(1.0, 0.55, 0.0, 0.25)
## Color for the current target waypoint in an active search path (yellow).
const ACTIVE_TARGET_COLOR := Color(1.0, 1.0, 0.0, 1.0)
## Radius of each waypoint circle in world pixels.
const WAYPOINT_RADIUS := 10.0
## Number of segments for circle approximations.
const CIRCLE_SEGMENTS := 16

## AIState.SEARCHING enum value from enemy.gd (IDLE=0..ASSAULT=8, SEARCHING=9).
const AI_STATE_SEARCHING := 9

## The overlay node used for rendering.
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


## Refresh the active search paths every frame when the overlay is visible,
## so that dynamic enemy paths (spiral search) update in real time.
func _process(_delta: float) -> void:
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Apply current search path visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_paths: bool = experimental_settings.has_method("is_search_path_visible_enabled") and \
		experimental_settings.is_search_path_visible_enabled()
	if show_paths:
		_log_info("SearchPathMonitor: enabled, refreshing overlay")
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
	get_tree().root.add_child(_overlay)
	_log_info("SearchPathMonitor: overlay created")


## Re-apply after a new SearchPathWaypoints node or enemy is added (e.g. after scene load).
func _on_node_added(node: Node) -> void:
	if node.is_in_group("search_path_waypoints"):
		# Defer refresh so all Marker2D children are fully populated
		call_deferred("_deferred_refresh")
	# Also refresh when a new enemy is added (it may start in SEARCHING state)
	if node.has_method("get_search_waypoints"):
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Write an info-level log entry for debugging (visible in game log when logging is on).
func _log_info(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[SearchPathMonitor] " + message)
	elif OS.is_debug_build():
		print("[SearchPathMonitor] " + message)


## Generate circle outline points as a PackedVector2Array for use with Line2D.
static func _circle_points(center: Vector2, radius: float, segments: int = CIRCLE_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (TAU * i) / segments
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Inner class: a CanvasLayer that renders search path data using Line2D nodes.
## Issue #1392: Node2D._draw() is unreliable in gl_compatibility exported builds;
## Line2D scene nodes use Godot's built-in rendering pipeline reliably.
class _SearchPathOverlay extends CanvasLayer:
	## Container node for all line child nodes.
	var _container: Node2D = null
	## Pool of reusable Line2D nodes to avoid per-frame allocation.
	var _line_pool: Array[Line2D] = []
	## How many pool nodes are currently in use.
	var _pool_used: int = 0

	func _init() -> void:
		# Render above game world (layer 10) but below UI (layer 100+)
		layer = 10
		# Follow the viewport camera so world-space coordinates align correctly
		follow_viewport_enabled = true
		_container = Node2D.new()
		_container.name = "SearchPathContainer"
		add_child(_container)

	## Get a Line2D from the pool (reuse or create).
	func _get_line() -> Line2D:
		if _pool_used < _line_pool.size():
			var line: Line2D = _line_pool[_pool_used]
			line.show()
			_pool_used += 1
			return line
		var line := Line2D.new()
		_container.add_child(line)
		_line_pool.append(line)
		_pool_used += 1
		return line

	## Hide all unused pool nodes after refresh.
	func _finish_refresh() -> void:
		for i in range(_pool_used, _line_pool.size()):
			_line_pool[i].hide()

	## Collect all search path data and render using Line2D nodes.
	func refresh() -> void:
		if _container == null:
			return
		_pool_used = 0

		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			_finish_refresh()
			return

		# --- Predefined SearchPathWaypoints (static scene nodes) ---
		var path_nodes: Array = tree.get_nodes_in_group("search_path_waypoints")
		for path_node in path_nodes:
			if not is_instance_valid(path_node):
				continue
			var positions: Array[Vector2] = []
			for child in path_node.get_children():
				if child is Marker2D:
					positions.append(child.global_position)
			if positions.size() == 0:
				continue

			# Draw connecting lines (closed loop)
			var loop_pts := PackedVector2Array()
			for pos in positions:
				loop_pts.append(pos)
			loop_pts.append(positions[0])  # Close the loop
			var loop_line: Line2D = _get_line()
			loop_line.points = loop_pts
			loop_line.default_color = SearchPathMonitor.PREDEFINED_PATH_COLOR
			loop_line.width = 2.0

			# Draw waypoint circles
			for pos in positions:
				var fill_circle: Line2D = _get_line()
				fill_circle.points = SearchPathMonitor._circle_points(pos, SearchPathMonitor.WAYPOINT_RADIUS)
				fill_circle.default_color = SearchPathMonitor.PREDEFINED_FILL_COLOR
				fill_circle.width = SearchPathMonitor.WAYPOINT_RADIUS

				var outline_circle: Line2D = _get_line()
				outline_circle.points = SearchPathMonitor._circle_points(pos, SearchPathMonitor.WAYPOINT_RADIUS)
				outline_circle.default_color = SearchPathMonitor.PREDEFINED_PATH_COLOR
				outline_circle.width = 2.0

		# --- Active enemy search paths (dynamic spiral/predefined waypoints) ---
		var enemies: Array = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if not enemy.has_method("get_current_state"):
				continue
			if int(enemy.get_current_state()) != 9:
				continue
			if not enemy.has_method("get_search_waypoints"):
				continue
			var waypoints: Array = enemy.get_search_waypoints()
			if waypoints.size() == 0:
				continue
			var current_idx: int = 0
			if enemy.has_method("get_search_current_waypoint_index"):
				current_idx = enemy.get_search_current_waypoint_index()
			var enemy_pos: Vector2 = enemy.global_position

			# Draw connecting lines between waypoints (open path)
			if waypoints.size() >= 2:
				var path_pts := PackedVector2Array()
				for wp in waypoints:
					path_pts.append(wp)
				var path_line: Line2D = _get_line()
				path_line.points = path_pts
				path_line.default_color = SearchPathMonitor.ACTIVE_PATH_COLOR
				path_line.width = 2.0

			# Draw waypoint circles
			for i in range(waypoints.size()):
				var pos: Vector2 = waypoints[i]
				var fill_circle: Line2D = _get_line()
				fill_circle.points = SearchPathMonitor._circle_points(pos, SearchPathMonitor.WAYPOINT_RADIUS)
				fill_circle.default_color = SearchPathMonitor.ACTIVE_FILL_COLOR
				fill_circle.width = SearchPathMonitor.WAYPOINT_RADIUS

				var outline_circle: Line2D = _get_line()
				outline_circle.points = SearchPathMonitor._circle_points(pos, SearchPathMonitor.WAYPOINT_RADIUS)
				outline_circle.default_color = SearchPathMonitor.ACTIVE_PATH_COLOR
				outline_circle.width = 2.0

			# Highlight current target waypoint in yellow
			if current_idx < waypoints.size():
				var target_pos: Vector2 = waypoints[current_idx]
				var target_circle: Line2D = _get_line()
				target_circle.points = SearchPathMonitor._circle_points(target_pos, SearchPathMonitor.WAYPOINT_RADIUS * 0.6)
				target_circle.default_color = SearchPathMonitor.ACTIVE_TARGET_COLOR
				target_circle.width = SearchPathMonitor.WAYPOINT_RADIUS * 0.6

				# Draw line from enemy to current target
				var target_line: Line2D = _get_line()
				target_line.points = PackedVector2Array([enemy_pos, target_pos])
				target_line.default_color = SearchPathMonitor.ACTIVE_TARGET_COLOR
				target_line.width = 1.5

		_finish_refresh()
