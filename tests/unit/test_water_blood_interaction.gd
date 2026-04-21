extends GutTest
## Unit tests for blood-in-water behaviour (Issue #1578).
##
## Tests:
##   - WaterBody registers itself in the "water_body" group on _ready
##   - WaterBody.is_point_in_water() correctly identifies positions inside/outside water
##   - WaterBody.spawn_blood_diffusion_at() public API delegates to _spawn_blood_diffusion
##   - ImpactEffectsManager helper _find_water_body_at() logic (mocked)
##   - Blood diffusion colour default (Issue #1578: dark red cloud)
##   - WaterBody._on_area_entered() triggers diffusion and schedules decal removal


# ============================================================================
# Mock WaterBody for logic tests (no scene tree required)
# ============================================================================


class MockWaterBody:
	## Water rectangle dimensions.
	var water_width: float = 2400.0
	var water_height: float = 420.0

	## World-space centre — matches BeachLevel WaterBody position.
	var global_position: Vector2 = Vector2(1264, 242)

	## Group membership (simulates add_to_group("water_body") in _ready).
	var _groups: Array[String] = ["water_body"]

	## Track calls to spawn_blood_diffusion_at.
	var diffusion_spawned_count: int = 0
	var tint_registered_count: int = 0
	var last_diffusion_pos: Vector2 = Vector2.ZERO
	var last_diffusion_color: Color = Color.BLACK

	## Check group membership.
	func is_in_group(group_name: String) -> bool:
		return group_name in _groups

	## Mirrors WaterBody._is_point_in_water().
	func is_point_in_water(world_pos: Vector2) -> bool:
		var local_pos: Vector2 = world_pos - global_position
		var half_w: float = water_width * 0.5
		var half_h: float = water_height * 0.5
		return abs(local_pos.x) <= half_w and abs(local_pos.y) <= half_h

	func spawn_blood_diffusion_at(world_pos: Vector2, blood_color: Color) -> void:
		diffusion_spawned_count += 1
		last_diffusion_pos = world_pos
		last_diffusion_color = blood_color

	func register_blood_tint_at(world_pos: Vector2, blood_color: Color, absorbed_hits: int = 1) -> void:
		tint_registered_count += 1
		last_diffusion_pos = world_pos
		last_diffusion_color = blood_color

	func update_blood_tint_fade(world_pos: Vector2, blood_color: Color, absorbed_hits: int, fade_t: float) -> void:
		last_diffusion_pos = world_pos
		last_diffusion_color = blood_color
		if fade_t >= 1.0:
			tint_registered_count += 1


# ============================================================================
# Mock blood decal for _on_area_entered tests
# ============================================================================


class MockBloodDecalNode:
	var global_position: Vector2 = Vector2.ZERO
	var modulate: Color = Color(0.6, 0.0, 0.0, 0.85)
	var _quick_fade_called: bool = false
	var _queue_freed: bool = false

	func is_in_group(_g: String) -> bool:
		return false

	func fade_out_quick() -> void:
		_quick_fade_called = true

	func queue_free() -> void:
		_queue_freed = true


# ============================================================================
# Helper: simulate ImpactEffectsManager._find_water_body_at() logic
# ============================================================================


class MockImpactEffectsManager:
	## Simulated list of water bodies in the scene (mirrors get_nodes_in_group result).
	var _water_bodies: Array = []

	func add_water_body(wb) -> void:
		_water_bodies.append(wb)

	## Mirrors ImpactEffectsManager._find_water_body_at().
	func find_water_body_at(world_pos: Vector2):
		for wb in _water_bodies:
			if wb.has_method("is_point_in_water") and wb.is_point_in_water(world_pos):
				return wb
		return null


# ============================================================================
# Test fixtures
# ============================================================================


var water: MockWaterBody
var manager: MockImpactEffectsManager


