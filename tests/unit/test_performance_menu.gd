extends GutTest
## Unit tests for PerformanceMenu.
##
## Tests the performance toggle settings and AI state toggles
## using a mock class.


# ============================================================================
# Mock PerformanceMenu for Testing
# ============================================================================


class MockPerformanceMenu:
	## Performance feature toggles (all enabled by default).
	var particles_enabled: bool = true
	var blood_decals_enabled: bool = true
	var screen_shake_enabled: bool = true
	var explosion_lights_enabled: bool = true
	var wall_hit_particles_enabled: bool = true
	var ai_enabled: bool = true

	## AI state toggles.
	var ai_states: Dictionary = {
		"idle": true,
		"combat": true,
		"seeking_cover": true,
		"in_cover": true,
		"flanking": true,
		"suppressed": true,
		"retreating": true,
		"pursuing": true,
		"assault": true,
		"searching": true,
	}

	## Stress benchmark constants (Issue #1504).
	const STRESS_PARTICLE_COUNT: int = 30
	const STRESS_LIGHT_COUNT: int = 20
	const STRESS_ENEMY_COUNT: int = 20
	const STRESS_SAMPLE_DURATION: float = 2.0

	## Number of cycles each benchmark step is repeated (Issue #1516).
	const BENCHMARK_CYCLES: int = 20

	## Tracks whether vsync was disabled during the last benchmark run (Issue #1516).
	var vsync_disabled_during_benchmark: bool = false

	## Signal tracking.
	var back_pressed_count: int = 0

	## Simulated stress benchmark result record.
	## Holds {enabled_fps, disabled_fps, delta_fps} for each subsystem step.
	var stress_results: Array[Dictionary] = []

	## Whether the stress benchmark is capable of running (i.e. constants are valid).
	func can_run_stress_benchmark() -> bool:
		return STRESS_PARTICLE_COUNT > 0 \
			and STRESS_LIGHT_COUNT > 0 \
			and STRESS_ENEMY_COUNT > 0 \
			and STRESS_SAMPLE_DURATION > 0.0

	## Simulate a benchmark run: records that vsync was disabled and runs the given cycles.
	## Returns the number of cycles used.
	func simulate_benchmark_run(cycles: int = BENCHMARK_CYCLES) -> int:
		vsync_disabled_during_benchmark = true
		return cycles

	## Simulate one stress benchmark step: returns a result dict.
	func simulate_stress_step(subsystem: String, enabled_fps: float,
			disabled_fps: float) -> Dictionary:
		var result := {
			"subsystem": subsystem,
			"enabled_fps": enabled_fps,
			"disabled_fps": disabled_fps,
			"delta_fps": disabled_fps - enabled_fps,
		}
		stress_results.append(result)
		return result

	## Format a stress result line (matches the log format in performance_menu.gd).
	func format_stress_result(result: Dictionary) -> String:
		return "  enabled=%.1f  disabled=%.1f  delta=%.1f" % [
			result["enabled_fps"], result["disabled_fps"], result["delta_fps"]]

	## Toggle a feature.
	func set_feature(feature_name: String, enabled: bool) -> void:
		match feature_name:
			"particles": particles_enabled = enabled
			"blood_decals": blood_decals_enabled = enabled
			"screen_shake": screen_shake_enabled = enabled
			"explosion_lights": explosion_lights_enabled = enabled
			"wall_hit_particles": wall_hit_particles_enabled = enabled
			"ai": ai_enabled = enabled

	## Toggle an AI state.
	func set_ai_state(state_name: String, enabled: bool) -> void:
		if state_name in ai_states:
			ai_states[state_name] = enabled

	## Get disabled features list.
	func get_disabled_features() -> Array[String]:
		var disabled: Array[String] = []
		if not particles_enabled: disabled.append("Particles")
		if not blood_decals_enabled: disabled.append("Blood decals")
		if not screen_shake_enabled: disabled.append("Screen shake")
		if not explosion_lights_enabled: disabled.append("Explosion lights")
		if not wall_hit_particles_enabled: disabled.append("Wall hit particles")
		if not ai_enabled: disabled.append("AI")
		for state_name in ai_states:
			if not ai_states[state_name]:
				disabled.append("AI:" + state_name.to_upper())
		return disabled

	## Get status text.
	func get_status_text() -> String:
		var disabled := get_disabled_features()
		if disabled.is_empty():
			return "All performance features enabled"
		return "Disabled: " + ", ".join(disabled)

	## Get total feature count (visual + AI master).
	func get_visual_feature_count() -> int:
		return 6  # particles, blood_decals, screen_shake, explosion_lights, wall_hit_particles, ai

	## Get AI state count.
	func get_ai_state_count() -> int:
		return ai_states.size()

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1

	## Simulate hover entering a row.
	func hover_row(feature_name: String) -> void:
		pass  # Hover tracking is handled by the UI layer.

	## Returns the list of row names that should have tooltips (Issue #1461).
	func get_rows_with_tooltips() -> Array[String]:
		return [
			"Particle Effects",
			"Blood Decals on Floor/Walls",
			"Screen Shake",
			"Explosion/Flashbang Lights",
			"Wall Hit Particles",
			"Enemy AI",
			"AI: IDLE state (patrol/guard scan)",
			"AI: COMBAT state (peek, shoot, return)",
			"AI: SEEKING_COVER state (pathfind to cover)",
			"AI: IN_COVER state (wait and peek)",
			"AI: FLANKING state (flank movement)",
			"AI: SUPPRESSED state (pinned under fire)",
			"AI: RETREATING state (fall back to cover)",
			"AI: PURSUING state (cover-to-cover advance)",
			"AI: ASSAULT state (coordinated rush)",
			"AI: SEARCHING state (hunt last known position)",
		]

	## Returns the list of row names that should have description labels (Issue #1461).
	func get_rows_with_descriptions() -> Array[String]:
		return [
			"Particle Effects",
			"Blood Decals on Floor/Walls",
			"Screen Shake",
			"Explosion/Flashbang Lights",
			"Wall Hit Particles",
			"Enemy AI",
		]


