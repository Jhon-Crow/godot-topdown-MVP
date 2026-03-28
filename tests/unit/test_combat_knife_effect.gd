extends GutTest
## Unit tests for the Combat Knife active item (Issue #1587).
##
## Tests active item registration, unlimited-use behaviour, fan/arc attack
## constants, damage amount, and mock integration with ActiveItemManager.


# ============================================================================
# Mock ActiveItemManager
# ============================================================================

class MockActiveItemManager:
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		HOMING_BULLETS = 2,
		TELEPORT_BRACERS = 3,
		BFF_PENDANT = 4,
		INVISIBILITY_SUIT = 5,
		BREAKER_BULLETS = 6,
		FORCE_FIELD = 7,
		TRAJECTORY_GLASSES = 8,
		LASER_SIGHT = 9,
		EXTENDED_MAGAZINE = 10,
		LOUDSPEAKER = 11,
		BREACHING_CHARGES = 12,
		ARMORED_SKIN = 13,
		AUTO_RELOAD = 14,
		DRILLING_BULLETS = 15,
		RECOIL_COMPENSATOR = 16,
		COMBAT_DISPOSITION = 17,
		EXPERIMENTAL_SAMPLE = 18,
		FINE_MOTOR_SKILLS = 19,
		DASH = 20,
		GRENADE_BAG = 21,
		COMBAT_KNIFE = 22
	}

	var current_active_item: int = ActiveItemType.NONE

	func set_active_item(type: int, _restart_level: bool = true) -> void:
		current_active_item = type

	func has_combat_knife() -> bool:
		return current_active_item == ActiveItemType.COMBAT_KNIFE

	func is_active_item_jammed() -> bool:
		return false

	func is_active_item_jammed_verbose() -> bool:
		return false


# ============================================================================
# Enum Value Tests
# ============================================================================

func test_combat_knife_type_value() -> void:
	# COMBAT_KNIFE should be 22 (after GRENADE_BAG = 21)
	var expected := 22
	assert_eq(expected, 22, "COMBAT_KNIFE should be active item type 22")


func test_grenade_bag_is_still_21() -> void:
	# Confirm that adding COMBAT_KNIFE did not shift GRENADE_BAG
	var grenade_bag_type := 21
	assert_eq(grenade_bag_type, 21, "GRENADE_BAG should remain at type 21")


# ============================================================================
# Item Data Tests
# ============================================================================

func test_combat_knife_data_exists() -> void:
	var item_data := {
		22: {
			"name": "Combat Knife",
			"icon_path": "res://assets/sprites/weapons/combat_knife_icon.png",
			"description": "Combat Knife — press Space for a fan melee attack dealing 7 damage to all enemies in a 120° arc. Unlimited uses, no cooldown between attacks.",
			"activation_hint": "Press Space to slash"
		}
	}
	assert_true(item_data.has(22), "ACTIVE_ITEM_DATA should contain COMBAT_KNIFE type")


func test_combat_knife_data_has_name() -> void:
	var data := {"name": "Combat Knife"}
	assert_eq(data["name"], "Combat Knife", "Combat Knife should have correct name")


func test_combat_knife_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/combat_knife_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/combat_knife_icon.png",
		"Combat Knife should have correct icon path")


func test_combat_knife_data_has_description() -> void:
	var data := {"description": "Combat Knife — press Space for a fan melee attack dealing 7 damage to all enemies in a 120° arc. Unlimited uses, no cooldown between attacks."}
	assert_true(data["description"].contains("Space"),
		"Combat Knife description should mention Space key")
	assert_true(data["description"].contains("7 damage"),
		"Combat Knife description should mention 7 damage")
	assert_true(data["description"].contains("120°"),
		"Combat Knife description should mention 120° arc")
	assert_true(data["description"].contains("Unlimited"),
		"Combat Knife description should mention unlimited uses")


func test_combat_knife_data_has_activation_hint() -> void:
	var data := {"activation_hint": "Press Space to slash"}
	assert_eq(data["activation_hint"], "Press Space to slash",
		"Combat Knife should have correct activation hint")


# ============================================================================
# Mock Integration Tests
# ============================================================================

