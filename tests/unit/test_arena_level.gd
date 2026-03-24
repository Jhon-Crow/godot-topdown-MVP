extends GutTest
## Unit tests for arena_level.gd — Arena Mode.
##
## Tests wave progression, enemy spawning logic, pickup spawning,
## health/ammo/weapon/grenade pickup application, wave-in-progress guard,
## and score-on-death.
## All tests use a lightweight mock class and do not require a running Godot scene.
##
## Issue #1063.


# ============================================================================
# Mock Arena Level (mirrors arena_level.gd without scene dependencies)
# ============================================================================


class MockArenaLevel:
	## Constants mirrored from arena_level.gd.
	const BASE_ENEMIES_PER_WAVE: int = 3
	const ENEMIES_PER_WAVE_INCREMENT: int = 2
	const MAX_CONCURRENT_ENEMIES: int = 12
	const INTER_WAVE_DELAY: float = 5.0
	const FIRST_WAVE_DELAY: float = 2.0
	const HEALTH_PICKUPS_PER_WAVE: int = 2
	const AMMO_PICKUPS_PER_WAVE: int = 2
	const GRENADE_PICKUPS_PER_WAVE: int = 1
	const WEAPON_PICKUP_WAVE_INTERVAL: int = 2

	## Current wave number.
	var _wave_number: int = 0
	## Target enemy count for the current wave.
	var _wave_enemy_target: int = 0
	## Enemies still alive in the current wave.
	var _enemies_alive: int = 0
	## Total enemies spawned this wave.
	var _enemies_spawned: int = 0
	## Whether a wave is currently active.
	var _wave_in_progress: bool = false
	## Whether the level is active.
	var _level_active: bool = true
	## Whether the score screen was shown.
	var _score_shown: bool = false
	## Whether we are between waves.
	var _between_waves: bool = false
	## Inter-wave timer.
	var _wave_timer: float = 0.0
	## Number of times score was shown.
	var score_shown_count: int = 0
	## Whether player died was handled.
	var player_died_handled: bool = false

	## Pickups spawned (recorded as type strings).
	var pickups_spawned: Array[String] = []
	## Enemies spawned this wave (recorded count).
	var enemies_spawned_this_wave: int = 0
	## Player mock for health/ammo.
	var mock_player: MockPlayer = MockPlayer.new()

	## Start the next wave (mirrors _start_wave).
	func start_wave() -> void:
		_wave_number += 1
		_wave_enemy_target = BASE_ENEMIES_PER_WAVE + (_wave_number - 1) * ENEMIES_PER_WAVE_INCREMENT
		_enemies_alive = 0
		_enemies_spawned = 0
		_wave_in_progress = true
		enemies_spawned_this_wave = 0

		var to_spawn: int = mini(_wave_enemy_target, MAX_CONCURRENT_ENEMIES)
		for i in range(to_spawn):
			spawn_enemy()

	## Spawn one enemy.
	func spawn_enemy() -> void:
		_enemies_spawned += 1
		_enemies_alive += 1
		enemies_spawned_this_wave += 1

	## Called when enemy dies.
	## Guard: only process deaths while a wave is in progress to prevent
	## _end_wave() from being called multiple times (bug fix #1063 round 2).
	func on_enemy_died() -> void:
		if not _wave_in_progress:
			return

		_enemies_alive -= 1

		# Spawn additional if more remain.
		if _enemies_spawned < _wave_enemy_target:
			spawn_enemy()

		# Check wave complete.
		if _enemies_alive <= 0 and _enemies_spawned >= _wave_enemy_target:
			end_wave()

	## End the wave and start inter-wave timer.
	func end_wave() -> void:
		_wave_in_progress = false
		spawn_wave_pickups()
		_wave_timer = INTER_WAVE_DELAY
		_between_waves = true

	## Spawn pickups.
	func spawn_wave_pickups() -> void:
		for i in range(HEALTH_PICKUPS_PER_WAVE):
			pickups_spawned.append("health")
		for i in range(AMMO_PICKUPS_PER_WAVE):
			pickups_spawned.append("ammo")
		for i in range(GRENADE_PICKUPS_PER_WAVE):
			pickups_spawned.append("grenade")
		if _wave_number % WEAPON_PICKUP_WAVE_INTERVAL == 0:
			pickups_spawned.append("weapon")

	## Apply health pickup.
	func apply_health_pickup() -> void:
		mock_player.health = mini(mock_player.max_health, mock_player.health + 1)

	## Apply ammo pickup.
	func apply_ammo_pickup(ammo_amount: int) -> void:
		mock_player.reserve_ammo += ammo_amount

	## Apply weapon pickup (simulates weapon ID change).
	func apply_weapon_pickup(new_weapon_id: String) -> void:
		mock_player.weapon_id = new_weapon_id

	## Apply grenade pickup (+1 grenade to player inventory).
	func apply_grenade_pickup() -> void:
		mock_player.grenades = mini(mock_player.grenades + 1, mock_player.max_grenades)

	## Apply active item charge pickup (+1 charge if player has charge-based item).
	func apply_active_item_charge_pickup() -> void:
		if mock_player.active_item_charges < mock_player.max_active_item_charges:
			mock_player.active_item_charges += 1

	## Calculate enemies per wave.
	func get_enemies_for_wave(wave: int) -> int:
		return BASE_ENEMIES_PER_WAVE + (wave - 1) * ENEMIES_PER_WAVE_INCREMENT

	## Number of enemies spawned initially (capped at MAX_CONCURRENT_ENEMIES).
	func get_initial_spawn_count_for_wave(wave: int) -> int:
		return mini(get_enemies_for_wave(wave), MAX_CONCURRENT_ENEMIES)

	## Handle player death.
	func on_player_died() -> void:
		if not _level_active:
			return
		_level_active = false
		player_died_handled = true
		complete_level_with_score()

	## Show score (simulated).
	func complete_level_with_score() -> void:
		if _score_shown:
			return
		_score_shown = true
		score_shown_count += 1


