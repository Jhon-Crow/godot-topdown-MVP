extends GutTest
## Unit tests for water_body.gd (Issue #1445, enhanced Issue #1550).
##
## Tests:
##   - UV coordinate conversion of world positions to shader obstacle UVs
##   - Clamping of UV values to [0..1] range
##   - Obstacle slot limit (MAX_OBSTACLE_SHADER_SLOTS = 8)
##   - Point-in-water boundary check logic
##   - Camera limit constant (WallTop bottom edge at y=64)
##   - Wave animation time-stop for last chance effect (Issue #1585)


# ============================================================================
# Mock WaterBody for UV conversion and obstacle logic tests
# ============================================================================


class MockWaterBody:
	## Size of the water rectangle in pixels (matches BeachLevel defaults after Issue #1573).
	var water_width: float = 2400.0
	var water_height: float = 420.0

	## Maximum obstacle UV slots passed to shader (must match shader array size).
	const MAX_OBSTACLE_SHADER_SLOTS: int = 8

	## World-space centre of the water body (matches BeachLevel WaterBody position).
	var global_position: Vector2 = Vector2(1264, 242)

	## Bodies currently inside the water area: body → last_position.
	var _bodies_in_water: Dictionary = {}

	## Convert a world position to UV coordinates within the water rectangle.
	## Mirrors _update_obstacle_shader_params() in water_body.gd.
	func world_to_water_uv(world_pos: Vector2) -> Vector2:
		var local: Vector2 = world_pos - global_position
		var uv: Vector2 = Vector2(
			(local.x + water_width * 0.5) / water_width,
			(local.y + water_height * 0.5) / water_height
		)
		return uv.clamp(Vector2.ZERO, Vector2.ONE)

	## Check if a world position is within the water area bounds.
	## Mirrors _is_point_in_water() in water_body.gd.
	func is_point_in_water(world_pos: Vector2) -> bool:
		var local_pos: Vector2 = world_pos - global_position
		var half_w: float = water_width * 0.5
		var half_h: float = water_height * 0.5
		return abs(local_pos.x) <= half_w and abs(local_pos.y) <= half_h

	## Collect UV positions from _bodies_in_water up to MAX_OBSTACLE_SHADER_SLOTS.
	## Mirrors the collection loop in _update_obstacle_shader_params().
	func collect_obstacle_uvs() -> Array:
		var uvs: Array = []
		for body in _bodies_in_water.keys():
			var world_pos: Vector2 = _bodies_in_water[body]
			var uv: Vector2 = world_to_water_uv(world_pos)
			uvs.append(uv)
			if uvs.size() >= MAX_OBSTACLE_SHADER_SLOTS:
				break
		# Pad with sentinel out-of-range UVs
		while uvs.size() < MAX_OBSTACLE_SHADER_SLOTS:
			uvs.append(Vector2(-1.0, -1.0))
		return uvs

	## Add a fake body at a world position.
	func add_body_at(key: String, world_pos: Vector2) -> void:
		_bodies_in_water[key] = world_pos

	## Remove a body.
	func remove_body(key: String) -> void:
		_bodies_in_water.erase(key)


# ============================================================================
# Camera limit constant (Issue #1550 — restrict camera top to hide WallTop)
# ============================================================================


class MockBeachLevelCamera:
	## WallTop bottom edge in world space (matches BeachLevel.tscn):
	## WallTop position = (1264, 48), height = 32 → bottom = 48 + 16 = 64.
	const WALL_TOP_BOTTOM_EDGE: int = 64

	## Camera limit_top as set by _setup_camera_limits() — Issue #1550.
	var camera_limit_top: int = 0

	func setup_camera_limits() -> void:
		camera_limit_top = WALL_TOP_BOTTOM_EDGE


var water: MockWaterBody
var beach_cam: MockBeachLevelCamera


func before_each() -> void:
	water = MockWaterBody.new()
	beach_cam = MockBeachLevelCamera.new()


func after_each() -> void:
	water = null
	beach_cam = null


# ============================================================================
# UV Coordinate Conversion Tests (Issue #1550 wave interruption)
# ============================================================================


func test_water_centre_maps_to_uv_half() -> void:
	# The centre of the water body in world space should map to UV (0.5, 0.5).
	var uv: Vector2 = water.world_to_water_uv(water.global_position)
	assert_almost_eq(uv.x, 0.5, 0.001, "Water centre X should map to UV 0.5")
	assert_almost_eq(uv.y, 0.5, 0.001, "Water centre Y should map to UV 0.5")


