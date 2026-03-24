extends Node
## CoverRaycastMonitor - Toggles cover raycast debug rendering at runtime.
##
## Controlled by ExperimentalSettings:
##   - cover_raycast_visible_enabled: show cover raycast overlay (default: off)
##
## When enabled, draws rays from each enemy showing how they search for cover:
##   - Thin gray lines for raycasts that miss (no obstacle found)
##   - Yellow lines for raycasts that hit an obstacle (candidate cover)
##   - A green circle at the chosen cover position (if valid)
##   - A red line from the player to the chosen cover position showing the
##     line-of-sight check the enemy uses to verify it is hidden
##
## Issue #1359: Added to visualize enemy cover calculation and selection.
## Issue #1392: Replaced Node2D._draw() with Line2D scene nodes to fix
##              invisible overlays in gl_compatibility exported builds.

## Radius of the cover position marker.
const COVER_MARKER_RADIUS := 12.0
## Radius of the collision point dot.
const COLLISION_DOT_RADIUS := 4.0
## Width of raycast lines.
const RAY_LINE_WIDTH := 1.5
## Width of the player-to-cover LOS line.
const LOS_LINE_WIDTH := 2.0
## Max display length for non-colliding rays (Issue #1378: infinite rays would draw 10 000 px lines).
const RAY_DISPLAY_MAX_LENGTH := 800.0
## Number of segments for circle approximations.
const CIRCLE_SEGMENTS := 16

## The overlay node used for rendering.
var _overlay: _CoverRaycastOverlay = null


func _ready() -> void:
	_apply_settings()
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)
	get_tree().node_added.connect(_on_node_added)


## Refresh the overlay every frame while visible.
func _process(_delta: float) -> void:
	if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
		_overlay.refresh()


## Apply current cover raycast visibility setting.
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null:
		return
	var show_rays: bool = experimental_settings.has_method("is_cover_raycast_visible_enabled") and \
		experimental_settings.is_cover_raycast_visible_enabled()
	_set_overlay_visible(show_rays)


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
	_overlay = _CoverRaycastOverlay.new()
	get_tree().root.add_child(_overlay)
	_log("CoverRaycastMonitor: overlay created")


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
		file_logger.log_info("[CoverRaycastMonitor] " + message)
	elif OS.is_debug_build():
		print("[CoverRaycastMonitor] " + message)


## Generate circle outline points as a PackedVector2Array for use with Line2D.
static func _circle_points(center: Vector2, radius: float, segments: int = CIRCLE_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (TAU * i) / segments
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Inner class: a CanvasLayer that renders cover raycast debug info using Line2D nodes.
## Issue #1392: Node2D._draw() is unreliable in gl_compatibility exported builds;
## Line2D scene nodes use Godot's built-in rendering pipeline reliably.
class _CoverRaycastOverlay extends CanvasLayer:
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
		_container.name = "CoverRaycastContainer"
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

	## Collect cover raycast data from all active enemies and render using Line2D nodes.
	func refresh() -> void:
		if _container == null:
			return
		_pool_used = 0

		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			_finish_refresh()
			return

		# Find the player position for LOS lines
		var player_pos := Vector2.ZERO
		var has_player := false
		var players: Array = tree.get_nodes_in_group("player")
		if players.size() > 0 and is_instance_valid(players[0]):
			player_pos = players[0].global_position
			has_player = true

		var enemies: Array = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if not enemy.has_method("get_cover_raycast_data") or not enemy.has_method("get_cover_info"):
				continue

			var rays: Array = enemy.get_cover_raycast_data()
			var cover_info: Dictionary = enemy.get_cover_info()
			var cover_pos: Vector2 = cover_info["position"]
			var cover_valid: bool = cover_info["valid"]

			# Draw each raycast
			for ray_data in rays:
				var origin: Vector2 = ray_data["origin"]
				var target: Vector2 = ray_data["target"]
				var colliding: bool = ray_data["colliding"]

				if colliding:
					var point: Vector2 = ray_data["point"]
					# Yellow line from origin to collision point
					var ray_line: Line2D = _get_line()
					ray_line.points = PackedVector2Array([origin, point])
					ray_line.default_color = Color(1.0, 1.0, 0.0, 0.5)
					ray_line.width = CoverRaycastMonitor.RAY_LINE_WIDTH

					# Small dot at collision point (circle outline)
					var dot: Line2D = _get_line()
					dot.points = CoverRaycastMonitor._circle_points(point, CoverRaycastMonitor.COLLISION_DOT_RADIUS)
					dot.default_color = Color(1.0, 0.8, 0.0, 0.7)
					dot.width = CoverRaycastMonitor.COLLISION_DOT_RADIUS
				else:
					# Thin gray line for miss — clamp display length
					var dir := (target - origin)
					var display_target := origin + dir.normalized() * minf(dir.length(), CoverRaycastMonitor.RAY_DISPLAY_MAX_LENGTH)
					var miss_line: Line2D = _get_line()
					miss_line.points = PackedVector2Array([origin, display_target])
					miss_line.default_color = Color(0.5, 0.5, 0.5, 0.2)
					miss_line.width = CoverRaycastMonitor.RAY_LINE_WIDTH * 0.5

			# Draw chosen cover position
			if cover_valid:
				# Green filled circle
				var fill_circle: Line2D = _get_line()
				fill_circle.points = CoverRaycastMonitor._circle_points(cover_pos, CoverRaycastMonitor.COVER_MARKER_RADIUS)
				fill_circle.default_color = Color(0.0, 1.0, 0.0, 0.3)
				fill_circle.width = CoverRaycastMonitor.COVER_MARKER_RADIUS

				# Green outline
				var outline_circle: Line2D = _get_line()
				outline_circle.points = CoverRaycastMonitor._circle_points(cover_pos, CoverRaycastMonitor.COVER_MARKER_RADIUS)
				outline_circle.default_color = Color(0.0, 1.0, 0.0, 0.9)
				outline_circle.width = CoverRaycastMonitor.LOS_LINE_WIDTH

				# Red line from player to cover position (LOS check)
				if has_player:
					var los_line: Line2D = _get_line()
					los_line.points = PackedVector2Array([player_pos, cover_pos])
					los_line.default_color = Color(1.0, 0.0, 0.0, 0.4)
					los_line.width = CoverRaycastMonitor.LOS_LINE_WIDTH

		_finish_refresh()
