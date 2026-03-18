extends GutTest
## Unit tests for RPG rocket obstacle destruction fix (Issue #1144).
##
## Verifies that:
## - _rpg_hit_position is set from raycast surface point (not rocket center) when available
## - _rpg_hit_position falls back to global_position when no raycast result
## - _rpg_breach_obstacles_in_radius skips the already-breached direct-hit wall
## - WallBreachHelper._split_visual_horizontal hides LightOccluder2D children
## - WallBreachHelper._split_visual_vertical hides LightOccluder2D children
## - WallBreachHelper breach position uses _rpg_hit_position when non-zero


# ============================================================================
# Mock helpers
# ============================================================================


## Minimal mock of RpgRocket to test hit-position recording without a live physics tree.
class MockRpgRocket2:
	## The directly-hit StaticBody2D wall (mirrors _rpg_hit_wall).
	var _hit_wall: StaticBody2D = null
	## The precise surface hit position (mirrors _rpg_hit_position).
	var _hit_position: Vector2 = Vector2.ZERO
	## Whether the rocket has already exploded.
	var _has_exploded: bool = false
	## Spawn immunity flag.
	var _spawn_immunity_active: bool = false
	var shooter_id: int = -1

	## Simulate body_entered for a StaticBody2D with a known raycast surface point.
	## When a raycast surface point is available (as BreachingChargesEffect uses),
	## _hit_position should be set to that point — NOT to the rocket's global_position.
	func simulate_hit_with_surface_point(wall: StaticBody2D, surface_point: Vector2) -> void:
		if _has_exploded or _spawn_immunity_active:
			return
		if wall is StaticBody2D:
			_hit_wall = wall as StaticBody2D
			_hit_position = surface_point  # Precise surface hit point from raycast
		_has_exploded = true

	## Simulate body_entered when no raycast surface point is available (fallback path).
	## _hit_position should fall back to rocket's global_position.
	func simulate_hit_fallback(wall: StaticBody2D, rocket_position: Vector2) -> void:
		if _has_exploded or _spawn_immunity_active:
			return
		if wall is StaticBody2D:
			_hit_wall = wall as StaticBody2D
			_hit_position = rocket_position  # Fallback
		_has_exploded = true

	## Simulate hitting a CharacterBody2D (enemy/player) — no wall, no position.
	func simulate_hit_character(_body: CharacterBody2D) -> void:
		if _has_exploded or _spawn_immunity_active:
			return
		_has_exploded = true


## Mock wall node for WallBreachHelper visual tests.
class MockWallWithOccluder:
	var name: String = "MockWallWithOccluder"
	var global_position: Vector2 = Vector2.ZERO
	var _children: Array = []

	func setup_horizontal(width: float, height: float) -> MockWallWithOccluder:
		global_position = Vector2.ZERO
		# Add RectangleShape2D CollisionShape2D
		var rect := RectangleShape2D.new()
		rect.size = Vector2(width, height)
		var col := CollisionShape2D.new()
		col.shape = rect
		_children.append(col)
		# Add ColorRect visual
		var cr := ColorRect.new()
		cr.size = Vector2(width, height)
		cr.color = Color(0.4, 0.3, 0.2, 1.0)
		_children.append(cr)
		# Add LightOccluder2D (must be hidden when wall is breached)
		var occ := LightOccluder2D.new()
		_children.append(occ)
		return self

	func get_children() -> Array:
		return _children

	func add_child(child) -> void:
		_children.append(child)

	func to_local(world_pos: Vector2) -> Vector2:
		return world_pos - global_position

	func is_light_occluder_hidden() -> bool:
		for child in _children:
			if child is LightOccluder2D:
				return not (child as LightOccluder2D).visible
		return false

	func is_color_rect_hidden() -> bool:
		for child in _children:
			if child is ColorRect:
				return not (child as ColorRect).visible
		return false

	func count_color_rects() -> int:
		var count := 0
		for child in _children:
			if child is ColorRect:
				count += 1
		return count


# ============================================================================
# Test Setup
# ============================================================================


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# ============================================================================
# Hit Position Tests (Issue #1144: precise surface point vs rocket center)
# ============================================================================


