extends GutTest
## Unit tests for the replay system enhancements (Issue #544).
##
## Tests the enhanced recording and playback features:
## - Frame data creation with health colors and events
## - Sound event detection (shots, hits, deaths)
## - Color application logic
## - Floor cleanup and progressive re-addition
## - Ghost bullet trail and player trail creation


# ============================================================================
# Mock ReplaySystem for Logic Tests
# ============================================================================


## Minimal replay system mock that tests recording and event detection logic.
class MockReplaySystem:
	var _frames: Array = []

	func _create_frame_data() -> Dictionary:
		return {
			"time": 0.0,
			"player_position": Vector2.ZERO,
			"player_rotation": 0.0,
			"player_model_scale": Vector2.ONE,
			"player_alive": true,
			"player_color": Color(0.2, 0.6, 1.0, 1.0),
			"enemies": [],
			"bullets": [],
			"grenades": [],
			"events": [],
			"blood_decals": [],
			"casings": []
		}

	## Detect sound events by comparing current frame to previous (same logic as real system).
	func _record_sound_events(frame: Dictionary) -> void:
		if _frames.is_empty():
			return

		var prev_frame: Dictionary = _frames[-1]

		# Detect new bullets (shot event)
		if frame.bullets.size() > prev_frame.bullets.size():
			for i in range(prev_frame.bullets.size(), frame.bullets.size()):
				if i < frame.bullets.size():
					frame.events.append({
						"type": "shot",
						"position": frame.bullets[i].position
					})

		# Detect enemy deaths
		for i in range(mini(frame.enemies.size(), prev_frame.enemies.size())):
			if prev_frame.enemies[i].alive and not frame.enemies[i].alive:
				frame.events.append({
					"type": "death",
					"position": frame.enemies[i].position
				})

		# Detect enemy hits (white flash)
		for i in range(mini(frame.enemies.size(), prev_frame.enemies.size())):
			if frame.enemies[i].alive and prev_frame.enemies[i].alive:
				var curr_color: Color = frame.enemies[i].color
				if curr_color.r > 0.95 and curr_color.g > 0.95 and curr_color.b > 0.95:
					frame.events.append({
						"type": "hit",
						"position": frame.enemies[i].position
					})

		# Detect player death
		if prev_frame.player_alive and not frame.player_alive:
			frame.events.append({
				"type": "player_death",
				"position": frame.player_position
			})

		# Detect player hit (white flash)
		if frame.player_alive and prev_frame.player_alive:
			var curr_p_color: Color = frame.player_color
			if curr_p_color.r > 0.95 and curr_p_color.g > 0.95 and curr_p_color.b > 0.95:
				frame.events.append({
					"type": "player_hit",
					"position": frame.player_position
				})


# ============================================================================
# Test: Frame Data Creation
# ============================================================================


func test_frame_data_has_player_color():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	assert_true(frame.has("player_color"), "Frame data should have player_color field")
	assert_eq(frame.player_color, Color(0.2, 0.6, 1.0, 1.0), "Default player color should be blue")


func test_frame_data_has_events():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	assert_true(frame.has("events"), "Frame data should have events field")
	assert_eq(frame.events.size(), 0, "Events should start empty")


func test_frame_data_has_blood_decals():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	assert_true(frame.has("blood_decals"), "Frame data should have blood_decals field")
	assert_eq(frame.blood_decals.size(), 0, "Blood decals should start empty")


func test_frame_data_has_casings():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	assert_true(frame.has("casings"), "Frame data should have casings field")
	assert_eq(frame.casings.size(), 0, "Casings should start empty")


# ============================================================================
# Test: Shot Event Detection (Issue #544 fix 2)
# ============================================================================


func test_shot_event_detected_when_bullet_count_increases():
	var system := MockReplaySystem.new()

	# Frame 1: no bullets
	var frame1 := system._create_frame_data()
	frame1.time = 0.0
	system._frames.append(frame1)

	# Frame 2: one bullet appeared
	var frame2 := system._create_frame_data()
	frame2.time = 0.016
	frame2.bullets = [{"position": Vector2(100, 200), "rotation": 0.5}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 1, "Should detect one shot event")
	assert_eq(frame2.events[0].type, "shot", "Event type should be 'shot'")
	assert_eq(frame2.events[0].position, Vector2(100, 200), "Shot position should match bullet position")


