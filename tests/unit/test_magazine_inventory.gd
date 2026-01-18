extends GutTest
## Unit tests for MagazineInventory functionality.
##
## Tests the magazine tracking, swapping, and selection logic.
## Note: Since MagazineInventory is a C# class, these tests use a mock implementation
## that mirrors the expected behavior for testing purposes.


# Mock implementation that mirrors MagazineInventory behavior
class MockMagazineData:
	var current_ammo: int
	var max_capacity: int

	func _init(p_current_ammo: int, p_max_capacity: int) -> void:
		current_ammo = p_current_ammo
		max_capacity = p_max_capacity

	func is_empty() -> bool:
		return current_ammo <= 0

	func is_full() -> bool:
		return current_ammo >= max_capacity


class MockMagazineInventory:
	## Mirrors the C# MagazineInventory class behavior for testing
	var _spare_magazines: Array[MockMagazineData] = []
	var current_magazine: MockMagazineData = null

	func get_spare_magazines() -> Array[MockMagazineData]:
		return _spare_magazines

	func get_total_magazine_count() -> int:
		return (1 if current_magazine != null else 0) + _spare_magazines.size()

	func get_total_spare_ammo() -> int:
		var total := 0
		for mag in _spare_magazines:
			total += mag.current_ammo
		return total

	func initialize(magazine_count: int, magazine_size: int, fill_all_magazines: bool = true) -> void:
		_spare_magazines.clear()

		# Create the current magazine (always full at start)
		current_magazine = MockMagazineData.new(magazine_size, magazine_size)

		# Create spare magazines
		for i in range(1, magazine_count):
			var ammo := magazine_size if fill_all_magazines else 0
			_spare_magazines.append(MockMagazineData.new(ammo, magazine_size))

	func swap_to_fullest_magazine() -> MockMagazineData:
		if _spare_magazines.is_empty():
			return null

		# Find the magazine with the most ammo
		var max_ammo_index := 0
		var max_ammo := _spare_magazines[0].current_ammo

		for i in range(1, _spare_magazines.size()):
			if _spare_magazines[i].current_ammo > max_ammo:
				max_ammo = _spare_magazines[i].current_ammo
				max_ammo_index = i

		# Don't swap if the best available magazine is empty
		if max_ammo <= 0:
			return null

		# Get the magazine to swap in
		var new_magazine := _spare_magazines[max_ammo_index]
		_spare_magazines.remove_at(max_ammo_index)

		# Store old magazine in spares (if it exists)
		var old_magazine := current_magazine
		if old_magazine != null:
			_spare_magazines.append(old_magazine)

		# Set new current magazine
		current_magazine = new_magazine

		return old_magazine

	func has_spare_ammo() -> bool:
		for mag in _spare_magazines:
			if mag.current_ammo > 0:
				return true
		return false

	func consume_ammo() -> bool:
		if current_magazine == null or current_magazine.current_ammo <= 0:
			return false
		current_magazine.current_ammo -= 1
		return true

	func get_magazine_display_string() -> String:
		var parts: Array[String] = []

		if current_magazine != null:
			parts.append("[%d]" % current_magazine.current_ammo)

		# Sort spare magazines by ammo count (highest first) for display
		var sorted_spares := _spare_magazines.duplicate()
		sorted_spares.sort_custom(func(a, b): return a.current_ammo > b.current_ammo)
		for mag in sorted_spares:
			parts.append(str(mag.current_ammo))

		return " | ".join(parts)

	func get_magazine_ammo_counts() -> Array[int]:
		var counts: Array[int] = []

		if current_magazine != null:
			counts.append(current_magazine.current_ammo)

		# Sort spare magazines by ammo count (highest first)
		var sorted_spares := _spare_magazines.duplicate()
		sorted_spares.sort_custom(func(a, b): return a.current_ammo > b.current_ammo)
		for mag in sorted_spares:
			counts.append(mag.current_ammo)

		return counts

	func add_spare_magazine(current_ammo: int, max_capacity: int) -> void:
		_spare_magazines.append(MockMagazineData.new(current_ammo, max_capacity))


var inventory: MockMagazineInventory


func before_each() -> void:
	inventory = MockMagazineInventory.new()


func after_each() -> void:
	inventory = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_initialize_creates_correct_number_of_magazines() -> void:
	inventory.initialize(4, 30, true)

	assert_eq(inventory.get_total_magazine_count(), 4, "Should have 4 total magazines")
	assert_eq(inventory.get_spare_magazines().size(), 3, "Should have 3 spare magazines")


