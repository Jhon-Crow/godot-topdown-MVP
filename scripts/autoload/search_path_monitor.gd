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
##   - Lines connecting consecutive waypoints via the actual navigation mesh path
##     (wall-aware, using NavigationServer2D.map_get_path) so paths respect walls.
##   - For active paths: highlights the current target waypoint in yellow
##
## Issue #1251: Added as part of AI search path debugging tools.
##   Fix: Added active enemy search path visualization so paths are visible in all levels,
##   not just levels with predefined SearchPathWaypoints nodes.
## Issue #1275: Fixed path lines to follow the navigation mesh instead of drawing
##   straight lines through walls. Paths now use NavigationServer2D.map_get_path()
##   between consecutive waypoints so wall boundaries are respected.

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

## AIState.SEARCHING enum value from enemy.gd (IDLE=0..ASSAULT=8, SEARCHING=9).
const AI_STATE_SEARCHING := 9

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
	_overlay.predefined_path_color = PREDEFINED_PATH_COLOR
	_overlay.predefined_fill_color = PREDEFINED_FILL_COLOR
	_overlay.active_path_color = ACTIVE_PATH_COLOR
	_overlay.active_fill_color = ACTIVE_FILL_COLOR
	_overlay.active_target_color = ACTIVE_TARGET_COLOR
	_overlay.waypoint_radius = WAYPOINT_RADIUS
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
	print("[SearchPathMonitor] " + message)


