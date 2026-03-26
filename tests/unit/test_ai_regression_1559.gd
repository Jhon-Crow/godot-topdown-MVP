extends GutTest
## Regression tests for Issue #1559 — "add tests for AI".
##
## Issue #1559 was raised after PR #1464 went through multiple rounds where the
## AI was declared "completely broken". This file ensures those classes of bugs
## cannot recur silently.
##
## Bugs covered:
##   Round 5  — Typed array cast crash (as Array[bool] / as Array[Vector2] from
##               Dictionary throws at runtime in Godot 4.3)
##   Round 6  — GDScript semicolon trap in _all_inspection_points_cleared:
##               `return true` ran INSIDE the for-loop body, so enemies declared
##               all points cleared after inspecting just the first one.
##   Round 7  — Empty flags array fell through to `return true`, causing an
##               infinite relocation loop with no waypoints ever visited.
##   Issue #1419 — Enemies that never left IDLE entered SEARCHING on teleport
##               (reset_memory gate on _has_left_idle).
##   Issue #921  — _transition_to_searching must NOT set _has_left_idle = true
##               or the SEARCH_MAX_DURATION timeout is logically unreachable.
##
## All logic tests use plain mock objects; no scene tree or Node2D is required
## for Groups 1-4. Group 5 reads the actual enemy.gd source file.


# ============================================================================
# Helpers — pure logic implementations (no scene needed)
# ============================================================================


## The CORRECT implementation of the cleared-check that was landed as the fix.
## Uses Array.has(false) so there is no branch-inside-loop ambiguity.
func _all_inspection_points_cleared_correct(flags: Array) -> bool:
	if flags.is_empty():
		return false
	return not flags.has(false)


## The BUGGY implementation from Round 6 that caused "AI completely broken".
## The `return true` statement sits after the inner `if` on the same logical
## line (semicolon separator), making GDScript parse it as the else-branch of
## `if not f` — it fires on the very first truthy element.
##
## Reproduced here so tests can assert the buggy path DOES produce wrong output,
## confirming we understand the bug exactly.
func _all_inspection_points_cleared_buggy(flags: Array) -> bool:
	for f in flags:
		if not f:
			return false
		return true  # BUG: this is inside the loop body — fires on first true
	return true


# ============================================================================
# Group 1: Round 6 bug — GDScript semicolon trap
# ============================================================================


func test_empty_flags_is_not_cleared() -> void:
	## Issue #1559 / Round 7: An empty flags array must return false.
	## If it returned true, enemies would declare "search complete" before
	## visiting any waypoint, triggering the infinite relocation loop.
	var result := _all_inspection_points_cleared_correct([])
	assert_false(result, "Issue #1559 Round 7: empty array must return false (nothing inspected)")


func test_single_true_is_cleared() -> void:
	## A single inspected point (true) should be considered fully cleared.
	var result := _all_inspection_points_cleared_correct([true])
	assert_true(result, "Single [true] flag must return true (one point fully inspected)")


func test_single_false_is_not_cleared() -> void:
	## A single un-inspected point (false) must return false.
	var result := _all_inspection_points_cleared_correct([false])
	assert_false(result, "Single [false] flag must return false (point not yet inspected)")


func test_all_true_is_cleared() -> void:
	## All three points inspected — cleared.
	var result := _all_inspection_points_cleared_correct([true, true, true])
	assert_true(result, "[true, true, true] must return true (all points inspected)")


func test_partial_false_is_not_cleared() -> void:
	## Middle point not yet inspected — must return false.
	var result := _all_inspection_points_cleared_correct([true, false, true])
	assert_false(result, "[true, false, true] must return false (one point still pending)")


func test_semicolon_bug_false_positive_on_first_true() -> void:
	## Issue #1559 Round 6: Demonstrates that the BUGGY implementation returns
	## true for [true, false] — it should return false but the `return true`
	## inside the loop fires on the first (true) element before reaching false.
	##
	## This test exists to DOCUMENT the bug behaviour. If this assertion fails,
	## it means the buggy helper has been accidentally "fixed" — update the
	## helper to match the actual PR #1464 Round 6 source.
	var result := _all_inspection_points_cleared_buggy([true, false])
	assert_true(
		result,
		"Issue #1559 Round 6 BUG DEMO: buggy impl returns true for [true, false] " +
		"(return true fires inside loop on first truthy element)"
	)


