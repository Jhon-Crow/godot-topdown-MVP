# Case Study: Issue #1202 — IDLE state disable does not work at spawn

## Summary

When the IDLE AI state is disabled via `PerformanceSettings`, enemies still spawn in IDLE state instead of being redirected to SEARCHING. The fix introduced in PR #1190 only protected `_transition_to_idle()` (called during runtime transitions) but did not account for the **initial spawn path**, where `_current_state` is set directly without going through `_transition_to_idle()`.

---

## Timeline / Sequence of Events

### 1. Issue #1186 reported
A user reported that toggling AI states in the Performance settings had no effect — enemies kept transitioning into disabled states (e.g., `IDLE→COMBAT` log appeared even when COMBAT was disabled). The root cause was that `filter_ai_state()` was applied *after* transitions had already occurred, making the filter cosmetic only.

### 2. PR #1190 merged (fix for #1186)
The fix in PR #1190 added guard clauses **at the top of each `_transition_to_X()` function** that check `PerformanceSettings` before entering a state. For example, `_transition_to_idle()` now checks `is_ai_state_idle_enabled()` at its entry and redirects to SEARCHING if disabled.

The IDLE toggle was specifically designed so that:
- `IDLE disabled → SEARCHING` (keeps enemies active for load testing)

### 3. Issue #1202 reported (this issue)
After PR #1190 was merged, the IDLE disable still does not work **at game start / spawn**. Enemies begin the level standing still in IDLE state, even when IDLE is turned off in settings.

---

## Root Cause Analysis

### Primary Bug: Initial spawn bypasses `_transition_to_idle()`

**File:** `scripts/objects/enemy.gd`
**Location:** `_ready()` function, lines 428–429

```gdscript
# Line 428 (Issue #1121: initial state override)
if initial_state != AIState.IDLE: _current_state = initial_state
if initial_state == AIState.SEARCHING: _has_left_idle = true; _transition_to_searching(global_position)
```

When `initial_state == AIState.IDLE` (the default for all enemies), neither branch executes. The enemy's `_current_state` variable was initialized to `AIState.IDLE` at declaration (line 191):

```gdscript
var _current_state: AIState = AIState.IDLE  ## AI state
```

So the enemy starts in IDLE **without ever calling `_transition_to_idle()`**. All the protection logic in `_transition_to_idle()` is therefore skipped:

```gdscript
func _transition_to_idle() -> void:
    var _ps := get_node_or_null("/root/PerformanceSettings")
    if _ps and not _ps.is_ai_state_idle_enabled():  # Issue #1186: IDLE disabled -> SEARCHING
        _current_state = AIState.SEARCHING; ...
        return  # <-- never reached during spawn!
    _current_state = AIState.IDLE
    ...
```

### Why the fix in PR #1190 was incomplete

PR #1190 correctly added guards to all `_transition_to_X()` functions. However, the initial state assignment bypasses these transition functions entirely — it directly writes `_current_state = initial_state` (or relies on the default `= AIState.IDLE`). This is a classic "initialization vs. transition" gap in state machine design.

**Godot best practice** (per [The Shaggy Dev](https://shaggydev.com/2023/10/08/godot-4-state-machines/)): initialization should call `enter()` / the transition function, not set state directly, so that all entry guards are honored.

### Contributing Factor: Issue #1121's initial state logic

The code for #1121 at line 428 handles `initial_state != IDLE` and `initial_state == SEARCHING` as explicit overrides, but says nothing about the case where `initial_state == IDLE` and IDLE is disabled. The two issues (#1121 and #1186) create an interaction that was not addressed.

---

## Evidence

From the game log in PR #1190 (`docs/case-studies/issue-1186/game_log_20260320_073559.txt`, line 121):
```
[07:35:59] [INFO] [PerformanceSettings] PerformanceSettings initialized - particles: true, blood_decals: true, screen_shake: true, explosion_lights: true, ai: false
```
This shows `ai: false` — AI is disabled entirely — yet enemies still spawned (confirmed by BloodyFeet log entries). This is a different but related symptom.

---

## Proposed Solutions

### Solution A (Minimal, Recommended): Call `_transition_to_idle()` at spawn when `initial_state == IDLE`

Replace the direct default initialization with a deferred call to `_transition_to_idle()` at the end of `_ready()`, so the guard clause in `_transition_to_idle()` is honored.

**Change in `_ready()`** (around line 428):

```gdscript
# Before (lines 428-429):
if initial_state != AIState.IDLE: _current_state = initial_state
if initial_state == AIState.SEARCHING: _has_left_idle = true; _transition_to_searching(global_position)

# After:
if initial_state == AIState.SEARCHING:
    _has_left_idle = true
    _transition_to_searching(global_position)
elif initial_state != AIState.IDLE:
    _current_state = initial_state
else:
    _transition_to_idle()  # Issue #1202: honor IDLE disable at spawn
```

This ensures enemies with `initial_state == AIState.IDLE` go through `_transition_to_idle()`, which redirects to SEARCHING if IDLE is disabled.

### Solution B (Alternative): Add IDLE-disable check inline at spawn

Add the same check directly at line 428, without calling `_transition_to_idle()`:

```gdscript
if initial_state != AIState.IDLE: _current_state = initial_state
elif not PerformanceSettings.is_ai_state_idle_enabled():
    _has_left_idle = true; _transition_to_searching(global_position)
```

This is more explicit but duplicates logic from `_transition_to_idle()`.

**Recommendation: Solution A** — it reuses the existing redirect logic and is consistent with how PR #1190 structured the fix. Minimal diff, no duplication.

---

## Files Affected

- `scripts/objects/enemy.gd` — `_ready()` function (~line 428)

---

## References

- Issue #1202: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1202
- PR #1190 (original fix for #1186): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1190
- Issue #1186 (root issue): referenced in PR #1190
- Issue #1121 (initial_state override): referenced at line 428-429 in enemy.gd
- Godot 4 state machine best practices: https://shaggydev.com/2023/10/08/godot-4-state-machines/
