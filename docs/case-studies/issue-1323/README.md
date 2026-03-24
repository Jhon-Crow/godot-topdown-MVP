# Case Study: Issue #1323 — Weapon in Hands Not Updating in Roguelike Mode

## Summary

**Issue:** In roguelike mode, the weapon held by the player did not visually update when picking up a new weapon (or re-picking the same weapon) from the treasure pedestal. PR #1327 attempted to fix this, but introduced a new regression: the game crashes (or stops functioning) when the player touches the pedestal.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Original | Bug reported: weapon in hands not updating when picking up from pedestal |
| PR #1327 created | Fix applied in `Player.cs → ApplySelectedWeaponFromGameManager()` |
| PR #1327 marked ready | AI review: "all CI checks passed" |
| `game_log_20260322_165808.txt` | Owner tested, reports game breaks when touching pedestal |
| `game_log_20260322_165933.txt` | Second test session (failed to upload) |

---

## Root Cause Analysis

### Original Bug (Issue #1323)

Two bugs existed in `ApplySelectedWeaponFromGameManager()` in `Scripts/Characters/Player.cs`:

**Bug 1 — Early return for `makarov_pm`:**
```csharp
// BEFORE (buggy):
if (string.IsNullOrEmpty(selectedWeaponId) || selectedWeaponId == "makarov_pm")
    return; // no-op — MakarovPM re-pickup was silently ignored
```
If the player swapped away from MakarovPM (e.g. to Revolver) and then touched the pedestal to get MakarovPM back, nothing happened.

**Bug 2 — Only MakarovPM removed by name:**
```csharp
// BEFORE (buggy):
var defaultWeapon = GetNodeOrNull<BaseWeapon>("MakarovPM");
if (defaultWeapon != null)
{
    RemoveChild(defaultWeapon);
    defaultWeapon.QueueFree();
}
CurrentWeapon = null;
```
When the player held a non-default weapon (e.g. Shotgun), `GetNodeOrNull<BaseWeapon>("MakarovPM")` returned `null`. The old weapon node was never removed from the player's scene tree — duplicate weapon nodes accumulated as children.

### Regression (PR #1327)

The PR replaced `GetNodeOrNull<BaseWeapon>("MakarovPM")` with `CurrentWeapon`, fixing the orphaned-node bug:

```csharp
// AFTER (PR fix):
if (CurrentWeapon != null)
{
    var oldWeaponName = CurrentWeapon.Name;
    RemoveChild(CurrentWeapon);
    CurrentWeapon.QueueFree();
    CurrentWeapon = null;
    LogToFile($"[Player.Weapon] Removed current weapon: {oldWeaponName}");
}
```

**However, this introduced a regression:**

The Player scene (`scenes/characters/csharp/Player.tscn`) has MakarovPM **pre-placed as a child node** in the .tscn file. When the player node is instantiated:

1. MakarovPM exists as a pre-placed scene child
2. `_Ready()` detects `CurrentWeapon = GetNodeOrNull<BaseWeapon>("MakarovPM")`
3. `ApplySelectedWeaponFromGameManager()` is called with `selected_weapon = "makarov_pm"`
4. **With our fix**: the pre-placed MakarovPM is **removed and freed**, then a **new instance is loaded and added**

This causes three problems:

**Problem A — Unnecessary churn on `_Ready()`:** The weapon is removed and re-added every time the player enters the roguelike treasure room with `makarov_pm` selected. This is wasteful and potentially unsafe: removing a scene-placed node during `_Ready()` while other parts of the engine might still reference the pre-placed node.

**Problem B — Signal disconnection:** The roguelike level's `_setup_player_tracking()` (line 980-994 in `roguelike_level.gd`) connects to the weapon's `AmmoChanged`, `MagazinesChanged`, `Fired`, `ShellCountChanged` signals. After our fix removes and re-adds the weapon during `_Ready()`, these signal connections may be established to the old (soon-freed) weapon rather than the new one.

**Problem C — Weapon pose not re-applied after pedestal swap:** The `_weaponPoseApplied` flag is set to `true` after the initial weapon detection. When a weapon is swapped mid-game (via pedestal), `DetectAndApplyWeaponPose()` is not called again, leaving the player's arm pose in the wrong position.

**Problem D — Double weapon replacement potential:** When `body_entered` fires (pedestal interaction), `_apply_pedestal_weapon` calls `player.ApplySelectedWeaponFromGameManager()` synchronously during physics processing. If `CurrentWeapon` is in the middle of a physics update or signal emission, removing it during a physics callback can cause engine-level crashes in Godot 4.

---

## Evidence from Log (`game_log_20260322_165808.txt`)

