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
## Issue #1458: Color for uninspected inspection points (green).
const INSPECT_POINT_COLOR := Color(0.2, 1.0, 0.2, 0.9)
## Issue #1458: Color for inspected (cleared) inspection points (gray).
const INSPECT_CLEARED_COLOR := Color(0.5, 0.5, 0.5, 0.4)
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
	_overlay.inspect_point_color = INSPECT_POINT_COLOR
	_overlay.inspect_cleared_color = INSPECT_CLEARED_COLOR
	_overlay.waypoint_radius = WAYPOINT_RADIUS
	add_child(_overlay)
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


## Inner class: a CanvasLayer that draws all search path data.
## Using a CanvasLayer ensures the overlay renders above the game world
## and is not affected by the camera transform.
class _SearchPathOverlay extends CanvasLayer:
	var predefined_path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var predefined_fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var active_path_color: Color = Color(1.0, 0.55, 0.0, 0.9)
	var active_fill_color: Color = Color(1.0, 0.55, 0.0, 0.25)
	var active_target_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	var inspect_point_color: Color = Color(0.2, 1.0, 0.2, 0.9)
	var inspect_cleared_color: Color = Color(0.5, 0.5, 0.5, 0.4)
	var waypoint_radius: float = 10.0
	## The Node2D child that does the actual drawing.
	## Initialized in _init() so it is available immediately after .new(),
	## before _ready() fires (which is deferred to the next frame by add_child).
	var _draw_node: _SearchPathDrawNode = null

	func _init() -> void:
		# Issue #1392: raised above all visual effects (layers 97-103).
		layer = 150
		# Follow the viewport camera so world-space coordinates in _draw() align correctly
		follow_viewport_enabled = true
		# IMPORTANT: _draw_node must be created here in _init(), NOT in _ready().
		# _ready() is deferred to the next frame after add_child(), so if refresh()
		# is called immediately after _SearchPathOverlay.new() + add_child(), _draw_node
		# would still be null and the overlay would silently draw nothing.
		_draw_node = _SearchPathDrawNode.new()
		_draw_node.predefined_path_color = predefined_path_color
		_draw_node.predefined_fill_color = predefined_fill_color
		_draw_node.active_path_color = active_path_color
		_draw_node.active_fill_color = active_fill_color
		_draw_node.active_target_color = active_target_color
		_draw_node.inspect_point_color = inspect_point_color
		_draw_node.inspect_cleared_color = inspect_cleared_color
		_draw_node.waypoint_radius = waypoint_radius
		add_child(_draw_node)
		# Issue #1392: diagnostic label
		var _diag_label := Label.new()
		_diag_label.text = "[SearchPath overlay active]"
		_diag_label.position = Vector2(10, 90)
		_diag_label.add_theme_color_override("font_color", Color(0, 1, 0.8, 1))
		_diag_label.add_theme_font_size_override("font_size", 14)
		add_child(_diag_label)

	## Collect all search path data and pass it to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return

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

		# --- Active enemy search paths (dynamic waypoints) ---
		# Collect from all enemies currently in SEARCHING state.
		# AIState.SEARCHING == 9 (0-indexed enum from enemy.gd: IDLE=0..ASSAULT=8, SEARCHING=9)
		var active_paths: Array = []
		var inspection_data: Array = []  ## Issue #1458: inspection point data
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
			if waypoints.size() == 0 and not enemy.has_method("get_search_inspection_points"):
				continue
			if waypoints.size() > 0:
				var current_idx: int = 0
				if enemy.has_method("get_search_current_waypoint_index"):
					current_idx = enemy.get_search_current_waypoint_index()
				active_paths.append({
					"waypoints": waypoints,
					"current_idx": current_idx,
					"enemy_pos": enemy.global_position
				})
			# Issue #1458 round 3: Collect inspection point data
			if enemy.has_method("get_search_inspection_points"):
				var ipoints: Array = enemy.get_search_inspection_points()
				if ipoints.size() > 0:
					var iflags: Array = enemy.get_search_inspected_flags() if enemy.has_method("get_search_inspected_flags") else []
					var assigned: int = enemy.get_search_assigned_point_index() if enemy.has_method("get_search_assigned_point_index") else -1
					inspection_data.append({
						"points": ipoints,
						"flags": iflags,
						"assigned_idx": assigned,
						"enemy_pos": enemy.global_position
					})

		_draw_node.set_path_data(predefined_sets, active_paths, inspection_data)