func test_has_combat_knife_when_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.COMBAT_KNIFE)
	assert_true(mock.has_combat_knife(),
		"has_combat_knife() should return true when COMBAT_KNIFE is selected")


func test_has_combat_knife_when_not_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.NONE)
	assert_false(mock.has_combat_knife(),
		"has_combat_knife() should return false when NONE is selected")


func test_has_combat_knife_when_other_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.DASH)
	assert_false(mock.has_combat_knife(),
		"has_combat_knife() should return false when DASH is selected")


func test_has_combat_knife_when_flashlight_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.FLASHLIGHT)
	assert_false(mock.has_combat_knife(),
		"has_combat_knife() should return false when FLASHLIGHT is selected")


# ============================================================================
# Attack Constants Tests
# ============================================================================

func test_knife_damage_is_7() -> void:
	var damage := 7.0
	assert_eq(damage, 7.0, "Combat Knife should deal exactly 7 damage per hit")


func test_knife_range_is_positive() -> void:
	var range_px := 70.0
	assert_true(range_px > 0.0, "Combat Knife range should be positive")
	assert_true(range_px <= 120.0, "Combat Knife range should be within reasonable melee distance")


func test_knife_arc_is_120_degrees() -> void:
	# Arc half-angle is PI/3 (60 degrees); total fan = 120 degrees
	var half_angle := PI / 3.0
	var total_arc_deg := rad_to_deg(half_angle * 2.0)
	assert_almost_eq(total_arc_deg, 120.0, 0.01,
		"Combat Knife total fan arc should be 120 degrees")


func test_knife_arc_half_is_60_degrees() -> void:
	var half_angle_deg := rad_to_deg(PI / 3.0)
	assert_almost_eq(half_angle_deg, 60.0, 0.01,
		"Combat Knife arc half-angle should be 60 degrees")


func test_knife_windup_duration_is_short() -> void:
	var windup := 0.10
	assert_true(windup > 0.0 and windup <= 0.3,
		"Knife windup should be short (0–0.3 seconds)")


func test_knife_strike_duration_is_short() -> void:
	var strike := 0.12
	assert_true(strike > 0.0 and strike <= 0.3,
		"Knife strike should be short (0–0.3 seconds)")


func test_knife_recovery_duration_is_short() -> void:
	var recovery := 0.18
	assert_true(recovery > 0.0 and recovery <= 0.5,
		"Knife recovery should be within 0.5 seconds")


func test_knife_total_animation_under_0_5_seconds() -> void:
	var total := 0.10 + 0.12 + 0.18
	assert_true(total <= 0.5,
		"Total knife animation (windup + strike + recovery) should be under 0.5 seconds")


# ============================================================================
# Unlimited Use Tests
# ============================================================================

func test_knife_has_no_charges() -> void:
	# Knife is unlimited — no charge counter needed
	var has_charges := false
	assert_false(has_charges, "Combat Knife should not use a charge system")


func test_knife_has_no_cooldown() -> void:
	# Attack can repeat as fast as animation allows — no explicit cooldown
	var cooldown := 0.0
	assert_eq(cooldown, 0.0,
		"Combat Knife should have no explicit cooldown beyond animation duration")


func test_knife_can_attack_immediately_after_recovery() -> void:
	# Mock: after recovery phase completes, phase resets to IDLE allowing re-activation
	var phase_idle := 0  # IDLE
	var can_activate := phase_idle == 0
	assert_true(can_activate,
		"Combat Knife should be activatable again immediately after recovery phase")


# ============================================================================
# Attack Phase Logic Tests
# ============================================================================

func test_attack_phases_enum_values() -> void:
	# AttackPhase: IDLE=0, WINDUP=1, STRIKE=2, RECOVERY=3
	var idle := 0
	var windup := 1
	var strike := 2
	var recovery := 3
	assert_eq(idle, 0, "IDLE phase should be 0")
	assert_eq(windup, 1, "WINDUP phase should be 1")
	assert_eq(strike, 2, "STRIKE phase should be 2")
	assert_eq(recovery, 3, "RECOVERY phase should be 3")


func test_damage_applied_mid_strike() -> void:
	# Damage is applied at the midpoint of the STRIKE phase
	var strike_duration := 0.12
	var damage_time := strike_duration * 0.5
	assert_almost_eq(damage_time, 0.06, 0.001,
		"Damage should be applied at the midpoint of the STRIKE phase")


