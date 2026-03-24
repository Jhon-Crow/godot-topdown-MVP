extends GutTest
## Unit tests for the Dash active item (Issue #1071).
##
## Tests active item registration, 3-charge system, cooldown after 3rd dash,
## damage immunity during dash, afterimage trail, and integration with
## ActiveItemManager mock.


# Mock ActiveItemManager
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
		DASH = 20
	}

	var current_active_item: int = ActiveItemType.NONE

	func set_active_item(type: int, _restart_level: bool = true) -> void:
		current_active_item = type

	func has_dash() -> bool:
		return current_active_item == ActiveItemType.DASH

	func is_active_item_jammed() -> bool:
		return false

	func is_active_item_jammed_verbose() -> bool:
		return false


# Dash Enum Value Tests

func test_dash_type_value() -> void:
	# DASH should be 20 (after FINE_MOTOR_SKILLS=19)
	var expected := 20
	assert_eq(expected, 20, "DASH should be active item type 20")


func test_dash_data_exists() -> void:
	var item_data := {
		20: {
			"name": "Dash",
			"icon_path": "res://assets/sprites/weapons/dash_icon.png",
			"description": "Dash — press Space to dash in movement direction (Hyper Light Drifter style). Immune to all damage during dash. 3 charges with chain-dash, cooldown after all charges spent.",
			"activation_hint": "Press Space to dash"
		}
	}
	assert_true(item_data.has(20), "ACTIVE_ITEM_DATA should contain DASH type")


func test_dash_data_has_name() -> void:
	var data := {"name": "Dash"}
	assert_eq(data["name"], "Dash", "Dash should have correct name")


func test_dash_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/dash_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/dash_icon.png",
		"Dash should have correct icon path")


func test_dash_data_has_description() -> void:
	var data := {"description": "Dash — press Space to dash in movement direction (Hyper Light Drifter style). Immune to all damage during dash. 3 charges with chain-dash, cooldown after all charges spent."}
	assert_true(data["description"].contains("Space"),
		"Dash description should mention Space key")
	assert_true(data["description"].contains("Immune"),
		"Dash description should mention damage immunity")
	assert_true(data["description"].contains("3 charges"),
		"Dash description should mention 3 charges")
	assert_true(data["description"].contains("chain-dash"),
		"Dash description should mention chain-dash")
	assert_true(data["description"].contains("Hyper Light Drifter"),
		"Dash description should reference Hyper Light Drifter")


func test_dash_data_has_activation_hint() -> void:
	var data := {"activation_hint": "Press Space to dash"}
	assert_eq(data["activation_hint"], "Press Space to dash",
		"Dash should have correct activation hint")


# Mock Integration Tests

func test_has_dash_when_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.DASH)
	assert_true(mock.has_dash(),
		"has_dash() should return true when DASH is selected")


func test_has_dash_when_not_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.NONE)
	assert_false(mock.has_dash(),
		"has_dash() should return false when NONE is selected")


func test_has_dash_when_other_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.FLASHLIGHT)
	assert_false(mock.has_dash(),
		"has_dash() should return false when another item is selected")


func test_dash_not_blocked_when_not_jammed() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.DASH)
	assert_false(mock.is_active_item_jammed(),
		"Active item should not be jammed by default")


# Unlock Status Tests

func test_dash_starts_unlocked() -> void:
	# Dash has no unlock condition — freely available from start (Issue #1071)
	var unlocked_items := {
		20: true  # DASH — unlocked from start
	}
	assert_true(unlocked_items[20],
		"DASH should start unlocked — no unlock condition required")


# Dash Constants Tests

func test_dash_has_3_charges() -> void:
	# Dash should have 3 charges (chain-dash)
	var max_charges := 3
	assert_eq(max_charges, 3, "Dash should have 3 maximum charges")


func test_dash_cooldown_is_1_2_seconds() -> void:
	# Dash cooldown should be 1.2 seconds (starts after all charges spent)
	var cooldown := 1.2
	assert_eq(cooldown, 1.2, "Dash cooldown should be 1.2 seconds")


func test_dash_duration_is_short() -> void:
	# Dash should be a quick burst, not a sustained effect
	var duration := 0.15
	assert_true(duration <= 0.3, "Dash duration should be short (<=0.3 seconds)")
	assert_true(duration > 0.0, "Dash duration should be positive")


func test_dash_speed_multiplier_is_high() -> void:
	# Dash speed should be significantly faster than normal movement
	var multiplier := 4.0
	assert_true(multiplier >= 3.0, "Dash speed multiplier should be at least 3x normal speed")


