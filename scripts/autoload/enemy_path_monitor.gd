extends Node
## EnemyPathMonitor - Toggles enemy navigation path debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - enemy_path_visible_enabled: show enemy nav path overlay (default: off)
##
## When enabled, draws the actual NavigationAgent2D computed path for every
## active enemy in the "enemies" group, refreshed every frame. Each path is
## drawn as a polyline with dots at waypoints, colored by the enemy's current
## AI state so designers can tell at a glance what each enemy is doing and
## where it is heading.
##
## State color scheme (matches AIState enum in enemy.gd):
##   IDLE/patrol        — Gray
##   COMBAT / ASSAULT   — Red
##   SEEKING_COVER / IN_COVER / SUPPRESSED / RETREATING — Orange
##   FLANKING           — Magenta
##   PURSUING           — Yellow
##   SEARCHING          — Cyan (consistent with SearchPathMonitor active paths)
##   EVADING_GRENADE    — White
##   PACIFIST           — Green
##
## Issue #1277: Added as part of AI navigation debugging tools.
## Issue #1392: Replaced Node2D._draw() with Line2D scene nodes to fix
##              invisible overlays in gl_compatibility exported builds.

## AIState enum values (mirrors enemy.gd AIState — keep in sync).
const AI_STATE_IDLE := 0
const AI_STATE_COMBAT := 1
const AI_STATE_SEEKING_COVER := 2
const AI_STATE_IN_COVER := 3
const AI_STATE_FLANKING := 4
const AI_STATE_SUPPRESSED := 5
const AI_STATE_RETREATING := 6
const AI_STATE_PURSUING := 7
const AI_STATE_ASSAULT := 8
const AI_STATE_SEARCHING := 9
const AI_STATE_EVADING_GRENADE := 10
const AI_STATE_PACIFIST := 11

## Radius of waypoint dots along the path.
const WAYPOINT_RADIUS := 6.0
## Radius of the dot at the path destination (final target).
const TARGET_RADIUS := 10.0
## Width of the path polyline.
const LINE_WIDTH := 2.0
## Number of segments for circle approximations.
const CIRCLE_SEGMENTS := 12

## The overlay node used for rendering.
var _overlay: _EnemyPathOverlay = null


func _ready() -> void:
	_apply_settings()
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	get_tree().node_added.connect(_on_node_added)


## Refresh the path overlay every frame while visible.
func _process(_delta: float) -> void:
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Apply current enemy path visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_paths: bool = experimental_settings.has_method("is_enemy_path_visible_enabled") and \
		experimental_settings.is_enemy_path_visible_enabled()
	_set_overlay_visible(show_paths)


## Show or hide the overlay.
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
	_overlay = _EnemyPathOverlay.new()
	get_tree().root.add_child(_overlay)
	_log("EnemyPathMonitor: overlay created")


## Re-apply when a new enemy is added to the scene.
func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemies") and _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_apply_settings()
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Log an info message.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[EnemyPathMonitor] " + message)
	elif OS.is_debug_build():
		print("[EnemyPathMonitor] " + message)


## Return the overlay color for a given AI state integer.
static func _color_for_state(state: int) -> Color:
	match state:
		AI_STATE_IDLE:
			return Color(0.6, 0.6, 0.6, 0.9)        # Gray — idle/patrol
		AI_STATE_COMBAT, AI_STATE_ASSAULT:
			return Color(1.0, 0.2, 0.2, 0.9)        # Red — combat/assault
		AI_STATE_SEEKING_COVER, AI_STATE_IN_COVER, AI_STATE_SUPPRESSED, AI_STATE_RETREATING:
			return Color(1.0, 0.55, 0.1, 0.9)       # Orange — cover states
		AI_STATE_FLANKING:
			return Color(1.0, 0.0, 1.0, 0.9)        # Magenta — flanking
		AI_STATE_PURSUING:
			return Color(1.0, 1.0, 0.0, 0.9)        # Yellow — pursuing
		AI_STATE_SEARCHING:
			return Color(0.0, 1.0, 0.8, 0.9)        # Cyan — searching
		AI_STATE_EVADING_GRENADE:
			return Color(1.0, 1.0, 1.0, 0.9)        # White — evading
		AI_STATE_PACIFIST:
			return Color(0.2, 1.0, 0.2, 0.9)        # Green — pacifist
		_:
			return Color(0.8, 0.8, 0.8, 0.9)        # Light gray — unknown