func test_water_left_edge_maps_to_uv_zero_x() -> void:
	# Left edge = global_position.x - water_width/2
	var left_edge: Vector2 = Vector2(water.global_position.x - water.water_width * 0.5,
	                                  water.global_position.y)
	var uv: Vector2 = water.world_to_water_uv(left_edge)
	assert_almost_eq(uv.x, 0.0, 0.001, "Left edge should map to UV x=0")


func test_water_right_edge_maps_to_uv_one_x() -> void:
	var right_edge: Vector2 = Vector2(water.global_position.x + water.water_width * 0.5,
	                                   water.global_position.y)
	var uv: Vector2 = water.world_to_water_uv(right_edge)
	assert_almost_eq(uv.x, 1.0, 0.001, "Right edge should map to UV x=1")


func test_water_top_edge_maps_to_uv_zero_y() -> void:
	var top_edge: Vector2 = Vector2(water.global_position.x,
	                                 water.global_position.y - water.water_height * 0.5)
	var uv: Vector2 = water.world_to_water_uv(top_edge)
	assert_almost_eq(uv.y, 0.0, 0.001, "Top edge should map to UV y=0")


func test_water_bottom_edge_maps_to_uv_one_y() -> void:
	var bottom_edge: Vector2 = Vector2(water.global_position.x,
	                                    water.global_position.y + water.water_height * 0.5)
	var uv: Vector2 = water.world_to_water_uv(bottom_edge)
	assert_almost_eq(uv.y, 1.0, 0.001, "Bottom edge should map to UV y=1")


func test_uv_clamped_for_position_outside_water_left() -> void:
	# A position far to the left should clamp UV x to 0.
	var far_left: Vector2 = Vector2(-9999.0, water.global_position.y)
	var uv: Vector2 = water.world_to_water_uv(far_left)
	assert_eq(uv.x, 0.0, "UV x should be clamped to 0 for positions left of water")


func test_uv_clamped_for_position_outside_water_right() -> void:
	var far_right: Vector2 = Vector2(99999.0, water.global_position.y)
	var uv: Vector2 = water.world_to_water_uv(far_right)
	assert_eq(uv.x, 1.0, "UV x should be clamped to 1 for positions right of water")


func test_uv_values_always_in_range() -> void:
	# Arbitrary positions inside and around the water area.
	var positions: Array = [
		water.global_position,
		water.global_position + Vector2(100, 50),
		water.global_position - Vector2(300, 80),
		Vector2(0, 0),
		Vector2(9999, 9999),
	]
	for pos in positions:
		var uv: Vector2 = water.world_to_water_uv(pos)
		assert_gte(uv.x, 0.0, "UV.x must be >= 0")
		assert_lte(uv.x, 1.0, "UV.x must be <= 1")
		assert_gte(uv.y, 0.0, "UV.y must be >= 0")
		assert_lte(uv.y, 1.0, "UV.y must be <= 1")


# ============================================================================
# Obstacle Slot Limit Tests (Issue #1550)
# ============================================================================


func test_no_bodies_produces_max_sentinel_uvs() -> void:
	var uvs: Array = water.collect_obstacle_uvs()
	assert_eq(uvs.size(), MockWaterBody.MAX_OBSTACLE_SHADER_SLOTS,
		"UV array must always have MAX_OBSTACLE_SHADER_SLOTS entries")
	for uv in uvs:
		assert_eq(uv, Vector2(-1.0, -1.0),
			"Empty slots should be padded with sentinel (-1, -1)")


func test_one_body_in_water_produces_one_valid_uv() -> void:
	water.add_body_at("player", water.global_position)
	var uvs: Array = water.collect_obstacle_uvs()
	assert_eq(uvs.size(), MockWaterBody.MAX_OBSTACLE_SHADER_SLOTS,
		"UV array size must always equal MAX_OBSTACLE_SHADER_SLOTS")
	# First entry should be valid (centre = 0.5, 0.5)
	assert_almost_eq(uvs[0].x, 0.5, 0.001, "Player at centre → UV x=0.5")
	assert_almost_eq(uvs[0].y, 0.5, 0.001, "Player at centre → UV y=0.5")
	# Remaining slots must be sentinels
	for i in range(1, uvs.size()):
		assert_eq(uvs[i], Vector2(-1.0, -1.0),
			"Unused slots should remain as sentinels")


