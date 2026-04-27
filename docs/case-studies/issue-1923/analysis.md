# Issue #1923 — Teleport Bracers Completely Broken: Deep Case Study

**Date:** 2026-04-27  
**Reported by:** Jhon-Crow  
**Log:** `game_log_20260427_163312.txt`  
**Build path:** `I:/Рабочий стол/godot old version game/100 (не проверенная)/`

---

## 1. Timeline / Sequence of Events

| Timestamp | Event |
|-----------|-------|
| 16:33:12 | Game started. LabyrinthLevel loaded. **Flashlight** selected as active item (type=1). Teleport bracers NOT selected. |
| 16:33:13 | Navigated automatically to **CityLevel** (PersistManager last-played level restore). TeleporterEnemy initialized with `EnemyTeleportComponent`. |
| 16:33:26 | Navigated to **Labyrinth2Level**. Still Flashlight selected. |
| 16:34:10 | Navigated to a different level. Still Flashlight selected. |
| 16:35:13 | Player in another level. Flashlight still selected. |
| 16:35:19 | **Active item changed from Breaker Bullets to Teleport Bracers** (type=3). `restart_scene()` called immediately. |
| 16:35:19 | **FactoryLevel instance 1** loaded. Teleport bracers initialized: 6 charges. Player ready. |
| 16:35:19 | Enemy1 immediately spots player (IDLE→COMBAT at frame 0). Combat starts within 1 second. |
| 16:35:20 | Player takes 1 damage (HP: 4→3). |
| 16:35:21 | Player takes 0.5 damage (HP: 3→2.5). Multiple enemies in combat. |
| 16:35:38 | Player restarts FactoryLevel (scene reload, ~19s of gameplay). **FactoryLevel instance 2** starts. Bracers equipped again: 6 charges. |
| 16:35:39 | Enemy1 spots player immediately. Player takes 1 damage (HP: 4→1). **PenultimateHit effect triggers** (10x slowdown, time_scale=0.1). |
| 16:35:41 | Scene changes to **TestTier (Tutorial)**. PenultimateHit reset, time_scale restored to 1.0. Bracers initialized again: 6 charges, Health: 2/4. |
| 16:35:43 | `player_valid=False` in ReplayManager (2.0s after TestTier load). Player node invalidated — no combat, no enemies. |
| 16:35:41–16:36:00 | ReplayManager continues recording with `player_valid=False`. Player appears dead/absent. No restart. |
| 16:36:00 | **Game closed.** |

**Critical observation**: In the entire session, there is **zero evidence of teleport being attempted**. The log would contain `[Player.TeleportBracers] Aiming started` if Space was pressed while bracers were equipped. This log line is absent.

---

## 2. Root Cause Analysis

### 2.1 Immediate Cause: No Teleport Attempt in Log

The game log shows:
- Teleport bracers equipped and initialized correctly (6 charges, 3 times across the session)
- `HandleTeleportBracersInput()` would log `[Player.TeleportBracers] Aiming started` if Space was held while equipped
- This log line is **completely absent** throughout the session

This means either:
1. The player never pressed Space while bracers were equipped, OR
2. Space was blocked before the log could fire

### 2.2 Primary Root Cause: Combat Pressure + Rapid Death

In FactoryLevel:
- **Instance 1**: Player is immediately under fire from multiple enemies (Enemy1 detects at frame 0). The player was managing 13 enemies. They took damage at T+1s and T+2s. The level restarted at T+19s without a single teleport attempt logged. Likely explanation: the player was focused on survival, reloading, or navigating the armory, and didn't have opportunity/time to test the teleport.

- **Instance 2**: Player took lethal-threshold damage at T+0.4s (1 HP remaining), triggering PenultimateHit (10x slowdown). Scene changed at T+2s. With time_scale=0.1, the game runs at 1/10 speed, making combat feel very different. The player may have been disoriented.

### 2.3 Secondary Root Cause: `player_valid=False` at 2.0s in TestTier

In TestTier (Tutorial), there are no enemies. The player's node became invalid at 2.0s without any damage, death event, or scene reload log entry. This suggests:
- The player may have navigated away via the Pause Menu (no log entry for that transition)
- OR there is a bug where the Player node gets freed prematurely in TestTier

### 2.4 Code Defects Found During Investigation

#### Bug 1: `_teleportCharges` not reset in `DeequipAllActiveItems`

**File**: `Scripts/Characters/Player.ActiveItems.cs`, method `DeequipAllActiveItems()`

```csharp
// Teleport bracers
_teleportBracersEquipped = false;
_teleportAiming = false;
// BUG: _teleportCharges NOT reset here
```

In roguelike mode (no scene restart on item change), if a player uses all 6 charges and then swaps items, the charges field persists at 0 until `InitTeleportBracers()` runs. While `InitTeleportBracers()` does reset charges when called, there is a window where the state is inconsistent. If `InitTeleportBracers` is called via a path that doesn't reset charges first, the teleport would silently fail.

