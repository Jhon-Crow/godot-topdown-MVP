# Case Study: Issue #676 — Force Field Active Item

## Problem Statement

**Report**: "При нажатии пробел при выбранном силовом поле ничего не происходит."
("When pressing Space with Force Field selected, nothing happens.")

**Game version**: Godot 4.3-stable (Windows export, non-debug build)
**First report**: 2026-02-15
**Second report**: 2026-02-24 (after PR #791 was believed to be fixed)
**Log files**: `game_log_20260215_231653.txt`, `game_log_20260224_195827.txt`, `game_log_20260224_195916.txt`

---

## Timeline of Events

### Session 1 — 2026-02-15 (Original Report)

| Timestamp  | Event |
|------------|-------|
| 23:16:53   | Game started |
| 23:16:54   | Player initialized: all other active items check and log "not selected" — **no `[Player.ForceField]` log** |
| 23:16:58   | ActiveItemManager: Active item changed from None to **Force Field** |
| 23:16:58   | Level restarted — Player re-initialized again with no force field log |
| 23:17:35   | Game ended, space was never pressed (no force field log) |

### Session 2 — 2026-02-24 (Post-PR #791 Report)

| Timestamp  | Event |
|------------|-------|
| 19:58:27   | Game started |
| 19:58:33   | ActiveItemManager: Active item unlocked: Force Field |
| 19:58:34   | ActiveItemManager: Active item changed from None to **Force Field** |
| 19:58:34   | Player._ready(): logs all items except ForceField — **still no `[Player.ForceField]` log** |
| 19:58:41   | New scene loaded, player re-initialized — **still no `[Player.ForceField]` log** |

### Session 3 — 2026-02-24 (Second game session same day)

| Timestamp  | Event |
|------------|-------|
| 19:59:17   | Game started |
| 19:59:25   | ActiveItemManager: Active item unlocked: Force Field |
| 19:59:49   | ActiveItemManager: Active item changed from None to Force Field |
| 19:59:50   | Player._ready(): all other items log "not selected" — **still no `[Player.ForceField]` log** |

**Key observation across ALL sessions**: There are ZERO force field related log entries from the Player script. The `[Player.ForceField]` category never appears, not even "Force field not selected."

---

## Root Cause Analysis

### Root Cause #1 (Original, 2026-02-15)
**`_init_force_field()` was missing from `player.gd`**

This was identified and added in PR #791. However, the fix was applied to the **wrong player script**.

### Root Cause #2 (Active, discovered 2026-02-24)
**The game uses `Player.cs` (C#), not `player.gd`**

The project has two parallel player implementations:
- `scenes/characters/Player.tscn` → `scripts/characters/player.gd` (GDScript, NOT used by levels)
- `scenes/characters/csharp/Player.tscn` → `Scripts/Characters/Player.cs` (C#, **ALL levels use this**)

Every level scene references `csharp/Player.tscn`:
```
scenes/levels/LabyrinthLevel.tscn  → scenes/characters/csharp/Player.tscn
scenes/levels/BuildingLevel.tscn   → scenes/characters/csharp/Player.tscn
scenes/levels/CityLevel.tscn       → scenes/characters/csharp/Player.tscn
scenes/levels/CastleLevel.tscn     → scenes/characters/csharp/Player.tscn
scenes/levels/BeachLevel.tscn      → scenes/characters/csharp/Player.tscn
scenes/levels/DocksLevel.tscn      → scenes/characters/csharp/Player.tscn
```

The C# `Player.cs` initializes all other active items:
```csharp
InitFlashlight();        // Issue #546
InitTeleportBracers();   // Issue #672
InitHomingBullets();     // Issue #677
InitInvisibilitySuit();  // Issue #673
InitBreakerBullets();    // Issue #678
// InitForceField() was MISSING ← Root Cause #2
```

And calls their input handlers in `_PhysicsProcess`:
```csharp
HandleFlashlightInput();           // Issue #546
HandleTeleportBracersInput();      // Issue #672
HandleHomingBulletsInput(delta);   // Issue #677
HandleInvisibilitySuitInput();     // Issue #673
// HandleForceFieldInput(delta) was MISSING ← Root Cause #2
```

**Why `player.gd` appeared to work in isolation**: It has both functions, but it is never actually run in a real game session because all levels use `csharp/Player.tscn`.

### Why the logs confirm this

The game log shows `[Player.Flashlight] No flashlight selected in ActiveItemManager` — this log string is in **both** `player.gd` and `Player.cs`. The C# version's logs (`[Player.InvisibilitySuit]`, `[Player.BreakerBullets]`) appear verbatim, confirming `Player.cs` is running.

The force field category `[Player.ForceField]` never appears because `InitForceField()` was never added to `Player.cs`.

---

## Solution

### Fix: Add `InitForceField()` and `HandleForceFieldInput()` to `Player.cs`

Following the exact pattern of `InitInvisibilitySuit()`:

1. **Add fields** (`_forceFieldEquipped`, `_forceFieldEffect`) to C# Player
2. **Add `InitForceField()`** — checks `ActiveItemManager.has_force_field()`, loads `force_field_effect.gd` script, attaches as child node
3. **Add `HandleForceFieldInput(delta)`** — hold Space → `activate()`, release → `deactivate()`
4. **Call both** from `_Ready()` and `_PhysicsProcess()` respectively

### Architecture

```
Player.cs (C# — runs in all game levels):
  _Ready() → InitForceField()
    - Checks ActiveItemManager.Call("has_force_field")
    - Loads force_field_effect.gd via GD.Load<Script>()
    - Creates new Node2D, SetScript(), AddChild()
    - Sets _forceFieldEquipped = true

  _PhysicsProcess(delta) → HandleForceFieldInput(delta)
    - If Input.IsActionPressed("flashlight_toggle"): _forceFieldEffect.Call("activate")
    - Else: _forceFieldEffect.Call("deactivate")

force_field_effect.gd (GDScript — unchanged):
  - activate(): shows shield, drains 8s charge
  - deactivate(): hides shield
  - is_active: property checked from C#
  - is_protecting(): method for external queries
```

---

## Files Changed

| File | Change |
|------|--------|
| `Scripts/Characters/Player.cs` | Added `InitForceField()`, `HandleForceFieldInput()`, fields, and call sites |
| `scripts/effects/force_field_effect.gd` | Unchanged (already correct) |
| `scenes/effects/ForceFieldEffect.tscn` | Unchanged (already correct) |
| `scripts/shaders/force_field.gdshader` | Unchanged (already correct) |
| `scripts/autoload/active_item_manager.gd` | Unchanged (already has `has_force_field()`) |
| `docs/case-studies/issue-676/README.md` | Updated with root cause #2 analysis |

---

## Verification Checklist

- [ ] `[Player.ForceField]` log category now appears on game start with Force Field selected
- [ ] Force field visual (glowing ring) appears when Space is held
- [ ] Shield disappears when Space is released
- [ ] 8-second charge depletes while active
- [ ] Shield blinks when charge is below 2 seconds
- [ ] Force field can be re-activated after partial use (charge preserved)
- [ ] No regression for other active items (flashlight, invisibility suit, etc.)