## Compute the actual navigation mesh path between two world-space points.
## Returns a PackedVector2Array following the nav mesh (wall-aware).
## Falls back to a straight two-point segment if no valid nav map is available.
static func _nav_path_between(nav_map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if nav_map.is_valid():
		var path := NavigationServer2D.map_get_path(nav_map, from, to, true)
		if path.size() >= 2:
			return path
	# Fallback: straight line (no nav map or empty result)
	var fallback := PackedVector2Array()
	fallback.append(from)
	fallback.append(to)
	return fallback


## Inner class: a CanvasLayer that draws all search path data.
## Using a CanvasLayer ensures the overlay renders above the game world
## and is not affected by the camera transform.
class _SearchPathOverlay extends CanvasLayer:
	var predefined_path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var predefined_fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var active_path_color: Color = Color(1.0, 0.55, 0.0, 0.9)
	var active_fill_color: Color = Color(1.0, 0.55, 0.0, 0.25)
	var active_target_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	var waypoint_radius: float = 10.0
	## The Node2D child that does the actual drawing.
	var _draw_node: _SearchPathDrawNode = null

	func _ready() -> void:
		# Render above game world (layer 10) but below UI (layer 100+)
		layer = 10
		# Follow the viewport camera so world-space coordinates in _draw() align correctly
		follow_viewport_enabled = true
		_draw_node = _SearchPathDrawNode.new()
		_draw_node.predefined_path_color = predefined_path_color
		_draw_node.predefined_fill_color = predefined_fill_color
		_draw_node.active_path_color = active_path_color
		_draw_node.active_fill_color = active_fill_color
		_draw_node.active_target_color = active_target_color
		_draw_node.waypoint_radius = waypoint_radius
		add_child(_draw_node)

	## Collect all search path data and pass it to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return

		# Obtain a valid navigation map RID from any enemy that has one.
		# This is used to compute wall-aware paths between waypoints (Issue #1275).
		var nav_map: RID = RID()
		var enemies: Array = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if enemy.has_method("get_nav_map"):
				var candidate: RID = enemy.get_nav_map()
				if candidate.is_valid():
					nav_map = candidate
					break

		# --- Predefined SearchPathWaypoints (static scene nodes) ---
		var predefined_sets: Array = []
		var path_nodes: Array = tree.get_nodes_in_group("search_path_waypoints")
		for path_node in path_nodes:
			if not is_instance_valid(path_node):
				continue
			var positions: Array[Vector2] = []
			for child in path_node.get_children():
				if child is Marker2D:
					positions.append(child.global_position)
			if positions.size() > 0:
				predefined_sets.append(positions)

		# --- Active enemy search paths (dynamic spiral/predefined waypoints) ---
		# Collect from all enemies currently in SEARCHING state.
		# AIState.SEARCHING == 9 (0-indexed enum from enemy.gd: IDLE=0..ASSAULT=8, SEARCHING=9)
		var active_paths: Array = []
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
			active_paths.append({
				"waypoints": waypoints,
				"current_idx": current_idx,
				"enemy_pos": enemy.global_position
			})

		_draw_node.set_path_data(predefined_sets, active_paths, nav_map)


## Inner draw node: performs the actual draw calls each frame.
class _SearchPathDrawNode extends Node2D:
	var predefined_path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var predefined_fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var active_path_color: Color = Color(1.0, 0.55, 0.0, 0.9)
	var active_fill_color: Color = Color(1.0, 0.55, 0.0, 0.25)
	var active_target_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	var waypoint_radius: float = 10.0
	var _predefined_sets: Array = []
	var _active_paths: Array = []
	## Navigation map RID used to compute wall-aware paths between waypoints (Issue #1275).
	var _nav_map: RID = RID()

	func set_path_data(predefined_sets: Array, active_paths: Array, nav_map: RID) -> void:
		_predefined_sets = predefined_sets
		_active_paths = active_paths
		_nav_map = nav_map
		queue_redraw()

	func _draw() -> void:
		# Draw predefined SearchPathWaypoints (cyan, closed loop)
		for waypoints in _predefined_sets:
			if waypoints.size() == 0:
				continue
			# Draw connecting lines as wall-aware nav paths (closed loop)
			for i in range(waypoints.size()):
				var from: Vector2 = waypoints[i]
				var to: Vector2 = waypoints[(i + 1) % waypoints.size()]
				var nav_segment: PackedVector2Array = SearchPathMonitor._nav_path_between(_nav_map, from, to)
				for j in range(nav_segment.size() - 1):
					draw_line(nav_segment[j], nav_segment[j + 1], predefined_path_color, 2.0)
			# Draw waypoint circles
			for pos in waypoints:
				draw_circle(pos, waypoint_radius, predefined_fill_color)
				_draw_circle_outline(pos, waypoint_radius, predefined_path_color, 2.0)

		# Draw active enemy search paths (orange, open sequence + current target highlighted)
		for path_data in _active_paths:
			var waypoints: Array = path_data["waypoints"]
			var current_idx: int = path_data["current_idx"]
			var enemy_pos: Vector2 = path_data["enemy_pos"]
			if waypoints.size() == 0:
				continue
			# Draw connecting lines as wall-aware nav paths between consecutive waypoints
			for i in range(waypoints.size() - 1):
				var from: Vector2 = waypoints[i]
				var to: Vector2 = waypoints[i + 1]
				var nav_segment: PackedVector2Array = SearchPathMonitor._nav_path_between(_nav_map, from, to)
				for j in range(nav_segment.size() - 1):
					draw_line(nav_segment[j], nav_segment[j + 1], active_path_color, 2.0)
			# Draw waypoint circles
			for i in range(waypoints.size()):
				var pos: Vector2 = waypoints[i]
				draw_circle(pos, waypoint_radius, active_fill_color)
				_draw_circle_outline(pos, waypoint_radius, active_path_color, 2.0)
			# Highlight current target waypoint in yellow
			if current_idx < waypoints.size():
				var target_pos: Vector2 = waypoints[current_idx]
				draw_circle(target_pos, waypoint_radius * 0.6, active_target_color)
				# Draw line from enemy to current target using actual nav path
				var to_target: PackedVector2Array = SearchPathMonitor._nav_path_between(_nav_map, enemy_pos, target_pos)
				for j in range(to_target.size() - 1):
					draw_line(to_target[j], to_target[j + 1], active_target_color, 1.5)

	## Draw a circle outline using line segments.
	func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
		const SEGMENTS := 16
		for i in range(SEGMENTS):
			var angle_a := (TAU * i) / SEGMENTS
			var angle_b := (TAU * (i + 1)) / SEGMENTS
			var p1 := center + Vector2(cos(angle_a), sin(angle_a)) * radius
			var p2 := center + Vector2(cos(angle_b), sin(angle_b)) * radius
			draw_line(p1, p2, color, width)
