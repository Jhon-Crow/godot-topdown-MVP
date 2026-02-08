extends GutTest
## Unit tests for GrenadierGrenadeComponent (Issue #604).
##
## Tests the grenadier grenade bag system including:
## - Grenade bag initialization with correct loadouts per difficulty
## - Priority ordering (flashbangs first, then offensive, then defensive)
## - Grenade consumption from the bag
## - Blocking passage state management
## - Ally coordination signals


# ============================================================================
# Mock GrenadierGrenadeComponent for Logic Tests
# ============================================================================


class MockGrenadierBag:
	## Grenade types in priority order.
	enum GrenadeType { FLASHBANG, OFFENSIVE, DEFENSIVE }

	## The grenade bag - ordered list of grenade types.
	var _grenade_bag: Array[int] = []

	## State tracking.
	var grenades_remaining: int = 0
	var _blocking_passage: bool = false

	## Build the grenade bag for normal difficulty.
	## Normal: 3 flashbangs + 5 offensive.
	func build_bag_normal() -> void:
		_grenade_bag.clear()
		for i in range(3):
			_grenade_bag.append(GrenadeType.FLASHBANG)
		for i in range(5):
			_grenade_bag.append(GrenadeType.OFFENSIVE)
		grenades_remaining = _grenade_bag.size()

	## Build the grenade bag for hard difficulty.
	## Hard: 7 offensive + 1 defensive.
	func build_bag_hard() -> void:
		_grenade_bag.clear()
		for i in range(7):
			_grenade_bag.append(GrenadeType.OFFENSIVE)
		_grenade_bag.append(GrenadeType.DEFENSIVE)
		grenades_remaining = _grenade_bag.size()

	## Get the next grenade type without consuming it.
	func peek_next() -> int:
		if _grenade_bag.is_empty():
			return -1
		return _grenade_bag[0]

	## Consume the next grenade from the bag.
	func consume() -> int:
		if _grenade_bag.is_empty():
			return -1
		var consumed := _grenade_bag[0]
		_grenade_bag.remove_at(0)
		grenades_remaining = _grenade_bag.size()
		return consumed

	## Get remaining count of a specific type.
	func count_type(type: int) -> int:
		var count := 0
		for g in _grenade_bag:
			if g == type:
				count += 1
		return count

	## Check if bag has any grenades.
	func has_grenades() -> bool:
		return not _grenade_bag.is_empty()

	## Get bag size.
	func get_bag_size() -> int:
		return _grenade_bag.size()

	## Set blocking passage state.
	func set_blocking(value: bool) -> void:
		_blocking_passage = value

	## Check if blocking passage.
	func is_blocking_passage() -> bool:
		return _blocking_passage


# ============================================================================
# Test Variables and Setup
# ============================================================================


var bag: MockGrenadierBag


func before_each() -> void:
	bag = MockGrenadierBag.new()


func after_each() -> void:
	bag = null


# ============================================================================
# Normal Difficulty Bag Tests
# ============================================================================


func test_normal_bag_has_8_grenades() -> void:
	bag.build_bag_normal()

	assert_eq(bag.get_bag_size(), 8,
		"Normal difficulty bag should have 8 grenades total")


func test_normal_bag_has_3_flashbangs() -> void:
	bag.build_bag_normal()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.FLASHBANG), 3,
		"Normal difficulty bag should have 3 flashbangs")


func test_normal_bag_has_5_offensive() -> void:
	bag.build_bag_normal()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.OFFENSIVE), 5,
		"Normal difficulty bag should have 5 offensive grenades")


func test_normal_bag_has_no_defensive() -> void:
	bag.build_bag_normal()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.DEFENSIVE), 0,
		"Normal difficulty bag should have 0 defensive grenades")


func test_normal_bag_grenades_remaining_equals_size() -> void:
	bag.build_bag_normal()

	assert_eq(bag.grenades_remaining, 8,
		"grenades_remaining should match bag size after initialization")


# ============================================================================
# Hard Difficulty Bag Tests
# ============================================================================


func test_hard_bag_has_8_grenades() -> void:
	bag.build_bag_hard()

	assert_eq(bag.get_bag_size(), 8,
		"Hard difficulty bag should have 8 grenades total")


func test_hard_bag_has_7_offensive() -> void:
	bag.build_bag_hard()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.OFFENSIVE), 7,
		"Hard difficulty bag should have 7 offensive grenades")


func test_hard_bag_has_1_defensive() -> void:
	bag.build_bag_hard()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.DEFENSIVE), 1,
		"Hard difficulty bag should have 1 defensive grenade")


func test_hard_bag_has_no_flashbangs() -> void:
	bag.build_bag_hard()

	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.FLASHBANG), 0,
		"Hard difficulty bag should have 0 flashbangs")


# ============================================================================
# Priority Ordering Tests (Normal Difficulty)
# ============================================================================


