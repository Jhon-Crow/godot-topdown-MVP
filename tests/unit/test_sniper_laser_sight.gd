extends GutTest
## Unit tests for sniper enemy laser sight (Issue #1336).
##
## Verifies that the sniper enemy component creates a red laser sight
## matching the player's M16 assault rifle laser.


# ============================================================================
# Source file content verification tests
# ============================================================================


func test_sniper_component_has_laser_sight_line2d() -> void:
	# enemy_sniper_component.gd must create a Line2D laser sight node. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_laser_sight"),
		"enemy_sniper_component.gd must define _laser_sight variable [#1336]")
	assert_true(text.contains("Line2D.new()"),
		"enemy_sniper_component.gd must create a Line2D for the laser [#1336]")


func test_sniper_laser_color_is_red() -> void:
	# Laser color must be red with transparency, same as M16 assault rifle. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("Color(1.0, 0.0, 0.0, 0.5)"),
		"LASER_COLOR must be red Color(1.0, 0.0, 0.0, 0.5) matching M16 [#1336]")


func test_sniper_laser_has_glow_layers() -> void:
	# Laser must have glow layers for volumetric look (like M16 LaserGlowEffect). [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_laser_glow_layers"),
		"enemy_sniper_component.gd must have glow layers for volumetric effect [#1336]")
	assert_true(text.contains("BLEND_MODE_ADD"),
		"Glow layers must use additive blending [#1336]")


func test_sniper_laser_has_endpoint_light() -> void:
	# Laser must have an endpoint glow (PointLight2D) like M16 laser. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_laser_endpoint_light"),
		"enemy_sniper_component.gd must have endpoint PointLight2D [#1336]")
	assert_true(text.contains("PointLight2D.new()"),
		"enemy_sniper_component.gd must create PointLight2D for endpoint glow [#1336]")


func test_sniper_laser_has_update_method() -> void:
	# update_laser_sight() must exist so enemy.gd can call it each frame. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("func update_laser_sight()"),
		"enemy_sniper_component.gd must define update_laser_sight() method [#1336]")


func test_sniper_laser_has_hide_method() -> void:
	# hide_laser() must exist so enemy.gd can hide it on death. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("func hide_laser()"),
		"enemy_sniper_component.gd must define hide_laser() method [#1336]")


func test_sniper_laser_uses_wall_and_character_collision_raycast() -> void:
	# Laser must raycast against walls (layer 3, value 4) AND characters (layer 1, value 1)
	# so the laser stops at the player body instead of passing through. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("intersect_ray"),
		"update_laser_sight must use raycast to detect obstacles [#1336]")
	# Collision mask 5 = walls (4) + characters (1)
	assert_true(text.contains(", 5)"),
		"Laser raycast must use collision mask 5 (walls + characters) [#1336]")
	assert_true(text.contains("enemy.get_rid()"),
		"Laser raycast must exclude the enemy's own collider [#1336]")


func test_sniper_laser_uses_visual_barrel_direction() -> void:
	# Laser and hitscan must both use get_visual_barrel_direction() so they always match.
	# This uses the actual weapon sprite transform instead of the instant player direction,
	# ensuring the laser visually aligns with the barrel and tracer. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("func get_visual_barrel_direction()"),
		"Must define get_visual_barrel_direction() for consistent laser/bullet direction [#1336]")
	assert_true(text.contains("_weapon_sprite.global_transform.x.normalized()"),
		"Visual barrel direction must use _weapon_sprite.global_transform.x [#1336]")


func test_sniper_laser_width_matches_m16() -> void:
	# Laser width must be 2.0px, same as M16 assault rifle. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("LASER_WIDTH: float = 2.0"),
		"LASER_WIDTH must be 2.0 matching M16 LaserSightWidth [#1336]")


# ============================================================================
# enemy.gd integration tests
# ============================================================================


func test_enemy_execute_shoot_uses_barrel_direction_for_sniper() -> void:
	# _execute_shoot must use get_visual_barrel_direction() for sniper hitscan
	# so the tracer matches the laser sight. [#1336]
	var src := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	assert_not_null(src, "enemy.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_sniper_component.get_visual_barrel_direction()"),
		"enemy.gd must use get_visual_barrel_direction() for sniper shots [#1336]")
	assert_true(text.contains("_sniper_component._get_barrel_spawn_position("),
		"enemy.gd must use _get_barrel_spawn_position() for sniper spawn point [#1336]")


func test_enemy_calls_update_laser_in_physics_process() -> void:
	# enemy.gd must call _sniper_component.update_laser_sight() in _physics_process. [#1336]
	var src := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	assert_not_null(src, "enemy.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_sniper_component.update_laser_sight()"),
		"enemy.gd _physics_process must call _sniper_component.update_laser_sight() [#1336]")


func test_enemy_hides_laser_on_death() -> void:
	# enemy.gd _on_death must call _sniper_component.hide_laser(). [#1336]
	var src := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	assert_not_null(src, "enemy.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_sniper_component.hide_laser()"),
		"enemy.gd _on_death must call _sniper_component.hide_laser() [#1336]")


# ============================================================================
# EnemySniperComponent constant verification
# ============================================================================


func test_laser_color_constant_matches_m16_assault_rifle() -> void:
	# EnemySniperComponent.LASER_COLOR must be Color(1.0, 0.0, 0.0, 0.5), same as AssaultRifle.cs.
	assert_eq(EnemySniperComponent.LASER_COLOR, Color(1.0, 0.0, 0.0, 0.5),
		"LASER_COLOR must match M16 red laser Color(1.0, 0.0, 0.0, 0.5) [#1336]")


func test_laser_width_constant_matches_m16_assault_rifle() -> void:
	# EnemySniperComponent.LASER_WIDTH must be 2.0, same as AssaultRifle.cs LaserSightWidth.
	assert_eq(EnemySniperComponent.LASER_WIDTH, 2.0,
		"LASER_WIDTH must match M16 LaserSightWidth of 2.0px [#1336]")


func test_laser_max_length_is_sufficient() -> void:
	# LASER_MAX_LENGTH must be long enough to cover the sniper's engagement range.
	assert_true(EnemySniperComponent.LASER_MAX_LENGTH >= EnemySniperComponent.PREFERRED_DISTANCE * 2,
		"LASER_MAX_LENGTH must be >= 2x PREFERRED_DISTANCE for adequate visibility [#1336]")


func test_sniper_laser_uses_direct_is_alive_access() -> void:
	# update_laser_sight must use direct enemy._is_alive property access instead of
	# enemy.get("_is_alive") which can return null and cause `not null` to evaluate
	# to true, permanently hiding the laser. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("enemy._is_alive"),
		"update_laser_sight must use direct enemy._is_alive access [#1336]")
	assert_false(text.contains('enemy.get("_is_alive")'),
		"Must NOT use enemy.get('_is_alive') which can return null [#1336]")


func test_sniper_laser_cleanup_on_exit_tree() -> void:
	# _exit_tree must free laser nodes since they are parented to scene root. [#1336]
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("func _exit_tree()"),
		"Must define _exit_tree() to clean up laser nodes on scene root [#1336]")
	assert_true(text.contains("_laser_sight.queue_free()"),
		"_exit_tree must queue_free _laser_sight [#1336]")