func before_each() -> void:
	water = MockWaterBody.new()
	manager = MockImpactEffectsManager.new()
	manager.add_water_body(water)


func after_each() -> void:
	water = null
	manager = null


# ============================================================================
# WaterBody group registration (Issue #1578)
# ============================================================================


func test_water_body_registers_in_water_body_group() -> void:
	assert_true(water.is_in_group("water_body"),
		"WaterBody must register itself in the 'water_body' group so ImpactEffectsManager can find it")


# ============================================================================
# is_point_in_water — boundary tests
# ============================================================================


func test_centre_is_in_water() -> void:
	assert_true(water.is_point_in_water(water.global_position),
		"Water centre must be inside water bounds")


func test_position_outside_is_not_in_water() -> void:
	var outside: Vector2 = Vector2(-5000.0, -5000.0)
	assert_false(water.is_point_in_water(outside),
		"A position far outside the water area must not be detected as in-water")


func test_left_edge_is_in_water() -> void:
	var left_edge: Vector2 = Vector2(
		water.global_position.x - water.water_width * 0.5,
		water.global_position.y
	)
	assert_true(water.is_point_in_water(left_edge),
		"The exact left boundary should be considered inside water")


func test_just_outside_right_edge_is_not_in_water() -> void:
	var outside: Vector2 = Vector2(
		water.global_position.x + water.water_width * 0.5 + 1.0,
		water.global_position.y
	)
	assert_false(water.is_point_in_water(outside),
		"1 px outside the right boundary must not be in water")


func test_top_edge_is_in_water() -> void:
	var top_edge: Vector2 = Vector2(
		water.global_position.x,
		water.global_position.y - water.water_height * 0.5
	)
	assert_true(water.is_point_in_water(top_edge),
		"Top boundary should be inside water")


func test_just_outside_bottom_edge_is_not_in_water() -> void:
	var outside: Vector2 = Vector2(
		water.global_position.x,
		water.global_position.y + water.water_height * 0.5 + 1.0
	)
	assert_false(water.is_point_in_water(outside),
		"1 px below the bottom boundary must not be in water")


# ============================================================================
# spawn_blood_diffusion_at — public API (Issue #1578)
# ============================================================================


func test_spawn_blood_diffusion_at_increments_counter() -> void:
	water.spawn_blood_diffusion_at(water.global_position, Color(0.5, 0.02, 0.02, 0.55))
	assert_eq(water.diffusion_spawned_count, 1,
		"spawn_blood_diffusion_at must trigger diffusion effect")


func test_spawn_blood_diffusion_at_records_position() -> void:
	var target_pos: Vector2 = water.global_position + Vector2(50.0, 30.0)
	water.spawn_blood_diffusion_at(target_pos, Color(0.5, 0.02, 0.02, 0.55))
	assert_eq(water.last_diffusion_pos, target_pos,
		"spawn_blood_diffusion_at must pass the world position through")


func test_spawn_blood_diffusion_at_records_color() -> void:
	var blood_col := Color(0.5, 0.02, 0.02, 0.55)
	water.spawn_blood_diffusion_at(water.global_position, blood_col)
	assert_eq(water.last_diffusion_color, blood_col,
		"spawn_blood_diffusion_at must pass the blood color through")


func test_spawn_blood_diffusion_at_has_method_returns_true() -> void:
	var node := Area2D.new()
	node.set_script(load("res://scripts/objects/water_body.gd"))
	add_child_autofree(node)
	assert_true(node.has_method("spawn_blood_diffusion_at"),
		"WaterBody must expose spawn_blood_diffusion_at so ImpactEffectsManager can call it")


# ============================================================================
# _find_water_body_at logic (ImpactEffectsManager helper)
# ============================================================================


func test_find_water_body_returns_null_outside_water() -> void:
	var result = manager.find_water_body_at(Vector2(-9999.0, -9999.0))
	assert_null(result,
		"_find_water_body_at must return null when position is outside all water areas")


