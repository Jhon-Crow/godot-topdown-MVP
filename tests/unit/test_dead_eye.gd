extends GutTest
## Unit tests for Dead Eye passive item behavior (Issue #1069).
##
## Tests the Dead Eye damage multiplier mechanics:
## - Starts at -20% damage (multiplier 0.8)
## - Each hit increases multiplier by +5% (0.8 → 0.85 → 0.90 → ...)
## - After a miss (volley window closes without hit), resets to 0.8
## - Returns 1.0 multiplier when inactive (item not equipped)


# ============================================================================
# Mock DeadEyeManager for Logic Tests
# ============================================================================


class MockDeadEyeManager:
	## Starting damage multiplier (base -20%).
	const BASE_MULTIPLIER: float = 0.8

	## Damage increase per hit streak step (+5%).
	const HIT_STEP: float = 0.05

	## Duration of a single volley window in seconds.
	const VOLLEY_WINDOW: float = 1.0

	## Current damage multiplier.
	var _multiplier: float = BASE_MULTIPLIER

	## Whether at least one bullet in the current volley hit an enemy.
	var _volley_had_hit: bool = false

	## Whether a volley is currently active.
	var _volley_active: bool = false

	## Timer tracking how long since the last bullet was fired.
	var _volley_timer: float = 0.0

	## Whether Dead Eye is currently active (item equipped).
	var _is_active: bool = false

	## Activates or deactivates Dead Eye tracking.
	func set_active(active: bool) -> void:
		_is_active = active
		if active:
			_reset()

	## Called when a bullet is fired by the player.
	func notify_bullet_fired() -> void:
		if not _is_active:
			return
		if not _volley_active:
			_volley_active = true
			_volley_had_hit = false
		_volley_timer = VOLLEY_WINDOW

	## Called when a player bullet hits an enemy.
	func notify_hit() -> void:
		if not _is_active:
			return
		_volley_had_hit = true

	## Simulates the passage of time (called instead of _process in tests).
	func simulate_time(delta: float) -> void:
		if not _is_active or not _volley_active:
			return
		_volley_timer -= delta
		if _volley_timer <= 0.0:
			_close_volley()

	## Closes the current volley window and updates the multiplier.
	func _close_volley() -> void:
		_volley_active = false
		_volley_timer = 0.0
		if _volley_had_hit:
			_multiplier += HIT_STEP
		else:
			_multiplier = BASE_MULTIPLIER
		_volley_had_hit = false

	## Manually close volley for testing convenience.
	func force_close_volley() -> void:
		if _volley_active:
			_close_volley()

	## Returns the current damage multiplier.
	func get_damage_multiplier() -> float:
		if not _is_active:
			return 1.0
		return _multiplier

	## Returns the current hit streak count (number of stacks above base).
	func get_hit_streak() -> int:
		if not _is_active:
			return 0
		return int(round((_multiplier - BASE_MULTIPLIER) / HIT_STEP))

	## Internal reset helper.
	func _reset() -> void:
		_multiplier = BASE_MULTIPLIER
		_volley_active = false
		_volley_had_hit = false
		_volley_timer = 0.0


# ============================================================================
# Setup
# ============================================================================


var _manager: MockDeadEyeManager


func before_each() -> void:
	_manager = MockDeadEyeManager.new()


# ============================================================================
# Inactive State Tests
# ============================================================================


func test_returns_1_when_inactive() -> void:
	# When Dead Eye is not active, multiplier should be 1.0 (no modification)
	assert_almost_eq(_manager.get_damage_multiplier(), 1.0, 0.001,
		"Inactive Dead Eye should return 1.0 multiplier")


func test_notify_hit_does_nothing_when_inactive() -> void:
	# Hits should be ignored when not active
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 1.0, 0.001,
		"Inactive Dead Eye should not track hits")


func test_notify_bullet_fired_does_nothing_when_inactive() -> void:
	_manager.notify_bullet_fired()
	_manager.simulate_time(2.0)
	assert_almost_eq(_manager.get_damage_multiplier(), 1.0, 0.001,
		"Inactive Dead Eye should not track bullets fired")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_at_base_multiplier_when_activated() -> void:
	_manager.set_active(true)
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"Dead Eye should start at 0.8 (-20%%) when activated")


func test_base_multiplier_is_minus_20_percent() -> void:
	# 0.8 = 1.0 - 0.2 = -20%
	assert_almost_eq(MockDeadEyeManager.BASE_MULTIPLIER, 0.8, 0.001,
		"BASE_MULTIPLIER should be 0.8 (-20%%)")


func test_hit_step_is_5_percent() -> void:
	assert_almost_eq(MockDeadEyeManager.HIT_STEP, 0.05, 0.001,
		"HIT_STEP should be 0.05 (+5%%)")


func test_volley_window_is_1_second() -> void:
	assert_almost_eq(MockDeadEyeManager.VOLLEY_WINDOW, 1.0, 0.001,
		"VOLLEY_WINDOW should be 1.0 second")


# ============================================================================
# Hit Streak Tests
# ============================================================================


func test_hit_increases_multiplier() -> void:
	_manager.set_active(true)
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.85, 0.001,
		"After 1 hit, multiplier should be 0.85")


func test_two_hits_increase_multiplier_by_10_percent() -> void:
	_manager.set_active(true)
	# First hit volley
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	# Second hit volley
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.9, 0.001,
		"After 2 hits, multiplier should be 0.90")


func test_four_hits_restore_base_damage() -> void:
	_manager.set_active(true)
	for i in range(4):
		_manager.notify_bullet_fired()
		_manager.notify_hit()
		_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 1.0, 0.001,
		"After 4 hits, multiplier should reach 1.0 (base damage restored)")