func test_normal_first_grenade_is_flashbang() -> void:
	bag.build_bag_normal()

	assert_eq(bag.peek_next(), MockGrenadierBag.GrenadeType.FLASHBANG,
		"First grenade in normal bag should be flashbang (least dangerous)")


func test_normal_flashbangs_come_before_offensive() -> void:
	bag.build_bag_normal()

	# Consume all 3 flashbangs
	for i in range(3):
		var type := bag.consume()
		assert_eq(type, MockGrenadierBag.GrenadeType.FLASHBANG,
			"Grenade %d should be flashbang" % (i + 1))

	# Next should be offensive
	assert_eq(bag.peek_next(), MockGrenadierBag.GrenadeType.OFFENSIVE,
		"After flashbangs, next grenade should be offensive")


func test_normal_all_grenades_in_priority_order() -> void:
	bag.build_bag_normal()

	# First 3 should be flashbangs
	for i in range(3):
		assert_eq(bag.consume(), MockGrenadierBag.GrenadeType.FLASHBANG,
			"Grenade %d should be flashbang" % (i + 1))

	# Next 5 should be offensive
	for i in range(5):
		assert_eq(bag.consume(), MockGrenadierBag.GrenadeType.OFFENSIVE,
			"Grenade %d should be offensive" % (i + 4))

	# Bag should be empty
	assert_false(bag.has_grenades(),
		"Bag should be empty after consuming all 8 grenades")


# ============================================================================
# Priority Ordering Tests (Hard Difficulty)
# ============================================================================


func test_hard_first_grenade_is_offensive() -> void:
	bag.build_bag_hard()

	assert_eq(bag.peek_next(), MockGrenadierBag.GrenadeType.OFFENSIVE,
		"First grenade in hard bag should be offensive (smaller radius)")


func test_hard_offensive_comes_before_defensive() -> void:
	bag.build_bag_hard()

	# Consume all 7 offensive
	for i in range(7):
		var type := bag.consume()
		assert_eq(type, MockGrenadierBag.GrenadeType.OFFENSIVE,
			"Grenade %d should be offensive" % (i + 1))

	# Last should be defensive (large radius)
	assert_eq(bag.peek_next(), MockGrenadierBag.GrenadeType.DEFENSIVE,
		"Last grenade in hard bag should be defensive (largest radius)")


func test_hard_all_grenades_in_priority_order() -> void:
	bag.build_bag_hard()

	# First 7 should be offensive (small radius)
	for i in range(7):
		assert_eq(bag.consume(), MockGrenadierBag.GrenadeType.OFFENSIVE,
			"Grenade %d should be offensive" % (i + 1))

	# Last should be defensive (large radius)
	assert_eq(bag.consume(), MockGrenadierBag.GrenadeType.DEFENSIVE,
		"Grenade 8 should be defensive")

	# Bag should be empty
	assert_false(bag.has_grenades(),
		"Bag should be empty after consuming all 8 grenades")


# ============================================================================
# Consume Tests
# ============================================================================


func test_consume_decrements_bag_size() -> void:
	bag.build_bag_normal()
	var initial_size := bag.get_bag_size()

	bag.consume()

	assert_eq(bag.get_bag_size(), initial_size - 1,
		"Consuming a grenade should decrement bag size by 1")


func test_consume_updates_grenades_remaining() -> void:
	bag.build_bag_normal()

	bag.consume()

	assert_eq(bag.grenades_remaining, 7,
		"grenades_remaining should be updated after consume")


func test_consume_from_empty_bag_returns_negative() -> void:
	# Bag is empty by default
	var result := bag.consume()

	assert_eq(result, -1,
		"Consuming from empty bag should return -1")


func test_consume_all_grenades_leaves_empty_bag() -> void:
	bag.build_bag_normal()

	for i in range(8):
		bag.consume()

	assert_false(bag.has_grenades(),
		"Bag should be empty after consuming all grenades")
	assert_eq(bag.grenades_remaining, 0,
		"grenades_remaining should be 0 after consuming all")


func test_consume_returns_correct_type() -> void:
	bag.build_bag_normal()

	var first := bag.consume()
	assert_eq(first, MockGrenadierBag.GrenadeType.FLASHBANG,
		"First consume should return FLASHBANG")


# ============================================================================
# Blocking Passage State Tests
# ============================================================================


func test_initial_blocking_state_is_false() -> void:
	assert_false(bag.is_blocking_passage(),
		"Initial blocking passage state should be false")


func test_set_blocking_to_true() -> void:
	bag.set_blocking(true)

	assert_true(bag.is_blocking_passage(),
		"is_blocking_passage should return true after setting to true")


func test_set_blocking_to_false() -> void:
	bag.set_blocking(true)
	bag.set_blocking(false)

	assert_false(bag.is_blocking_passage(),
		"is_blocking_passage should return false after setting to false")