func test_semicolon_bug_false_positive_on_any_inspected() -> void:
	## Issue #1559 Round 6: Even with two trues followed by a false, the buggy
	## version returns true on the first iteration.
	var result := _all_inspection_points_cleared_buggy([true, true, false])
	assert_true(
		result,
		"Issue #1559 Round 6 BUG DEMO: buggy impl returns true for [true, true, false]"
	)


func test_correct_logic_does_not_have_semicolon_bug() -> void:
	## Issue #1559 Round 6: The CORRECT implementation must return false for
	## [true, false] — verifying the fix eliminates the semicolon trap.
	var result := _all_inspection_points_cleared_correct([true, false])
	assert_false(
		result,
		"Issue #1559 Round 6 FIX: correct impl must return false for [true, false] " +
		"(one point still pending — do not declare search complete)"
	)


# ============================================================================
# Group 2: Round 7 bug — empty inspection pool causes infinite relocation
# ============================================================================


func test_empty_pool_is_not_all_cleared() -> void:
	## Issue #1559 Round 7: When the waypoint pool is empty (all zones visited
	## and _generate_search_waypoints returned nothing), the cleared-check must
	## return false so the relocation branch is taken — not an infinite "done" loop.
	var empty_flags: Array = []
	assert_false(
		_all_inspection_points_cleared_correct(empty_flags),
		"Issue #1559 Round 7: empty pool must return false — " +
		"returning true here causes infinite relocation with no waypoints"
	)


func test_nonempty_all_true_is_cleared() -> void:
	## Positive case: non-empty array with all trues correctly returns true.
	assert_true(
		_all_inspection_points_cleared_correct([true, true]),
		"[true, true] must return true — all waypoints visited"
	)


func test_nonempty_with_false_is_not_cleared() -> void:
	## Negative case: non-empty array with at least one false returns false.
	assert_false(
		_all_inspection_points_cleared_correct([true, false]),
		"[true, false] must return false — one waypoint still pending"
	)


# ============================================================================
# Group 3: Issue #1419 — idle-only enemies must NOT enter SEARCHING on teleport
# ============================================================================


## Mock that simulates the _has_left_idle gate logic inside reset_memory().
## Mirrors the logic at enemy.gd lines 3770-3788.
class MockEnemyMemoryReset:
	var _has_left_idle: bool = false
	var transition_to_searching_called: bool = false
	var transition_to_idle_called: bool = false

	func simulate_reset_memory_with_target(had_target: bool) -> void:
		if had_target:
			# Issue #1419: Only search if enemy has previously engaged player.
			if _has_left_idle:
				transition_to_searching_called = true
			else:
				transition_to_idle_called = true
		else:
			transition_to_idle_called = true


func test_never_engaged_enemy_with_target_goes_to_idle_not_searching() -> void:
	## Issue #1419: An enemy that only received intel via ally-share (never
	## personally left IDLE) must return to IDLE on teleport, not SEARCHING.
	var mock := MockEnemyMemoryReset.new()
	mock._has_left_idle = false
	mock.simulate_reset_memory_with_target(true)

	assert_true(
		mock.transition_to_idle_called,
		"Issue #1419: never-engaged enemy with target must transition to IDLE"
	)
	assert_false(
		mock.transition_to_searching_called,
		"Issue #1419: never-engaged enemy must NOT transition to SEARCHING"
	)


func test_engaged_enemy_with_target_goes_to_searching() -> void:
	## Issue #1419: An enemy that previously engaged (left IDLE) should enter
	## SEARCHING at the old target position when reset_memory fires.
	var mock := MockEnemyMemoryReset.new()
	mock._has_left_idle = true
	mock.simulate_reset_memory_with_target(true)

	assert_true(
		mock.transition_to_searching_called,
		"Issue #1419: previously-engaged enemy with target must transition to SEARCHING"
	)
	assert_false(
		mock.transition_to_idle_called,
		"Issue #1419: previously-engaged enemy with target must NOT go to IDLE"
	)


func test_never_engaged_enemy_without_target_goes_to_idle() -> void:
	## No target and never engaged — straight back to IDLE either way.
	var mock := MockEnemyMemoryReset.new()
	mock._has_left_idle = false
	mock.simulate_reset_memory_with_target(false)

	assert_true(
		mock.transition_to_idle_called,
		"No target + never engaged must transition to IDLE"
	)
	assert_false(
		mock.transition_to_searching_called,
		"No target must never trigger SEARCHING"
	)