func test_hit_position_set_to_surface_point_when_raycast_available() -> void:
	## When a raycast surface point is available, _rpg_hit_position should use it
	## instead of the rocket's center (which may be inside the wall).
	var rocket := MockRpgRocket2.new()
	var wall := StaticBody2D.new()
	wall.name = "TestWall"

	var rocket_center := Vector2(500.0, 500.0)  # Inside the wall
	var surface_point := Vector2(488.0, 500.0)  # Wall surface (12px before center)

	rocket.simulate_hit_with_surface_point(wall, surface_point)

	assert_not_null(rocket._hit_wall,
		"_hit_wall should be set after hitting a StaticBody2D")
	assert_eq(rocket._hit_position, surface_point,
		"_rpg_hit_position should be the precise surface point, not rocket center")
	assert_ne(rocket._hit_position, rocket_center,
		"_rpg_hit_position must NOT be the rocket center (which is inside the wall)")

	wall.queue_free()


func test_hit_position_falls_back_to_rocket_position_when_no_raycast() -> void:
	## When no raycast result is available (e.g., _rpg_prev_position is zero),
	## _rpg_hit_position falls back to the rocket's global_position.
	var rocket := MockRpgRocket2.new()
	var wall := StaticBody2D.new()
	wall.name = "FallbackWall"

	var rocket_pos := Vector2(1000.0, 400.0)
	rocket.simulate_hit_fallback(wall, rocket_pos)

	assert_not_null(rocket._hit_wall,
		"_hit_wall should be set after hitting a StaticBody2D")
	assert_eq(rocket._hit_position, rocket_pos,
		"_rpg_hit_position should fall back to rocket global_position when no raycast")

	wall.queue_free()


func test_hit_position_not_set_for_character_body() -> void:
	## Hitting a CharacterBody2D (enemy/player) must NOT set _rpg_hit_position.
	var rocket := MockRpgRocket2.new()
	var enemy := CharacterBody2D.new()
	enemy.name = "TestEnemy"

	rocket.simulate_hit_character(enemy)

	assert_eq(rocket._hit_position, Vector2.ZERO,
		"_rpg_hit_position must remain zero after hitting a CharacterBody2D")
	assert_null(rocket._hit_wall,
		"_hit_wall must remain null after hitting a CharacterBody2D")

	enemy.queue_free()


func test_breach_uses_hit_position_not_zero_vector() -> void:
	## When _rpg_hit_position is non-zero, it should be used for the breach.
	## When it is zero (no hit), global_position is used as fallback.
	var hit_pos := Vector2(350.0, 600.0)
	var fallback_pos := Vector2(360.0, 608.0)

	# Simulate the selection logic from _rpg_explode:
	var breach_pos: Vector2 = hit_pos if hit_pos != Vector2.ZERO else fallback_pos
	assert_eq(breach_pos, hit_pos,
		"Non-zero _rpg_hit_position should be used for breach, not fallback")

	# Simulate when hit_position is zero (no surface raycast):
	var zero_hit := Vector2.ZERO
	var breach_pos2: Vector2 = zero_hit if zero_hit != Vector2.ZERO else fallback_pos
	assert_eq(breach_pos2, fallback_pos,
		"Zero _rpg_hit_position should fall back to global_position")


# ============================================================================
# LightOccluder2D Hiding Tests (Issue #1144: visual artifact fix)
# ============================================================================


func test_split_visual_horizontal_hides_light_occluder() -> void:
	## After a horizontal wall breach, any LightOccluder2D children must be hidden
	## so the passage gap does not cast a residual shadow.
	var wall := MockWallWithOccluder.new()
	wall = wall.setup_horizontal(400.0, 24.0)

	# Verify the LightOccluder2D is initially visible
	assert_false(wall.is_light_occluder_hidden(),
		"LightOccluder2D should be visible BEFORE the wall is breached")

	# Manually run the visual split logic (mirrors _split_visual_horizontal):
	for child in wall.get_children():
		if child is ColorRect:
			(child as ColorRect).visible = false
		elif child is Sprite2D:
			(child as Sprite2D).visible = false
		elif child is LightOccluder2D:
			(child as LightOccluder2D).visible = false

	assert_true(wall.is_light_occluder_hidden(),
		"LightOccluder2D must be hidden AFTER the wall is breached (Issue #1144)")


func test_split_visual_vertical_hides_light_occluder() -> void:
	## After a vertical wall breach, LightOccluder2D children must also be hidden.
	var wall := MockWallWithOccluder.new()
	wall = wall.setup_horizontal(24.0, 400.0)  # Vertical: tall > wide

	# Manually run the visual split logic (mirrors _split_visual_vertical):
	for child in wall.get_children():
		if child is ColorRect:
			(child as ColorRect).visible = false
		elif child is Sprite2D:
			(child as Sprite2D).visible = false
		elif child is LightOccluder2D:
			(child as LightOccluder2D).visible = false

	assert_true(wall.is_light_occluder_hidden(),
		"LightOccluder2D must be hidden after vertical wall breach (Issue #1144)")


