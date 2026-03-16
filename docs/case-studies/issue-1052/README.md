# Case Study: Issue #1052 — Fix Unlocks (fix анлоки)

## Summary

After restarting the game, items that the player had already opened from cases (by holding LMB on a gold slot in the Armory) appear as locked again — the player is required to open them a second time.

---

## Timeline / Sequence of Events

1. **Player earns unlock condition** — completes a level at the required grade (e.g., Labyrinth D+ unlocks Mini Uzi).
2. **Player opens case in Armory** — holds LMB on the gold slot; unlock animation plays; `GameManager.unlock_weapon("mini_uzi")` is called.
3. **PersistManager saves** — catches `weapon_unlocked` signal and writes `mini_uzi = true` to `user://game_state.cfg`.
4. **Player restarts the game** — the autoload singletons initialize in order.
5. **PersistManager._load_state()** runs — reads `game_state.cfg` and sets `game_manager.unlocked_weapons["mini_uzi"] = true`. ✓
6. **UnlockManager._ready()** runs — calls `call_deferred("_reset_and_apply_all_unlocks")`.
7. **_reset_and_apply_all_unlocks() fires** (deferred, after _load_state) — calls `_reset_condition_gated_items()`, which sets **all condition-gated items back to `false`**, including `mini_uzi`.
8. **The restored unlock state is lost** — the player sees the case icon again and must re-open it.

---

## Root Cause Analysis

### File: `scripts/autoload/unlock_manager.gd`

```gdscript
func _reset_and_apply_all_unlocks() -> void:
    _reset_condition_gated_items()
    # BUG: no re-application of saved unlock state happens here
```

The function `_reset_and_apply_all_unlocks()` was designed (per its name and comments) to:
1. Reset condition-gated items to locked state (to prevent old/corrupt saves from granting items incorrectly).
2. Re-apply earned unlocks from progress.

However, step 2 was **never implemented**. The function only resets and does not restore items that the player legitimately unlocked by holding LMB on a gold slot.

### Why the Reset Was Added

The reset was introduced (Issue #894) to handle a scenario where an old/corrupt save file might have condition-gated items marked as `true` when the condition was never met. The intent was: "reset everything, then re-derive what should be unlocked from ProgressManager data."

### Why Re-application Was Never Implemented

The armory unlock system uses a two-step model:
- **Condition met** (based on level progress) → slot turns gold.
- **Player holds LMB** → item is permanently unlocked and saved.

The reset logic was written assuming that items could be re-derived purely from ProgressManager (i.e., condition met → auto-unlock). But the design explicitly requires player interaction to unlock — the LMB hold is the irreversible "open the case" action. The persistent unlock flag in `game_state.cfg` IS the source of truth for whether an item is unlocked, not the level condition.

### Consequence

The `_reset_condition_gated_items()` call **discards the PersistManager's correctly loaded state**, losing the player's legitimately earned unlocks on every game restart.

---

## Fix

The fix is to restore the saved unlock state **after** the reset, reading directly from the managers (which PersistManager already restored from the save file). Since `_reset_and_apply_all_unlocks()` is called deferred after `PersistManager._load_state()` has already applied the saved state, we need to capture the saved state before resetting, then restore it.

### Approach

Before calling `_reset_condition_gated_items()`, snapshot the currently-unlocked condition-gated items (which PersistManager already restored from disk). After the reset, re-apply the snapshot.

This ensures:
- Corrupt save data is cleaned up (items that should not be unlocked because their condition was never met are locked).
- Legitimately player-unlocked items (condition was met AND player performed the LMB hold) are preserved.

**File changed:** `scripts/autoload/unlock_manager.gd`

```gdscript
func _reset_and_apply_all_unlocks() -> void:
    # Snapshot which condition-gated items are currently unlocked
    # (PersistManager already loaded these from the save file)
    var saved_weapons: Array[String] = _get_unlocked_condition_gated_weapons()
    var saved_grenades: Array[int] = _get_unlocked_condition_gated_grenades()
    var saved_active_items: Array[int] = _get_unlocked_condition_gated_active_items()

    # Reset all condition-gated items to locked (removes any corrupt state)
    _reset_condition_gated_items()

    # Re-apply only items whose condition is also currently met
    # (i.e., legitimately unlocked: condition was met AND player held LMB)
    _restore_saved_unlocks(saved_weapons, saved_grenades, saved_active_items)
```

---

## Online Research

- Godot's `call_deferred()` executes at the end of the current frame, after all `_ready()` calls complete — this is the correct pattern to ensure PersistManager loads first.
- Godot `ConfigFile` reliably persists to `user://` path across restarts on all platforms.
- The two-phase unlock design (condition check → player action → permanent save) is a standard "loot box" pattern. The save file is the authoritative unlock record, not the condition check.

---

## Proposed Solutions (Considered)

| Option | Description | Chosen? |
|--------|-------------|---------|
| **Snapshot + restore** | Snapshot saved state before reset; restore after. Keeps reset's corruption-cleaning benefit. | ✓ Yes |
| Remove the reset entirely | Simpler, but loses the corruption-cleaning logic that prevented Issue #894 bugs | No |
| Move reset before PersistManager loads | Would require changing autoload order; more invasive | No |
| Auto-unlock from condition on reset | Would bypass the LMB hold mechanic (player must always open the case) | No |