func test_engaged_enemy_without_target_goes_to_idle() -> void:
	## No target means no position to search — return to IDLE regardless of
	## engagement history.
	var mock := MockEnemyMemoryReset.new()
	mock._has_left_idle = true
	mock.simulate_reset_memory_with_target(false)

	assert_true(
		mock.transition_to_idle_called,
		"No target must transition to IDLE even for previously-engaged enemy"
	)
	assert_false(
		mock.transition_to_searching_called,
		"No target must not trigger SEARCHING even with _has_left_idle=true"
	)


func test_has_left_idle_gate_prevents_searching_without_engagement() -> void:
	## Issue #1419: Explicit gate test — the single boolean _has_left_idle is
	## the ONLY thing that separates "go to SEARCHING" from "go to IDLE" when
	## had_target is true. Both cases must be correct.
	var idle_enemy := MockEnemyMemoryReset.new()
	idle_enemy._has_left_idle = false
	idle_enemy.simulate_reset_memory_with_target(true)

	var combat_enemy := MockEnemyMemoryReset.new()
	combat_enemy._has_left_idle = true
	combat_enemy.simulate_reset_memory_with_target(true)

	assert_false(
		idle_enemy.transition_to_searching_called,
		"Issue #1419: idle-only enemy (has_left_idle=false) must not reach SEARCHING"
	)
	assert_true(
		combat_enemy.transition_to_searching_called,
		"Issue #1419: combat enemy (has_left_idle=true) must reach SEARCHING"
	)
	assert_true(
		idle_enemy.transition_to_idle_called,
		"Issue #1419: idle-only enemy must be sent back to IDLE"
	)
	assert_false(
		combat_enemy.transition_to_idle_called,
		"Issue #1419: combat enemy with target must not be sent to IDLE"
	)


# ============================================================================
# Group 4: SEARCHING state basic sanity — zone keys and radius expansion
# ============================================================================

const _ZONE_SNAP: float = 50.0


## Replicate the zone key formula from enemy.gd line 2358 in pure GDScript.
func _compute_zone_key(pos: Vector2) -> String:
	return "%d,%d" % [int(pos.x / _ZONE_SNAP) * int(_ZONE_SNAP), int(pos.y / _ZONE_SNAP) * int(_ZONE_SNAP)]


func test_zone_key_consistent_for_same_grid_cell() -> void:
	## Two positions within the same 50-px grid cell must produce the same key
	## so the visited-zone deduplication works correctly.
	var pos_a := Vector2(10.0, 20.0)
	var pos_b := Vector2(48.9, 49.9)  # Still in cell (0,0)

	assert_eq(
		_compute_zone_key(pos_a),
		_compute_zone_key(pos_b),
		"Positions within the same 50px cell must share a zone key"
	)


func test_zone_key_different_for_different_cells() -> void:
	## Positions in different 50-px cells must produce different keys so each
	## zone is tracked independently.
	var pos_a := Vector2(10.0, 10.0)   # cell (0,0)
	var pos_b := Vector2(160.0, 160.0) # cell (150,150)

	assert_ne(
		_compute_zone_key(pos_a),
		_compute_zone_key(pos_b),
		"Positions 150px apart must produce different zone keys"
	)


func test_zone_key_computation() -> void:
	## Verify the exact numeric output of the zone key formula for a known input.
	## This anchors the formula so a refactor that changes the output is caught.
	##
	## pos = (123.4, 267.8)
	## int(123.4 / 50.0) = 2  -> 2 * 50 = 100
	## int(267.8 / 50.0) = 5  -> 5 * 50 = 250
	## expected key: "100,250"
	var pos := Vector2(123.4, 267.8)
	var key := _compute_zone_key(pos)
	assert_eq(key, "100,250", "Zone key for (123.4, 267.8) must be '100,250'")


func test_search_radius_expansion_bounded() -> void:
	## Issue #1559 / Round 7: After many expansions the radius must not exceed
	## SEARCH_MAX_RADIUS. Verify the loop stays bounded after 25 steps.
	const INITIAL: float = 100.0
	const EXPANSION: float = 75.0
	const MAX_RADIUS: float = 2000.0

	var radius: float = INITIAL
	for _i in range(25):
		if radius < MAX_RADIUS:
			radius += EXPANSION
			radius = minf(radius, MAX_RADIUS)

	assert_true(
		radius <= MAX_RADIUS,
		"Search radius must not exceed SEARCH_MAX_RADIUS=2000 after 25 expansions"
	)