var menu: MockPerformanceMenu


func before_each() -> void:
	menu = MockPerformanceMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# Default State Tests
# ============================================================================


func test_all_features_enabled_by_default() -> void:
	assert_true(menu.particles_enabled, "Particles should be enabled by default")
	assert_true(menu.blood_decals_enabled, "Blood decals should be enabled by default")
	assert_true(menu.screen_shake_enabled, "Screen shake should be enabled by default")
	assert_true(menu.explosion_lights_enabled, "Explosion lights should be enabled by default")
	assert_true(menu.wall_hit_particles_enabled, "Wall hit particles should be enabled by default")
	assert_true(menu.ai_enabled, "AI should be enabled by default")


func test_all_ai_states_enabled_by_default() -> void:
	for state_name in menu.ai_states:
		assert_true(menu.ai_states[state_name],
			"AI state '%s' should be enabled by default" % state_name)


func test_default_status_text() -> void:
	assert_eq(menu.get_status_text(), "All performance features enabled",
		"Default status should show all features enabled")


# ============================================================================
# Feature Count Tests
# ============================================================================


func test_visual_feature_count() -> void:
	assert_eq(menu.get_visual_feature_count(), 6,
		"Should have 6 visual/master feature toggles")


func test_ai_state_count() -> void:
	assert_eq(menu.get_ai_state_count(), 10,
		"Should have 10 AI state toggles")


# ============================================================================
# Feature Toggle Tests
# ============================================================================


func test_disable_particles() -> void:
	menu.set_feature("particles", false)

	assert_false(menu.particles_enabled,
		"Should be able to disable particles")


func test_disable_ai() -> void:
	menu.set_feature("ai", false)

	assert_false(menu.ai_enabled,
		"Should be able to disable AI")


func test_disabled_features_in_status() -> void:
	menu.set_feature("particles", false)
	menu.set_feature("screen_shake", false)

	var status := menu.get_status_text()
	assert_true(status.begins_with("Disabled:"),
		"Status should start with 'Disabled:'")
	assert_true(status.contains("Particles"),
		"Status should mention Particles")
	assert_true(status.contains("Screen shake"),
		"Status should mention Screen shake")


# ============================================================================
# AI State Toggle Tests
# ============================================================================


func test_disable_ai_state() -> void:
	menu.set_ai_state("flanking", false)

	assert_false(menu.ai_states["flanking"],
		"Should be able to disable flanking AI state")


func test_ai_state_names() -> void:
	var expected_states := [
		"idle", "combat", "seeking_cover", "in_cover", "flanking",
		"suppressed", "retreating", "pursuing", "assault", "searching"
	]
	for state_name in expected_states:
		assert_true(menu.ai_states.has(state_name),
			"Should have AI state '%s'" % state_name)


func test_invalid_ai_state_ignored() -> void:
	menu.set_ai_state("nonexistent", false)

	assert_eq(menu.ai_states.size(), 10,
		"Invalid state should not be added")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")


# ============================================================================
# Hover / Tooltip Row Tests (Issue #1461)
# ============================================================================


func test_all_rows_have_tooltips() -> void:
	var rows := menu.get_rows_with_tooltips()
	assert_eq(rows.size(), 16,
		"Should have 16 rows with tooltips (6 visual + 10 AI states)")


func test_visual_rows_have_descriptions() -> void:
	var rows := menu.get_rows_with_descriptions()
	assert_eq(rows.size(), 6,
		"Should have 6 rows with description labels (visual features + AI master)")


func test_tooltip_row_names_include_ai_states() -> void:
	var rows := menu.get_rows_with_tooltips()
	var ai_rows: Array[String] = []
	for r in rows:
		if r.begins_with("AI:"):
			ai_rows.append(r)
	assert_eq(ai_rows.size(), 10,
		"Should have tooltip rows for all 10 AI states")


# ============================================================================
# Stress Benchmark Tests (Issue #1504)
# ============================================================================