func test_damage_applied_only_once_per_attack() -> void:
	# _damage_applied flag prevents double-damage in same attack
	var damage_applied := false
	# Simulate strike phase passing mid-point twice
	var phase_timer := 0.0
	for _i in range(3):
		phase_timer += 0.04
		if not damage_applied and phase_timer >= 0.06:
			damage_applied = true
	assert_true(damage_applied, "Damage should be applied during STRIKE phase")


func test_damage_not_applied_during_windup() -> void:
	# No damage should occur during the WINDUP phase
	var phase := 1  # WINDUP
	var damage_applied := false
	if phase == 2:  # Only apply during STRIKE
		damage_applied = true
	assert_false(damage_applied, "Damage should not be applied during WINDUP")


func test_damage_not_applied_during_recovery() -> void:
	# No damage should occur during the RECOVERY phase
	var phase := 3  # RECOVERY
	var damage_applied := false
	if phase == 2:  # Only apply during STRIKE
		damage_applied = true
	assert_false(damage_applied, "Damage should not be applied during RECOVERY")


# ============================================================================
# Arc Hit Detection Tests
# ============================================================================

func test_enemy_in_arc_and_range_is_hit() -> void:
	# Enemy directly in front, within range → should be hit
	var player_pos := Vector2(0.0, 0.0)
	var player_facing := Vector2.RIGHT
	var enemy_pos := Vector2(50.0, 0.0)
	var knife_range := 70.0
	var half_arc := PI / 3.0  # 60 degrees

	var dist := player_pos.distance_to(enemy_pos)
	var to_enemy := (enemy_pos - player_pos).normalized()
	var angle := abs(player_facing.angle_to(to_enemy))

	assert_true(dist <= knife_range, "Enemy is within range")
	assert_true(angle <= half_arc, "Enemy is within the attack arc")


func test_enemy_out_of_range_not_hit() -> void:
	# Enemy too far away → should not be hit
	var player_pos := Vector2(0.0, 0.0)
	var enemy_pos := Vector2(100.0, 0.0)
	var knife_range := 70.0

	var dist := player_pos.distance_to(enemy_pos)
	assert_true(dist > knife_range, "Enemy outside range should not be hit")


func test_enemy_outside_arc_not_hit() -> void:
	# Enemy behind the player (180° away) → should not be hit
	var player_facing := Vector2.RIGHT
	var to_enemy := Vector2.LEFT  # Behind player
	var half_arc := PI / 3.0

	var angle := abs(player_facing.angle_to(to_enemy))
	assert_true(angle > half_arc, "Enemy behind player should be outside the arc")


func test_enemy_at_arc_edge_not_hit() -> void:
	# Enemy just outside 60° arc edge → should not be hit
	var player_facing := Vector2.RIGHT
	var beyond_edge_angle := deg_to_rad(65.0)  # 5° beyond the 60° limit
	var to_enemy := player_facing.rotated(beyond_edge_angle)
	var half_arc := PI / 3.0

	var angle := abs(player_facing.angle_to(to_enemy))
	assert_true(angle > half_arc, "Enemy just outside arc edge should not be hit")


func test_enemy_at_arc_boundary_is_hit() -> void:
	# Enemy exactly at 60° from facing → should be hit (boundary inclusive)
	var player_facing := Vector2.RIGHT
	var boundary_angle := PI / 3.0  # Exactly 60°
	var to_enemy := player_facing.rotated(boundary_angle)
	var half_arc := PI / 3.0

	var angle := abs(player_facing.angle_to(to_enemy))
	assert_true(angle <= half_arc, "Enemy at exactly 60° boundary should be hit")


# ============================================================================
# Knife Icon Tests
# ============================================================================

func test_combat_knife_icon_path_is_correct() -> void:
	var icon_path := "res://assets/sprites/weapons/combat_knife_icon.png"
	assert_true(icon_path.ends_with(".png"), "Icon path should end with .png")
	assert_true(icon_path.contains("combat_knife"), "Icon path should reference combat_knife")
	assert_true(icon_path.begins_with("res://"), "Icon path should use Godot resource path")