class MockPlayer:
	var health: int = 3
	var max_health: int = 4
	var reserve_ammo: int = 30
	var weapon_id: String = "makarov_pm"
	var grenades: int = 1
	var max_grenades: int = 3
	var active_item_charges: int = 1
	var max_active_item_charges: int = 2


# ============================================================================
# Wave Progression Tests
# ============================================================================


func test_wave_1_enemy_count() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	assert_eq(arena._wave_number, 1, "Should be wave 1")
	assert_eq(arena._wave_enemy_target, 3, "Wave 1 should have 3 enemies (BASE=3)")


func test_wave_2_enemy_count() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()  # wave 1
	# Skip wave 1 enemies.
	for i in range(arena.get_enemies_for_wave(1)):
		arena.on_enemy_died()
	arena.start_wave()  # wave 2
	assert_eq(arena._wave_number, 2, "Should be wave 2")
	assert_eq(arena._wave_enemy_target, 5, "Wave 2 should have 5 enemies (3 + 2)")


func test_wave_5_enemy_count() -> void:
	var arena := MockArenaLevel.new()
	for w in range(5):
		arena.start_wave()
		var target: int = arena._wave_enemy_target
		for i in range(target):
			arena.on_enemy_died()
	assert_eq(arena._wave_number, 5, "Should be wave 5")
	assert_eq(arena._wave_enemy_target, 11, "Wave 5 = 3 + 4*2 = 11 enemies")