func test_obstacle_count_capped_at_max_slots() -> void:
	# Add more than MAX_OBSTACLE_SHADER_SLOTS bodies.
	for i in range(12):
		water.add_body_at("body_%d" % i, water.global_position + Vector2(i * 10, 0))
	var uvs: Array = water.collect_obstacle_uvs()
	assert_eq(uvs.size(), MockWaterBody.MAX_OBSTACLE_SHADER_SLOTS,
		"collect_obstacle_uvs must not exceed MAX_OBSTACLE_SHADER_SLOTS entries")
	# None should be the sentinel value (all 8 slots filled)
	var valid_count: int = 0
	for uv in uvs:
		if uv != Vector2(-1.0, -1.0):
			valid_count += 1
	assert_eq(valid_count, MockWaterBody.MAX_OBSTACLE_SHADER_SLOTS,
		"All 8 slots should be valid positions when more than 8 bodies are present")


func test_max_obstacle_shader_slots_is_eight() -> void:
	assert_eq(MockWaterBody.MAX_OBSTACLE_SHADER_SLOTS, 8,
		"MAX_OBSTACLE_SHADER_SLOTS must be 8 to match shader array size")


# ============================================================================
# Point-In-Water Boundary Tests
# ============================================================================


func test_centre_is_in_water() -> void:
	assert_true(water.is_point_in_water(water.global_position),
		"Water centre should be inside water bounds")


func test_far_outside_is_not_in_water() -> void:
	assert_false(water.is_point_in_water(Vector2(-9999, -9999)),
		"Position far outside should not be in water")


func test_exact_left_edge_is_in_water() -> void:
	var edge: Vector2 = Vector2(water.global_position.x - water.water_width * 0.5,
	                             water.global_position.y)
	assert_true(water.is_point_in_water(edge),
		"Exact left boundary should be considered inside water")


func test_just_outside_right_edge_is_not_in_water() -> void:
	var outside: Vector2 = Vector2(water.global_position.x + water.water_width * 0.5 + 1.0,
	                                water.global_position.y)
	assert_false(water.is_point_in_water(outside),
		"1px outside right boundary should not be inside water")


# ============================================================================
# Camera Top Limit Tests (Issue #1550 — WallTop must not be visible)
# ============================================================================


func test_wall_top_bottom_edge_constant() -> void:
	# WallTop in BeachLevel.tscn: position=(1264,48), size=(2464,32).
	# Centre y=48, half-height=16 → bottom edge = 48 + 16 = 64.
	assert_eq(MockBeachLevelCamera.WALL_TOP_BOTTOM_EDGE, 64,
		"WALL_TOP_BOTTOM_EDGE should be 64 (WallTop bottom edge in world space)")


func test_camera_limit_top_set_to_wall_bottom_edge() -> void:
	beach_cam.setup_camera_limits()
	assert_eq(beach_cam.camera_limit_top, 64,
		"Camera limit_top must equal WALL_TOP_BOTTOM_EDGE (64) after setup")


func test_camera_limit_not_zero_after_setup() -> void:
	# Default value is 0 (shows wall). After setup it should be 64.
	assert_eq(beach_cam.camera_limit_top, 0,
		"Before setup, camera_limit_top should be 0 (default)")
	beach_cam.setup_camera_limits()
	assert_ne(beach_cam.camera_limit_top, 0,
		"After setup, camera_limit_top must not be 0 — WallTop must be hidden")


func test_water_top_edge_above_wall_bottom_edge() -> void:
	# Water node in BeachLevel: position=(1264,242), height=420 (Issue #1573 increased from 356).
	# Top edge = 242 - 420/2 = 242 - 210 = 32.
	# This is above (less than) WallTop bottom edge (64) — the water now visually overlaps
	# the wall area at the top to allow the shore-wash gradient to work correctly.
	var water_top_y: float = water.global_position.y - water.water_height * 0.5
	assert_almost_eq(water_top_y, 32.0, 0.001,
		"Water top edge (world y) should be 32 with water_height=420")
	assert_lt(water_top_y, float(MockBeachLevelCamera.WALL_TOP_BOTTOM_EDGE),
		"Water top edge (32) should be above WallTop bottom edge (64) — Issue #1573 shore wash")