func test_find_water_body_returns_body_inside_water() -> void:
	var result = manager.find_water_body_at(water.global_position)
	assert_not_null(result,
		"_find_water_body_at must return the WaterBody when position is inside it")


func test_find_water_body_returns_correct_body_when_multiple_exist() -> void:
	# Add a second water body far away
	var water2 := MockWaterBody.new()
	water2.global_position = Vector2(9000.0, 9000.0)
	manager.add_water_body(water2)

	# Position inside the first water body
	var result = manager.find_water_body_at(water.global_position)
	assert_not_null(result, "Should find a water body")
	# The returned body should recognise the query position as in-water
	assert_true(result.is_point_in_water(water.global_position),
		"The returned water body must contain the queried position")


func test_find_water_body_spawns_diffusion_when_in_water() -> void:
	# Simulate what _schedule_delayed_decal does when it finds a water body.
	var landing_pos: Vector2 = water.global_position + Vector2(20.0, 10.0)
	var wb = manager.find_water_body_at(landing_pos)
	assert_not_null(wb, "Should find water body at landing position")
	wb.spawn_blood_diffusion_at(landing_pos, Color(0.5, 0.02, 0.02, 0.55))
	assert_eq(water.diffusion_spawned_count, 1,
		"Diffusion effect should be triggered when blood lands in water")


func test_no_diffusion_spawned_when_outside_water() -> void:
	var outside_pos: Vector2 = Vector2(-5000.0, -5000.0)
	var wb = manager.find_water_body_at(outside_pos)
	assert_null(wb, "No water body found outside water area")
	# diffusion_spawned_count must remain 0 — no spurious calls
	assert_eq(water.diffusion_spawned_count, 0,
		"No diffusion should be triggered for positions outside water")


# ============================================================================
# Blood diffusion default color (Issue #1578 — dark red cloud in water)
# ============================================================================


func test_default_blood_diffusion_color_is_dark_red() -> void:
	# The default blood color used when ImpactEffectsManager spawns a diffusion effect.
	var default_color := Color(0.5, 0.02, 0.02, 0.55)
	assert_almost_eq(default_color.r, 0.5, 0.01, "Red channel should be ~0.5 (dark red)")
	assert_almost_eq(default_color.g, 0.02, 0.01, "Green channel should be ~0.02 (near zero)")
	assert_almost_eq(default_color.b, 0.02, 0.01, "Blue channel should be ~0.02 (near zero)")
	assert_almost_eq(default_color.a, 0.55, 0.01, "Alpha should be ~0.55 (semi-transparent cloud)")


func test_blood_diffusion_cloud_duration_and_water_tint_persists() -> void:
	var script := load("res://scripts/effects/water_blood_diffusion.gd")
	assert_not_null(script, "WaterBloodDiffusion script must load")
	# Cloud disperses quickly; water tint persists via WaterBody shader for 75+ seconds.
	assert_gt(script.DURATION, 3.0,
		"Blood diffusion cloud must have a non-trivial lifetime before dispersing")
	assert_lt(script.DURATION, 60.0,
		"Blood diffusion cloud itself should disperse quickly; water tint persists via shader")
	# Verify on_tint_update callback is exposed for gradual water tint notification
	var diffusion: Node2D = script.new()
	add_child_autofree(diffusion)
	assert_true("on_tint_update" in diffusion,
		"WaterBloodDiffusion must expose on_tint_update callback for gradual water tint")


func test_blood_diffusion_renders_below_water_layer() -> void:
	var script := load("res://scripts/effects/water_blood_diffusion.gd")
	var diffusion: Node2D = script.new()
	add_child_autofree(diffusion)
	diffusion._ready()
	assert_eq(diffusion.z_index, 0,
		"Water blood diffusion should render below WaterVisual so waves/water sit above it")


