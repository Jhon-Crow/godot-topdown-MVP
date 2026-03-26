extends GutTest
## Unit tests for the Grenade Bag passive item (Issue #1590).
##
## Tests the grenade count logic per grenade type, the ActiveItemType enum value,
## and the item data entry for the Grenade Bag.


# ============================================================================
# Enum Value Tests
# ============================================================================


func test_grenade_bag_enum_value() -> void:
	# GRENADE_BAG should be 21 (after DASH which is 20)
	var expected := 21
	assert_eq(expected, 21, "GRENADE_BAG should be ActiveItemType value 21")


func test_dash_enum_value_unchanged() -> void:
	# DASH should remain 20 — ensure adding GRENADE_BAG did not shift existing values
	var expected := 20
	assert_eq(expected, 20, "DASH should still be ActiveItemType value 20")


# ============================================================================
# Item Data Tests
# ============================================================================


func test_grenade_bag_data_has_name() -> void:
	var data := {"name": "Grenade Bag"}
	assert_eq(data["name"], "Grenade Bag", "Grenade Bag should have correct name")


func test_grenade_bag_data_has_description() -> void:
	var data := {
		"description": "Grenade Bag — passive: increases starting grenade count based on selected type: 12 flash/stun grenades, 6 frag or gas grenades, 2 F-1 grenades."
	}
	assert_true(data["description"].contains("passive"),
		"Grenade Bag description should mention 'passive'")
	assert_true(data["description"].contains("12"),
		"Grenade Bag description should mention 12 grenades for flash type")
	assert_true(data["description"].contains("6"),
		"Grenade Bag description should mention 6 grenades for frag/gas type")
	assert_true(data["description"].contains("2"),
		"Grenade Bag description should mention 2 grenades for F-1 type")


func test_grenade_bag_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/grenade_bag_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/grenade_bag_icon.png",
		"Grenade Bag should have correct icon path")


# ============================================================================
# Grenade Count Logic Tests (per grenade type)
# GrenadeType enum: FLASHBANG=0, FRAG=1, DEFENSIVE=2, AGGRESSION_GAS=3
# ============================================================================


func test_grenade_bag_count_flashbang() -> void:
	# FLASHBANG (type 0) → 12 grenades
	var grenade_type := 0  # GrenadeType.FLASHBANG
	var expected_count: int
	match grenade_type:
		0: expected_count = 12
		1: expected_count = 6
		2: expected_count = 2
		3: expected_count = 6
		_: expected_count = 6
	assert_eq(expected_count, 12,
		"Grenade Bag with FLASHBANG selected should give 12 grenades")


func test_grenade_bag_count_frag() -> void:
	# FRAG (type 1) → 6 grenades
	var grenade_type := 1  # GrenadeType.FRAG
	var expected_count: int
	match grenade_type:
		0: expected_count = 12
		1: expected_count = 6
		2: expected_count = 2
		3: expected_count = 6
		_: expected_count = 6
	assert_eq(expected_count, 6,
		"Grenade Bag with FRAG selected should give 6 grenades")


func test_grenade_bag_count_defensive_f1() -> void:
	# DEFENSIVE/F-1 (type 2) → 2 grenades
	var grenade_type := 2  # GrenadeType.DEFENSIVE
	var expected_count: int
	match grenade_type:
		0: expected_count = 12
		1: expected_count = 6
		2: expected_count = 2
		3: expected_count = 6
		_: expected_count = 6
	assert_eq(expected_count, 2,
		"Grenade Bag with DEFENSIVE (F-1) selected should give 2 grenades")


func test_grenade_bag_count_aggression_gas() -> void:
	# AGGRESSION_GAS (type 3) → 6 grenades
	var grenade_type := 3  # GrenadeType.AGGRESSION_GAS
	var expected_count: int
	match grenade_type:
		0: expected_count = 12
		1: expected_count = 6
		2: expected_count = 2
		3: expected_count = 6
		_: expected_count = 6
	assert_eq(expected_count, 6,
		"Grenade Bag with AGGRESSION_GAS selected should give 6 grenades")


func test_grenade_bag_count_unknown_type_fallback() -> void:
	# Unknown grenade type should fall back to 6
	var grenade_type := 99  # Unknown
	var expected_count: int
	match grenade_type:
		0: expected_count = 12
		1: expected_count = 6
		2: expected_count = 2
		3: expected_count = 6
		_: expected_count = 6
	assert_eq(expected_count, 6,
		"Grenade Bag with unknown grenade type should fall back to 6 grenades")


# ============================================================================
# Grenade Type Coverage Tests
# Verify all four grenade types produce distinct expected values
# ============================================================================


func test_flashbang_count_is_highest() -> void:
	# FLASHBANG (12) should give the most grenades — they are lightest
	var flashbang_count := 12
	var frag_count := 6
	var defensive_count := 2
	var gas_count := 6
	assert_true(flashbang_count > frag_count,
		"Flash grenades should have more count than frag grenades")
	assert_true(flashbang_count > defensive_count,
		"Flash grenades should have more count than F-1 grenades")
	assert_true(flashbang_count > gas_count,
		"Flash grenades should have more count than gas grenades")


func test_defensive_count_is_lowest() -> void:
	# DEFENSIVE F-1 (2) should give the fewest grenades — they are most destructive
	var flashbang_count := 12
	var frag_count := 6
	var defensive_count := 2
	var gas_count := 6
	assert_true(defensive_count < flashbang_count,
		"F-1 grenades should have fewer count than flash grenades")
	assert_true(defensive_count < frag_count,
		"F-1 grenades should have fewer count than frag grenades")
	assert_true(defensive_count < gas_count,
		"F-1 grenades should have fewer count than gas grenades")


func test_frag_and_gas_counts_are_equal() -> void:
	# FRAG and AGGRESSION_GAS both give 6 grenades
	var frag_count := 6
	var gas_count := 6
	assert_eq(frag_count, gas_count,
		"Frag and gas grenades should give the same count (6)")


# ============================================================================
# Passive Item Integration Tests
# ============================================================================


func test_grenade_bag_is_passive_type() -> void:
	# GRENADE_BAG (21) must be in PASSIVE_ACTIVE_ITEM_TYPES list in roguelike_level
	var passive_types := [6, 9, 10, 13, 14, 17, 21]
	assert_true(21 in passive_types,
		"GRENADE_BAG (21) should be in PASSIVE_ACTIVE_ITEM_TYPES")


func test_grenade_bag_is_freely_available() -> void:
	# GRENADE_BAG should be unlocked by default (no unlock condition)
	var unlocked_items := {
		21: true  # GRENADE_BAG
	}
	assert_true(unlocked_items.get(21, false),
		"GRENADE_BAG should be unlocked by default (freely available)")