func test_initialize_fills_all_magazines_when_requested() -> void:
	inventory.initialize(4, 30, true)

	assert_eq(inventory.current_magazine.current_ammo, 30, "Current magazine should be full")
	assert_eq(inventory.get_total_spare_ammo(), 90, "Spare ammo should be 90 (3 x 30)")


func test_initialize_only_fills_current_magazine_when_not_filling_all() -> void:
	inventory.initialize(4, 30, false)

	assert_eq(inventory.current_magazine.current_ammo, 30, "Current magazine should be full")
	assert_eq(inventory.get_total_spare_ammo(), 0, "Spare ammo should be 0")


# ============================================================================
# Magazine Swap Tests
# ============================================================================


func test_swap_to_fullest_magazine_selects_highest_ammo() -> void:
	inventory.initialize(4, 30, true)

	# Partially empty the current magazine
	for i in range(20):
		inventory.consume_ammo()

	# Now current has 10 bullets, spares all have 30
	var old_mag := inventory.swap_to_fullest_magazine()

	assert_eq(old_mag.current_ammo, 10, "Old magazine should have 10 bullets")
	assert_eq(inventory.current_magazine.current_ammo, 30, "New magazine should be full")


func test_swap_preserves_old_magazine_ammo() -> void:
	inventory.initialize(4, 30, true)

	# Use 25 bullets from current magazine
	for i in range(25):
		inventory.consume_ammo()

	# Swap to a full magazine
	inventory.swap_to_fullest_magazine()

	# The old magazine with 5 bullets should now be in spares
	var spare_ammo_counts: Array[int] = []
	for mag in inventory.get_spare_magazines():
		spare_ammo_counts.append(mag.current_ammo)

	assert_true(5 in spare_ammo_counts, "Old magazine with 5 bullets should be in spares")


func test_swap_does_not_combine_ammo() -> void:
	inventory.initialize(4, 30, true)

	# Use 20 bullets from current magazine (10 remaining)
	for i in range(20):
		inventory.consume_ammo()

	var old_ammo := inventory.current_magazine.current_ammo  # Should be 10

	# Swap to a full magazine
	inventory.swap_to_fullest_magazine()

	var new_ammo := inventory.current_magazine.current_ammo  # Should be 30

	# Verify ammo was NOT combined (should be exactly 30, not 40)
	assert_eq(new_ammo, 30, "New magazine should have exactly 30, not combined ammo")
	assert_ne(new_ammo, 40, "Ammo should NOT be combined")

	# Verify old magazine is preserved with its original ammo
	var found_old := false
	for mag in inventory.get_spare_magazines():
		if mag.current_ammo == old_ammo:
			found_old = true
			break
	assert_true(found_old, "Old magazine should be preserved with original ammo")


func test_swap_returns_null_when_no_spare_ammo() -> void:
	inventory.initialize(4, 30, false)  # Spares are empty

	var old_mag := inventory.swap_to_fullest_magazine()

	assert_null(old_mag, "Should return null when no spare magazines have ammo")


func test_swap_selects_magazine_with_most_ammo_from_varied_spares() -> void:
	inventory.initialize(1, 30, true)  # Just current mag

	# Add spares with varied ammo counts
	inventory.add_spare_magazine(10, 30)
	inventory.add_spare_magazine(25, 30)
	inventory.add_spare_magazine(5, 30)

	# Empty current magazine
	while inventory.current_magazine.current_ammo > 0:
		inventory.consume_ammo()

	# Swap to fullest
	inventory.swap_to_fullest_magazine()

	assert_eq(inventory.current_magazine.current_ammo, 25, "Should swap to magazine with 25 bullets")


# ============================================================================
# Consume Ammo Tests
# ============================================================================


func test_consume_ammo_decrements_current_magazine() -> void:
	inventory.initialize(4, 30, true)

	var result := inventory.consume_ammo()

	assert_true(result, "Should return true when ammo consumed")
	assert_eq(inventory.current_magazine.current_ammo, 29, "Ammo should be decremented")


func test_consume_ammo_returns_false_when_empty() -> void:
	inventory.initialize(4, 30, true)

	# Empty the magazine
	while inventory.current_magazine.current_ammo > 0:
		inventory.consume_ammo()

	var result := inventory.consume_ammo()

	assert_false(result, "Should return false when magazine is empty")


# ============================================================================
# Display and Query Tests
# ============================================================================