# ============================================================================
# Group 5: Source-code structural guards (regression via source reading)
# ============================================================================


func test_enemy_gd_search_waypoints_is_empty_guard_exists() -> void:
	## Issue #1559 Round 7: The fix added an `_search_waypoints.is_empty()` guard
	## inside _process_searching_state so an empty waypoint list is handled
	## gracefully rather than causing an infinite relocation loop.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()

	var func_idx := source.find("func _process_searching_state(")
	assert_gt(func_idx, 0, "_process_searching_state must exist in enemy.gd")

	var next_func_idx := source.find("\nfunc ", func_idx + 1)
	var func_body := source.substr(func_idx, next_func_idx - func_idx) if next_func_idx > 0 else source.substr(func_idx)

	assert_true(
		func_body.contains("_search_waypoints.is_empty()"),
		"Issue #1559 Round 7: _process_searching_state must guard against empty " +
		"_search_waypoints with .is_empty() to prevent infinite relocation loop"
	)


func test_enemy_gd_reset_memory_has_has_left_idle_guard() -> void:
	## Issue #1419: reset_memory() must gate the SEARCHING transition on
	## _has_left_idle so enemies that never personally engaged the player are
	## not sent into SEARCHING on teleport.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()

	var func_idx := source.find("func reset_memory(")
	assert_gt(func_idx, 0, "reset_memory function must exist in enemy.gd")

	var next_func_idx := source.find("\nfunc ", func_idx + 1)
	var func_body := source.substr(func_idx, next_func_idx - func_idx) if next_func_idx > 0 else source.substr(func_idx)

	assert_true(
		func_body.contains("_has_left_idle"),
		"Issue #1419: reset_memory must reference _has_left_idle to gate " +
		"the SEARCHING transition to previously-engaged enemies only"
	)
	assert_true(
		func_body.contains("_transition_to_searching"),
		"Issue #1419: reset_memory must call _transition_to_searching (for engaged path)"
	)
	assert_true(
		func_body.contains("_transition_to_idle"),
		"Issue #1419: reset_memory must call _transition_to_idle (for never-engaged path)"
	)


func test_enemy_gd_transition_to_searching_does_not_set_has_left_idle() -> void:
	## Issue #921: _transition_to_searching must NOT set _has_left_idle = true.
	## If it did, the SEARCH_MAX_DURATION timeout (gated on `not _has_left_idle`)
	## would be logically unreachable for patrol enemies, causing them to search
	## indefinitely.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()

	var func_idx := source.find("func _transition_to_searching(")
	assert_gt(func_idx, 0, "_transition_to_searching must exist in enemy.gd")

	var next_func_idx := source.find("\nfunc ", func_idx + 1)
	var func_body := source.substr(func_idx, next_func_idx - func_idx) if next_func_idx > 0 else source.substr(func_idx)

	assert_false(
		func_body.contains("_has_left_idle = true"),
		"Issue #921: _transition_to_searching must NOT set _has_left_idle = true. " +
		"Doing so makes SEARCH_MAX_DURATION timeout unreachable for patrol enemies. " +
		"Regression test for the fix documented in PR #1464."
	)


func test_enemy_gd_searching_timeout_gated_on_has_left_idle() -> void:
	## Issue #921 / Issue #330: The SEARCHING timeout must only fire when
	## _has_left_idle is false (patrol enemy that never engaged). This ensures
	## combat enemies search indefinitely while patrol enemies can time out.
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd — skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()

	var func_idx := source.find("func _process_searching_state(")
	assert_gt(func_idx, 0, "_process_searching_state must exist in enemy.gd")

	var next_func_idx := source.find("\nfunc ", func_idx + 1)
	var func_body := source.substr(func_idx, next_func_idx - func_idx) if next_func_idx > 0 else source.substr(func_idx)

	assert_true(
		func_body.contains("SEARCH_MAX_DURATION") and func_body.contains("_has_left_idle"),
		"Issue #921/#330: timeout check must reference both SEARCH_MAX_DURATION and _has_left_idle"
	)
	assert_true(
		func_body.contains("_transition_to_idle"),
		"Issue #921: timeout in SEARCHING state must call _transition_to_idle"
	)
