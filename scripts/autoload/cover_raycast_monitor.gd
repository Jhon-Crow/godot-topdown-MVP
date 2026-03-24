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

## The overlay node used for custom drawing.
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
	add_child(_overlay)
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
	else:
		print("[CoverRaycastMonitor] " + message)


## Inner class: a CanvasLayer that draws cover raycast debug info.
class _CoverRaycastOverlay extends CanvasLayer:
	var _draw_node: _CoverRaycastDrawNode = null

	func _init() -> void:
		# Issue #1392: raised above visual effects (layers 97-103) to remain visible.
		layer = 150
		follow_viewport_enabled = true
		_draw_node = _CoverRaycastDrawNode.new()
		add_child(_draw_node)
		# Issue #1392: diagnostic label
		var _diag_label := Label.new()
		_diag_label.text = "[CoverRaycast overlay active]"
		_diag_label.position = Vector2(10, 70)
		_diag_label.add_theme_color_override("font_color", Color(1, 0.5, 0, 1))
		_diag_label.add_theme_font_size_override("font_size", 14)
		add_child(_diag_label)

	## Collect cover raycast data from all active enemies and pass to the draw node.
	func refresh() -> void:
		if _draw_node == null:
			return
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return

		# Find the player position for LOS lines
		var player_pos := Vector2.ZERO
		var has_player := false
		var players: Array = tree.get_nodes_in_group("player")
		if players.size() > 0 and is_instance_valid(players[0]):
			player_pos = players[0].global_position
			has_player = true

		var enemy_data: Array = []
		var enemies: Array = tree.get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if not enemy.has_method("get_cover_raycast_data") or not enemy.has_method("get_cover_info"):
				continue

			var rays: Array = enemy.get_cover_raycast_data()
			var cover_info: Dictionary = enemy.get_cover_info()
			enemy_data.append({
				"rays": rays,
				"cover_position": cover_info["position"],
				"cover_valid": cover_info["valid"],
				"enemy_pos": enemy.global_position,
			})

		_draw_node.set_data(enemy_data, player_pos, has_player)


## Inner draw node: performs the actual draw calls each frame.
class _CoverRaycastDrawNode extends Node2D:
	var _enemy_data: Array = []
	var _player_pos: Vector2 = Vector2.ZERO
	var _has_player: bool = false

	func set_data(data: Array, player_pos: Vector2, has_player: bool) -> void:
		_enemy_data = data
		_player_pos = player_pos
		_has_player = has_player
		queue_redraw()

	func _draw() -> void:
		for entry in _enemy_data:
			var rays: Array = entry["rays"]
			var cover_pos: Vector2 = entry["cover_position"]
			var cover_valid: bool = entry["cover_valid"]

			# Draw each raycast
			for ray_data in rays:
				var origin: Vector2 = ray_data["origin"]
				var target: Vector2 = ray_data["target"]
				var colliding: bool = ray_data["colliding"]

				if colliding:
					var point: Vector2 = ray_data["point"]
					# Yellow line from origin to collision point
					draw_line(origin, point, Color(1.0, 1.0, 0.0, 0.5), CoverRaycastMonitor.RAY_LINE_WIDTH)
					# Small dot at collision point
					draw_circle(point, CoverRaycastMonitor.COLLISION_DOT_RADIUS, Color(1.0, 0.8, 0.0, 0.7))
				else:
					# Thin gray line for miss — clamp display length so infinite rays (10 000 px) don't
					# draw far off-screen and make the overlay unreadable (Issue #1378).
					var dir := (target - origin)
					var display_target := origin + dir.normalized() * minf(dir.length(), CoverRaycastMonitor.RAY_DISPLAY_MAX_LENGTH)
					draw_line(origin, display_target, Color(0.5, 0.5, 0.5, 0.2), CoverRaycastMonitor.RAY_LINE_WIDTH * 0.5)

			# Draw chosen cover position
			if cover_valid:
				# Green filled circle with outline
				draw_circle(cover_pos, CoverRaycastMonitor.COVER_MARKER_RADIUS, Color(0.0, 1.0, 0.0, 0.3))
				_draw_circle_outline(cover_pos, CoverRaycastMonitor.COVER_MARKER_RADIUS, Color(0.0, 1.0, 0.0, 0.9), CoverRaycastMonitor.LOS_LINE_WIDTH)

				# Red dashed line from player to cover position (LOS check)
				if _has_player:
					draw_line(_player_pos, cover_pos, Color(1.0, 0.0, 0.0, 0.4), CoverRaycastMonitor.LOS_LINE_WIDTH)

	## Draw a circle outline using line segments.
	func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
		const SEGMENTS := 16
		for i in range(SEGMENTS):
			var angle_a := (TAU * i) / SEGMENTS
			var angle_b := (TAU * (i + 1)) / SEGMENTS
			var p1 := center + Vector2(cos(angle_a), sin(angle_a)) * radius
			var p2 := center + Vector2(cos(angle_b), sin(angle_b)) * radius
			draw_line(p1, p2, color, width)
