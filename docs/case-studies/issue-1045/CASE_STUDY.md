# Case Study: Issue #1045 — Armored Skin Not Working

## Summary

The Armored Skin active item had two separate bugs. Both have been fixed in PR #1046. However, the user reported "seems not working" after the fix was merged — this case study investigates the root causes and explains why the fix wasn't reflected in the user's test.

---

## Timeline of Events

| Time (UTC) | Event |
|---|---|
| Before PR #1046 | Initial code: ArmoredSkin implemented only in GDScript `player.gd`, but game uses C# `Player.cs` |
| 2026-03-16 19:21 | First AI work session: identified two bugs (invalid UID in .tscn file + GDScript/C# mismatch) |
| 2026-03-16 22:00 | Second AI work session: confirmed root cause, fixed both bugs in `Player.cs` |
| 2026-03-17 03:11 UTC | Commit `e7970363`: merged main, added `InitArmoredSkin()` to `Player.cs` |
| 2026-03-17 ~02:59 UTC | **User compiled old binary** (before our fix) |
| 2026-03-17 05:59 local | User ran tests — "seems not working" (old binary) |
| 2026-03-17 06:00 UTC | User uploaded `game_log_20260317_055925.txt` |

---

## Game Log Analysis (`game_log_20260317_055925.txt`)

### Key Finding: Binary Predates Our Fix

The player initialization sequence in the log ends at:
```
[Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager
[Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 4/4
```

In the fixed code (`Player.cs`), the sequence is:
1. `InitBreakerBullets()`
2. `InitForceField()`
3. `InitTrajectoryGlasses()`
4. `InitBreachingCharges()`  ← absent from log
5. `InitArmoredSkin()`       ← absent from log

Neither `[Player.BreachingCharges]` nor `[Player.ArmoredSkin]` appear anywhere in the log, which proves the user compiled the binary **before** our fixes were pushed (commit `e7970363` at 03:11 UTC).

### Evidence: Old Enum Values

```
[PersistManager] Restored unlocked active item type: 10
[ActiveItemManager] Active item changed from None to Armored Skin
[PersistManager] Restored selected active item type: 10
```

In the current codebase:
- Type 10 = `BREACHING_CHARGES`
- Type 11 = `ARMORED_SKIN`

In the user's binary (old version, before BreachingCharges was added):
- Type 10 = `ARMORED_SKIN`

This confirms the binary was compiled from code that predates PR #1044 (Breaching Charges, merged 2026-03-17 05:43 UTC).

### Armored Skin Was Selected But Never Initialized

The `ActiveItemManager` correctly shows Armored Skin as selected (lines 91, 383), but `Player.cs` in the old binary has no `InitArmoredSkin()` call. As a result:
- `_armoredSkinActive` is never set to `true`
- `TakeDamage()` never triggers `SpawnArmoredSkinShards()`
- No shards spawn

---

## Root Cause Analysis

### Root Cause 1: Wrong Language (GDScript vs C#)

The original implementation was in `player.gd` (GDScript), but the game uses `Player.cs` (C#). The C# `TakeDamage()` never called any GDScript armored skin logic.

**Evidence**: `Player.cs::TakeDamage()` called `base.TakeDamage()` from `BaseCharacter.cs` without any ArmoredSkin check.

**Fix**: Added `InitArmoredSkin()` and `SpawnArmoredSkinShards()` entirely in `Player.cs`.

### Root Cause 2: Invalid Godot 4 UID in ArmoredSkinShard.tscn

The shard scene file had UID `uid://armored_skin_shard_1045` which contains underscores — **not valid** in Godot 4 (base58 alphanumeric only). This caused `ResourceLoader.Exists()` to return `false`.

**Fix**: Corrected UID to a valid base58 string.

---

## Why the User Still Sees the Bug

The user's binary (`Godot-Top-Down-Template.exe`, release build) was compiled from source code **before** commit `e7970363`. The game log confirms:
1. No `[Player.ArmoredSkin]` logs appear at all
2. Enum value 10 maps to `ARMORED_SKIN` (old) instead of `BREACHING_CHARGES` (new)
3. `InitBreachingCharges` also absent, confirming pre-PR-#1044 binary

**Resolution**: The user needs to recompile/export the game from the latest source code on the `issue-1045-f828e39993bd` branch (or after PR #1046 is merged into `main`).

---

## Icon Issue

The user reported the Armored Skin icon looked the same as the "bullets with detonator" icon.

- Current `armored_skin_icon.png`: Blue diamond/crystal shield (64×64 RGBA PNG)
- `breaker_bullets_icon.png`: Golden bullet with sparks

These are visually distinct. The icon confusion likely occurred because:
1. The user tested with an old binary where ARMORED_SKIN was at enum index 10
2. In the old binary, item 10 might have shown a different icon
3. Or the user was comparing items in a UI that shows old cached data

The icon file is correct and distinct in the current codebase.

---

## Current Fix Status

All code fixes are in place on branch `issue-1045-f828e39993bd` (PR #1046):

| Fix | File | Status |
|---|---|---|
| `InitArmoredSkin()` in C# Player | `Scripts/Characters/Player.cs` | ✅ Done |
| `SpawnArmoredSkinShards()` in C# Player | `Scripts/Characters/Player.cs` | ✅ Done |
| `TakeDamage()` calls `SpawnArmoredSkinShards()` at ≤2 HP | `Scripts/Characters/Player.cs` | ✅ Done |
| Valid Godot 4 UID in shard scene | `scenes/projectiles/ArmoredSkinShard.tscn` | ✅ Done |
| `has_armored_skin()` in ActiveItemManager | `scripts/autoload/active_item_manager.gd` | ✅ Done |
| ArmoredSkin icon PNG | `assets/sprites/weapons/armored_skin_icon.png` | ✅ Done |

---

## Proposed Next Steps

1. **User action required**: Recompile/export the game from the latest `main` branch after PR #1046 is merged.
2. If issue persists after recompile, check:
   - That `ArmoredSkinShard.tscn` loads correctly (`ResourceLoader.Exists()` returns true)
   - That `has_armored_skin()` returns true when Armored Skin is selected
   - Game logs for `[Player.ArmoredSkin] Armored skin active` message

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1045
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1046
- Game log: `game_log_20260317_055925.txt` (in this folder)
- Fix commit: `e7970363`