func test_max_concurrent_enemies_cap() -> void:
	var arena := MockArenaLevel.new()
	# Wave 6 would be 3 + 5*2 = 13 enemies — exceeds MAX_CONCURRENT_ENEMIES (12).
	for w in range(6):
		arena.start_wave()
		var target: int = arena._wave_enemy_target
		for i in range(target):
			arena.on_enemy_died()
	assert_eq(arena._wave_number, 6, "Should be wave 6")
	assert_eq(arena._wave_enemy_target, 13, "Wave 6 should target 13 enemies")
	# But initial spawn should be capped.
	assert_eq(
		arena.get_initial_spawn_count_for_wave(6),
		12,
		"Initial concurrent enemies capped at MAX_CONCURRENT_ENEMIES=12"
	)


func test_enemies_progress_correctly_through_wave() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()  # wave 1: 3 enemies
	assert_eq(arena._enemies_alive, 3, "3 enemies alive at wave start")

	arena.on_enemy_died()
	assert_eq(arena._enemies_alive, 2, "2 enemies alive after first kill")
	assert_true(arena._wave_in_progress, "Wave still in progress")

	arena.on_enemy_died()
	assert_eq(arena._enemies_alive, 1, "1 enemy alive after second kill")

	arena.on_enemy_died()
	assert_eq(arena._enemies_alive, 0, "0 enemies alive after third kill")
	assert_false(arena._wave_in_progress, "Wave ended after all enemies killed")


func test_wave_ends_trigger_inter_wave_timer() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	assert_true(arena._between_waves, "Should be between waves after wave ends")
	assert_eq(arena._wave_timer, MockArenaLevel.INTER_WAVE_DELAY, "Timer should be set to INTER_WAVE_DELAY")


# ============================================================================
# Pickup Spawning Tests
# ============================================================================


func test_wave_1_spawns_health_ammo_grenade_not_weapon() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	# Wave 1 should spawn 2 health + 2 ammo + 1 grenade, no weapon (weapon only on even waves).
	var health_count: int = arena.pickups_spawned.count("health")
	var ammo_count: int = arena.pickups_spawned.count("ammo")
	var grenade_count: int = arena.pickups_spawned.count("grenade")
	var weapon_count: int = arena.pickups_spawned.count("weapon")
	assert_eq(health_count, MockArenaLevel.HEALTH_PICKUPS_PER_WAVE, "Should spawn HEALTH_PICKUPS_PER_WAVE health pickups")
	assert_eq(ammo_count, MockArenaLevel.AMMO_PICKUPS_PER_WAVE, "Should spawn AMMO_PICKUPS_PER_WAVE ammo pickups")
	assert_eq(grenade_count, MockArenaLevel.GRENADE_PICKUPS_PER_WAVE, "Should spawn GRENADE_PICKUPS_PER_WAVE grenade pickups")
	assert_eq(weapon_count, 0, "Wave 1 should not spawn weapon pickup (odd wave)")


func test_wave_2_spawns_weapon_pickup() -> void:
	var arena := MockArenaLevel.new()
	for w in range(2):
		arena.start_wave()
		for i in range(arena._wave_enemy_target):
			arena.on_enemy_died()
	var weapon_count: int = arena.pickups_spawned.count("weapon")
	assert_eq(weapon_count, 1, "Wave 2 (even) should spawn 1 weapon pickup")


func test_weapon_pickup_every_two_waves() -> void:
	var arena := MockArenaLevel.new()
	for w in range(4):
		arena.start_wave()
		for i in range(arena._wave_enemy_target):
			arena.on_enemy_died()
	var weapon_count: int = arena.pickups_spawned.count("weapon")
	assert_eq(weapon_count, 2, "4 waves should produce 2 weapon pickups (waves 2 and 4)")


# ============================================================================
# Pickup Application Tests
# ============================================================================


func test_health_pickup_restores_one_hp() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.health = 2
	arena.mock_player.max_health = 4
	arena.apply_health_pickup()
	assert_eq(arena.mock_player.health, 3, "Health pickup should restore +1 HP")


func test_health_pickup_does_not_exceed_max() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.health = 4
	arena.mock_player.max_health = 4
	arena.apply_health_pickup()
	assert_eq(arena.mock_player.health, 4, "Health pickup should not exceed max_health")