func test_hits_can_exceed_base_damage() -> void:
	_manager.set_active(true)
	for i in range(6):
		_manager.notify_bullet_fired()
		_manager.notify_hit()
		_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 1.1, 0.001,
		"After 6 hits, multiplier should be 1.1 (+10%% above base)")


# ============================================================================
# Miss Reset Tests
# ============================================================================


func test_miss_resets_multiplier_to_base() -> void:
	_manager.set_active(true)
	# Build up streak
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	# Verify streak built up
	assert_almost_eq(_manager.get_damage_multiplier(), 0.85, 0.001,
		"After 1 hit, multiplier should be 0.85")
	# Now miss: fire a bullet but don't hit, then close volley
	_manager.notify_bullet_fired()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"After a miss, multiplier should reset to 0.8")


func test_miss_after_long_streak_resets_to_base() -> void:
	_manager.set_active(true)
	# Build up a long streak
	for i in range(10):
		_manager.notify_bullet_fired()
		_manager.notify_hit()
		_manager.force_close_volley()
	# One miss
	_manager.notify_bullet_fired()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"After a miss following a long streak, multiplier should reset to 0.8")


# ============================================================================
# Volley Window Tests
# ============================================================================


func test_volley_closes_after_window_expires() -> void:
	_manager.set_active(true)
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	# Simulate time passing (more than VOLLEY_WINDOW = 1 second)
	_manager.simulate_time(1.1)
	assert_almost_eq(_manager.get_damage_multiplier(), 0.85, 0.001,
		"After volley window expires with a hit, multiplier should increase")


func test_volley_miss_after_window_expires() -> void:
	_manager.set_active(true)
	_manager.notify_bullet_fired()
	# No hit — only simulate time to close the volley
	_manager.simulate_time(1.1)
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"After volley window expires without a hit, multiplier should stay at base")


func test_automatic_weapon_extends_volley_window() -> void:
	_manager.set_active(true)
	# Fire 5 bullets within 1 second (simulating automatic fire at ~5 shots/sec)
	for i in range(5):
		_manager.notify_bullet_fired()
		_manager.simulate_time(0.15)  # 0.15s between shots = extends timer each time
	# Hit on the last bullet
	_manager.notify_hit()
	# Wait for the window to close after last shot
	_manager.simulate_time(1.1)
	assert_almost_eq(_manager.get_damage_multiplier(), 0.85, 0.001,
		"Hitting with any bullet in an auto burst should count as a hit")


func test_shotgun_volley_one_pellet_hit_counts() -> void:
	_manager.set_active(true)
	# Shotgun fires multiple pellets simultaneously — all call notify_bullet_fired
	for i in range(12):  # e.g., 12 pellets
		_manager.notify_bullet_fired()
	# Only one pellet hits
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.85, 0.001,
		"If any shotgun pellet hits, the volley counts as a hit")


func test_shotgun_volley_no_hits_is_miss() -> void:
	_manager.set_active(true)
	# Fire 12 pellets, none hit
	for i in range(12):
		_manager.notify_bullet_fired()
	_manager.force_close_volley()
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"If no shotgun pellets hit, the volley counts as a miss")


# ============================================================================
# Reactivation Tests
# ============================================================================


func test_reactivation_resets_state() -> void:
	_manager.set_active(true)
	# Build up streak
	for i in range(5):
		_manager.notify_bullet_fired()
		_manager.notify_hit()
		_manager.force_close_volley()
	var multiplier_after_streak := _manager.get_damage_multiplier()
	assert_true(multiplier_after_streak > 0.8,
		"Multiplier should have increased after streak")
	# Reactivate (simulates level restart)
	_manager.set_active(true)
	assert_almost_eq(_manager.get_damage_multiplier(), 0.8, 0.001,
		"After reactivation, multiplier should reset to base 0.8")


func test_deactivation_returns_1() -> void:
	_manager.set_active(true)
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	# Deactivate (item unequipped)
	_manager.set_active(false)
	assert_almost_eq(_manager.get_damage_multiplier(), 1.0, 0.001,
		"After deactivation, multiplier should return to 1.0")


# ============================================================================
# Hit Streak Counter Tests
# ============================================================================


func test_get_hit_streak_zero_when_inactive() -> void:
	assert_eq(_manager.get_hit_streak(), 0,
		"Streak should be 0 when inactive")


func test_get_hit_streak_zero_at_base() -> void:
	_manager.set_active(true)
	assert_eq(_manager.get_hit_streak(), 0,
		"Streak should be 0 at base multiplier (no hits yet)")


func test_get_hit_streak_increments() -> void:
	_manager.set_active(true)
	# First hit
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_eq(_manager.get_hit_streak(), 1,
		"Streak should be 1 after first hit")
	# Second hit
	_manager.notify_bullet_fired()
	_manager.notify_hit()
	_manager.force_close_volley()
	assert_eq(_manager.get_hit_streak(), 2,
		"Streak should be 2 after second hit")


func test_get_hit_streak_resets_on_miss() -> void:
	_manager.set_active(true)
	# Build streak
	for i in range(3):
		_manager.notify_bullet_fired()
		_manager.notify_hit()
		_manager.force_close_volley()
	assert_eq(_manager.get_hit_streak(), 3, "Streak should be 3")
	# Miss — fire but no hit, then let volley close
	_manager.notify_bullet_fired()
	_manager.force_close_volley()
	assert_eq(_manager.get_hit_streak(), 0,
		"Streak should reset to 0 after miss")
