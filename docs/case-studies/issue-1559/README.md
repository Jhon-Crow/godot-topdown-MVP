# Case Study: Issue #1559 — AI Regression Tests

## Summary

Issue #1559 ("добавь тесты на ии" / "add tests for AI") was raised after PR #1464 went
through multiple rounds of fixing where the AI was declared "completely broken" in rounds 5,
6, and 7. The issue asked for regression tests so these classes of bugs could never silently
recur without being caught by the test suite.

This case study documents the root causes, the timeline, and how the tests in
`tests/unit/test_ai_regression_1559.gd` prevent each class of bug from recurring.

---

## Timeline of Events

### PR #1464 — Multi-round AI fix

PR #1464 attempted to improve the SEARCHING state AI behavior. It went through at least 7
rounds of fixes before stabilizing. Three of those rounds reached the "AI completely broken"
state:

| Round | Bug | Symptom |
|-------|-----|---------|
| Round 5 | Typed array cast crash | `as Array[bool]` / `as Array[Vector2]` typed cast from `Dictionary` throws runtime error in Godot 4.3 — entire AI state machine crashes |
| Round 6 | GDScript semicolon trap in `_all_inspection_points_cleared` | `return true` ran INSIDE the `for` loop body (one-liner with semicolons) — enemies declared "all cleared" after just one inspected point and abandoned search immediately |
| Round 7 | `_all_inspection_points_cleared` called on empty flags array | Empty array iterates 0 times, falls through to `return true` — infinite relocation loop with no waypoints ever visited |

### Issue #1419 — Idle enemies entering SEARCHING on teleport

Enemies that had never personally engaged the player (never left IDLE state) were entering
SEARCHING when `reset_memory()` was called on teleport. These enemies had only received
intel via ally-sharing — they had no personal reason to search. The fix added a gate on the
`_has_left_idle` flag inside `reset_memory()`.

### Issue #921 — `_transition_to_searching` must NOT set `_has_left_idle`

If `_transition_to_searching` set `_has_left_idle = true`, the `SEARCH_MAX_DURATION` timeout
became impossible to trigger for patrol enemies (the timeout is gated on `not _has_left_idle`).
The fix added a comment and removed the assignment, preserving whatever value the caller had.

---

## Root Causes in Detail

### 1. Typed Array Cast Crash (Round 5)

In Godot 4.3, casting a plain `Dictionary` value with `as Array[bool]` or `as Array[Vector2]`
throws a runtime error even when the underlying data is valid. The fix was to use untyped
`Array` for flag and waypoint containers, and cast individual elements only as needed.

**Why it broke AI completely:** The crash happened inside `_process_searching_state`, which
is called every physics tick while in SEARCHING state. Any unhandled error in a physics
callback stops the entire script, leaving the enemy frozen.

### 2. GDScript Semicolon Trap (Round 6)

The original one-liner implementation:

```gdscript
for f in flags: if not f: return false; return true
```

GDScript's semicolon-as-statement-separator means `return true` is parsed as the `else`
branch of the `if not f` statement — it runs on the FIRST iteration where `f` is truthy.
So the function returned `true` (all cleared) after visiting just one point, even if
subsequent points were still `false`.

The correct implementation:

```gdscript
func _all_inspection_points_cleared(flags: Array) -> bool:
    if flags.is_empty(): return false
    return not flags.has(false)
```

**Why it broke AI completely:** Enemies entered SEARCHING, immediately believed all points
were cleared, teleported to a new location, and looped — never actually searching anything.

### 3. Empty Array Falls Through to `return true` (Round 7)

When all zones were visited and `_generate_search_waypoints()` returned an empty list,
calling the cleared-check on an empty `[]` iterated zero times and fell through to
`return true`. The enemy thought it was "done" and relocated — then regenerated an empty
list again — infinite loop.

The fix: guard with `if flags.is_empty(): return false` at the top of the function.
In the current codebase this manifests as the `_search_waypoints.is_empty()` guards in
`_process_searching_state` (lines 2376–2407 of `enemy.gd`).

### 4. Idle-Only Enemies Entering SEARCHING (Issue #1419)

`reset_memory()` is called when the player teleports. Before the fix, any enemy that had a
remembered player position (even from an ally intel-share) would enter SEARCHING. After the
fix, only enemies where `_has_left_idle == true` (i.e., enemies that personally engaged the
player at least once) enter SEARCHING. Others return to IDLE.

---

## How the Tests Prevent Recurrence

The test file `tests/unit/test_ai_regression_1559.gd` contains five test groups:

| Group | What it tests | Bug it guards |
|-------|---------------|---------------|
| Group 1 | `_all_inspection_points_cleared` correct logic vs. buggy semicolon trap | Round 6 |
| Group 2 | Empty array must return `false`, not `true` | Round 7 |
| Group 3 | `_has_left_idle` gate in `reset_memory` / teleport path | Issue #1419 |
| Group 4 | Zone key computation and search radius expansion invariants | General SEARCHING sanity |
| Group 5 | Source-code structural guards (read `enemy.gd` and assert fix markers) | Issues #921, #1419, Round 7 |

Group 5 tests are especially powerful: they read the actual source of `enemy.gd` and assert
that the structural properties of the fix are present. If a future round of changes removes
the `_has_left_idle` guard from `reset_memory`, removes the `.is_empty()` guard from the
waypoint logic, or accidentally adds `_has_left_idle = true` back to
`_transition_to_searching`, the corresponding test will immediately fail and name the issue
number it is protecting.