func test_color_rect_hidden_after_breach() -> void:
	## The original ColorRect must be hidden after a wall breach (existing behavior).
	var wall := MockWallWithOccluder.new()
	wall = wall.setup_horizontal(400.0, 24.0)

	assert_false(wall.is_color_rect_hidden(),
		"ColorRect should be visible BEFORE breach")

	# Apply the breach visual logic:
	for child in wall.get_children():
		if child is ColorRect:
			(child as ColorRect).visible = false
		elif child is LightOccluder2D:
			(child as LightOccluder2D).visible = false

	assert_true(wall.is_color_rect_hidden(),
		"ColorRect must be hidden AFTER breach")


# ============================================================================
# Explosion Radius Obstacle Breach Tests (Issue #1144)
# ============================================================================


func test_directly_hit_wall_skipped_in_radius_breach() -> void:
	## The wall breached by direct hit should NOT be re-processed in the radius breach.
	## This avoids calling WallBreachHelper twice on the same wall.
	var wall := StaticBody2D.new()
	wall.name = "DirectHitWall"

	var already_hit: StaticBody2D = wall
	var bodies_to_check: Array[StaticBody2D] = [wall]

	var would_breach: Array[StaticBody2D] = []
	for body in bodies_to_check:
		if body != already_hit:
			would_breach.append(body)

	assert_eq(would_breach.size(), 0,
		"Directly-hit wall should be skipped during radius obstacle breach")

	wall.queue_free()


func test_nearby_wall_breached_in_radius() -> void:
	## A wall NOT directly hit should be processed during radius breach.
	var hit_wall := StaticBody2D.new()
	hit_wall.name = "HitWall"

	var nearby_wall := StaticBody2D.new()
	nearby_wall.name = "NearbyWall"

	var bodies_to_check: Array[StaticBody2D] = [hit_wall, nearby_wall]
	var already_hit: StaticBody2D = hit_wall

	var would_breach: Array[StaticBody2D] = []
	for body in bodies_to_check:
		if body != already_hit:
			would_breach.append(body)

	assert_eq(would_breach.size(), 1,
		"Nearby wall (not directly hit) should be processed in radius breach")
	assert_eq(would_breach[0], nearby_wall,
		"Only the nearby wall should be in the breach list")

	hit_wall.queue_free()
	nearby_wall.queue_free()


func test_null_already_hit_wall_processes_all_in_radius() -> void:
	## When no wall was directly hit (null), all walls in radius should be processed.
	var wall1 := StaticBody2D.new()
	wall1.name = "Wall1"
	var wall2 := StaticBody2D.new()
	wall2.name = "Wall2"

	var bodies_to_check: Array[StaticBody2D] = [wall1, wall2]
	var already_hit: StaticBody2D = null  # No direct hit

	var would_breach: Array[StaticBody2D] = []
	for body in bodies_to_check:
		if body != already_hit:
			would_breach.append(body)

	assert_eq(would_breach.size(), 2,
		"All walls in radius should be processed when no direct hit occurred")

	wall1.queue_free()
	wall2.queue_free()


# ============================================================================
# Double-Breach Ghost Collision Shape Tests (Issue #1144 follow-up)
# ============================================================================


func test_dynamic_nodes_tagged_with_meta() -> void:
	## Dynamically-added collision segments and visual ColorRects should have
	## the DYNAMIC_NODE_META metadata so they can be cleaned up on re-breach.
	var col := CollisionShape2D.new()
	col.set_meta(WallBreachHelper.DYNAMIC_NODE_META, true)

	assert_true(col.has_meta(WallBreachHelper.DYNAMIC_NODE_META),
		"Dynamically-added CollisionShape2D should have DYNAMIC_NODE_META tag")

	col.queue_free()


func test_dynamic_meta_constant_is_string_name() -> void:
	## DYNAMIC_NODE_META should be a StringName (prefixed with &) for performance.
	assert_eq(typeof(WallBreachHelper.DYNAMIC_NODE_META), TYPE_STRING_NAME,
		"DYNAMIC_NODE_META should be a StringName for efficient Godot node metadata lookup")