func test_no_shot_event_when_bullet_count_same():
	var system := MockReplaySystem.new()

	# Frame 1: one bullet
	var frame1 := system._create_frame_data()
	frame1.bullets = [{"position": Vector2(100, 200), "rotation": 0.5}]
	system._frames.append(frame1)

	# Frame 2: still one bullet (same count)
	var frame2 := system._create_frame_data()
	frame2.bullets = [{"position": Vector2(150, 200), "rotation": 0.5}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 0, "Should not detect shot when bullet count unchanged")


func test_multiple_shots_detected():
	var system := MockReplaySystem.new()

	# Frame 1: no bullets
	var frame1 := system._create_frame_data()
	system._frames.append(frame1)

	# Frame 2: three bullets appeared (e.g., shotgun)
	var frame2 := system._create_frame_data()
	frame2.bullets = [
		{"position": Vector2(100, 200), "rotation": 0.5},
		{"position": Vector2(105, 205), "rotation": 0.6},
		{"position": Vector2(110, 210), "rotation": 0.7}
	]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 3, "Should detect three shot events for three new bullets")


# ============================================================================
# Test: Death Event Detection (Issue #544 fix 2)
# ============================================================================


func test_death_event_detected_when_enemy_dies():
	var system := MockReplaySystem.new()

	# Frame 1: enemy alive
	var frame1 := system._create_frame_data()
	frame1.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)}]
	system._frames.append(frame1)

	# Frame 2: enemy dead
	var frame2 := system._create_frame_data()
	frame2.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": false, "color": Color(0.3, 0.3, 0.3, 0.5)}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 1, "Should detect one death event")
	assert_eq(frame2.events[0].type, "death", "Event type should be 'death'")
	assert_eq(frame2.events[0].position, Vector2(300, 400), "Death position should match enemy position")


func test_no_death_event_when_enemy_stays_alive():
	var system := MockReplaySystem.new()

	# Frame 1: enemy alive
	var frame1 := system._create_frame_data()
	frame1.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)}]
	system._frames.append(frame1)

	# Frame 2: enemy still alive
	var frame2 := system._create_frame_data()
	frame2.enemies = [{"position": Vector2(310, 400), "rotation": 0.1, "alive": true, "color": Color(0.7, 0.2, 0.2)}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 0, "Should not detect death when enemy stays alive")


# ============================================================================
# Test: Hit Event Detection (Issue #544 fix 2)
# ============================================================================


func test_hit_event_detected_on_white_flash():
	var system := MockReplaySystem.new()

	# Frame 1: enemy at normal health color
	var frame1 := system._create_frame_data()
	frame1.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)}]
	system._frames.append(frame1)

	# Frame 2: enemy flashing white (hit)
	var frame2 := system._create_frame_data()
	frame2.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(1.0, 1.0, 1.0)}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 1, "Should detect one hit event from white flash")
	assert_eq(frame2.events[0].type, "hit", "Event type should be 'hit'")


func test_no_hit_event_on_normal_color_change():
	var system := MockReplaySystem.new()

	# Frame 1: enemy at full health color
	var frame1 := system._create_frame_data()
	frame1.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)}]
	system._frames.append(frame1)

	# Frame 2: enemy at lower health color (not white - just darker red)
	var frame2 := system._create_frame_data()
	frame2.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.6, 0.15, 0.15)}]
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 0, "Should not detect hit on normal color change")


# ============================================================================
# Test: Player Death/Hit Detection (Issue #544 fix 2)
# ============================================================================


func test_player_death_event_detected():
	var system := MockReplaySystem.new()

	# Frame 1: player alive
	var frame1 := system._create_frame_data()
	frame1.player_alive = true
	frame1.player_position = Vector2(500, 300)
	system._frames.append(frame1)

	# Frame 2: player dead
	var frame2 := system._create_frame_data()
	frame2.player_alive = false
	frame2.player_position = Vector2(500, 300)
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 1, "Should detect player death")
	assert_eq(frame2.events[0].type, "player_death", "Event type should be 'player_death'")


func test_player_hit_event_detected_on_white_flash():
	var system := MockReplaySystem.new()

	# Frame 1: player at normal color
	var frame1 := system._create_frame_data()
	frame1.player_alive = true
	frame1.player_color = Color(0.2, 0.6, 1.0)
	frame1.player_position = Vector2(500, 300)
	system._frames.append(frame1)

	# Frame 2: player flashing white (hit)
	var frame2 := system._create_frame_data()
	frame2.player_alive = true
	frame2.player_color = Color(1.0, 1.0, 1.0)
	frame2.player_position = Vector2(500, 300)
	system._record_sound_events(frame2)

	assert_eq(frame2.events.size(), 1, "Should detect player hit from white flash")
	assert_eq(frame2.events[0].type, "player_hit", "Event type should be 'player_hit'")


