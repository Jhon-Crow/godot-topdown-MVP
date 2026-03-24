# Case Study: Issue #1454 — IDLE Enemies Incorrectly Enter SEARCHING During Special Last Chance

## Summary

**Report**: During the Special Last Chance effect, enemies that were in IDLE state and had never seen the player (nor been approached by other enemies) were incorrectly included in the post-effect search.

**Root cause**: SoundPropagation calls `on_sound_heard_with_intensity` as a **direct method call**, which bypasses `PROCESS_MODE_DISABLED`. During Last Chance, enemies are frozen via `PROCESS_MODE_DISABLED`, but can still receive and process sound events. IDLE enemies (with `_has_left_idle = false`) that hear a player gunshot during the freeze call `_transition_to_combat()`, which sets `_has_left_idle = true`. When the effect ends, `reset_memory()` sees `_has_left_idle = true` and sends the enemy to SEARCHING.

**Fix**: Add `if process_mode == Node.PROCESS_MODE_DISABLED: return` at the top of `on_sound_heard_with_intensity`.

---

## Log File

- `game_log_20260324_200105.txt` — original log from issue reporter

---

## Timeline Reconstruction

All times from `game_log_20260324_200105.txt`.

### First Last Chance (20:01:18 → 20:01:24)

| Time | Event |
|------|-------|
| 20:01:11 | Enemy8 spawned at (1900, 1450), GUARD, IDLE. `_has_left_idle = false`. |
| 20:01:11 | Enemy9 spawned at (2100, 1550), GUARD, IDLE. `_has_left_idle = false`. |
| 20:01:18 | Player damaged to 1 HP → Last Chance triggers. Enemies frozen (`PROCESS_MODE_DISABLED`). |
| **20:01:23** | **Player fires. SoundPropagation emits GUNSHOT. All 10 enemies receive `on_sound_heard_with_intensity` as a direct call — bypassing `PROCESS_MODE_DISABLED`.** |
| **20:01:23** | **Enemy8 logs: "Heard gunshot at (1170, 760), distance=1003". Enemy was IDLE with `_has_left_idle=false`.** |
| **20:01:23** | **Enemy9 logs: "Heard gunshot at (1170, 760), distance=1219". Enemy was IDLE with `_has_left_idle=false`.** |
| **20:01:23** | **Both enemies process the sound, update memory, call `_transition_to_combat()` → sets `_has_left_idle = true`.** |
| 20:01:24 | Last Chance ends. `reset_memory()` called on all enemies. |
| 20:01:24 | Enemy8: `had_target=true`, `_has_left_idle=true` → enters SEARCHING at (1170, 760). **BUG.** |
| 20:01:24 | Enemy9: `had_target=true`, `_has_left_idle=true` → enters SEARCHING at (1170, 760). **BUG.** |

Without the fix: both enemies spend ~11 seconds searching an area they were never meant to patrol.

---

## Root Cause Analysis

### Architecture

- **Last Chance freeze**: sets all non-player CharacterBody2D nodes to `PROCESS_MODE_DISABLED` (line 579 of `last_chance_effects_manager.gd`).
- **SoundPropagation**: emits sounds by iterating registered listeners and calling `on_sound_heard_with_intensity(...)` directly on each node (not via signal).
- **Godot's `PROCESS_MODE_DISABLED`**: prevents `_process`, `_physics_process`, `_input` callbacks from running, but does **NOT** prevent external direct method calls.

### Bug Path (before fix)

```
Player fires during Last Chance freeze
  → SoundPropagation.emit_sound()
    → for each listener: listener.on_sound_heard_with_intensity(...)  # direct call
      → Enemy8.on_sound_heard_with_intensity(GUNSHOT, ...)            # bypasses DISABLED!
        → _is_alive check: pass (enemy is alive)
        → _memory_reset_confusion_timer check: pass (timer is 0, no prior reset)
        → updates _memory.suspected_position
        → calls _transition_to_combat()
          → _has_left_idle = true  ← CORRUPTION
          → _current_state = COMBAT
  → Last Chance ends
    → reset_memory() called on Enemy8
      → had_target = true (memory was updated during freeze)
      → _has_left_idle = true (set during freeze)
      → → _transition_to_searching(old_position)  ← WRONG: enemy never engaged
```

### Fix

```gdscript
func on_sound_heard_with_intensity(...) -> void:
    if not _is_alive: return
    if process_mode == Node.PROCESS_MODE_DISABLED: return  # Issue #1454
    ...
```

When enemies are frozen by Last Chance, `process_mode == PROCESS_MODE_DISABLED`. The guard returns early, preventing any state changes from occurring during the freeze.

---

## Relation to Prior Issues

| Issue | Connection |
|-------|------------|
| #318 | Introduced `reset_memory()` and the confusion timer system for Last Chance |
| #910 | Added player-gunshot bypass for the confusion timer (`is_player_gunshot` exception) |
| #1419 | Added `_has_left_idle` guard in `reset_memory()` for the `had_target=true` branch — but did not address sound reception during the freeze itself |
| **#1454** | **Fix: prevent sound processing entirely while enemy is frozen** |

Issue #1419 fixed the case where enemies received intel via ally-share (passive, during normal gameplay). Issue #1454 is a different path: enemies actively process sounds during the freeze window because direct method calls bypass `PROCESS_MODE_DISABLED`.

---

## Verification

After the fix, Enemy8 and Enemy9 will:
1. Be in IDLE state when Last Chance triggers
2. Receive `on_sound_heard_with_intensity` calls during the freeze — but return immediately due to the `PROCESS_MODE_DISABLED` check
3. Keep `_has_left_idle = false` and `_memory.has_target() = false`
4. After Last Chance ends: `reset_memory()` → `had_target = false`, not in combat state → stay IDLE ✓
