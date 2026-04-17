extends GutTest
## Unit tests for Issue #1526 performance optimizations.
##
## Tests the distraction-attack log rate-limiting, navmesh path stagger logic,
## particle warm-up delay constant, and SceneLoader cache-first behavior.


# ============================================================================
# Mock Enemy for distraction log rate-limiting (Fix 1)
# ============================================================================


class MockEnemyDistraction:
	## Mirrors the distraction-attack log rate-limiting from enemy.gd (Issue #1526).
	var _distraction_attack_logged: bool = false
	var _goap_world_state: Dictionary = {"player_distracted": false}
	var log_calls: Array[String] = []

	func _log_to_file(msg: String) -> void:
		log_calls.append(msg)

	## Simulates the distraction-attack code path (enemy.gd ~line 1312).
	func simulate_distraction_shot() -> void:
		if not _distraction_attack_logged:
			_log_to_file("Player distracted - priority attack triggered")
			_distraction_attack_logged = true

	## Simulates the world-state update that resets the log flag (enemy.gd ~line 963).
	func update_player_distracted(is_distracted: bool) -> void:
		_goap_world_state["player_distracted"] = is_distracted
		if not is_distracted:
			_distraction_attack_logged = false


# ============================================================================
# Mock Enemy for navmesh path stagger (Fix 2)
# ============================================================================


class MockEnemyNavStagger:
	## Mirrors the navmesh path stagger logic from enemy.gd (Issue #1526).
	enum AIState { IDLE, COMBAT, PURSUING, SEARCHING }

	var _current_state: AIState = AIState.SEARCHING
	var _nav_path_update_frame: int = 0
	const NAV_PATH_UPDATE_INTERVAL: int = 10
	var target_position_updates: int = 0
	var _nav_target_position: Vector2 = Vector2.ZERO

	## Simulates _get_nav_direction_to() stagger logic.
	func update_nav_target(target_pos: Vector2, current_frame: int) -> void:
		if _current_state in [AIState.SEARCHING, AIState.PURSUING]:
			if current_frame - _nav_path_update_frame >= NAV_PATH_UPDATE_INTERVAL:
				_nav_target_position = target_pos
				_nav_path_update_frame = current_frame
				target_position_updates += 1
		else:
			_nav_target_position = target_pos
			target_position_updates += 1


# ============================================================================
# Mock SceneLoader for cache-first behavior (Fix 4)
# ============================================================================


class MockSceneLoaderWithCache:
	## Mirrors the cache-first logic from scene_loader.gd (Issue #1526).
	var _is_loading: bool = false
	var _current_load_path: String = ""
	var _cached_resources: Dictionary = {}
	var used_cache: bool = false
	var started_threaded_load: bool = false
	var load_attempts: Array[String] = []
	var _valid_paths: Dictionary = {}

	func register_valid_path(path: String) -> void:
		_valid_paths[path] = true

	func register_cached_resource(path: String) -> void:
		_cached_resources[path] = true

	func has_cached(path: String) -> bool:
		return _cached_resources.has(path)

	## Simulates _start_background_load() with cache-first logic.
	func start_background_load(path: String) -> void:
		_current_load_path = path
		_is_loading = true
		load_attempts.append(path)

		if has_cached(path):
			used_cache = true
			_is_loading = false
			_current_load_path = ""
			return

		started_threaded_load = true

	func is_loading() -> bool:
		return _is_loading


# ============================================================================
# Distraction Log Rate-Limiting Tests (Fix 1)
# ============================================================================


var distraction_enemy: MockEnemyDistraction


func before_each() -> void:
	distraction_enemy = MockEnemyDistraction.new()


func after_each() -> void:
	distraction_enemy = null


func test_distraction_log_fires_once_on_first_shot() -> void:
	distraction_enemy.update_player_distracted(true)
	distraction_enemy.simulate_distraction_shot()

	assert_eq(distraction_enemy.log_calls.size(), 1,
		"Should log once on first distraction shot")


func test_distraction_log_does_not_repeat_on_subsequent_shots() -> void:
	distraction_enemy.update_player_distracted(true)

	# Simulate 10 shots (at 10 shots/sec for 1 second)
	for i in range(10):
		distraction_enemy.simulate_distraction_shot()

	assert_eq(distraction_enemy.log_calls.size(), 1,
		"Should log only once despite 10 shots in same distraction episode")


