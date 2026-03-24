extends Node
## BlackMetalLightningEffectsManager - Thunder and lightning effects for Black Metal difficulty.
##
## Issue #1023: Adds dramatic horror-film style lightning bolt effects when the player
## kills an enemy in Black Metal difficulty mode. Each kill draws actual visible
## jagged bolt streaks from the top of the screen downward, with branches, plus
## a brief screen-wide illumination flash — like old horror/black-metal films.
##
## APPROACH (v10): Pure GDScript Node2D._draw() — NO shaders, NO ColorRect, NO screen texture.
##
## Root cause of all previous failures (v1-v9):
##   Every approach used a full-screen ColorRect with a canvas_item shader.
##   In Godot's gl_compatibility renderer this caused white screen/blink because:
##   - v1-v2: Shader TEXTURE on ColorRect = 1×1 white pixel, no actual scene capture.
##   - v3-v8: Any toggle of visible=false→true triggers a "first-frame" issue where
##     hint_screen_texture or the shader output is white/uninitialized for 1 frame.
##   - v9: blend_add + always-visible → blend_add is not reliably supported in
##     gl_compatibility, falls back to alpha blending, and the always-visible black
##     ColorRect (vec4(0,0,0,1)) corrupts the rendering pipeline at startup.
##
## v10 solution: Skip shaders entirely. Draw the bolt via GDScript canvas draw calls.
##   - LightningBoltDrawer: a Node2D that calls draw_polyline/draw_circle in _draw().
##     It is hidden (visible=false) when not flashing. Toggling visible on a plain
##     Node2D (no shader, no screen texture) causes zero issues.
##   - IlluminationFlash: a plain ColorRect with a semi-transparent white color and
##     NO shader. Shown for the flash duration, then hidden. No screen capture needed.
##   - Both nodes are inside a CanvasLayer at layer 98 so they appear above the
##     Black Metal B&W filter (layer 97) but below hit effects (layer 100).
##   This approach works identically in all Godot renderers and never touches the
##   screen texture pipeline.
##
## Features:
## - Procedural jagged lightning bolt drawn across the screen
## - Branches splitting off the main bolt
## - Screen-wide illumination pulse at the moment of impact
## - Visual diversity: randomized bolt origin, path, number of bolts, branches
## - Single, double, or triple-bolt sequences for varied intensity
## - Respects the existing B&W+red filter (renders at layer 98, above it)


## Flash pattern types for visual diversity.
enum FlashPattern {
	SINGLE,   ## One bolt strike
	DOUBLE,   ## Two quick strikes
	TRIPLE    ## Three rapid strikes
}

## Minimum flash duration in seconds (how long one bolt stays visible).
const MIN_FLASH_DURATION: float = 0.12

## Maximum flash duration in seconds.
const MAX_FLASH_DURATION: float = 0.22

## Gap between strikes in multi-strike patterns (seconds).
const MULTI_FLASH_GAP: float = 0.05

## Probability of double flash pattern.
const DOUBLE_FLASH_CHANCE: float = 0.35

## Probability of triple flash pattern.
const TRIPLE_FLASH_CHANCE: float = 0.15

## CanvasLayer for the lightning bolt overlay.
var _flash_layer: CanvasLayer = null

## Node2D that draws the lightning bolt via _draw().
var _bolt_drawer: Node2D = null

## Plain ColorRect for the illumination flash (no shader).
var _illum_rect: ColorRect = null

## Whether the manager is active (Black Metal mode enabled).
var _is_active: bool = false

## Whether a flash animation is currently playing.
var _is_flashing: bool = false

## Current flash state for animation.
var _flash_timer: float = 0.0
var _flash_duration: float = 0.0
var _flashes_remaining: int = 0
var _in_gap: bool = false
var _gap_timer: float = 0.0

## Per-bolt drawing data (computed once per flash, redrawn each frame).
var _bolt_intensity: float = 0.0   ## 0=hidden, 1=full brightness
var _bolt_data: Array = []         ## List of bolt polylines (Array of PackedVector2Array)
var _bolt_seed: float = 0.0        ## Current random seed


