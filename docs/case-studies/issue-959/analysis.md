# Case Study: Issue #959 — Loudspeaker Progression System Bug

## Summary

The Loudspeaker active item (implemented in PR #1018) has a critical regression in its progression system: the `LoudspeakerProgress` object is re-created on every scene/level load, resetting all state. As a result:

- `used_this_level` is always `false` → first-use 100% effect chance applies on every activation
- `levels_completed_with_loudspeaker` stays at 0 → item never advances past level 1
- `on_level_completed()` is never called → progress never advances

**User report (2026-03-17):** "Seems like stages 4+ are not implemented. On first use (even if a map has already been completed with successful use) 2 enemies become pacifists, which does not match the original issue."

## Timeline / Sequence of Events

| Time (from log) | Event |
|---|---|
| 08:23:32 | Game starts, BFF Pendant selected |
| 08:23:39 | Player switches to Loudspeaker → `_init_loudspeaker()` called → new `LoudspeakerProgress` created (Lv1, 2/2 charges) |
| 08:23:44 | **First activation** → `used_this_level=false` → 100% chance → 2 enemies pacified |
| 08:24:12 | Level reloaded → `_init_loudspeaker()` called again → **new** `LoudspeakerProgress` created (Lv1, 2/2 charges, `used_this_level=false`) |
| 08:24:13 | **"Second" activation** → but again 100% chance because `used_this_level` was reset |
| 08:24:15–08:24:24 | Pattern repeats 4+ more times — each reload gives fresh 100% chance |

## Root Causes

### 1. `LoudspeakerProgress` re-created on every level load (PRIMARY)

**File:** `scripts/characters/player.gd`, line 3905

```gdscript
func _init_loudspeaker() -> void:
    # ...
    _loudspeaker_progress = LoudspeakerProgress.new()  # ← BUG: new object every call
```

`_init_loudspeaker()` is called from `_ready()` (line 374). Every time the scene restarts (on level change, item re-equip, death), `_ready()` runs again and creates a brand-new `LoudspeakerProgress`. Since `used_this_level` starts as `false`, the first-use 100% effect always applies.

### 2. `on_level_completed()` is never called (SECONDARY)

**File:** `scripts/components/loudspeaker_progress.gd`, lines 168–174

```gdscript
func on_level_completed(had_kills: bool) -> void:
    levels_completed_with_loudspeaker += 1
    if not had_kills:
        has_completed_pacifist_level = true
    _update_level()
```

This method exists but is never called. No level script calls it when the player completes a level. Without this, `levels_completed_with_loudspeaker` stays at 0 and `current_level` never advances from 1.

### 3. Loudspeaker progress not persisted to disk (TERTIARY)

**File:** `scripts/autoload/persist_manager.gd`

The `PersistManager` saves weapon selection, grenade type, and active item type — but has no code to save or load the `LoudspeakerProgress` data (`current_level`, `levels_completed_with_loudspeaker`, etc.). Even if the progress object survived between scenes, restarting the game would reset all progress.

## Game Log Evidence

```
[08:23:39] [INFO] [Player.Loudspeaker] Loudspeaker equipped, charges: 2/2
[08:23:44] [INFO] [Player.Loudspeaker] Activated! Direction: ..., Effect chance: 100%, Charges: 1/2

[08:24:12] [INFO] [Player.Loudspeaker] Loudspeaker equipped, charges: 2/2   ← re-initialized
[08:24:13] [INFO] [Player.Loudspeaker] Activated! Direction: ..., Effect chance: 100%, Charges: 1/2  ← 100% again

[08:24:15] [INFO] [Player.Loudspeaker] Loudspeaker equipped, charges: 2/2   ← re-initialized again
[08:24:17] [INFO] [Player.Loudspeaker] Activated! Direction: ..., Effect chance: 100%, Charges: 1/2  ← 100% again
```

The log shows the loudspeaker is initialized at least 6 times in 52 seconds, each time with fresh 2/2 charges.

## Proposed Solutions

### Fix 1: Store `LoudspeakerProgress` in `ActiveItemManager` (autoload singleton)

Move the `LoudspeakerProgress` instance to `ActiveItemManager`, which is a singleton that persists for the entire game session. `_init_loudspeaker()` in `player.gd` should fetch it from there instead of creating a new one.

```gdscript
# In active_item_manager.gd
var loudspeaker_progress: LoudspeakerProgress = LoudspeakerProgress.new()
```

```gdscript
# In player.gd _init_loudspeaker()
var aim := get_node_or_null("/root/ActiveItemManager")
_loudspeaker_progress = aim.loudspeaker_progress  # reuse, don't recreate
_loudspeaker_progress.reset_for_new_level()       # only reset charges
```

### Fix 2: Add `on_level_completed()` call in each level script

Each level script's `_complete_level_with_score()` function should notify loudspeaker progress:

```gdscript
var aim := get_node_or_null("/root/ActiveItemManager")
if aim and aim.has_method("notify_level_completed"):
    var had_kills: bool = score_data.get("kills", 0) > 0
    aim.notify_level_completed(had_kills)
```

### Fix 3: Persist loudspeaker progress via `PersistManager`

Add save/load of `loudspeaker_progress.to_dict()` / `from_dict()` in `PersistManager._save_state_with_level()` and `_load_state()`.

## Files Affected

| File | Change |
|---|---|
| `scripts/autoload/active_item_manager.gd` | Add `loudspeaker_progress` field and `notify_level_completed()` |
| `scripts/characters/player.gd` | Use progress from `ActiveItemManager`, don't recreate |
| `scripts/autoload/persist_manager.gd` | Save/load loudspeaker progress data |
| `scripts/levels/labyrinth_level.gd` | Call `notify_level_completed()` at level completion |
| `scripts/levels/beach_level.gd` | Same |
| `scripts/levels/building_level.gd` | Same |
| `scripts/levels/castle_level.gd` | Same |
| `scripts/levels/city_level.gd` | Same |
| `scripts/levels/decadence_level.gd` | Same |
| `scripts/levels/docks_level.gd` | Same |
| `scripts/levels/factory_level.gd` | Same |

## References

- Issue #959: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/959
- PR #1018 (original implementation): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1018
- Game log: `game_log_20260317_082332.txt`
- `scripts/components/loudspeaker_progress.gd` — progression logic (correct, but never properly connected)
- `scripts/autoload/active_item_manager.gd` — correct place to store persistent progress
