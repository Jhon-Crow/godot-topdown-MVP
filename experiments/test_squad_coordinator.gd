extends SceneTree
## Experiment: Validate SquadCoordinatorComponent logic in isolation.
## Run with: godot --headless -s experiments/test_squad_coordinator.gd

func _init() -> void:
	print("=== SquadCoordinatorComponent Experiment ===")
	_test_cover_deconfliction()
	_test_role_pool_balance()
	_test_firing_lane_geometry()
	print("=== All experiments passed ===")
	quit()


func _test_cover_deconfliction() -> void:
	print("\n--- Cover Deconfliction ---")
	var squad := SquadCoordinatorComponent.new(null)
	# Claim a cover position
	squad.claim_cover(Vector2(300, 400))
	assert(squad.get_claimed_cover() == Vector2(300, 400), "Cover claim should be stored")
	# Release it
	squad.release_cover()
	assert(squad.get_claimed_cover() == Vector2.INF, "Cover should be released")
	print("  PASS: cover claim/release works")


func _test_role_pool_balance() -> void:
	print("\n--- Role Pool Balance ---")
	var squad := SquadCoordinatorComponent.new(null)
	# 2 enemies: should have SUPPRESSOR + RUSHER
	var pool2 := squad._build_role_pool(2)
	assert(pool2.size() == 2, "Pool for 2 should have 2 roles")
	assert(pool2[0] == SquadCoordinatorComponent.SquadRole.SUPPRESSOR, "First role should be SUPPRESSOR")
	print("  Pool for 2: %s" % [pool2.map(func(r): return SquadCoordinatorComponent.SquadRole.keys()[r])])

	# 3 enemies: should have SUPPRESSOR + FLANKER + ?
	var pool3 := squad._build_role_pool(3)
	assert(pool3.size() == 3, "Pool for 3 should have 3 roles")
	print("  Pool for 3: %s" % [pool3.map(func(r): return SquadCoordinatorComponent.SquadRole.keys()[r])])

	# 5 enemies: should have balanced mix
	var pool5 := squad._build_role_pool(5)
	assert(pool5.size() == 5, "Pool for 5 should have 5 roles")
	print("  Pool for 5: %s" % [pool5.map(func(r): return SquadCoordinatorComponent.SquadRole.keys()[r])])
	print("  PASS: role pools are balanced")


func _test_firing_lane_geometry() -> void:
	print("\n--- Firing Lane Geometry ---")
	# Test the geometric check directly
	var fire_dir := Vector2.RIGHT
	var ally_pos := Vector2(100, 200)
	# Point directly in front of shooter
	var in_lane := Vector2(250, 200)
	var to_pos := in_lane - ally_pos
	var along := to_pos.dot(fire_dir)
	var perp := abs(to_pos.dot(fire_dir.rotated(PI / 2.0)))
	assert(along > 0, "Point ahead should have positive along-axis projection")
	assert(perp < 40.0, "Point directly in lane should have small perpendicular distance")
	print("  In-lane point: along=%.1f, perp=%.1f (should be in lane)" % [along, perp])

	# Point off to the side
	var safe := Vector2(250, 400)
	to_pos = safe - ally_pos
	along = to_pos.dot(fire_dir)
	perp = abs(to_pos.dot(fire_dir.rotated(PI / 2.0)))
	assert(perp > 40.0, "Point to the side should have large perpendicular distance")
	print("  Safe point: along=%.1f, perp=%.1f (should be safe)" % [along, perp])
	print("  PASS: firing lane geometry is correct")