## Inner draw node: performs the actual draw calls each frame.
class _SearchPathDrawNode extends Node2D:
	var predefined_path_color: Color = Color(0.0, 1.0, 0.8, 0.9)
	var predefined_fill_color: Color = Color(0.0, 1.0, 0.8, 0.25)
	var active_path_color: Color = Color(1.0, 0.55, 0.0, 0.9)
	var active_fill_color: Color = Color(1.0, 0.55, 0.0, 0.25)
	var active_target_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	var inspect_point_color: Color = Color(0.2, 1.0, 0.2, 0.9)
	var inspect_cleared_color: Color = Color(0.5, 0.5, 0.5, 0.4)
	var waypoint_radius: float = 10.0
	var _predefined_sets: Array = []
	var _active_paths: Array = []
	var _inspection_data: Array = []  ## Issue #1458: inspection point visualization data

	func set_path_data(predefined_sets: Array, active_paths: Array, inspection_data: Array = []) -> void:
		_predefined_sets = predefined_sets
		_active_paths = active_paths
		_inspection_data = inspection_data
		queue_redraw()

	func _draw() -> void:
		# Draw predefined SearchPathWaypoints (cyan, closed loop)
		for waypoints in _predefined_sets:
			if waypoints.size() == 0:
				continue
			# Draw connecting lines (closed loop)
			for i in range(waypoints.size()):
				var from: Vector2 = waypoints[i]
				var to: Vector2 = waypoints[(i + 1) % waypoints.size()]
				draw_line(from, to, predefined_path_color, 2.0)
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
			# Draw connecting lines between waypoints (open path, not closed loop)
			for i in range(waypoints.size() - 1):
				var from: Vector2 = waypoints[i]
				var to: Vector2 = waypoints[i + 1]
				draw_line(from, to, active_path_color, 2.0)
			# Draw waypoint circles
			for i in range(waypoints.size()):
				var pos: Vector2 = waypoints[i]
				draw_circle(pos, waypoint_radius, active_fill_color)
				_draw_circle_outline(pos, waypoint_radius, active_path_color, 2.0)
			# Highlight current target waypoint in yellow
			if current_idx < waypoints.size():
				var target_pos: Vector2 = waypoints[current_idx]
				draw_circle(target_pos, waypoint_radius * 0.6, active_target_color)
				# Draw line from enemy to current target
				draw_line(enemy_pos, target_pos, active_target_color, 1.5)

		# Issue #1458 round 3: Draw inspection points (green = uninspected, gray = cleared)
		for idata in _inspection_data:
			var points: Array = idata["points"]
			var flags: Array = idata["flags"]
			var assigned_idx: int = idata.get("assigned_idx", -1)
			var enemy_pos: Vector2 = idata["enemy_pos"]
			for i in range(points.size()):
				var pos: Vector2 = points[i]
				var cleared: bool = flags[i] if i < flags.size() else false
				var color: Color = inspect_cleared_color if cleared else inspect_point_color
				draw_circle(pos, waypoint_radius * 0.7, color)
				_draw_circle_outline(pos, waypoint_radius * 0.7, color, 1.5)
			# Draw line from enemy to assigned inspection point
			if assigned_idx >= 0 and assigned_idx < points.size():
				draw_line(enemy_pos, points[assigned_idx], active_target_color, 2.0)

	## Draw a circle outline using line segments.
	func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
		const SEGMENTS := 16
		for i in range(SEGMENTS):
			var angle_a := (TAU * i) / SEGMENTS
			var angle_b := (TAU * (i + 1)) / SEGMENTS
			var p1 := center + Vector2(cos(angle_a), sin(angle_a)) * radius
			var p2 := center + Vector2(cos(angle_b), sin(angle_b)) * radius
			draw_line(p1, p2, color, width)
