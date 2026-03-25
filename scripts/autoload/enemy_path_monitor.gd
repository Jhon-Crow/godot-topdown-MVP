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

## The overlay node used for custom drawing.
var _overlay: _EnemyPathOverlay = null
## Issue #1392: diagnostic counter — log stats periodically instead of every frame.
var _diag_frame_count: int = 0
var _diag_last_path_count: int = -1

## Issue #1487: Throttle path data refresh to 10 Hz to reduce per-frame overhead.
## At 60 fps with 10 enemies, refreshing every frame causes hundreds of draw_line() calls
## per frame. Capping at 10 Hz cuts overhead ~83% while paths still update visibly smoothly.
const PATH_REFRESH_INTERVAL: float = 0.1  # 10 Hz
var _path_refresh_timer: float = 0.0


func _ready() -> void:
	_apply_settings()
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	get_tree().node_added.connect(_on_node_added)


## Refresh the path overlay at a throttled rate while visible (Issue #1487).
## Previously refreshed every frame; with 10 enemies this caused hundreds of draw_line()
## calls per frame. Now refreshes at PATH_REFRESH_INTERVAL (10 Hz) to reduce overhead.
func _process(delta: float) -> void:
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		# Issue #1487: throttle to PATH_REFRESH_INTERVAL (10 Hz) to cap draw overhead
		_path_refresh_timer += delta
		if _path_refresh_timer >= PATH_REFRESH_INTERVAL:
			_path_refresh_timer -= PATH_REFRESH_INTERVAL
			_overlay.refresh()
		# Issue #1392: periodic diagnostic logging (every 60 frames ≈ 1s)
		_diag_frame_count += 1
		if _diag_frame_count % 60 == 1:
			var path_count: int = _overlay.get_path_count()
			if path_count != _diag_last_path_count:
				_diag_last_path_count = path_count
				var enemies_count: int = get_tree().get_nodes_in_group("enemies").size()
				_log("diag: overlay.visible=%s, paths=%d, enemies=%d, draw_node=%s, draw_count=%d" % [
					_overlay.visible, path_count, enemies_count,
					str(_overlay._draw_node != null), _overlay.get_draw_count()])


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
	_overlay.waypoint_radius = WAYPOINT_RADIUS
	_overlay.target_radius = TARGET_RADIUS
	_overlay.line_width = LINE_WIDTH
	add_child(_overlay)
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
	else:
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


## Inner class: a CanvasLayer that draws all enemy nav paths.
class _EnemyPathOverlay extends CanvasLayer:
	var waypoint_radius: float = 6.0
	var target_radius: float = 10.0
	var line_width: float = 2.0
	var _draw_node: _EnemyPathDrawNode = null

	func _init() -> void:
		# Issue #1392: raised above visual effects (layers 97-103) to remain visible.
		layer = 150
		follow_viewport_enabled = true
		_draw_node = _EnemyPathDrawNode.new()
		_draw_node.waypoint_radius = waypoint_radius
		_draw_node.target_radius = target_radius
		_draw_node.line_width = line_width
		add_child(_draw_node)
		# Issue #1392: diagnostic label
		var _diag_label := Label.new()
		_diag_label.text = "[EnemyPath overlay active]"
		_diag_label.position = Vector2(10, 50)
		_diag_label.add_theme_color_override("font_color", Color(1, 1, 0, 1))
		_diag_label.add_theme_font_size_override("font_size", 14)
		add_child(_diag_label)

	## Issue #1392: diagnostic helpers.
	func get_path_count() -> int:
		return _draw_node._paths.size() if _draw_node != null else -1

	func get_draw_count() -> int:
		return _draw_node._draw_call_count if _draw_node != null else -1

	## Collect nav path data from all active enemies and pass to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return

		var paths: Array = []
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
			paths.append({
				"path": path,
				"state": state,
				"enemy_pos": enemy.global_position,
			})

		_draw_node.set_path_data(paths)