# ============================================================================
# Bullet Pass-Through Tests (Issue #1577 — water must not block bullets)
# ============================================================================


class MockCollisionLayers:
	## Collision layers from project.godot.
	const LAYER_PLAYER: int = 1       # layer 1
	const LAYER_ENEMIES: int = 2      # layer 2
	const LAYER_OBSTACLES: int = 4    # layer 3
	const LAYER_PROJECTILES: int = 16 # layer 5
	const LAYER_TARGETS: int = 32     # layer 6
	const LAYER_DECORATIVE: int = 64  # layer 7

	## Water collision_layer (Area2D, set in _ready() and WaterBody.tscn).
	const WATER_COLLISION_LAYER: int = 0
	## Water collision_mask: detects player, enemies, targets, decorative — NOT projectiles.
	const WATER_COLLISION_MASK: int = 99  # 1+2+32+64 = layers 1,2,6,7

	## Bullet collision_layer (projectiles layer).
	const BULLET_COLLISION_LAYER: int = 16  # layer 5
	## Bullet collision_mask: detects player, enemies, obstacles, targets.
	const BULLET_COLLISION_MASK: int = 39   # 1+2+4+32 = layers 1,2,3,6


func test_water_collision_layer_is_zero() -> void:
	# WaterBody must NOT be on any collision layer so nothing (including bullets)
	# can detect it directly. Set in water_body.gd _ready() and WaterBody.tscn.
	assert_eq(MockCollisionLayers.WATER_COLLISION_LAYER, 0,
		"WaterBody collision_layer must be 0 — it has no layer, so bullets cannot detect it")


func test_water_collision_mask_excludes_projectiles() -> void:
	# Water detects player, enemies, targets, decorative — but NOT projectiles (layer 5 = 16).
	# This was explicitly fixed in Issue #1495 to prevent water from stopping bullets.
	var mask: int = MockCollisionLayers.WATER_COLLISION_MASK
	var bullet_layer: int = MockCollisionLayers.BULLET_COLLISION_LAYER
	assert_eq(mask & bullet_layer, 0,
		"Water collision_mask must NOT include projectiles layer (5=16) — Issue #1495 fix")


func test_bullet_cannot_interact_with_water_area2d() -> void:
	# In Godot 4, two Area2D nodes interact via area_entered when:
	#   A.collision_layer & B.collision_mask != 0  OR
	#   B.collision_layer & A.collision_mask != 0
	# Neither condition holds for bullet and water.
	var bullet_layer: int = MockCollisionLayers.BULLET_COLLISION_LAYER
	var bullet_mask: int = MockCollisionLayers.BULLET_COLLISION_MASK
	var water_layer: int = MockCollisionLayers.WATER_COLLISION_LAYER
	var water_mask: int = MockCollisionLayers.WATER_COLLISION_MASK

	# Water cannot detect bullet: bullet.layer not in water.mask
	assert_eq(water_mask & bullet_layer, 0,
		"Water.collision_mask must not include bullet.collision_layer — bullet should not trigger water area_entered")

	# Bullet cannot detect water: water.layer not in bullet.mask
	assert_eq(bullet_mask & water_layer, 0,
		"Bullet.collision_mask must not include water.collision_layer — water should not trigger bullet area_entered")


func test_water_collision_mask_value_is_correct() -> void:
	# 99 = 1 + 2 + 32 + 64 = layers 1(player) + 2(enemies) + 6(targets) + 7(decorative).
	# This is the exact mask from water_body.gd: 0b01100011 = 99.
	var expected_mask: int = (
		MockCollisionLayers.LAYER_PLAYER +
		MockCollisionLayers.LAYER_ENEMIES +
		MockCollisionLayers.LAYER_TARGETS +
		MockCollisionLayers.LAYER_DECORATIVE
	)
	assert_eq(MockCollisionLayers.WATER_COLLISION_MASK, expected_mask,
		"Water collision_mask (99) should equal layers 1+2+6+7 = 1+2+32+64")


# ============================================================================
# Mock WaterBody for time-stop tests (Issue #1585)
# ============================================================================