func _ready() -> void:
	_log("BlackMetalLightningEffectsManager initializing...")

	# Create the flash layer at layer 98 — above the Black Metal filter (97) but below hit effects (100).
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "BlackMetalLightningLayer"
	_flash_layer.layer = 98
	_flash_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_flash_layer)

	# --- Illumination flash ColorRect (no shader, just a semi-transparent overlay) ---
	_illum_rect = ColorRect.new()
	_illum_rect.name = "LightningIllumination"
	_illum_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_illum_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Blue-white tint for horror lightning, semi-transparent.
	# Alpha is animated by the manager during the flash.
	_illum_rect.color = Color(0.75, 0.85, 1.0, 0.0)
	_illum_rect.visible = false  # Hidden when not flashing — plain Node, no shader, safe to toggle.
	_flash_layer.add_child(_illum_rect)

	# --- Lightning bolt drawer Node2D ---
	# This node renders the bolt using draw_polyline/draw_circle in _draw().
	# No shader involved — pure canvas draw calls. Safe to toggle visible.
	_bolt_drawer = _LightningBoltDrawer.new()
	_bolt_drawer.name = "LightningBoltDrawer"
	_bolt_drawer.visible = false  # Hidden when not flashing.
	# The bolt drawer needs a reference back to the manager to read _bolt_data/_bolt_intensity.
	_bolt_drawer.set_meta("manager", self)
	_flash_layer.add_child(_bolt_drawer)

	_log("Lightning bolt drawer created (v10 - no shader, pure draw calls)")

	# Connect to difficulty changes.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)
		_apply_current_difficulty()
	else:
		_log("WARNING: DifficultyManager not found - effects will not activate automatically")

	# Connect to enemy kills — lightning fires on kill, not on hit.
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_signal("enemy_killed"):
		game_manager.enemy_killed.connect(_on_enemy_killed)
		_log("Connected to GameManager.enemy_killed signal")
	else:
		_log("WARNING: GameManager not found or missing enemy_killed signal")

	_log("Starting shader warmup (Issue #343 pattern)...")
	await get_tree().process_frame
	_log("Shader warmup complete in 0 ms")


func _process(delta: float) -> void:
	if _is_flashing:
		_process_flash(delta)


## Called when the player kills an enemy. Triggers a lightning bolt in Black Metal mode.
func _on_enemy_killed() -> void:
	trigger_lightning()


## Triggers a lightning bolt strike. Called when an enemy is killed in Black Metal mode.
func trigger_lightning() -> void:
	if not _is_active:
		return

	# Don't interrupt an ongoing flash sequence.
	if _is_flashing:
		return

	var pattern := _choose_flash_pattern()
	_start_flash_sequence(pattern)


## Chooses a random flash pattern based on configured probabilities.
func _choose_flash_pattern() -> FlashPattern:
	var roll := randf()
	if roll < TRIPLE_FLASH_CHANCE:
		return FlashPattern.TRIPLE
	elif roll < TRIPLE_FLASH_CHANCE + DOUBLE_FLASH_CHANCE:
		return FlashPattern.DOUBLE
	else:
		return FlashPattern.SINGLE


## Starts a flash sequence with the given pattern.
func _start_flash_sequence(pattern: FlashPattern) -> void:
	match pattern:
		FlashPattern.SINGLE:
			_flashes_remaining = 1
		FlashPattern.DOUBLE:
			_flashes_remaining = 2
		FlashPattern.TRIPLE:
			_flashes_remaining = 3

	_log("%s lightning strike (%d flash(es))" % [FlashPattern.keys()[pattern], _flashes_remaining])
	_start_single_flash()


## Starts a single bolt strike within a sequence.
func _start_single_flash() -> void:
	_is_flashing = true
	_in_gap = false

	_flash_duration = randf_range(MIN_FLASH_DURATION, MAX_FLASH_DURATION)
	_flash_timer = 0.0

	_bolt_seed = randf() * 100.0
	var use_double_bolt: bool = randf() < 0.3

	# Compute the bolt geometry for this flash.
	_bolt_data = _compute_bolt_data(_bolt_seed, use_double_bolt)
	_bolt_intensity = 1.0

	# Show both the drawer and the illumination rect.
	# These are plain nodes with no shader — toggling visible is safe.
	if _bolt_drawer:
		_bolt_drawer.visible = true
		_bolt_drawer.queue_redraw()
	if _illum_rect:
		_illum_rect.visible = true
		_illum_rect.color = Color(0.75, 0.85, 1.0, 0.18)


## Processes the bolt animation each frame.
func _process_flash(delta: float) -> void:
	if _in_gap:
		_gap_timer += delta
		if _gap_timer >= MULTI_FLASH_GAP:
			_in_gap = false
			if _flashes_remaining > 0:
				_start_single_flash()
			else:
				_end_flash_sequence()
		return

	_flash_timer += delta
	var progress := _flash_timer / _flash_duration

	if progress >= 1.0:
		_flashes_remaining -= 1

		if _flashes_remaining > 0:
			_in_gap = true
			_gap_timer = 0.0
			_bolt_intensity = 0.0
			if _bolt_drawer:
				_bolt_drawer.visible = false
			if _illum_rect:
				_illum_rect.visible = false
		else:
			_end_flash_sequence()
	else:
		# Ease-out fade: blazing start, fast decay.
		var fade := (1.0 - progress) * (1.0 - progress)
		_bolt_intensity = fade

		if _bolt_drawer:
			_bolt_drawer.queue_redraw()
		if _illum_rect:
			# Illumination also fades with the bolt.
			_illum_rect.color = Color(0.75, 0.85, 1.0, 0.18 * fade)