## Inner draw node: performs the actual draw calls each frame.
class _EnemyPathDrawNode extends Node2D:
	var waypoint_radius: float = 6.0
	var target_radius: float = 10.0
	var line_width: float = 2.0
	var _paths: Array = []
	## Issue #1392: count _draw() invocations for diagnostics.
	var _draw_call_count: int = 0
	## Issue #1487 Round 7: track previous paths size to skip queue_redraw when nothing changed.
	var _last_paths_size: int = -1

	func set_path_data(paths: Array) -> void:
		_paths = paths
		# Issue #1487 Round 7: only redraw when the path set actually changes (size changed or
		# always redraw when non-empty so positions update). Skip if both old and new are empty.
		if paths.size() > 0 or _last_paths_size != 0:
			_last_paths_size = paths.size()
			queue_redraw()

	func _draw() -> void:
		_draw_call_count += 1
		# Issue #1392: test rectangle at screen origin to verify _draw() rendering works.
		draw_rect(Rect2(60, 0, 50, 50), Color(1, 1, 0, 0.8))
		if _paths.is_empty():
			return
		# Issue #1487 Round 7: batch all line segments per color into a single draw_multiline()
		# call instead of one draw_line() per segment. Research shows ~30x speedup for batched
		# multiline vs individual draw_line calls (Godot forum benchmark, godot-proposals #8618).
		# Strategy: collect all segment endpoints by state-color, then one draw_multiline per color.
		var lines_by_color: Dictionary = {}  # Color -> PackedVector2Array (pairs of points)
		for path_data in _paths:
			var path: PackedVector2Array = path_data["path"]
			var state: int = path_data["state"]
			var enemy_pos: Vector2 = path_data["enemy_pos"]
			if path.size() < 2:
				continue

			var color: Color = EnemyPathMonitor._color_for_state(state)
			var fill_color: Color = Color(color.r, color.g, color.b, 0.25)

			# Accumulate line segments for batched draw_multiline
			if not lines_by_color.has(color):
				lines_by_color[color] = PackedVector2Array()
			var segments: PackedVector2Array = lines_by_color[color]
			# Segment: enemy position → first waypoint
			segments.append(enemy_pos)
			segments.append(path[0])
			# Segments between waypoints
			for i in range(path.size() - 1):
				segments.append(path[i])
				segments.append(path[i + 1])
			lines_by_color[color] = segments

			# Draw fill circles for waypoints and destination (these are per-enemy, few calls)
			for i in range(path.size() - 1):
				draw_circle(path[i], waypoint_radius, fill_color)
			var dest: Vector2 = path[path.size() - 1]
			draw_circle(dest, target_radius, fill_color)

		# Issue #1487 Round 7: one draw_multiline call per unique color (replaces N draw_line calls)
		for color: Color in lines_by_color:
			draw_multiline(lines_by_color[color], color, line_width)

		# Draw circle outlines via batched multiline (separate pass to keep fill/outline layering)
		var outline_lines_by_color: Dictionary = {}
		for path_data in _paths:
			var path: PackedVector2Array = path_data["path"]
			var state: int = path_data["state"]
			if path.size() < 2:
				continue
			var color: Color = EnemyPathMonitor._color_for_state(state)
			if not outline_lines_by_color.has(color):
				outline_lines_by_color[color] = PackedVector2Array()
			var outline_segs: PackedVector2Array = outline_lines_by_color[color]
			for i in range(path.size() - 1):
				_append_circle_outline_segments(outline_segs, path[i], waypoint_radius)
			_append_circle_outline_segments(outline_segs, path[path.size() - 1], target_radius)
			outline_lines_by_color[color] = outline_segs
		for color: Color in outline_lines_by_color:
			draw_multiline(outline_lines_by_color[color], color, line_width)

	## Append circle outline line-segment pairs to a PackedVector2Array for batched draw_multiline.
	## Issue #1487 Round 7: replaces _draw_circle_outline() which called draw_line() 12 times per
	## circle. Now all circles for the same color are batched into a single draw_multiline call.
	static func _append_circle_outline_segments(
			segs: PackedVector2Array, center: Vector2, radius: float) -> void:
		const SEGMENTS := 12
		for i in range(SEGMENTS):
			var angle_a := (TAU * i) / SEGMENTS
			var angle_b := (TAU * (i + 1)) / SEGMENTS
			segs.append(center + Vector2(cos(angle_a), sin(angle_a)) * radius)
			segs.append(center + Vector2(cos(angle_b), sin(angle_b)) * radius)