func test_distraction_log_resets_when_player_aims_back() -> void:
	distraction_enemy.update_player_distracted(true)
	distraction_enemy.simulate_distraction_shot()
	assert_eq(distraction_enemy.log_calls.size(), 1, "First episode: 1 log")

	# Player aims back at enemy
	distraction_enemy.update_player_distracted(false)

	# Player looks away again — new episode
	distraction_enemy.update_player_distracted(true)
	distraction_enemy.simulate_distraction_shot()
	assert_eq(distraction_enemy.log_calls.size(), 2,
		"Should log again for new distraction episode after reset")


func test_distraction_flag_initial_state() -> void:
	assert_false(distraction_enemy._distraction_attack_logged,
		"Distraction logged flag should be false initially")


# ============================================================================
# Navmesh Path Stagger Tests (Fix 2)
# ============================================================================


func test_nav_stagger_updates_on_first_frame() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.SEARCHING

	enemy.update_nav_target(Vector2(100, 200), 0)
	assert_eq(enemy.target_position_updates, 1,
		"Should update target on first frame (frame 0)")


func test_nav_stagger_skips_intermediate_frames() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.SEARCHING

	enemy.update_nav_target(Vector2(100, 200), 0)
	# Simulate frames 1–9 (should all be skipped)
	for frame in range(1, 10):
		enemy.update_nav_target(Vector2(100, 200), frame)

	assert_eq(enemy.target_position_updates, 1,
		"Should skip path updates on frames 1–9")


func test_nav_stagger_updates_after_interval() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.SEARCHING

	enemy.update_nav_target(Vector2(100, 200), 0)
	enemy.update_nav_target(Vector2(100, 200), 10)

	assert_eq(enemy.target_position_updates, 2,
		"Should update at frame 0 and frame 10 (interval=10)")


func test_nav_stagger_pursuing_state_also_staggered() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.PURSUING

	# 60 frames (1 second at 60 Hz)
	for frame in range(60):
		enemy.update_nav_target(Vector2(100, 200), frame)

	assert_eq(enemy.target_position_updates, 6,
		"PURSUING should update ~6 times per second (60 frames / 10 interval)")


func test_nav_stagger_combat_state_not_staggered() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.COMBAT

	# 60 frames — COMBAT should update every frame
	for frame in range(60):
		enemy.update_nav_target(Vector2(100, 200), frame)

	assert_eq(enemy.target_position_updates, 60,
		"COMBAT state should update every frame (no stagger)")


func test_nav_stagger_idle_state_not_staggered() -> void:
	var enemy := MockEnemyNavStagger.new()
	enemy._current_state = MockEnemyNavStagger.AIState.IDLE

	for frame in range(60):
		enemy.update_nav_target(Vector2(100, 200), frame)

	assert_eq(enemy.target_position_updates, 60,
		"IDLE state should update every frame (no stagger)")


# ============================================================================
# SceneLoader Cache-First Tests (Fix 4)
# ============================================================================


func test_cached_resource_skips_threaded_load() -> void:
	var loader := MockSceneLoaderWithCache.new()
	loader.register_valid_path("res://scenes/levels/SewerLevel.tscn")
	loader.register_cached_resource("res://scenes/levels/SewerLevel.tscn")

	loader.start_background_load("res://scenes/levels/SewerLevel.tscn")

	assert_true(loader.used_cache,
		"Should use cached resource when available")
	assert_false(loader.started_threaded_load,
		"Should NOT start threaded load for cached resource")
	assert_false(loader.is_loading(),
		"Should not be in loading state after using cache")


func test_uncached_resource_starts_threaded_load() -> void:
	var loader := MockSceneLoaderWithCache.new()
	loader.register_valid_path("res://scenes/levels/DocksLevel.tscn")

	loader.start_background_load("res://scenes/levels/DocksLevel.tscn")

	assert_false(loader.used_cache,
		"Should NOT use cache for uncached resource")
	assert_true(loader.started_threaded_load,
		"Should start threaded load for uncached resource")
	assert_true(loader.is_loading(),
		"Should be in loading state during threaded load")


func test_first_load_threaded_second_load_cached() -> void:
	var loader := MockSceneLoaderWithCache.new()
	var path := "res://scenes/levels/SewerLevel.tscn"
	loader.register_valid_path(path)

	# First load: not cached → threaded
	loader.start_background_load(path)
	assert_true(loader.started_threaded_load, "First load should be threaded")

	# Simulate load completion + caching
	loader._is_loading = false
	loader.started_threaded_load = false
	loader.register_cached_resource(path)

	# Second load: cached → instant
	loader.start_background_load(path)
	assert_true(loader.used_cache, "Second load should use cache")
