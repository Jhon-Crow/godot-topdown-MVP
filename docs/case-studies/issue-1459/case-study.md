# Case Study: Issue #1459 — Enemies Stay in SEARCHING State When AI Search is Disabled

## Summary

When the user disables the **SEARCHING** AI state via the performance settings menu, enemies that are
already in the SEARCHING state continue running that state indefinitely. Additionally, enemies can
re-enter the SEARCHING state through two code paths that bypass the PerformanceSettings guard.

**Bug report (original, Russian):**
> "сейчас даже если ai поиска отключён некоторые враги всё равно в состоянии поиска."
> ("Currently, even if AI search is disabled, some enemies remain in the search state.")

---

## Artifacts

| File | Description |
|------|-------------|
| `game_log_20260324_202954.txt` | Full game log provided by the reporter |

---

## Timeline / Sequence of Events (reconstructed from log)

| Timestamp | Event |
|-----------|-------|
| 20:29:54 | Game starts, PerformanceSettings loaded: `ai: true` |
| 20:29:55 | Enemies 1–5 spawn in **SEARCHING** state (`initial_state = SEARCHING`, set by level designer) |
| 20:30:00 | User disables **AI state SEARCHING** via performance menu (`[PerformanceSettings] AI state SEARCHING disabled`) |
| 20:30:00+ | Enemies 1–5 **continue running `_process_searching_state()` every frame** — toggle is not checked there |
| 20:30:07 | Scene changes to DocksLevel; new enemies spawn |
| 20:30:07 | New enemies enter SEARCHING from COMBAT/IDLE transitions: `ContainerYardB_Rifle`, `ContainerYardB_Machete`, `OpenArea_Patrol1`, etc. |
| 20:30:08 | Enemies transition: `SEARCHING -> COMBAT` on player sight (normal gameplay) |
| 20:30:14 | Hit reaction triggers COMBAT from SEARCHING: `[#910] Hit triggered COMBAT from SEARCHING` |
| 20:30:51 | `[AllyDeath] Witnessed at ..., entering SEARCHING` — ally death triggers SEARCHING despite toggle off |

---

## Root Cause Analysis

### Root Cause 1 — No guard in `_process_searching_state()` (PRIMARY)

**File:** `scripts/objects/enemy.gd`, function `_process_searching_state()` (line ~2358)

Once an enemy is in the SEARCHING state, the state processor runs **every physics frame**. There is
**no check** against `PerformanceSettings.is_ai_state_searching_enabled()` at the top of
`_process_searching_state()`.

The existing guard only runs at **transition time** — in `_transition_to_searching()`:

```gdscript
# Line 2823 — guard exists here:
func _transition_to_searching(center_position: Vector2) -> void:
    var _ps := get_node_or_null("/root/PerformanceSettings")
    if _ps and not _ps.is_ai_state_searching_enabled(): _transition_to_idle(); return
    ...
```

But if an enemy is **already** in SEARCHING when the toggle is flipped off, it is **never redirected**.
This is confirmed by the log: SEARCHING is disabled at 20:30:00, but enemies 1–5 (already in
SEARCHING at that time) continue the state until they naturally transition to COMBAT on player sight.

**Fix:** Add an early-exit guard at the top of `_process_searching_state()`:
```gdscript
func _process_searching_state(delta: float) -> void:
    var _ps := get_node_or_null("/root/PerformanceSettings")
    if _ps and not _ps.is_ai_state_searching_enabled(): _transition_to_idle(); return  # Issue #1459
    ...
```

---

### Root Cause 2 — `_transition_to_idle()` bypasses SEARCHING guard when IDLE is disabled

**File:** `scripts/objects/enemy.gd`, function `_transition_to_idle()` (line ~2640)

When the IDLE state is disabled in PerformanceSettings, `_transition_to_idle()` redirects enemies
directly to SEARCHING by setting `_current_state = AIState.SEARCHING` inline, **without calling
`_transition_to_searching()`**:

```gdscript
# Line 2642-2643 — bypasses _transition_to_searching() guard:
func _transition_to_idle() -> void:
    var _ps := get_node_or_null("/root/PerformanceSettings")
    if _ps and not _ps.is_ai_state_idle_enabled():  # IDLE disabled -> stay in SEARCHING
        _current_state = AIState.SEARCHING; ...  # directly sets state, no SEARCHING guard!
        _generate_search_waypoints(); return
    ...
```

If both IDLE **and** SEARCHING are disabled simultaneously, this code still forces the enemy into
SEARCHING. The fix is to also check `is_ai_state_searching_enabled()` before doing the bypass, or
(better) call `_transition_to_searching()` which already has the guard.

**Fix:** Add a SEARCHING check in the IDLE-disabled bypass:
```gdscript
if _ps and not _ps.is_ai_state_idle_enabled():
    if _ps.is_ai_state_searching_enabled():  # Issue #1459
        _current_state = AIState.SEARCHING; ...; return
    # Both IDLE and SEARCHING disabled — fall through to IDLE (inactive enemy)
```

Or alternatively call `_transition_to_searching()` and return, trusting its own guard to fall back
to idle if SEARCHING is also disabled. However, that would cause infinite recursion
(`_transition_to_searching` → `_transition_to_idle` → `_transition_to_searching` ...). The explicit
check is safer.

---

## Other Entry Points (NOT bugs — transition guard handles them)

The following code paths all go through `_transition_to_searching()` and are therefore correctly
guarded:

| Location | Description |
|----------|-------------|
| Line 866 | Global stuck detection → `_transition_to_searching()` |
| Line 1851 | Flanking: player lost, `_has_left_idle` → `_transition_to_searching()` |
| Line 2178 | Pursuing: no valid target, `_has_left_idle` → `_transition_to_searching()` |
| Line 2263 | Pursuing: low memory confidence → `_transition_to_searching()` |
| Line 2494 | Evasion end, restore previous SEARCHING → `_transition_to_searching()` |
| Line 3775 | Teleport: had target → `_transition_to_searching()` |
| Line 3790 | Teleport: no target, `_has_left_idle` → `_transition_to_searching()` |
| Line 4869 | `on_ally_died()` → `_transition_to_searching()` |

---

## Impact

- **Severity:** Medium — performance profiling feature broken; SEARCHING state cannot be fully
  disabled to measure CPU cost of other states.
- **Gameplay impact:** None in normal play (toggle is off by default). Only affects users actively
  profiling with performance settings.
- **Affected states:** SEARCHING AI toggle in the performance menu.

---

## Proposed Fix

Two targeted changes in `scripts/objects/enemy.gd`:

1. Add early-exit guard at the top of `_process_searching_state()` (handles already-in-state enemies).
2. Add SEARCHING enabled check inside the IDLE-disabled bypass of `_transition_to_idle()`.

See the PR for the actual code changes.

---

## References

- Issue #1186 (original PerformanceSettings implementation)
- Issue #322 (SEARCHING state)
- Issue #330 (engaged enemies search infinitely)
- Issue #409 (ally death SEARCHING trigger)
- Issue #910 (hit-triggered COMBAT)
- Game log: `game_log_20260324_202954.txt` (provided by reporter, 12 466 lines)