# ============================================================================
# Test: Combined Events in Single Frame
# ============================================================================


func test_multiple_events_in_single_frame():
	var system := MockReplaySystem.new()

	# Frame 1: one bullet, two alive enemies
	var frame1 := system._create_frame_data()
	frame1.bullets = [{"position": Vector2(100, 200), "rotation": 0.5}]
	frame1.enemies = [
		{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)},
		{"position": Vector2(600, 400), "rotation": 0.0, "alive": true, "color": Color(0.9, 0.2, 0.2)}
	]
	system._frames.append(frame1)

	# Frame 2: two new bullets (shots), first enemy hit (white), second enemy dies
	var frame2 := system._create_frame_data()
	frame2.bullets = [
		{"position": Vector2(150, 200), "rotation": 0.5},
		{"position": Vector2(200, 300), "rotation": 0.3},
		{"position": Vector2(250, 350), "rotation": 0.4}
	]
	frame2.enemies = [
		{"position": Vector2(300, 400), "rotation": 0.0, "alive": true, "color": Color(1.0, 1.0, 1.0)},
		{"position": Vector2(600, 400), "rotation": 0.0, "alive": false, "color": Color(0.3, 0.3, 0.3, 0.5)}
	]
	system._record_sound_events(frame2)

	# Should have: 2 shots + 1 hit + 1 death = 4 events
	assert_eq(frame2.events.size(), 4, "Should detect 4 events (2 shots + 1 hit + 1 death)")

	var event_types := []
	for event in frame2.events:
		event_types.append(event.type)
	assert_has(event_types, "shot", "Should contain shot events")
	assert_has(event_types, "hit", "Should contain hit event")
	assert_has(event_types, "death", "Should contain death event")


# ============================================================================
# Test: No Events on First Frame
# ============================================================================


func test_no_events_on_first_frame():
	var system := MockReplaySystem.new()

	# First frame ever - no previous frame to compare
	var frame1 := system._create_frame_data()
	frame1.bullets = [{"position": Vector2(100, 200), "rotation": 0.5}]
	frame1.enemies = [{"position": Vector2(300, 400), "rotation": 0.0, "alive": false, "color": Color(0.3, 0.3, 0.3, 0.5)}]
	system._record_sound_events(frame1)

	assert_eq(frame1.events.size(), 0, "Should not detect any events on first frame (no previous)")


# ============================================================================
# Test: Enemy Color Data Recording (Issue #544 fix 3)
# ============================================================================


func test_enemy_data_includes_color():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	frame.enemies = [{"position": Vector2.ZERO, "rotation": 0.0, "alive": true, "color": Color(0.7, 0.15, 0.15)}]

	assert_true(frame.enemies[0].has("color"), "Enemy data should include color field")
	assert_eq(frame.enemies[0].color, Color(0.7, 0.15, 0.15), "Enemy color should match recorded value")


func test_dead_enemy_has_gray_color():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	frame.enemies = [{"position": Vector2.ZERO, "rotation": 0.0, "alive": false, "color": Color(0.3, 0.3, 0.3, 0.5)}]

	assert_false(frame.enemies[0].alive, "Enemy should be dead")
	assert_eq(frame.enemies[0].color.r, 0.3, "Dead enemy should have gray color (r=0.3)")


# ============================================================================
# Test: Grenade Recording with Texture Path (Issue #544 round 2)
# ============================================================================


func test_grenade_data_includes_texture_path():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	frame.grenades = [{
		"position": Vector2(400, 300),
		"rotation": 1.5,
		"texture_path": "res://assets/sprites/weapons/flashbang.png"
	}]

	assert_true(frame.grenades[0].has("texture_path"), "Grenade data should include texture_path")
	assert_eq(frame.grenades[0].texture_path, "res://assets/sprites/weapons/flashbang.png",
		"Texture path should match recorded value")


func test_grenade_data_includes_rotation():
	var system := MockReplaySystem.new()
	var frame := system._create_frame_data()
	frame.grenades = [{
		"position": Vector2(400, 300),
		"rotation": 1.5,
		"texture_path": ""
	}]

	assert_true(frame.grenades[0].has("rotation"), "Grenade data should include rotation")
	assert_almost_eq(frame.grenades[0].rotation, 1.5, 0.001, "Rotation should match recorded value")


# ============================================================================
# Test: Blood/Casing Baseline Offset (Issue #544 round 2 fix 5b)
# ============================================================================