```
[16:59:10] [Player.Weapon] GameManager weapon selection: makarov_pm (MakarovPM)
[16:59:10] [Player.Weapon] Removed current weapon: MakarovPM       ← NEW: pre-placed removed
[16:59:10] [Player.Weapon] Equipped MakarovPM (ammo: 9/9)          ← NEW: dynamically added
[16:59:10] [RoguelikeLevel] Spawning treasure pedestal: Drilling Bullets
[16:59:10] [RoguelikeLevel] Treasure pedestal added to scene at (640, 360)
[16:59:11] [NavMeshMonitor] Overlay refreshed with 5 polygon(s)
[16:59:11] [ReplayManager] Recording frame 3720 (54,5s): player_valid=False, enemies=5
→ CRASH (abrupt log end, no shutdown message)
```

Key observations:
- The crash occurs at the start of the treasure room, BEFORE the player can walk to the pedestal
- `player_valid=False` in ReplayManager indicates a stale player reference (pre-existing bug unrelated to #1323)
- No error message is logged — likely a native/engine-level crash
- The crash correlates with the timing of `set_deferred("monitoring", true)` activating the pedestal (next physics frame after `_ready`)

---

## Proposed Solution

### Fix 1: Guard against unnecessary weapon replacement
Add a check: if the current weapon already has the correct type (matching node name), skip the remove/re-add cycle.

```csharp
// Skip if already equipped correctly
if (CurrentWeapon != null && CurrentWeapon.Name == weaponNodeName)
{
    LogToFile($"[Player.Weapon] Already equipped {weaponNodeName}, no change needed");
    return;
}
```

This prevents:
- Removing/re-adding the pre-placed MakarovPM during `_Ready()` when `makarov_pm` is already selected
- Removing/re-adding any weapon when the same weapon is selected again (pedestal swap to same type)

### Fix 2: Re-apply weapon pose after pedestal swap
After `ApplySelectedWeaponFromGameManager()` is called from GDScript during a pedestal swap, reset `_weaponPoseApplied` and re-run `DetectAndApplyWeaponPose()`.

### Fix 3: Reconnect roguelike level signals after weapon swap
In `_apply_pedestal_weapon`, after calling `ApplySelectedWeaponFromGameManager()`, reconnect the level's signal handlers to the new weapon.

---

## Files Changed

- `Scripts/Characters/Player.cs` — `ApplySelectedWeaponFromGameManager()`: add same-weapon guard
- `scripts/levels/roguelike_level.gd` — `_apply_pedestal_weapon()`: reconnect weapon signals after swap; `_spawn_treasure_pedestal()`: bind floating tween to pedestal node

---

## Second Regression: Tween Use-After-Free Crash

After the first regression fix (same-weapon guard, arm pose reset, signal reconnection), the owner reported a **second crash** (`game_log_20260322_181229.txt`): the game still crashed when touching a pedestal, at least with passive items (Breaker Bullets, Drilling Bullets).

### Evidence from Log (`game_log_20260322_181229.txt`)

```
[18:13:46] [RoguelikeLevel] Spawning treasure pedestal: Breaker Bullets
[18:13:46] [RoguelikeLevel] Treasure pedestal added to scene at (640, 360)
[18:13:46] [RoguelikeLevel] Treasure room ready — pedestal spawned: true
...
[18:14:55] [SoundPropagation] Sound emitted: type=GUNSHOT, ...
→ CRASH (abrupt log end, no shutdown message, no error)
```

Key observations:
- No `"[RoguelikeLevel] Pedestal collected by player"` message — the `_on_pedestal_body_entered` handler may or may not have printed before the crash
- The crash is a hard engine segfault (no GDScript/C# error in logs)
- Both crash logs (Drilling Bullets and Breaker Bullets) follow the same pattern: passive item pedestal → hard crash on touch

### Root Cause: Tween Bound to Level, Animating Pedestal Child

In `_spawn_treasure_pedestal()`, the floating animation tween was created with `create_tween()` (line 1538), which binds the tween to `self` (the roguelike level node). However, the tween animates `float_node`, which is a child of the pedestal:

```gdscript
# BEFORE (buggy):
var float_tween := create_tween()   # ← tween bound to LEVEL (self)
float_tween.set_loops()
float_tween.tween_property(float_node, "position:y", ...)  # ← target is pedestal child
```

When the player touches a passive-item pedestal, `_apply_pedestal_active_item()` calls `pedestal.queue_free()`, which frees the pedestal and all its children (including `float_node`). But the tween survives because it's bound to the level node. On the next tween tick, it tries to set `position:y` on the freed `float_node` → **use-after-free / segfault**.

### Fix 4: Bind tween to pedestal

```gdscript
# AFTER (fixed):
var float_tween := pedestal.create_tween()   # ← tween bound to PEDESTAL
```

When the pedestal is `queue_free()`-d, Godot automatically kills all tweens bound to it. The tween no longer outlives its target.

---

## References

- [Issue #1323](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1323) — Original bug report
- [PR #1327](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1327) — Fix PR (this case study)
- [Godot 4 Docs: Node signals](https://docs.godotengine.org/en/stable/classes/class_node.html)
- [Godot 4 Docs: SceneTree.create_tween](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-method-create-tween) — tween ownership semantics
- Game log: `game_log_20260322_165808.txt` (first regression — attached to PR #1327)
- Game log: `game_log_20260322_181229.txt` (second regression — attached to PR #1327)
