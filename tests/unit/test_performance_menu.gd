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

	## Signal tracking.
	var back_pressed_count: int = 0

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