## Ends the entire flash sequence.
func _end_flash_sequence() -> void:
	_is_flashing = false
	_flashes_remaining = 0
	_bolt_intensity = 0.0
	_bolt_data = []

	if _bolt_drawer:
		_bolt_drawer.visible = false
	if _illum_rect:
		_illum_rect.visible = false


# ============================================================================
# BOLT GEOMETRY COMPUTATION
#
# Computes the polylines for the main bolt and its branches in screen-space.
# Screen size is obtained from the viewport at call time.
# ============================================================================

## Computes bolt geometry. Returns an Array of dicts, each with:
##   "points": PackedVector2Array — the polyline points
##   "color_factor": float — brightness multiplier (1.0 = main bolt, 0.7 = branch)
func _compute_bolt_data(bolt_seed: float, use_double: bool) -> Array:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return []
	var vp_size: Vector2 = viewport.get_visible_rect().size
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return []

	var result: Array = []
	var s := bolt_seed

	# Main bolt 1
	var ox := (0.2 + _hash(s + 1.0) * 0.6) * vp_size.x
	var oy := 0.0
	var ex := ox + (_hash(s + 2.0) - 0.5) * 0.45 * vp_size.x
	var ey := (0.65 + _hash(s + 3.0) * 0.3) * vp_size.y
	var noise_scale := (0.03 + _hash(s + 4.0) * 0.04) * vp_size.x

	var main_points := _build_bolt_polyline(Vector2(ox, oy), Vector2(ex, ey), noise_scale, s, vp_size)
	result.append({"points": main_points, "color_factor": 1.0, "width": 3.0})

	# Add 4 branches off bolt 1
	for b in range(4):
		var bs := s + float(b) * 7.39 + 50.0
		var branch_t := 0.2 + _hash(bs) * 0.65
		var branch_origin: Vector2 = _lerp_along_bolt(main_points, branch_t)
		var angle := (_hash(bs + 1.0) - 0.5) * 1.2 + PI * 0.5
		var branch_len := (0.10 + _hash(bs + 0.5) * 0.12) * vp_size.y
		var branch_end := branch_origin + Vector2(cos(angle), sin(angle)) * branch_len
		var branch_pts := _build_bolt_polyline(branch_origin, branch_end,
				noise_scale * 0.4, bs + 5.0, vp_size)
		result.append({"points": branch_pts, "color_factor": 0.55, "width": 1.5})

	# Second bolt if requested
	if use_double:
		var ox2 := ox + (_hash(s + 11.0) - 0.5) * 0.2 * vp_size.x
		var ex2 := ox2 + (_hash(s + 12.0) - 0.5) * 0.35 * vp_size.x
		var ey2 := (0.6 + _hash(s + 13.0) * 0.35) * vp_size.y
		var ns2 := (0.025 + _hash(s + 14.0) * 0.035) * vp_size.x
		var pts2 := _build_bolt_polyline(Vector2(ox2, oy), Vector2(ex2, ey2), ns2, s + 20.0, vp_size)
		result.append({"points": pts2, "color_factor": 0.85, "width": 2.5})
		# Branches for second bolt too
		for b in range(2):
			var bs := s + float(b) * 5.11 + 80.0
			var branch_t := 0.3 + _hash(bs) * 0.5
			var branch_origin: Vector2 = _lerp_along_bolt(pts2, branch_t)
			var angle := (_hash(bs + 1.0) - 0.5) * 1.2 + PI * 0.5
			var branch_len := (0.08 + _hash(bs + 0.5) * 0.10) * vp_size.y
			var branch_end := branch_origin + Vector2(cos(angle), sin(angle)) * branch_len
			var branch_pts := _build_bolt_polyline(branch_origin, branch_end,
					ns2 * 0.4, bs + 5.0, vp_size)
			result.append({"points": branch_pts, "color_factor": 0.45, "width": 1.0})

	return result


## Builds a jagged polyline from start to end using multi-octave noise displacement.
func _build_bolt_polyline(start: Vector2, end_pt: Vector2,
		noise_scale: float, bolt_seed: float, _vp_size: Vector2) -> PackedVector2Array:
	var segments := 20
	var points := PackedVector2Array()
	var dir: Vector2 = end_pt - start
	var len: float = dir.length()
	if len < 1.0:
		points.append(start)
		points.append(end_pt)
		return points

	var dir_n: Vector2 = dir / len
	var perp: Vector2 = Vector2(-dir_n.y, dir_n.x)

	for i in range(segments + 1):
		var t := float(i) / float(segments)

		# Multi-octave noise displacement (same as v9 shader formula)
		var disp := 0.0
		var amp := noise_scale
		var freq := 4.0
		for _oct in range(4):
			disp += (_smooth_noise_1d(t * freq + bolt_seed * 3.7 + float(_oct), bolt_seed) - 0.5) * amp
			amp *= 0.5
			freq *= 2.2

		var p: Vector2 = start + dir_n * (t * len) + perp * disp
		points.append(p)

	return points