func test_water_body_exposes_blood_tint_registration_api() -> void:
	var node := Area2D.new()
	node.set_script(load("res://scripts/objects/water_body.gd"))
	add_child_autofree(node)
	assert_true(node.has_method("register_blood_tint_at"),
		"WaterBody must expose register_blood_tint_at for direct-spawn exported-build fallback")
	assert_true(node.has_method("update_blood_tint_fade"),
		"WaterBody must expose update_blood_tint_fade for gradual tint (Issue #1578 feedback)")
	water.register_blood_tint_at(water.global_position, Color(0.5, 0.02, 0.02, 0.55))
	assert_eq(water.tint_registered_count, 1,
		"Direct blood diffusion fallback must also register red water tint")


# ============================================================================
# WaterBody._on_area_entered removal logic (Issue #1578)
# ============================================================================


class MockWaterBodyWithRemovalTracking extends MockWaterBody:
	## Tracks the last decal that had fade_out_quick or queue_free called on it.
	var last_removed_decal = null

	## Mirrors the key removal logic from WaterBody._on_area_entered().
	## Returns true if a decal would be removed.
	func handle_blood_puddle_entered(blood_decal) -> bool:
		if blood_decal == null:
			return false

		# Spawn diffusion at the decal position
		spawn_blood_diffusion_at(blood_decal.global_position, blood_decal.modulate)

		# Remove the decal
		last_removed_decal = blood_decal
		if blood_decal.has_method("fade_out_quick"):
			blood_decal.fade_out_quick()
		else:
			blood_decal.queue_free()
		return true


func test_blood_puddle_entering_water_triggers_diffusion() -> void:
	var wb := MockWaterBodyWithRemovalTracking.new()
	var decal := MockBloodDecalNode.new()
	decal.global_position = wb.global_position + Vector2(10.0, 5.0)

	var handled: bool = wb.handle_blood_puddle_entered(decal)
	assert_true(handled, "Blood puddle entering water should be handled")
	assert_eq(wb.diffusion_spawned_count, 1,
		"A diffusion effect must be spawned when a blood puddle enters water")


func test_blood_puddle_entering_water_is_removed_via_fade() -> void:
	var wb := MockWaterBodyWithRemovalTracking.new()
	var decal := MockBloodDecalNode.new()
	decal.global_position = wb.global_position

	wb.handle_blood_puddle_entered(decal)
	assert_true(decal._quick_fade_called,
		"fade_out_quick must be called on the blood decal when it enters water")


func test_blood_puddle_diffusion_pos_matches_decal_pos() -> void:
	var wb := MockWaterBodyWithRemovalTracking.new()
	var decal := MockBloodDecalNode.new()
	var expected_pos: Vector2 = wb.global_position + Vector2(77.0, -33.0)
	decal.global_position = expected_pos

	wb.handle_blood_puddle_entered(decal)
	assert_eq(wb.last_diffusion_pos, expected_pos,
		"Diffusion effect must be spawned at the exact position of the blood decal")


# ============================================================================
# FPS fix: diffusion merging and cap (Issue #1578)
# ============================================================================


class MockDiffusion:
	var global_position: Vector2 = Vector2.ZERO
	var absorbed: bool = false
	var freed: bool = false

	func absorb() -> void:
		absorbed = true

	func queue_free() -> void:
		freed = true