class MockWaterBodyTimeStop:
	## Simulated shader material parameters.
	var _wave_speed: float = 0.3
	var _ripple_speed: float = 0.5
	var _surf_speed: float = 0.5
	var _distortion_strength: float = 0.35

	## Whether time is currently stopped.
	var _time_stopped: bool = false

	## Saved speed values for restoration.
	var _saved_wave_speed: float = 0.0
	var _saved_ripple_speed: float = 0.0
	var _saved_surf_speed: float = 0.0
	var _saved_distortion_strength: float = 0.0

	## Whether a shader material is attached (simulate missing material case).
	var has_material: bool = true


	## Simulate set_time_stopped from water_body.gd (Issue #1585, Issue #1738).
	func set_time_stopped(paused: bool) -> void:
		if _time_stopped == paused:
			return
		_time_stopped = paused
		if not has_material:
			return
		if paused:
			_saved_wave_speed = _wave_speed
			_saved_ripple_speed = _ripple_speed
			_saved_surf_speed = _surf_speed
			_saved_distortion_strength = _distortion_strength
			_wave_speed = 0.0
			_ripple_speed = 0.0
			_surf_speed = 0.0
			_distortion_strength = 0.0
		else:
			_wave_speed = _saved_wave_speed
			_ripple_speed = _saved_ripple_speed
			_surf_speed = _saved_surf_speed
			_distortion_strength = _saved_distortion_strength


class MockWaterDistortionComposite:
	## Mirrors the issue #1738 shader composition choice in simple scalar form.
	## The final pixel must be built from the DISTORTED screen sample only;
	## no undistorted "stable" copy may contribute to the output.

	func old_alpha_overlay_compose(distorted_scene: float, water_colour: float, water_alpha: float) -> float:
		return distorted_scene * (1.0 - water_alpha) + water_colour * water_alpha

	## New composition: distorted sample * water tint * brighten factor.
	## No undistorted scene contributes — the output is purely the refracted view tinted blue.
	func refracted_only_compose(distorted_scene: float, water_colour: float) -> float:
		return clamp(distorted_scene * water_colour * 2.0, 0.0, 1.0)


# ============================================================================
# Tests: Issue #1585 — Water waves stop during time-stop (last chance effect)
# ============================================================================


func test_water_wave_speed_zero_when_time_stopped() -> void:
	var wb := MockWaterBodyTimeStop.new()
	wb.set_time_stopped(true)
	assert_eq(wb._wave_speed, 0.0,
		"wave_speed must be 0 when time is stopped")
	assert_eq(wb._ripple_speed, 0.0,
		"ripple_speed must be 0 when time is stopped")
	assert_eq(wb._surf_speed, 0.0,
		"surf_speed must be 0 when time is stopped")


func test_water_wave_speed_restored_when_time_resumes() -> void:
	var wb := MockWaterBodyTimeStop.new()
	var original_wave: float = wb._wave_speed
	var original_ripple: float = wb._ripple_speed
	var original_surf: float = wb._surf_speed
	wb.set_time_stopped(true)
	wb.set_time_stopped(false)
	assert_almost_eq(wb._wave_speed, original_wave, 0.001,
		"wave_speed must be restored to original value after time resumes")
	assert_almost_eq(wb._ripple_speed, original_ripple, 0.001,
		"ripple_speed must be restored to original value after time resumes")
	assert_almost_eq(wb._surf_speed, original_surf, 0.001,
		"surf_speed must be restored to original value after time resumes")


func test_water_time_stopped_is_idempotent() -> void:
	var wb := MockWaterBodyTimeStop.new()
	wb.set_time_stopped(true)
	wb.set_time_stopped(true)
	assert_eq(wb._wave_speed, 0.0,
		"Calling set_time_stopped(true) twice must keep wave_speed at 0")


func test_water_saves_non_default_speeds() -> void:
	# Verify that whatever speed is active at freeze time is saved and restored,
	# not just the default constructor value.
	var wb := MockWaterBodyTimeStop.new()
	wb._wave_speed = 1.2
	wb._ripple_speed = 0.8
	wb._surf_speed = 2.0
	wb.set_time_stopped(true)
	assert_eq(wb._wave_speed, 0.0, "wave_speed must be 0 during time stop")
	wb.set_time_stopped(false)
	assert_almost_eq(wb._wave_speed, 1.2, 0.001,
		"Custom wave_speed must be restored after time resumes")
	assert_almost_eq(wb._ripple_speed, 0.8, 0.001,
		"Custom ripple_speed must be restored after time resumes")
	assert_almost_eq(wb._surf_speed, 2.0, 0.001,
		"Custom surf_speed must be restored after time resumes")


