# Case Study: Issue #723 - Enemies Not Losing Player on Teleport/Invisibility

## Issue Summary
**Issue**: After teleportation or going invisible, enemies should lose the player and enter search mode.
**Russian Title**: "после телепортации или переходе в невидимость враги должны терять игрока"
**Russian Description**: "враги должны переходить в режим поиска"

## Problem Report
User reported that the implemented solution "did not work" ("не сработало") and provided game logs.

---

## Timeline of Events (from game_log_20260210_204215.txt)

### 1. Level Initialization (20:42:23)
```
[20:42:23] [INFO] [ActiveItemManager] Active item changed from None to Invisibility
[20:42:23] [INFO] [Player.InvisibilitySuit] Invisibility suit is selected, initializing...
[20:42:23] [INFO] [InvisibilitySuit] Shader loaded successfully
[20:42:23] [INFO] [InvisibilitySuit] Initialized with player: Player, charges: 2/2
[20:42:23] [INFO] [Player.InvisibilitySuit] Invisibility suit equipped, charges: 2
[20:42:23] [INFO] [Player] Ready! Ammo: 9/9, Grenades: 1/3, Health: 2/4
```

### 2. Enemy Engagement (20:42:26)
```
[20:42:26] [ENEMY] [Enemy2] State: IDLE -> COMBAT
[20:42:26] [ENEMY] [Enemy3] Memory: high confidence (0.88) - transitioning to PURSUING
[20:42:26] [ENEMY] [Enemy3] State: IDLE -> PURSUING
```

### 3. Invisibility Activation (20:42:27)
```
[20:42:27] [INFO] [InvisibilitySuit] Shader applied to 8 sprites
[20:42:27] [INFO] [InvisibilitySuit] Activated! Duration: 4.0s, Charges remaining: 1/2
```

### 4. Expected Behavior (NOT OBSERVED)
The following log message should have appeared but DID NOT:
```
[Player] Reset memory for X enemies (invisibility activation - Issue #723)
```

### 5. Actual Behavior (Observed)
```
[20:42:28] [ENEMY] [Enemy2] PURSUING corner check: angle 50.7°
```
Enemies continued pursuing instead of transitioning to SEARCHING mode.

---

## Root Cause Analysis

### Architecture Overview
The player entity has **dual implementation**:
1. **C# Player** (`Scripts/Characters/Player.cs`) - Core player logic
2. **GDScript Player** (`scripts/characters/player.gd`) - Additional systems

Both implementations independently initialize and handle the invisibility suit.

### The Bug
When comparing the two implementations:

#### GDScript Version (player.gd:3156-3163) - CORRECT
```gdscript
func _on_invisibility_activated(charges_remaining: int) -> void:
    invisibility_changed.emit(true, charges_remaining, _invisibility_suit.MAX_CHARGES)
    if _invisibility_hud and is_instance_valid(_invisibility_hud):
        _invisibility_hud.set_active(true)
        _invisibility_hud.update_charges(charges_remaining, _invisibility_suit.MAX_CHARGES)

    # Issue #723: Reset enemy memory when player becomes invisible
    _reset_all_enemy_memories("invisibility activation")  # <-- This exists!
```

#### C# Version (Player.cs:4749-4756) - MISSING THE FIX
```csharp
private void OnInvisibilityActivated(int chargesRemaining)
{
    if (_invisibilityHud != null && IsInstanceValid(_invisibilityHud))
    {
        _invisibilityHud.Call("set_active", true);
        _invisibilityHud.Call("update_charges", chargesRemaining, InvisibilityMaxCharges);
    }
    // <-- Missing: ResetAllEnemyMemories() call!
}
```

### Why C# Was Used
Looking at the log format:
- `[Player.InvisibilitySuit]` uses format consistent with C# `LogToFile()` method
- The C# version's `InitInvisibilitySuit()` was executed (line 4642)
- Signal connection in C# (line 4683): `_invisibilitySuitEffect.Connect("invisibility_activated", Callable.From<int>(OnInvisibilityActivated))`

The C# implementation runs first in `_Ready()` and connects its own callback, which doesn't include the enemy memory reset logic.

### Evidence Chain
1. **Log shows C# init**: `[Player.InvisibilitySuit] Invisibility suit equipped, charges: 2`
2. **Log shows activation**: `[InvisibilitySuit] Activated! Duration: 4.0s`
3. **Missing log**: No `[Player] Reset memory for X enemies` message
4. **No enemy state change**: Enemies continued PURSUING instead of SEARCHING
5. **No "Memory reset" enemy log**: The enemy.gd `reset_memory()` function logs "Memory reset: confusion=..." but this was never logged

---

## Solution

### Fix Required
Add `ResetAllEnemyMemories()` call to the C# `OnInvisibilityActivated` callback in `Player.cs`.

### Code Change
File: `Scripts/Characters/Player.cs`
Location: `OnInvisibilityActivated()` method (lines 4749-4756)

```csharp
private void OnInvisibilityActivated(int chargesRemaining)
{
    if (_invisibilityHud != null && IsInstanceValid(_invisibilityHud))
    {
        _invisibilityHud.Call("set_active", true);
        _invisibilityHud.Call("update_charges", chargesRemaining, InvisibilityMaxCharges);
    }

    // Issue #723: Reset enemy memory when player becomes invisible
    // Enemies lose track and enter search mode at last known position
    ResetAllEnemyMemories();
}
```

Note: The `ResetAllEnemyMemories()` method already exists in the C# Player class (lines 4254-4272) as it was added for the teleport functionality. It just wasn't called from the invisibility callback.

---

## Lessons Learned

### 1. Dual Implementation Pitfall
When a system has both C# and GDScript implementations:
- Changes must be applied to **both** versions
- Signal callbacks may be connected by different implementations
- Testing must verify which implementation is actually executing

### 2. Log-Based Debugging
Key insight from logs:
- The presence of C#-style log messages (`[Player.InvisibilitySuit]`) indicated C# was handling initialization
- The absence of `[Player] Reset memory` message indicated the fix wasn't being executed
- The continued enemy PURSUING state confirmed the problem

### 3. Architecture Documentation
The dual C#/GDScript player architecture should be documented to prevent similar issues in future PRs.

---

## Files Referenced
- `Scripts/Characters/Player.cs` - C# player implementation (needs fix)
- `scripts/characters/player.gd` - GDScript player implementation (has correct code)
- `scripts/effects/invisibility_suit_effect.gd` - Invisibility effect (emits signal correctly)
- `scripts/objects/enemy.gd` - Enemy AI (reset_memory() method is correct)
- `docs/case-studies/issue-723/game_log_20260210_204215.txt` - User's game log

---

## Status
**Root Cause**: Found - C# callback missing enemy memory reset
**Fix**: Pending implementation
**Verification**: Will verify with new game log after fix