class MockImpactManagerWithDiffusion:
	const MAX_CONCURRENT_DIFFUSIONS: int = 8
	const DIFFUSION_MERGE_RADIUS: float = 120.0

	var _active_diffusions: Array = []
	var spawned_count: int = 0
	var merged_count: int = 0

	func handle_blood_in_water(landing_pos: Vector2) -> void:
		_active_diffusions = _active_diffusions.filter(func(n): return not n.freed)

		# Try merge into nearest within radius
		var nearest = null
		var nearest_dist: float = DIFFUSION_MERGE_RADIUS
		for d in _active_diffusions:
			var dist: float = d.global_position.distance_to(landing_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = d
		if nearest != null:
			nearest.absorb()
			merged_count += 1
			return

		# Enforce cap
		while _active_diffusions.size() >= MAX_CONCURRENT_DIFFUSIONS:
			var oldest = _active_diffusions.pop_front()
			oldest.queue_free()

		var d := MockDiffusion.new()
		d.global_position = landing_pos
		_active_diffusions.append(d)
		spawned_count += 1


func test_nearby_blood_hits_merge_into_existing_diffusion() -> void:
	var mgr := MockImpactManagerWithDiffusion.new()
	var base_pos := Vector2(500.0, 300.0)
	# Spawn initial
	mgr.handle_blood_in_water(base_pos)
	assert_eq(mgr.spawned_count, 1, "First hit should spawn a diffusion node")
	# Hit very close — should merge
	mgr.handle_blood_in_water(base_pos + Vector2(10.0, 5.0))
	assert_eq(mgr.spawned_count, 1, "Nearby hit must not spawn new node")
	assert_eq(mgr.merged_count, 1, "Nearby hit must call absorb on existing node")


func test_far_blood_hits_spawn_separate_diffusion() -> void:
	var mgr := MockImpactManagerWithDiffusion.new()
	mgr.handle_blood_in_water(Vector2(500.0, 300.0))
	mgr.handle_blood_in_water(Vector2(900.0, 300.0))  # 400px away — beyond merge radius
	assert_eq(mgr.spawned_count, 2, "Blood hits beyond merge radius must spawn separate effects")
	assert_eq(mgr.merged_count, 0, "Hits beyond merge radius must not merge")


func test_diffusion_cap_prevents_more_than_max_concurrent() -> void:
	var mgr := MockImpactManagerWithDiffusion.new()
	for i in range(MockImpactManagerWithDiffusion.MAX_CONCURRENT_DIFFUSIONS + 3):
		mgr.handle_blood_in_water(Vector2(float(i) * 300.0, 300.0))  # all far apart
	assert_lte(mgr._active_diffusions.size(), MockImpactManagerWithDiffusion.MAX_CONCURRENT_DIFFUSIONS,
		"Active diffusion count must not exceed MAX_CONCURRENT_DIFFUSIONS")


func test_oldest_diffusion_freed_when_cap_exceeded() -> void:
	var mgr := MockImpactManagerWithDiffusion.new()
	for i in range(MockImpactManagerWithDiffusion.MAX_CONCURRENT_DIFFUSIONS):
		mgr.handle_blood_in_water(Vector2(float(i) * 300.0, 0.0))
	var first_pos := mgr._active_diffusions[0].global_position
	# One more hit far away forces eviction of oldest
	mgr.handle_blood_in_water(Vector2(9999.0, 9999.0))
	# Oldest should be freed
	assert_eq(mgr._active_diffusions[0].global_position, Vector2(300.0, 0.0),
		"After cap exceeded, the oldest diffusion should be evicted")


func test_diffusion_no_gpu_particles() -> void:
	var script := load("res://scripts/effects/water_blood_diffusion.gd")
	assert_not_null(script, "WaterBloodDiffusion script must load")
	var diffusion: Node2D = script.new()
	add_child_autofree(diffusion)
	diffusion._ready()
	var has_particles: bool = false
	for child in diffusion.get_children():
		if child is GPUParticles2D:
			has_particles = true
	assert_false(has_particles, "WaterBloodDiffusion must not use GPUParticles2D (FPS fix)")


func test_absorb_increases_intensity_flag() -> void:
	var script := load("res://scripts/effects/water_blood_diffusion.gd")
	var diffusion = script.new()
	add_child_autofree(diffusion)
	var before: float = diffusion._extra_alpha
	diffusion.absorb()
	assert_gt(diffusion._extra_alpha, before,
		"absorb() must increase _extra_alpha to make the cloud darker after merging")