func test_water_set_time_stopped_noop_without_material() -> void:
	# Ensure no crash when shader material is unavailable.
	var wb := MockWaterBodyTimeStop.new()
	wb.has_material = false
	wb.set_time_stopped(true)
	# _time_stopped flag is set but speeds remain unchanged (no material to modify).
	assert_true(wb._time_stopped, "Time stopped flag should be set even without material")
	assert_almost_eq(wb._wave_speed, 0.3, 0.001,
		"wave_speed must be unchanged when no shader material is present")


# ============================================================================
# Tests: Issue #1738 — distortion_strength zeroed during time-stop
# ============================================================================


func test_distortion_strength_zero_when_time_stopped() -> void:
	var wb := MockWaterBodyTimeStop.new()
	wb.set_time_stopped(true)
	assert_eq(wb._distortion_strength, 0.0,
		"distortion_strength must be 0 when time is stopped (Issue #1738)")


func test_distortion_strength_restored_when_time_resumes() -> void:
	var wb := MockWaterBodyTimeStop.new()
	var original_distortion: float = wb._distortion_strength
	wb.set_time_stopped(true)
	wb.set_time_stopped(false)
	assert_almost_eq(wb._distortion_strength, original_distortion, 0.0001,
		"distortion_strength must be restored to original value after time resumes (Issue #1738)")


func test_distortion_strength_saves_non_default_value() -> void:
	var wb := MockWaterBodyTimeStop.new()
	wb._distortion_strength = 0.025
	wb.set_time_stopped(true)
	assert_eq(wb._distortion_strength, 0.0,
		"distortion_strength must be 0 during time stop regardless of prior value")
	wb.set_time_stopped(false)
	assert_almost_eq(wb._distortion_strength, 0.025, 0.0001,
		"Custom distortion_strength must be restored after time resumes")


func test_distortion_strength_noop_without_material() -> void:
	var wb := MockWaterBodyTimeStop.new()
	wb.has_material = false
	var original_distortion: float = wb._distortion_strength
	wb.set_time_stopped(true)
	assert_true(wb._time_stopped,
		"Time stopped flag should be set even without material")
	assert_almost_eq(wb._distortion_strength, original_distortion, 0.0001,
		"distortion_strength must be unchanged when no shader material is present (Issue #1738)")


func test_distortion_and_speeds_all_zero_when_time_stopped() -> void:
	# Regression: all motion parameters must be frozen together (Issue #1738).
	var wb := MockWaterBodyTimeStop.new()
	wb.set_time_stopped(true)
	assert_eq(wb._wave_speed, 0.0, "wave_speed must be 0 when time stopped")
	assert_eq(wb._ripple_speed, 0.0, "ripple_speed must be 0 when time stopped")
	assert_eq(wb._surf_speed, 0.0, "surf_speed must be 0 when time stopped")
	assert_eq(wb._distortion_strength, 0.0, "distortion_strength must be 0 when time stopped")


func test_distorted_scene_is_primary_image_not_alpha_overlay() -> void:
	# Regression: owner confirmed shimmer works, then requested that the original
	# non-distorted picture not remain visible as a second/stable layer.
	# Fix: output = clamp(distorted_scene * water_colour * 2.0, 0, 1)
	# No mix() with the undistorted screen_col — removing the stable layer entirely.
	var composite := MockWaterDistortionComposite.new()
	var distorted_scene := 0.20
	var water_colour := 0.80
	var water_alpha := 0.88
	var old_result := composite.old_alpha_overlay_compose(distorted_scene, water_colour, water_alpha)
	var new_result := composite.refracted_only_compose(distorted_scene, water_colour)

	# Old result is dominated by the stable water_colour (88% contribution) — too close to pure water.
	# New result is a multiply-tint of the distorted sample — no undistorted screen copy.
	assert_gt(abs(old_result - water_colour), abs(new_result - water_colour),
		"Old alpha overlay stays too close to stable water colour and doubles the image")
	# New result is further from the undistorted/stable scene than the old approach,
	# confirming the stable layer is no longer the primary contributor.
	var undistorted_scene := 1.0  # what would show without distortion (stable layer)
	assert_gt(abs(new_result - undistorted_scene), abs(old_result - undistorted_scene),
		"New composition must push the result further from the stable undistorted scene")