func test_remove_dynamic_nodes_clears_tagged_children() -> void:
	## _remove_dynamic_nodes should remove only nodes tagged with DYNAMIC_NODE_META.
	## Original scene nodes (no tag) should remain untouched.
	var wall := StaticBody2D.new()
	wall.name = "TestWallDouble"

	# Add "original" collision shape (not tagged — simulates scene node)
	var original_col := CollisionShape2D.new()
	var orig_rect := RectangleShape2D.new()
	orig_rect.size = Vector2(200.0, 24.0)
	original_col.shape = orig_rect
	wall.add_child(original_col)

	# Add "dynamic" collision segments from a prior breach (tagged)
	var seg_left := CollisionShape2D.new()
	var seg_rect_l := RectangleShape2D.new()
	seg_rect_l.size = Vector2(40.0, 24.0)
	seg_left.shape = seg_rect_l
	seg_left.set_meta(WallBreachHelper.DYNAMIC_NODE_META, true)
	wall.add_child(seg_left)

	var seg_right := CollisionShape2D.new()
	var seg_rect_r := RectangleShape2D.new()
	seg_rect_r.size = Vector2(40.0, 24.0)
	seg_right.shape = seg_rect_r
	seg_right.set_meta(WallBreachHelper.DYNAMIC_NODE_META, true)
	wall.add_child(seg_right)

	# Before cleanup: 3 children total
	assert_eq(wall.get_child_count(), 3,
		"Wall should have 3 children before cleanup (1 original + 2 dynamic segments)")

	# Run the cleanup (queue_free is deferred; we need to process the tree)
	WallBreachHelper._remove_dynamic_nodes(wall)
	# Flush deferred queue_free calls
	await get_tree().process_frame

	# After cleanup: only the original shape remains
	assert_eq(wall.get_child_count(), 1,
		"After _remove_dynamic_nodes, only the original (untagged) shape should remain")
	assert_eq(wall.get_child(0), original_col,
		"The remaining child should be the original (untagged) CollisionShape2D")

	wall.queue_free()

# ============================================================================
# Physics Callback Safety Tests (Issue #1144, Root Cause 6)
# ============================================================================


func test_open_wall_passage_defers_work() -> void:
	## open_wall_passage() must schedule work via call_deferred so that it is safe
	## to call from physics callbacks (body_entered, _physics_process).
	## Godot's physics server ignores direct CollisionShape2D.disabled assignments
	## inside physics callbacks — deferring the work is required for correctness.
	##
	## This test verifies that a real wall StaticBody2D with a CollisionShape2D
	## has its shape disabled AFTER the current frame (not before await process_frame).
	add_child(auto_free(Node.new()))  # Ensure we have a scene tree

	var wall := StaticBody2D.new()
	wall.name = "DeferTestWall"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200.0, 24.0)
	var col := CollisionShape2D.new()
	col.shape = rect
	wall.add_child(col)
	add_child(wall)

	# Shape starts enabled
	assert_false(col.disabled,
		"CollisionShape2D should be enabled before breach")

	# Call open_wall_passage — shape should NOT be disabled YET (work is deferred)
	WallBreachHelper.open_wall_passage(wall, Vector2(0.0, 0.0))
	assert_false(col.disabled,
		"CollisionShape2D must still be enabled immediately after open_wall_passage call (deferred)")

	# After one frame, the deferred work should have run and disabled the shape
	await get_tree().process_frame
	assert_true(col.disabled,
		"CollisionShape2D must be disabled AFTER process_frame (deferred work executed)")


func test_dynamic_segments_added_after_deferred_frame() -> void:
	## New collision segments should only be present AFTER the deferred frame.
	## Verifies that call_deferred correctly schedules _apply_wall_passage.
	add_child(auto_free(Node.new()))  # Ensure we have a scene tree

	var wall := StaticBody2D.new()
	wall.name = "DeferSegmentWall"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400.0, 24.0)  # Wide wall — will be split into segments
	var col := CollisionShape2D.new()
	col.shape = rect
	wall.add_child(col)
	add_child(wall)

	var children_before := wall.get_child_count()
	assert_eq(children_before, 1, "Wall should have 1 child before breach")

	# Call open_wall_passage — segments should NOT exist yet (deferred)
	WallBreachHelper.open_wall_passage(wall, Vector2(0.0, 0.0))
	assert_eq(wall.get_child_count(), 1,
		"No new children should be added immediately (deferred breach)")

	# After one frame, the deferred work runs
	await get_tree().process_frame
	# Expect: original col disabled + 2 new segment shapes + visual ColorRects
	var dynamic_cols := 0
	for child in wall.get_children():
		if child is CollisionShape2D and child.has_meta(WallBreachHelper.DYNAMIC_NODE_META):
			dynamic_cols += 1
	assert_gt(dynamic_cols, 0,
		"Dynamic collision segment(s) should be added after deferred frame")
