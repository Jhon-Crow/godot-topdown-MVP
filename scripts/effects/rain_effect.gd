extends Node2D
class_name RainEffect
## Hotline Miami 2-style top-down rain effect (Issue #1394, fixed #1499, #1546, #1579, #1615).
##
## Two-layer world-space particle system so raindrops stay at their spawned
## world positions as the camera moves — the rain no longer follows the player.
## The emitters track the camera center each frame so new drops always appear
## in the visible viewport area:
##   - RainStreaks: short oval dashes falling inward (top-down radial perspective)
##   - RainSplashes: circular ring ripples at the point where streaks land
##
## Rain is always active (continuous) while the node is active.
## Building exclusion zones are applied via a per-particle occlusion shader
## (rain_occlusion.gdshader) so rain is visually masked only inside building
## footprints — rain outside buildings remains unaffected regardless of where
## the camera or player is located (Fix #1615).
##
## Fix #1579: Emitters moved to world space (no CanvasLayer) and tracked to
## camera center each frame, matching the SnowEffect world-space approach so
## rain drops stay fixed in the world instead of following the screen.
##
## Fix #1615: Exclusion zones are now pushed to the particle shader as uniforms
## rather than toggling emitting on/off. This allows rain to continue globally
## while individual particles inside building zones are discarded by the GPU.

## Maximum exclusion zones supported by the occlusion shader.
const MAX_SHADER_ZONES: int = 8

## Indoor exclusion zones (rain particles inside these rects are discarded).
## Each Rect2 defines a rectangular area in global coordinates.
var exclusion_zones: Array[Rect2] = []

## Inward radial rain streaks particle node (defined in .tscn).
@onready var _streaks: GPUParticles2D = $RainStreaks

## Ground splash ripples particle node (defined in .tscn).
@onready var _splashes: GPUParticles2D = $RainSplashes

## Controls emission state of both particle layers.
var emitting: bool = false:
	set(value):
		emitting = value
		if _streaks:
			_streaks.emitting = value
		if _splashes:
			_splashes.emitting = value

## Whether time is currently stopped (e.g. last chance effect). When true,
## particle emission is paused regardless of exclusion zone state.
var _time_stopped: bool = false

## Cached camera reference, refreshed each frame if null.
var _camera: Camera2D = null


func _ready() -> void:
	# Register in group so LastChanceEffectsManager can find this node reliably
	# (script resource_path may be empty in exported builds).
	add_to_group("precipitation_effects")
	# Rain is always on from the start
	emitting = true
	_log("Rain started (continuous mode, world-space emitters, shader occlusion)")


func _process(_delta: float) -> void:
	# While time is stopped, do not update emission.
	if _time_stopped:
		return

	if _camera == null:
		_find_camera()
	if _camera == null:
		return

	# Keep emitters centered on the current camera so new drops always
	# spawn within the visible viewport area. Already-spawned drops remain
	# at their world positions — the rain does not follow the player.
	var cam_pos := _camera.get_screen_center_position()
	if _streaks:
		_streaks.global_position = cam_pos
	if _splashes:
		_splashes.global_position = cam_pos


## Adds a rectangular exclusion zone where rain particles will be discarded.
## The rect should be in global coordinates.
## After adding zones, call _update_shader_zones() to push to the GPU.
func add_exclusion_zone(rect: Rect2) -> void:
	exclusion_zones.append(rect)
	_update_shader_zones()


## Removes all exclusion zones and clears them from the shader.
func clear_exclusion_zones() -> void:
	exclusion_zones.clear()
	_update_shader_zones()


## Returns true if rain is currently emitting.
func is_raining() -> bool:
	return emitting


## Pauses or resumes particle emission for time-stop effects (e.g. last chance).
## When paused is true, both particle layers are frozen in place by disabling their
## process mode — existing particles stay visible, no new ones are spawned.
## When paused is false, particle processing is restored and emission resumes.
func set_time_stopped(paused: bool) -> void:
	if _time_stopped == paused:
		return
	_time_stopped = paused
	if paused:
		# Disable processing on particle nodes so they freeze in place (existing
		# particles remain visible) rather than disappearing via emitting = false.
		if _streaks:
			_streaks.process_mode = Node.PROCESS_MODE_DISABLED
		if _splashes:
			_splashes.process_mode = Node.PROCESS_MODE_DISABLED
		_log("Rain paused (time stopped)")
	else:
		# Restore particle processing.
		if _streaks:
			_streaks.process_mode = Node.PROCESS_MODE_INHERIT
		if _splashes:
			_splashes.process_mode = Node.PROCESS_MODE_INHERIT
		emitting = true
		_log("Rain resumed (time resumed)")


func _find_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	_camera = viewport.get_camera_2d()


## Pushes the current exclusion_zones array to both particle shader materials.
## Each Rect2 is encoded as a Vector4(x_min, y_min, x_max, y_max).
## Up to MAX_SHADER_ZONES zones are supported.
func _update_shader_zones() -> void:
	var count := mini(exclusion_zones.size(), MAX_SHADER_ZONES)

	# Build packed zone array (Vector4 per zone, padded to MAX_SHADER_ZONES).
	var zone_array: Array[Vector4] = []
	for i in range(MAX_SHADER_ZONES):
		if i < count:
			var r := exclusion_zones[i]
			zone_array.append(Vector4(r.position.x, r.position.y,
					r.position.x + r.size.x, r.position.y + r.size.y))
		else:
			zone_array.append(Vector4(0.0, 0.0, 0.0, 0.0))

	_set_shader_zones(_streaks, count, zone_array)
	_set_shader_zones(_splashes, count, zone_array)

	if count > 0:
		_log("Rain occlusion: %d zone(s) active" % count)
	else:
		_log("Rain occlusion: no zones (rain visible everywhere)")


func _set_shader_zones(particles: GPUParticles2D, count: int, zone_array: Array[Vector4]) -> void:
	if particles == null:
		return
	var mat := particles.material
	if mat == null or not mat is ShaderMaterial:
		return
	mat.set_shader_parameter("zone_count", count)
	mat.set_shader_parameter("zones", zone_array)


## Logs a rain effect message through the FileLogger autoload if available.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[RainEffect] " + message)
	else:
		print("[RainEffect] " + message)