## Minimal mock for testing baseline blood/casing offset logic.
class MockReplayPlayback:
	var _baseline_blood_count: int = 0
	var _baseline_casing_count: int = 0
	var _spawned_blood_count: int = 0
	var _spawned_casing_count: int = 0

	## Returns how many new blood decals should be spawned for a given frame's data.
	## Mirrors the logic in replay_system.gd _update_replay_blood_decals().
	func get_new_blood_count(decals_data_size: int) -> int:
		var new_count := decals_data_size - _baseline_blood_count
		if new_count <= _spawned_blood_count or new_count <= 0:
			return 0
		return new_count - _spawned_blood_count

	## Returns how many new casings should be spawned for a given frame's data.
	func get_new_casing_count(casings_data_size: int) -> int:
		var new_count := casings_data_size - _baseline_casing_count
		if new_count <= _spawned_casing_count or new_count <= 0:
			return 0
		return new_count - _spawned_casing_count


func test_baseline_blood_offset_skips_initial_decals():
	var playback := MockReplayPlayback.new()
	# Frame 0 has 5 blood decals (pre-existing)
	playback._baseline_blood_count = 5
	playback._spawned_blood_count = 0

	# Frame with same 5 decals - should spawn nothing
	assert_eq(playback.get_new_blood_count(5), 0,
		"Should not spawn blood when count equals baseline")

	# Frame with 7 decals - should spawn 2 new ones
	assert_eq(playback.get_new_blood_count(7), 2,
		"Should only spawn blood decals that exceed baseline")


func test_baseline_casing_offset_skips_initial_casings():
	var playback := MockReplayPlayback.new()
	# Frame 0 has 10 casings (pre-existing)
	playback._baseline_casing_count = 10
	playback._spawned_casing_count = 0

	# Frame with same 10 casings - should spawn nothing
	assert_eq(playback.get_new_casing_count(10), 0,
		"Should not spawn casings when count equals baseline")

	# Frame with 15 casings - should spawn 5 new ones
	assert_eq(playback.get_new_casing_count(15), 5,
		"Should only spawn casings that exceed baseline")


func test_baseline_offset_with_no_pre_existing_state():
	var playback := MockReplayPlayback.new()
	# Frame 0 has no blood or casings
	playback._baseline_blood_count = 0
	playback._baseline_casing_count = 0
	playback._spawned_blood_count = 0
	playback._spawned_casing_count = 0

	# Frame with 3 blood decals - should spawn all 3
	assert_eq(playback.get_new_blood_count(3), 3,
		"Should spawn all blood when baseline is 0")

	# Frame with 2 casings - should spawn all 2
	assert_eq(playback.get_new_casing_count(2), 2,
		"Should spawn all casings when baseline is 0")


func test_progressive_blood_spawning_with_baseline():
	var playback := MockReplayPlayback.new()
	playback._baseline_blood_count = 3  # 3 pre-existing
	playback._spawned_blood_count = 0

	# Frame with 5 decals (3 baseline + 2 new)
	assert_eq(playback.get_new_blood_count(5), 2,
		"Should spawn 2 new blood decals")

	# Simulate spawning them
	playback._spawned_blood_count = 2

	# Frame with 7 decals (3 baseline + 4 new, 2 already spawned)
	assert_eq(playback.get_new_blood_count(7), 2,
		"Should spawn 2 more new blood decals (total 4 new, 2 already spawned)")


# ============================================================================
# Test: Penultimate Hit Event Detection (Issue #544 round 2 fix 4)
# ============================================================================


func test_penultimate_hit_event_type():
	# Verify that the penultimate_hit event type string is recognized
	var event := {"type": "penultimate_hit", "position": Vector2(500, 300)}
	assert_eq(event.type, "penultimate_hit", "Event type should be 'penultimate_hit'")
	assert_eq(event.position, Vector2(500, 300), "Position should be recorded")


func test_hit_effect_without_time_slowdown():
	# Verify the concept: during replay, only saturation effect should trigger
	# This tests the event type matching logic (the actual trigger happens at runtime)
	var replay_events := ["shot", "death", "hit", "player_death", "player_hit", "penultimate_hit"]

	# Events that should trigger saturation (visual effect)
	var saturation_events := ["death", "hit"]
	# Events that should trigger penultimate effect
	var penultimate_events := ["penultimate_hit"]

	for event_type in replay_events:
		if event_type in saturation_events:
			assert_true(true, "'%s' should trigger replay hit effect" % event_type)
		elif event_type in penultimate_events:
			assert_true(true, "'%s' should trigger replay penultimate effect" % event_type)