func test_get_magazine_display_string_format() -> void:
	inventory.initialize(4, 30, true)

	var display := inventory.get_magazine_display_string()

	# Should show current in brackets, then sorted spares
	assert_eq(display, "[30] | 30 | 30 | 30", "Display should show current in brackets")


func test_get_magazine_display_string_with_varied_ammo() -> void:
	inventory.initialize(1, 30, true)
	inventory.add_spare_magazine(10, 30)
	inventory.add_spare_magazine(25, 30)
	inventory.add_spare_magazine(5, 30)

	# Partially use current magazine
	for i in range(15):
		inventory.consume_ammo()

	var display := inventory.get_magazine_display_string()

	# Should show [15] (current), then 25, 10, 5 (sorted descending)
	assert_eq(display, "[15] | 25 | 10 | 5", "Display should show sorted spare magazines")


func test_get_magazine_ammo_counts_returns_correct_array() -> void:
	inventory.initialize(1, 30, true)
	inventory.add_spare_magazine(20, 30)
	inventory.add_spare_magazine(10, 30)

	var counts := inventory.get_magazine_ammo_counts()

	assert_eq(counts[0], 30, "First element should be current magazine")
	assert_eq(counts[1], 20, "Second element should be highest spare")
	assert_eq(counts[2], 10, "Third element should be lowest spare")


# ============================================================================
# Has Spare Ammo Tests
# ============================================================================


func test_has_spare_ammo_returns_true_when_spares_have_ammo() -> void:
	inventory.initialize(4, 30, true)

	assert_true(inventory.has_spare_ammo(), "Should have spare ammo")


func test_has_spare_ammo_returns_false_when_spares_empty() -> void:
	inventory.initialize(4, 30, false)  # Spares not filled

	assert_false(inventory.has_spare_ammo(), "Should not have spare ammo")


# ============================================================================
# Realistic Scenario Tests
# ============================================================================


func test_realistic_combat_scenario() -> void:
	# Scenario: Player has 4 magazines (1 current + 3 spare), each with 30 rounds
	# Player fires 25 rounds, then reloads
	# Expected: Player should get a full magazine (30 rounds)
	# The partially used magazine (5 rounds) should be preserved in spares

	inventory.initialize(4, 30, true)

	# Fire 25 rounds
	for i in range(25):
		assert_true(inventory.consume_ammo(), "Should consume ammo")

	assert_eq(inventory.current_magazine.current_ammo, 5, "Current should have 5 rounds")

	# Reload (swap to fullest)
	var old_mag := inventory.swap_to_fullest_magazine()

	assert_eq(old_mag.current_ammo, 5, "Old magazine should have 5 rounds")
	assert_eq(inventory.current_magazine.current_ammo, 30, "New magazine should be full")

	# Verify the old magazine is in spares
	var found := false
	for mag in inventory.get_spare_magazines():
		if mag.current_ammo == 5:
			found = true
			break
	assert_true(found, "Old magazine should be in spares")

	# Total magazines should still be 4
	assert_eq(inventory.get_total_magazine_count(), 4, "Should still have 4 magazines")


func test_multiple_reloads_preserve_all_magazines() -> void:
	# Scenario: Player does multiple reloads, each with different ammo remaining
	# All magazines should be preserved with their exact ammo counts

	inventory.initialize(4, 30, true)

	# First combat: use 20 rounds, then reload (10 remaining)
	for i in range(20):
		inventory.consume_ammo()
	inventory.swap_to_fullest_magazine()

	# Second combat: use 15 rounds, then reload (15 remaining)
	for i in range(15):
		inventory.consume_ammo()
	inventory.swap_to_fullest_magazine()

	# Third combat: use 28 rounds, then reload (2 remaining)
	for i in range(28):
		inventory.consume_ammo()
	inventory.swap_to_fullest_magazine()

	# Now we should have magazines with: current (from the 10-round one), 15, 10, 2
	# Actually, let's count what we should have:
	# - Started with 4 x 30 = 120 rounds
	# - Used 20 + 15 + 28 = 63 rounds
	# - Remaining = 57 rounds across all magazines

	var total_ammo := inventory.current_magazine.current_ammo + inventory.get_total_spare_ammo()
	assert_eq(total_ammo, 57, "Total ammo should be preserved (120 - 63 = 57)")

	# Still have 4 magazines
	assert_eq(inventory.get_total_magazine_count(), 4, "Should still have 4 magazines")