func test_ammo_pickup_adds_ammo() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.reserve_ammo = 10
	arena.apply_ammo_pickup(60)
	assert_eq(arena.mock_player.reserve_ammo, 70, "Ammo pickup should add 60 rounds")


func test_weapon_pickup_changes_weapon() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.weapon_id = "makarov_pm"
	arena.apply_weapon_pickup("shotgun")
	assert_eq(arena.mock_player.weapon_id, "shotgun", "Weapon pickup should change weapon to shotgun")


# ============================================================================
# Player Death / Score Tests
# ============================================================================


func test_player_death_stops_level() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	arena.on_player_died()
	assert_false(arena._level_active, "Level should be inactive after player death")
	assert_true(arena.player_died_handled, "Player death should be handled")


func test_player_death_shows_score_once() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	arena.on_player_died()
	assert_eq(arena.score_shown_count, 1, "Score screen should appear exactly once on death")


func test_second_player_death_does_not_show_score_again() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()
	arena.on_player_died()
	arena.on_player_died()  # Second call — should be ignored.
	assert_eq(arena.score_shown_count, 1, "Score screen should not appear a second time")


func test_wave_number_recorded_at_death() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()  # wave 1
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	arena.start_wave()  # wave 2 — die during wave 2
	arena.on_player_died()
	assert_eq(arena._wave_number, 2, "Wave number should be 2 at death")


# ============================================================================
# Enemy Count Formula Tests
# ============================================================================


func test_enemy_count_formula_correctness() -> void:
	var arena := MockArenaLevel.new()
	assert_eq(arena.get_enemies_for_wave(1), 3, "Wave 1: 3 enemies")
	assert_eq(arena.get_enemies_for_wave(2), 5, "Wave 2: 5 enemies")
	assert_eq(arena.get_enemies_for_wave(3), 7, "Wave 3: 7 enemies")
	assert_eq(arena.get_enemies_for_wave(10), 21, "Wave 10: 21 enemies")


func test_initial_spawn_always_capped() -> void:
	var arena := MockArenaLevel.new()
	for wave in range(1, 15):
		var expected: int = mini(
			MockArenaLevel.BASE_ENEMIES_PER_WAVE + (wave - 1) * MockArenaLevel.ENEMIES_PER_WAVE_INCREMENT,
			MockArenaLevel.MAX_CONCURRENT_ENEMIES
		)
		assert_eq(
			arena.get_initial_spawn_count_for_wave(wave),
			expected,
			"Wave %d initial spawn count should be capped correctly" % wave
		)


# ============================================================================
# Additional enemy spawning during wave (batch replenishment)
# ============================================================================


func test_enemy_spawned_when_previous_dies_before_wave_full() -> void:
	## Wave target > MAX_CONCURRENT_ENEMIES.
	## As enemies die, new ones should spawn to approach the target.
	var arena := MockArenaLevel.new()
	# Manually set a large wave for testing replenishment.
	arena._wave_number = 5  # Simulate being on wave 6.
	arena._wave_enemy_target = 13  # Would be capped at 12 initially.
	arena._enemies_alive = 0
	arena._enemies_spawned = 0
	arena._wave_in_progress = true

	# Simulate initial spawn of 12 (MAX_CONCURRENT_ENEMIES).
	for i in range(12):
		arena.spawn_enemy()
	assert_eq(arena._enemies_alive, 12, "12 enemies alive after initial spawn")
	assert_eq(arena._enemies_spawned, 12, "12 enemies spawned")

	# Kill one — should trigger spawn of the 13th.
	arena.on_enemy_died()
	assert_eq(arena._enemies_spawned, 13, "13th enemy should be spawned after first death")
	assert_eq(arena._enemies_alive, 12, "Still 12 alive (killed 1, spawned 1)")