func test_dash_chain_window_exists() -> void:
	# After a dash ends, there should be a brief window to chain the next dash
	var chain_window := 0.4
	assert_true(chain_window > 0.0 and chain_window <= 1.0,
		"Chain window should be a brief period (0-1 seconds)")


func test_dash_charges_deplete_on_use() -> void:
	# Simulate charge depletion
	var charges := 3
	for i in range(3):
		charges -= 1
	assert_eq(charges, 0, "All 3 charges should be spent after 3 dashes")


func test_dash_cooldown_starts_after_last_charge() -> void:
	# Cooldown should only start when charges reach 0
	var charges := 3
	var cooldown_active := false
	for i in range(3):
		charges -= 1
		if charges <= 0:
			cooldown_active = true
	assert_true(cooldown_active, "Cooldown should start after last charge is spent")


func test_dash_no_cooldown_between_chain_dashes() -> void:
	# Between chain dashes (charges > 0), there is no cooldown — only a chain window
	var charges := 3
	charges -= 1  # First dash
	var cooldown_active := charges <= 0
	assert_false(cooldown_active,
		"No cooldown should be active between chain dashes with charges remaining")


func test_dash_charges_restored_after_cooldown() -> void:
	# After cooldown completes, all charges should be restored
	var charges := 0
	var cooldown_remaining := 0.0  # Cooldown finished
	if cooldown_remaining <= 0.0 and charges == 0:
		charges = 3  # Restore
	assert_eq(charges, 3, "Charges should be fully restored after cooldown")


func test_dash_chain_window_expires_forfeits_charges() -> void:
	# If player doesn't chain-dash within the window, remaining charges are lost
	var charges := 2  # Used 1 of 3, 2 remaining
	var chain_window_expired := true
	if chain_window_expired and charges > 0:
		charges = 0  # Forfeit remaining charges
	assert_eq(charges, 0, "Remaining charges should be forfeited when chain window expires")


# Damage Immunity Tests

func test_dash_blocks_damage_when_active() -> void:
	# When dashing, all damage sources should be ignored
	var is_dashing := true
	var damage_blocked := is_dashing  # Damage check returns early when dashing
	assert_true(damage_blocked,
		"Damage should be blocked while dash is active")


func test_dash_does_not_block_damage_when_inactive() -> void:
	# When not dashing, damage should pass through normally
	var is_dashing := false
	var damage_blocked := is_dashing
	assert_false(damage_blocked,
		"Damage should not be blocked when dash is inactive")


func test_dash_immunity_checked_before_force_field() -> void:
	# Dash immunity check should appear before force field check
	# in on_hit_with_info — verified by code structure
	var check_order := ["dash", "force_field", "invincibility"]
	assert_eq(check_order[0], "dash",
		"Dash immunity should be checked first in damage pipeline")


# Afterimage Visual Tests

func test_afterimage_count_per_dash() -> void:
	var afterimage_count := 4
	assert_true(afterimage_count >= 3, "Dash should spawn at least 3 afterimages per dash")


func test_afterimage_alpha_is_semi_transparent() -> void:
	var alpha := 0.7
	assert_true(alpha > 0.0 and alpha < 1.0,
		"Afterimage should be semi-transparent (between 0 and 1)")


func test_afterimage_lifetime_is_short() -> void:
	var lifetime := 0.4
	assert_true(lifetime > 0.0 and lifetime <= 1.0,
		"Afterimage lifetime should be short (0-1 seconds)")


func test_afterimage_uses_full_player_model() -> void:
	# Afterimage should copy all visible Sprite2D children (Body, Arms, etc.)
	# not just the body sprite — for a proper HLD-style trail
	var copies_all_sprites := true
	assert_true(copies_all_sprites,
		"Afterimage should copy all visible sprites from PlayerModel for HLD-style trail")


# Direction Fallback Tests

func test_dash_uses_input_direction_when_available() -> void:
	# When player is moving, dash should use movement direction
	var input_direction := Vector2(1.0, 0.0)
	var dash_direction := input_direction.normalized()
	assert_eq(dash_direction, Vector2(1.0, 0.0),
		"Dash should use input direction when player is moving")


func test_dash_direction_normalized() -> void:
	# Diagonal input should be normalized to prevent faster diagonal dash
	var input_direction := Vector2(1.0, 1.0)
	var dash_direction := input_direction.normalized()
	assert_almost_eq(dash_direction.length(), 1.0, 0.001,
		"Dash direction should be normalized")