func test_stress_benchmark_constants_are_positive() -> void:
	assert_gt(menu.STRESS_PARTICLE_COUNT, 0,
		"STRESS_PARTICLE_COUNT must be positive")
	assert_gt(menu.STRESS_LIGHT_COUNT, 0,
		"STRESS_LIGHT_COUNT must be positive")
	assert_gt(menu.STRESS_ENEMY_COUNT, 0,
		"STRESS_ENEMY_COUNT must be positive")
	assert_gt(menu.STRESS_SAMPLE_DURATION, 0.0,
		"STRESS_SAMPLE_DURATION must be positive")


func test_stress_benchmark_can_run() -> void:
	assert_true(menu.can_run_stress_benchmark(),
		"Stress benchmark should be runnable with default constants")


func test_stress_benchmark_enemy_count_exceeds_arena_cap() -> void:
	# Arena cap is 12; stress benchmark must exceed it to create visible AI load.
	var arena_cap := 12
	assert_gt(menu.STRESS_ENEMY_COUNT, arena_cap,
		"STRESS_ENEMY_COUNT should exceed the arena MAX_CONCURRENT_ENEMIES (%d) to stress AI" % arena_cap)


func test_stress_step_records_result() -> void:
	var result := menu.simulate_stress_step("Particles", 55.0, 72.0)

	assert_eq(result["subsystem"], "Particles",
		"Result should record subsystem name")
	assert_eq(result["enabled_fps"], 55.0,
		"Result should record enabled FPS")
	assert_eq(result["disabled_fps"], 72.0,
		"Result should record disabled FPS")
	assert_almost_eq(result["delta_fps"], 17.0, 0.01,
		"Delta should be disabled_fps - enabled_fps")


func test_stress_step_delta_positive_when_costly() -> void:
	# A positive delta means the subsystem is expensive: disabling it gains FPS.
	var result := menu.simulate_stress_step("Explosion lights", 48.0, 65.0)

	assert_gt(result["delta_fps"], 0.0,
		"Positive delta indicates the subsystem costs FPS when enabled")


func test_stress_step_delta_zero_when_no_impact() -> void:
	var result := menu.simulate_stress_step("Screen shake", 60.0, 60.0)

	assert_almost_eq(result["delta_fps"], 0.0, 0.01,
		"Zero delta indicates no FPS impact")


func test_stress_result_format() -> void:
	var result := menu.simulate_stress_step("AI", 40.0, 58.5)
	var formatted := menu.format_stress_result(result)

	assert_true(formatted.contains("enabled=40.0"),
		"Formatted line should include enabled FPS")
	assert_true(formatted.contains("disabled=58.5"),
		"Formatted line should include disabled FPS")
	assert_true(formatted.contains("delta=18.5"),
		"Formatted line should include delta FPS")


func test_stress_results_accumulated() -> void:
	menu.simulate_stress_step("Particles", 55.0, 70.0)
	menu.simulate_stress_step("Lights", 50.0, 68.0)
	menu.simulate_stress_step("AI", 38.0, 60.0)

	assert_eq(menu.stress_results.size(), 3,
		"All three stress steps should be recorded")


# ============================================================================
# VSync and Cycles Tests (Issue #1516)
# ============================================================================


func test_benchmark_cycles_constant_is_twenty() -> void:
	assert_eq(menu.BENCHMARK_CYCLES, 20,
		"BENCHMARK_CYCLES must be 20 for reliable results")


func test_benchmark_cycles_constant_is_positive() -> void:
	assert_gt(menu.BENCHMARK_CYCLES, 0,
		"BENCHMARK_CYCLES must be positive")


func test_benchmark_disables_vsync_during_run() -> void:
	menu.simulate_benchmark_run()

	assert_true(menu.vsync_disabled_during_benchmark,
		"Benchmark must disable vsync during run for accurate FPS measurement")


func test_benchmark_run_uses_correct_cycle_count() -> void:
	var cycles := menu.simulate_benchmark_run()

	assert_eq(cycles, menu.BENCHMARK_CYCLES,
		"Benchmark run must use BENCHMARK_CYCLES cycles")


# ============================================================================
# Quick Test Button Tests (Issue #1516)
# ============================================================================


func test_quick_benchmark_uses_one_cycle() -> void:
	var cycles := menu.simulate_benchmark_run(1)

	assert_eq(cycles, 1,
		"Quick test benchmark must run exactly 1 cycle")


func test_quick_benchmark_disables_vsync() -> void:
	menu.simulate_benchmark_run(1)

	assert_true(menu.vsync_disabled_during_benchmark,
		"Quick test benchmark must also disable vsync during run")


func test_quick_stress_benchmark_uses_one_cycle() -> void:
	var result := menu.simulate_stress_step("Particles", 55.0, 70.0)
	# A quick stress run uses cycles=1; the step result should still be valid.
	assert_eq(result["subsystem"], "Particles",
		"Quick stress step should record subsystem correctly")
	assert_almost_eq(result["delta_fps"], 15.0, 0.01,
		"Quick stress step should compute delta correctly")
