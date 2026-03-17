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

## Follow-Up Bugs (PR #1092 — 2026-03-17)

After the primary three-bug fix was applied, the user reported two additional issues via game log `game_log_20260317_085835.txt`:

### Bug 4 — First use pacifies multiple enemies instead of exactly 1 (at level 1)

**Reported:** "First use (even if a map was already completed with loudspeaker) makes enemies in the damage zone pacifists — only the first use should affect only one enemy."

**Evidence from log:**
```
[08:58:47] [ENEMY] [Enemy2] Transitioned to PACIFIST
[08:58:47] [ENEMY] [Enemy3] Transitioned to PACIFIST
[08:58:47] [INFO] [Player.Loudspeaker] Effect applied: 2/5 enemies pacified
[08:58:47] [INFO] [Player.Loudspeaker] Activated! Direction: ..., Effect chance: 100%, Charges: 1/2
```

**Root cause:** In `player.gd`, `effect_chance = 1.0` when `is_first_use = true`. Then in `_apply_loudspeaker_effect()`, `randf() > 1.0` is never true, so all eligible enemies in the cone get pacified. The spec says: "the first use — only ONE enemy that fell under the effect becomes pacifist."

**Fix:** Pass `max_pacify = 1` to `_apply_loudspeaker_effect()` when it is the first use at level 1. After pacifying 1 enemy, the loop breaks.

### Bug 5 — Level advances even when not all charges were used

**Reported:** "Loudspeaker level should only advance if the player used all charges and then completed the level (in one run)."

**Evidence from log:**
```
[08:58:54] [INFO] [Player.Loudspeaker] Activated! ..., Effect chance: 100%, Charges: 1/2
[08:58:54] [INFO] [Player.Loudspeaker] Activated! ..., Effect chance: 2%, Charges: 0/2
[08:59:58] [INFO] [ActiveItemManager] Loudspeaker level completed (had_kills=true). New level: 2
```

The first run used both charges (0/2 remaining) and then the level completed → level advanced to 2. This specific case was correct. However, the `on_level_completed()` in `loudspeaker_progress.gd` did NOT gate on charge exhaustion — it advanced on every level completion regardless. The log also shows subsequent runs where the player completed the level without using all charges.

**Root cause:** `on_level_completed()` always increments `levels_completed_with_loudspeaker` and calls `_update_level()` regardless of whether all charges were used.

**Fix:** Add `all_charges_used_this_level: bool` flag to `LoudspeakerProgress`. Set it to `true` in `use()` when charges drop to 0 (or for unlimited-charge levels, when any charge is spent). In `on_level_completed()`, only advance if `all_charges_used_this_level = true`. Reset the flag in `reset_for_new_level()`.

## Round 3 Bugs (PR #1092 — 2026-03-17, logs game_log_20260317_091947.txt and game_log_20260317_092204.txt)

After commits `fb1fd1cb` and `115faa7c`, the user reported two more issues:

### Bug 6 — First activation on every new-level visit still gets 100% effect chance

**Reported:** "First use on all maps (even if 1 map was already completed with loudspeaker use) makes enemies in the zone pacifists — should only be the first use globally at level 1."

**Evidence from game_log_20260317_092204.txt:**
```
[09:22:42] [INFO] [Player.Loudspeaker] Activated! Effect chance: 100%, Charges: 1/2  ← Level 2
[09:23:33] [INFO] [Player.Loudspeaker] Activated! Effect chance: 100%, Charges: 1/2  ← Level 3
[09:23:42] [INFO] [Player.Loudspeaker] Activated! Effect chance: 100%, Charges: 1/2  ← after respawn
... (repeated for every new level and every respawn)
```

**Root cause:** `reset_for_new_level()` in `loudspeaker_progress.gd` resets `used_this_level = false`. It was being called from `player.gd`'s `_init_loudspeaker()`, which runs on every `_ready()` — including player deaths/respawns. So `used_this_level` resets to `false` on every death, making every post-respawn first activation look like a "first use" triggering the 100% effect.

Additionally, `player.gd` line 3995 used `is_first_use` (any first use in any run) to decide the 100% chance, without checking if `current_level == 1`. At levels 2+ there should be no "100% first use" mechanic.

**Fix:**
1. Added `reset_for_respawn()` to `LoudspeakerProgress` that resets only charges, cooldown, and `all_charges_used_this_level` — NOT `used_this_level`.
2. `player.gd` now calls `reset_for_respawn()` instead of `reset_for_new_level()` in `_init_loudspeaker()`.
3. `reset_for_new_level()` (full reset including `used_this_level`) is called once after level completion in `ActiveItemManager.notify_level_completed()`.
4. `player.gd` condition for 100% / max_pacify=1 now checks both `is_first_use AND current_level == 1`.

### Bug 7 — Level progression never advances (level stays at 1 after multiple completions)

**Reported:** "Level system not working at all (completed almost all levels fully using loudspeaker, but its behavior didn't change)."

**Evidence from game_log_20260317_092204.txt:**
```
[09:22:35] [INFO] [ActiveItemManager] Loudspeaker level completed (had_kills=true). New level: 1
[09:23:25] [INFO] [ActiveItemManager] Loudspeaker level completed (had_kills=true). New level: 1
[09:27:12] [INFO] [ActiveItemManager] Loudspeaker level completed (had_kills=true). New level: 1
... (8 more completions, all "New level: 1")
```

**Root cause:** `all_charges_used_this_level` flag was gating progression but was reset on every player death/respawn by `reset_for_new_level()`. Players commonly die during levels. After a respawn, the player starts with fresh charges. If they do not use ALL charges in the final run before level completion, `all_charges_used_this_level` is `false` at the time `on_level_completed()` is called → level never advances.

Key evidence — in the 3rd level (CastleLevel), the player activated the loudspeaker once (09:23:33, Charges: 1/2), was then re-initialized (respawn at 09:23:37, Charges: 2/2 again), used 1 of 2 new charges (09:23:42, Charges: 1/2), got re-initialized AGAIN (09:23:44), etc. The `all_charges_used_this_level` flag was being reset on EVERY respawn so it was almost impossible to complete a level with the flag set to `true`.

**Fix:** Same as Bug 6 fix — `reset_for_respawn()` preserves `all_charges_used_this_level` within a single run. After the player uses all charges in their current run (from last respawn), the flag is set and will remain `true` unless they die again. If they complete the level without dying after exhausting charges, the gate passes and the level advances.

## References

- Issue #959: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/959
- PR #1018 (original implementation): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1018
- PR #1092 (this fix): https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1092
- Game logs: `game_log_20260317_082332.txt`, `game_log_20260317_085835.txt`, `game_log_20260317_091947.txt`, `game_log_20260317_092204.txt`
- `scripts/components/loudspeaker_progress.gd` — progression logic
- `scripts/autoload/active_item_manager.gd` — persistent progress storage
- `scripts/characters/player.gd` — activation and effect application