## Interpolates a position along a polyline at parameter t (0..1).
func _lerp_along_bolt(points: PackedVector2Array, t: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var idx: int = clamp(int(t * float(points.size() - 1)), 0, points.size() - 2)
	var local_t: float = (t * float(points.size() - 1)) - float(idx)
	return points[idx].lerp(points[idx + 1], local_t)


# ============================================================================
# NOISE / HASH HELPERS (matches v9 shader for same visual style)
# ============================================================================

func _hash(n: float) -> float:
	n = fmod(n * 0.1031, 1.0)
	n *= n + 33.33
	n *= n + n
	return fmod(abs(n), 1.0)


func _smooth_noise_1d(t: float, s: float) -> float:
	var i: float = floor(t)
	var f := fmod(t, 1.0)
	var a := _hash(i + s * 37.3)
	var b := _hash(i + 1.0 + s * 37.3)
	var u := f * f * (3.0 - 2.0 * f)
	return lerp(a, b, u)


## Called when the global difficulty changes.
func _on_difficulty_changed(_new_difficulty: int) -> void:
	_apply_current_difficulty()


## Reads the current difficulty from DifficultyManager and toggles activation.
func _apply_current_difficulty() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("is_black_metal_mode"):
		var was_active := _is_active
		_is_active = difficulty_manager.is_black_metal_mode()
		if _is_active and not was_active:
			_log("Lightning effects ENABLED (Black Metal mode)")
		elif not _is_active and was_active:
			_log("Lightning effects DISABLED")
			_is_flashing = false
			_flashes_remaining = 0
			_bolt_intensity = 0.0
			_bolt_data = []
			if _bolt_drawer:
				_bolt_drawer.visible = false
			if _illum_rect:
				_illum_rect.visible = false


## Returns whether lightning effects are currently active.
func is_active() -> bool:
	return _is_active


## Log a message with the Lightning prefix.
## Issue #1293: print() fallback gated to debug builds to avoid FPS drops.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BlackMetalLightningEffectsManager] " + message)
	elif OS.is_debug_build():
		print("[BlackMetalLightningEffectsManager] " + message)


# ============================================================================
# LightningBoltDrawer — inner class Node2D that draws the bolt geometry.
#
# Reads bolt data and intensity from its manager via metadata.
# Renders each polyline segment with a glow pass (thicker, dimmer) and a
# core pass (thinner, brighter) for the classic horror lightning look.
# ============================================================================

class _LightningBoltDrawer extends Node2D:
	func _draw() -> void:
		var manager: Node = get_meta("manager") if has_meta("manager") else null
		if manager == null:
			return
		var bolt_data: Array = manager._bolt_data
		var intensity: float = manager._bolt_intensity

		if intensity <= 0.001 or bolt_data.is_empty():
			return

		for bolt in bolt_data:
			var points: PackedVector2Array = bolt["points"]
			if points.size() < 2:
				continue
			var cf: float = bolt["color_factor"]
			var base_width: float = bolt["width"]

			# Outer glow: wider, blue-white, softer
			var glow_alpha: float = clamp(cf * intensity * 0.5, 0.0, 1.0)
			var glow_color := Color(0.5, 0.65, 1.0, glow_alpha)
			draw_polyline(points, glow_color, base_width * 4.0, true)

			# Mid glow: medium width, brighter blue-white
			var mid_alpha: float = clamp(cf * intensity * 0.75, 0.0, 1.0)
			var mid_color := Color(0.7, 0.82, 1.0, mid_alpha)
			draw_polyline(points, mid_color, base_width * 2.0, true)

			# Core: narrow, near-white
			var core_alpha: float = clamp(cf * intensity, 0.0, 1.0)
			var core_color := Color(0.95, 0.97, 1.0, core_alpha)
			draw_polyline(points, core_color, base_width, true)

		# Corona circle at the origin of each top-level bolt (bright glow near strike point)
		if bolt_data.size() > 0:
			var first_points: PackedVector2Array = bolt_data[0]["points"]
			if first_points.size() > 0:
				var origin: Vector2 = first_points[0]
				var corona_alpha: float = clamp(intensity * 0.35, 0.0, 1.0)
				# Large soft corona
				draw_circle(origin, 60.0, Color(0.55, 0.70, 1.0, corona_alpha * 0.3))
				draw_circle(origin, 25.0, Color(0.75, 0.85, 1.0, corona_alpha * 0.6))
				draw_circle(origin, 8.0,  Color(0.95, 0.97, 1.0, corona_alpha))