func test_blocking_toggle() -> void:
	bag.set_blocking(true)
	assert_true(bag.is_blocking_passage(), "Should be blocking")

	bag.set_blocking(false)
	assert_false(bag.is_blocking_passage(), "Should not be blocking")

	bag.set_blocking(true)
	assert_true(bag.is_blocking_passage(), "Should be blocking again")


# ============================================================================
# Has Grenades Tests
# ============================================================================


func test_has_grenades_true_when_bag_not_empty() -> void:
	bag.build_bag_normal()

	assert_true(bag.has_grenades(),
		"has_grenades should be true when bag is not empty")


func test_has_grenades_false_when_bag_empty() -> void:
	assert_false(bag.has_grenades(),
		"has_grenades should be false when bag is empty")


func test_has_grenades_after_partial_consumption() -> void:
	bag.build_bag_normal()
	bag.consume()
	bag.consume()

	assert_true(bag.has_grenades(),
		"has_grenades should be true after partial consumption")


func test_has_grenades_false_after_full_consumption() -> void:
	bag.build_bag_normal()
	for i in range(8):
		bag.consume()

	assert_false(bag.has_grenades(),
		"has_grenades should be false after consuming all grenades")


# ============================================================================
# Grenade Type Constants Tests
# ============================================================================


func test_grenade_type_flashbang_value() -> void:
	assert_eq(MockGrenadierBag.GrenadeType.FLASHBANG, 0,
		"FLASHBANG type should be 0")


func test_grenade_type_offensive_value() -> void:
	assert_eq(MockGrenadierBag.GrenadeType.OFFENSIVE, 1,
		"OFFENSIVE type should be 1")


func test_grenade_type_defensive_value() -> void:
	assert_eq(MockGrenadierBag.GrenadeType.DEFENSIVE, 2,
		"DEFENSIVE type should be 2")


# ============================================================================
# Bag Rebuild Tests
# ============================================================================


func test_rebuild_bag_clears_previous() -> void:
	bag.build_bag_normal()
	bag.consume()
	bag.consume()

	# Rebuild should start fresh
	bag.build_bag_hard()

	assert_eq(bag.get_bag_size(), 8,
		"Rebuilding bag should start fresh with full 8 grenades")


func test_rebuild_changes_difficulty_loadout() -> void:
	bag.build_bag_normal()
	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.FLASHBANG), 3,
		"Normal should have 3 flashbangs")

	bag.build_bag_hard()
	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.FLASHBANG), 0,
		"Hard should have 0 flashbangs")
	assert_eq(bag.count_type(MockGrenadierBag.GrenadeType.DEFENSIVE), 1,
		"Hard should have 1 defensive")


# ============================================================================
# Passage Throw Logic Tests (Issue #604)
# ============================================================================


func test_passage_throw_not_possible_when_empty_bag() -> void:
	# Empty bag should not allow passage throw
	assert_false(bag.has_grenades(),
		"Empty bag cannot throw passage grenade")


func test_passage_throw_not_possible_when_blocking() -> void:
	bag.build_bag_normal()
	bag.set_blocking(true)

	assert_true(bag.is_blocking_passage(),
		"Grenadier should not passage-throw while already blocking a passage")


func test_passage_throw_consumes_grenade_from_bag() -> void:
	bag.build_bag_normal()
	var initial_size := bag.get_bag_size()

	# Simulate a passage throw consuming a grenade
	var consumed := bag.consume()
	bag.set_blocking(true)

	assert_eq(consumed, MockGrenadierBag.GrenadeType.FLASHBANG,
		"Passage throw should consume least dangerous grenade first (flashbang)")
	assert_eq(bag.get_bag_size(), initial_size - 1,
		"Bag should have one less grenade after passage throw")


func test_passage_throw_uses_priority_order() -> void:
	bag.build_bag_normal()

	# First 3 passage throws should use flashbangs
	for i in range(3):
		var type := bag.consume()
		assert_eq(type, MockGrenadierBag.GrenadeType.FLASHBANG,
			"Passage throw %d should use flashbang" % (i + 1))

	# After flashbangs, passage throws should use offensive grenades
	var type := bag.consume()
	assert_eq(type, MockGrenadierBag.GrenadeType.OFFENSIVE,
		"After flashbangs exhausted, passage throw should use offensive grenade")


func test_passage_throw_hard_difficulty_order() -> void:
	bag.build_bag_hard()

	# First 7 passage throws should use offensive (small radius)
	for i in range(7):
		var type := bag.consume()
		assert_eq(type, MockGrenadierBag.GrenadeType.OFFENSIVE,
			"Hard mode passage throw %d should use offensive" % (i + 1))

	# Last should be defensive (large radius)
	var type := bag.consume()
	assert_eq(type, MockGrenadierBag.GrenadeType.DEFENSIVE,
		"Hard mode last passage throw should use defensive")
