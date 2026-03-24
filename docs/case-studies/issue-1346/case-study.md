# Case Study: Issue #1346 — Fine Motor Skills shot counter not working

## Summary

**Issue:** Shots fired with shotgun/sniper/revolver were not being counted toward the
Fine Motor Skills unlock condition (300 shots required).

**Root Cause:** `tutorial_level.gd`'s `_on_weapon_fired()` callback did not call
`GameManager.register_shot()`, so all shots fired while on the Tutorial level were
silently discarded from the progress counter.

**Fix:** Added `GameManager.register_shot()` call inside `_on_weapon_fired()` in
`tutorial_level.gd` — matching the pattern used in all other level scripts.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 20:08:04 | Game starts on **LabyrinthLevel** with `ak_gl` selected |
| 20:08:05 | `UnlockManager` restores saved state (shotgun/sniper/revolver already unlocked as weapons) |
| 20:08:25–20:08:54 | Player opens unlock table — sees Fine Motor Skills locked |
| 20:09:19–20:09:21 | Player opens unlock table again — still locked |
| 20:09:25 | Player switches to **shotgun** in armory |
| 20:09:25 | **Scene changes to Tutorial level** (standard weapon try-out level) |
| 20:09:26–20:10:07 | Player fires shotgun many times — `shots_fired_special_weapons` never incremented |
| 20:10:02–20:10:07 | Player opens unlock table — counter still 0, Fine Motor Skills still locked |

All shotgun shots happen in the **Tutorial** level where `register_shot()` was missing.

---

## Evidence from Game Log

**File:** `game_log_20260322_200804.txt`

1. Shotgun fires multiple times (e.g. line 867–879, 899–911, etc.) — the `Shotgun.FIX#212`
   entries confirm rounds were discharged.

2. `SoundPropagation` logs show: `source=PLAYER (Shotgun)` — the game correctly identifies
   the player is using the shotgun.

3. **No `shots_fired_special_weapons` log entry appears anywhere in the log.** The GameManager
   logs this value every time it changes (line 250 in `game_manager.gd`). Its absence proves
   `register_shot()` was never called for any of these shots.

4. `GameManager` log at line 803: `Weapon selected: shotgun` — `selected_weapon` is correctly
   set to `"shotgun"`. So the filtering logic in `register_shot()` would have worked correctly
   *if the function had been called*.

---

## Root Cause Analysis

### Architecture

Shots are counted through a chain:

```
C# Weapon fires
  → emits Fired signal
    → level script connects Fired → _on_shot_fired() / _on_weapon_fired()
      → calls GameManager.register_shot()
        → increments shots_fired + shots_fired_special_weapons (if special weapon)
          → emits shots_fired_special_weapons_updated
            → UnlockManager checks unlock condition
              → PersistManager saves progress
```

### Where It Breaks

**`tutorial_level.gd`, function `_on_weapon_fired()`** (line 878):

```gdscript
func _on_weapon_fired() -> void:
    _shots_fired += 1
    print("Tutorial: Shot fired (%d total)" % _shots_fired)
    # ... tutorial hint logic only, NO register_shot() call
```

The function only increments a **local** tutorial counter for tutorial hints. It does NOT
call `GameManager.register_shot()`.

Compare with **all other levels** (e.g. `labyrinth_level.gd`, line 1110):

```gdscript
func _on_shot_fired() -> void:
    if GameManager:
        GameManager.register_shot()
```

Every other level (`arena_level.gd`, `beach_level.gd`, `building_level.gd`,
`castle_level.gd`, `city_level.gd`, `decadence_level.gd`, `docks_level.gd`,
`factory_level.gd`, `labyrinth2_level.gd`, `labyrinth_level.gd`, `revolver_level.gd`,
`roguelike_level.gd`, `test_tier.gd`) correctly calls `GameManager.register_shot()`.

Only `tutorial_level.gd` was missing this call.

### Why Was It Missing?

The Tutorial level's `_on_weapon_fired()` was added to track shots for tutorial hint
progression (e.g., "bolt cycle hint after 1st shot", "reload hint after 2nd shot"). The
developer who wrote it focused on the tutorial-specific logic and did not add the
GameManager stat tracking call that all other levels include.

---

## Fix

In `scripts/levels/tutorial_level.gd`, `_on_weapon_fired()`:

```gdscript
func _on_weapon_fired() -> void:
    _shots_fired += 1
    print("Tutorial: Shot fired (%d total)" % _shots_fired)
    # Track shot in GameManager for unlock conditions (Issue #1346).
    if GameManager:
        GameManager.register_shot()
    # ... rest of hint logic unchanged
```

This makes the Tutorial level consistent with all other level scripts.

---

## Impact

- **Affected levels:** Tutorial level (the weapon tryout level shown when switching weapons
  in the armory).
- **Affected weapons:** Shotgun, sniper rifle, revolver (all 3 special weapons that need
  300 shots for Fine Motor Skills unlock).
- **Other unlock conditions:** The laser sight kill counter (`kills_without_laser_sight`)
  is tracked via `GameManager.register_kill()`, which IS called from the Tutorial level
  (via enemy death), so laser sight tracking was not affected.
- **Severity:** High — users who primarily use the Tutorial level to practice with special
  weapons will never accumulate enough shots to unlock Fine Motor Skills.

---

## Verification

After the fix, firing any shot in the Tutorial level will:
1. Call `GameManager.register_shot()`
2. If `selected_weapon` is `"shotgun"`, `"sniper"`, or `"revolver"`, increment
   `shots_fired_special_weapons`
3. Emit `shots_fired_special_weapons_updated` signal
4. `UnlockManager._on_shots_fired_special_weapons_updated()` checks if count ≥ 300
5. `PersistManager` saves the updated count to disk

The log will show: `[GameManager] shots_fired_special_weapons: N (weapon: shotgun)`
for each qualifying shot.