## Generate circle outline points as a PackedVector2Array for use with Line2D.
static func _circle_points(center: Vector2, radius: float, segments: int = CIRCLE_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (TAU * i) / segments
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Inner class: a CanvasLayer that renders enemy nav paths using Line2D nodes.
## Issue #1392: Node2D._draw() is unreliable in gl_compatibility exported builds;
## Line2D scene nodes use Godot's built-in rendering pipeline reliably.
class _EnemyPathOverlay extends CanvasLayer:
	## Container node for all line child nodes.
	var _container: Node2D = null
	## Pool of reusable Line2D nodes to avoid per-frame allocation.
	var _line_pool: Array[Line2D] = []
	## How many pool nodes are currently in use.
	var _pool_used: int = 0

	func _init() -> void:
		layer = 10
		follow_viewport_enabled = true
		_container = Node2D.new()
		_container.name = "EnemyPathContainer"
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

	## Collect nav path data from all active enemies and render using Line2D nodes.
	func refresh() -> void:
		if _container == null:
			return
		_pool_used = 0

		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			_finish_refresh()
			return

		var enemies: Array = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if not enemy.has_method("get_nav_path"):
				continue
			var path: PackedVector2Array = enemy.get_nav_path()
			if path.size() < 2:
				continue
			var state: int = 0
			if enemy.has_method("get_current_state"):
				state = int(enemy.get_current_state())

			var color: Color = EnemyPathMonitor._color_for_state(state)
			var fill_color: Color = Color(color.r, color.g, color.b, 0.25)
			var enemy_pos: Vector2 = enemy.global_position

			# Path line from enemy to first waypoint
			var lead_line: Line2D = _get_line()
			lead_line.points = PackedVector2Array([enemy_pos, path[0]])
			lead_line.default_color = color
			lead_line.width = EnemyPathMonitor.LINE_WIDTH

			# Path line through all waypoints
			var path_line: Line2D = _get_line()
			path_line.points = path
			path_line.default_color = color
			path_line.width = EnemyPathMonitor.LINE_WIDTH

			# Small dots at intermediate waypoints (circle outlines)
			for i in range(path.size() - 1):
				# Filled circle (use a closed Line2D with narrow width as approximation)
				var fill_circle: Line2D = _get_line()
				fill_circle.points = EnemyPathMonitor._circle_points(path[i], EnemyPathMonitor.WAYPOINT_RADIUS)
				fill_circle.default_color = fill_color
				fill_circle.width = EnemyPathMonitor.WAYPOINT_RADIUS  # Thick to appear filled

				var outline_circle: Line2D = _get_line()
				outline_circle.points = EnemyPathMonitor._circle_points(path[i], EnemyPathMonitor.WAYPOINT_RADIUS)
				outline_circle.default_color = color
				outline_circle.width = EnemyPathMonitor.LINE_WIDTH

			# Larger dot at the final target
			var dest: Vector2 = path[path.size() - 1]
			var fill_target: Line2D = _get_line()
			fill_target.points = EnemyPathMonitor._circle_points(dest, EnemyPathMonitor.TARGET_RADIUS)
			fill_target.default_color = fill_color
			fill_target.width = EnemyPathMonitor.TARGET_RADIUS

			var outline_target: Line2D = _get_line()
			outline_target.points = EnemyPathMonitor._circle_points(dest, EnemyPathMonitor.TARGET_RADIUS)
			outline_target.default_color = color
			outline_target.width = EnemyPathMonitor.LINE_WIDTH

		_finish_refresh()