**Fix**: Reset `_teleportCharges = 0` in `DeequipAllActiveItems()` so the field is always in a clean state before re-initialization.

#### Bug 2: `_teleportExperimentalActive` not reset in `DeequipAllActiveItems`

**File**: `Scripts/Characters/Player.ActiveItems.cs`, method `DeequipAllActiveItems()`

The `_teleportExperimentalActive` flag gates the teleport input handling:
```csharp
if (_teleportExperimentalActive) { ... return; }  // HandleTeleportBracersInput skips
```

If this flag becomes `true` (set by `HandleExperimentalSampleInput()` case 3) and the scene changes before the timer fires, a NEW player instance starts with `_teleportExperimentalActive = false` (field default), so this is not a persistence issue across scene loads. However, if the item is swapped in roguelike mode (no restart), the flag could incorrectly block input.

**Fix**: Reset `_teleportExperimentalActive = false` in `DeequipAllActiveItems()`.

#### Bug 3: Wrong Index Assertions in Unit Tests

**File**: `tests/unit/test_teleport_bracers.gd`

Multiple tests use wrong index value `2` for `TELEPORT_BRACERS` when the actual enum value is `3`:
- Line 210: `assert_eq(manager.current_active_item, 2, ...)` after `set_active_item(3)` — **should be 3**
- Line 315: `assert_eq(manager.current_active_item, 2)` after multiple `set_active_item(3)` calls — **should be 3**

The `MockArmoryWithTeleportBracers` class uses a local 4-item dict (0–3) where Teleport Bracers is at index 2, but the real `ActiveItemType` enum places TELEPORT_BRACERS at 3. This mismatch means these tests pass against the wrong mock but would fail if tested against the real `active_item_manager.gd`.

**Fix**: Correct all wrong index assertions from `2` to `3`.

#### Bug 4: No Warning Logged When Teleport Target is Default (0,0)

**File**: `Scripts/Characters/Player.ActiveItems.cs`, method `ExecuteTeleport()`

If `_teleportTargetPosition` is never updated (player presses and releases Space in the same frame, or `GetSafeTeleportPosition` fails), the player teleports to `(0,0)` clamped to the closest nav mesh point. This could silently teleport the player to a map corner with no visible feedback.

**Fix**: Log a warning if `_teleportTargetPosition` is `Vector2.Zero` when `ExecuteTeleport()` is called.

---

## 3. Timeline Reconstruction

```
[16:35:19] Teleport Bracers selected in armory (Breaker Bullets → Teleport Bracers)
           ↓
[16:35:19] restart_scene() called → NEW player instance
           ↓
[16:35:19] _Ready() → InitTeleportBracers() → _teleportBracersEquipped=true, _teleportCharges=6 ✓
           ↓
[16:35:19] FactoryLevel: 13 enemies, player under immediate fire
           ↓
[16:35:19-38] ~19s of combat. Player takes damage. NO TELEPORT ATTEMPT LOGGED.
           ↓
[16:35:38] Scene reload → FactoryLevel instance 2
           ↓
[16:35:38] _Ready() → InitTeleportBracers() → 6 charges ✓
           ↓
[16:35:39] Player hit to 1HP, PenultimateHit (0.1x time_scale) triggers
           ↓
[16:35:41] Scene changes to TestTier. PenultimateHit resets, time_scale=1.0
           ↓
[16:35:41] _Ready() → InitTeleportBracers() → 6 charges ✓
           ↓
[16:35:43] player_valid=False (2.0s after load). No enemies. Player node gone.
           ↓
[16:36:00] Game closed.
```

The teleport was never attempted. No bug in the teleport execution path is demonstrated by this log.

---

## 4. Proposed Solutions

### Immediate Fixes (Defensive Improvements)

1. **Reset `_teleportCharges` in `DeequipAllActiveItems`** to prevent latent roguelike-mode bug
2. **Reset `_teleportExperimentalActive` in `DeequipAllActiveItems`** for correctness
3. **Fix unit test assertions** for TELEPORT_BRACERS index (2 → 3)
4. **Add warning log** in `ExecuteTeleport()` when target is `Vector2.Zero`

### Investigation Suggestions for "Teleport Completely Stopped Working"

Since the log doesn't show any teleport attempt, we cannot determine what the actual failure mode was. The player should:
1. Equip teleport bracers in the armory
2. In a level: **hold Space** to start aiming (reticle should appear)
3. **Release Space** to teleport
4. If no reticle appears: check if jammed (radio jammer enemy nearby), check if out of charges
5. Report a new log showing the failed attempt with `[Player.TeleportBracers] Aiming started` followed by no teleport execution

### If Teleport Silently Fails (No Reticle)

Potential causes not yet eliminated:
- Navigation mesh not baked when teleport is first used (async baking issue)  
- `GetSafeTeleportPosition` returning the current position (no valid safe spot found)
- `ClampToNavigationMesh` clamping to current position (player is at closest nav mesh point)

To diagnose: add detailed logging in `GetSafeTeleportPosition` to log the computed target position on each frame while aiming.