func test_wave_ends_only_when_all_spawned_and_dead() -> void:
	var arena := MockArenaLevel.new()
	arena.start_wave()  # wave 1: 3 enemies
	arena.on_enemy_died()
	arena.on_enemy_died()
	assert_true(arena._wave_in_progress, "Wave should still be in progress with 1 enemy alive")
	arena.on_enemy_died()
	assert_false(arena._wave_in_progress, "Wave should end when all enemies dead")


# ============================================================================
# Bug Fix: _wave_in_progress guard prevents duplicate _end_wave calls
# ============================================================================


func test_enemy_death_after_wave_ends_does_not_respawn_pickups() -> void:
	## Regression: before the _wave_in_progress guard, enemies dying after
	## the wave ended (due to deferred signal connections) would call
	## _end_wave() again, causing pickups to spawn 7+ times per wave.
	var arena := MockArenaLevel.new()
	arena.start_wave()  # wave 1: 3 enemies
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	assert_false(arena._wave_in_progress, "Wave should have ended")
	var pickup_count_after_wave: int = arena.pickups_spawned.size()

	# Simulate stale enemy death signals arriving after wave ends.
	arena.on_enemy_died()
	arena.on_enemy_died()
	arena.on_enemy_died()

	assert_eq(
		arena.pickups_spawned.size(),
		pickup_count_after_wave,
		"Stale enemy deaths after wave ends must not spawn extra pickups"
	)


func test_end_wave_called_once_even_with_extra_deaths() -> void:
	## _wave_in_progress guard: once a wave ends, subsequent on_enemy_died()
	## calls are no-ops. This verifies the pickup list is not duplicated.
	var arena := MockArenaLevel.new()
	arena.start_wave()
	# Kill all enemies normally.
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	var expected_pickups: int = arena.pickups_spawned.size()

	# Extra deaths should have no effect.
	for i in range(5):
		arena.on_enemy_died()
	assert_eq(arena.pickups_spawned.size(), expected_pickups, "Extra deaths must not add more pickups")


# ============================================================================
# New Pickup Types: grenade and active item charge
# ============================================================================


func test_grenade_pickup_adds_one_grenade() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.grenades = 1
	arena.mock_player.max_grenades = 3
	arena.apply_grenade_pickup()
	assert_eq(arena.mock_player.grenades, 2, "Grenade pickup should add 1 grenade")


func test_grenade_pickup_does_not_exceed_max() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.grenades = 3
	arena.mock_player.max_grenades = 3
	arena.apply_grenade_pickup()
	assert_eq(arena.mock_player.grenades, 3, "Grenade pickup should not exceed max_grenades")


func test_active_item_charge_pickup_adds_one_charge() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.active_item_charges = 1
	arena.mock_player.max_active_item_charges = 2
	arena.apply_active_item_charge_pickup()
	assert_eq(arena.mock_player.active_item_charges, 2, "Active item charge pickup should add 1 charge")


func test_active_item_charge_pickup_does_not_exceed_max() -> void:
	var arena := MockArenaLevel.new()
	arena.mock_player.active_item_charges = 2
	arena.mock_player.max_active_item_charges = 2
	arena.apply_active_item_charge_pickup()
	assert_eq(arena.mock_player.active_item_charges, 2, "Charge pickup should not exceed max charges")


func test_grenade_pickup_spawned_every_wave() -> void:
	## Every wave should produce GRENADE_PICKUPS_PER_WAVE grenade pickups.
	var arena := MockArenaLevel.new()
	arena.start_wave()
	for i in range(arena._wave_enemy_target):
		arena.on_enemy_died()
	var grenade_count: int = arena.pickups_spawned.count("grenade")
	assert_eq(grenade_count, MockArenaLevel.GRENADE_PICKUPS_PER_WAVE,
		"Every wave should spawn GRENADE_PICKUPS_PER_WAVE grenade pickups")
