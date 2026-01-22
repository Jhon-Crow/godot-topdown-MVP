# Root Cause Analysis: Issue #227 - UZI Pose Fix

## Problem Statement
When the player holds an UZI, they hold it the same way as the M16 (as if the UZI had a long barrel). The UZI should be held with two hands in a compact pose appropriate for a submachine gun.

## Root Cause

### Primary Cause: Fixed Arm Positions
The player's arm positions are fixed and do not adapt to the equipped weapon type.

**Location**: `scripts/characters/player.gd`

**Evidence**:
```gdscript
# Base positions stored in _ready() - lines 242-250
_base_left_arm_pos = _left_arm_sprite.position   # (24, 6)
_base_right_arm_pos = _right_arm_sprite.position  # (-2, 6)
```

These positions are designed for a rifle (M16) with a long barrel, where:
- Left arm is extended forward (x=24) to support the front of the rifle
- Right arm is closer to the body (x=-2) holding the pistol grip

### Secondary Cause: No Weapon Type Detection
The player script has no mechanism to:
1. Detect which weapon is currently equipped
2. Adjust arm positions based on weapon type
3. Apply different base positions for different weapon categories

### Current Arm Positioning in Walking Animation
```gdscript
# Lines 384-433 - _update_walk_animation()
# Arms always return to the same base positions regardless of weapon
if _left_arm_sprite:
    _left_arm_sprite.position = _base_left_arm_pos + Vector2(arm_swing, 0)
if _right_arm_sprite:
    _right_arm_sprite.position = _base_right_arm_pos + Vector2(-arm_swing, 0)
```

### Weapon Scene Configurations
Both weapons use similar sprite offsets:
- **MiniUzi.tscn**: `offset = Vector2(15, 0)`
- **AssaultRifle.tscn**: `offset = Vector2(20, 0)`

The UZI has a slightly smaller offset (15 vs 20), but the arm positions don't account for this difference.

## Expected Behavior

For the UZI (compact SMG):
- Both hands should be closer together
- Left arm should be less extended (supporting a shorter barrel/handguard)
- Arms should create a compact, two-handed grip appropriate for a submachine gun

For the M16 (rifle):
- Hands spread further apart
- Left arm extended forward to support long barrel
- Traditional rifle stance

## Solution Approach

Add weapon-aware arm positioning to the player script:

1. **Detect equipped weapon type** by checking children of WeaponMount or player
2. **Apply weapon-specific arm offsets** to create appropriate poses:
   - SMG pose: Arms closer together for compact grip
   - Rifle pose: Arms spread for long barrel support
3. **Adjust base positions dynamically** when weapon changes or during _ready()

## Technical Implementation

### Option A: Modify `_ready()` in player.gd
- Detect weapon type after weapon is added
- Apply appropriate base arm positions

### Option B: Add setter/signal for weapon changes
- When weapon is equipped, adjust arm positions accordingly
- More flexible for runtime weapon switching

### Recommended: Option A (simpler)
Since weapons are set at level initialization and don't change during gameplay, we can simply detect the weapon in `_ready()` or add a deferred call to adjust positions.

## Files to Modify
1. `scripts/characters/player.gd` - Add weapon detection and arm position adjustment

## Testing
1. Start game with M16 selected - verify rifle pose
2. Start game with Mini UZI selected - verify compact SMG pose
3. Verify walking animation works correctly with both weapons
4. Verify grenade animation still works (it has its own arm positioning)

---

## Update (2026-01-22): Initial Fix Did Not Work

### Feedback from User
The user reported "поза не изменилась" (the pose did not change) after testing the initial fix.

### Investigation

#### Game Log Analysis
Analyzed log file: `game_log_20260122_120033.txt`

Key observations from the log:
1. `[Player] Ready! Grenades: 3/3` appears - Player's `_ready()` completes
2. `[GameManager] Weapon selected: mini_uzi` appears at 12:01:12
3. **Missing**: No `[Player] Detected weapon: Mini UZI (SMG pose)` log entries
4. This confirms the weapon detection code is NOT executing successfully

#### Code Flow Analysis

The issue is a **timing/sequencing problem**:

1. **Godot Scene Tree Initialization Order**:
   - Child nodes' `_ready()` is called BEFORE parent nodes' `_ready()`
   - Player (child of level) has its `_ready()` called FIRST
   - Tutorial level's `_ready()` is called AFTER player's `_ready()`

2. **Current Code Flow**:
   ```
   Player._ready()
   ├── Stores base arm positions
   ├── call_deferred("_detect_and_apply_weapon_pose")  <-- Scheduled
   └── Logs "[Player] Ready!"

   [Deferred calls execute]
   └── _detect_and_apply_weapon_pose()  <-- NO WEAPON EXISTS YET!
       └── get_node_or_null("MiniUzi") returns null

   TutorialLevel._ready()
   ├── Finds player
   └── _setup_selected_weapon()
       ├── Removes AssaultRifle
       └── Adds MiniUzi  <-- TOO LATE!
   ```

3. **Root Cause of Fix Failure**:
   - `call_deferred()` schedules the function to run at the END of the current frame
   - However, the tutorial level's `_ready()` (which adds the weapon) runs at the SAME deferred timing
   - Godot doesn't guarantee deferred call order between different nodes
   - The weapon detection runs BEFORE the level script adds the weapon

### True Root Cause

**The initial fix assumed `call_deferred` would wait for the level script to add the weapon, but this is incorrect.**

Godot's `_ready()` propagation and deferred call timing:
1. All child `_ready()` functions complete
2. Parent `_ready()` is called
3. Deferred calls from ALL nodes execute (order not guaranteed)

Since both player and level script use the same deferred timing, the weapon may not exist when detection runs.

### Corrected Solution Approach

**Option A: Multiple Deferred Calls (Chain Delays)**
- Use `call_deferred` twice to ensure execution after level script
- Risk: Still depends on timing, fragile

**Option B: Use `_process` with One-Time Check**
- Check for weapon in first few `_process` frames
- Guaranteed to run after all `_ready()` functions complete

**Option C: Level Script Triggers Detection**
- Have level script call player's pose update after equipping weapon
- Most reliable but requires modifying level scripts

**Option D: Signal-Based Detection**
- Player connects to weapon added signal
- Cleanest solution for dynamic weapon changes

**Recommended: Option B or C** - Most reliable approaches for the current architecture.

---

## Implemented Fix (2026-01-22)

### Solution: Option B - Frame-Delayed Detection in `_physics_process()`

Instead of using `call_deferred()` which has unpredictable timing relative to level script initialization, the fix waits for a few `_physics_process()` frames before detecting the weapon.

### Changes Made

1. **Removed `call_deferred` from `_ready()`**:
   ```gdscript
   # Old (broken):
   call_deferred("_detect_and_apply_weapon_pose")

   # New (comment explaining the approach):
   # Note: Weapon pose detection is done in _process() after a few frames
   # to ensure level scripts have finished adding weapons to the player.
   ```

2. **Added frame counter variables**:
   ```gdscript
   var _weapon_pose_applied: bool = false
   var _weapon_detect_frame_count: int = 0
   const WEAPON_DETECT_WAIT_FRAMES: int = 3
   ```

3. **Added detection logic to `_physics_process()`**:
   ```gdscript
   if not _weapon_pose_applied:
       _weapon_detect_frame_count += 1
       if _weapon_detect_frame_count >= WEAPON_DETECT_WAIT_FRAMES:
           _detect_and_apply_weapon_pose()
           _weapon_pose_applied = true
   ```

4. **Added debug logging**:
   ```gdscript
   FileLogger.info("[Player] Detecting weapon pose (frame %d)..." % _weapon_detect_frame_count)
   ```

### Why This Works

1. `_physics_process()` runs AFTER all `_ready()` functions have completed
2. By waiting 3 frames, we ensure:
   - All `_ready()` functions in the scene tree have run
   - Level scripts have had time to add weapons to the player
   - Any deferred calls from level scripts have also executed
3. The one-time check (`_weapon_pose_applied`) ensures detection only runs once

### Expected Log Output (After Fix)

```
[Player] Ready! Grenades: 3/3
[GameManager] Weapon selected: mini_uzi
[Player] Detecting weapon pose (frame 3)...
[Player] Detected weapon: Mini UZI (SMG pose)
[Player] Applied SMG arm pose: Left=(14, 6), Right=(1, 6)
```

---

## ACTUAL Root Cause Found (2026-01-22): C# Player Missing Implementation

### User Feedback After Frame-Delay Fix
User reported: "the right arm is still extended far forward"

### Key Discovery
Upon analyzing the user's new game log (`game_log_20260122_122038.txt`), a critical observation was made:

**User's log format**: `[12:20:39] [INFO] [Player] Ready! Grenades: 1/3`

**Expected GDScript format**: `[Player] Ready! Ammo: X/X, Grenades: X/X, Health: X/X`

This mismatch revealed that the user is running the **C# version** of the player (`Player.cs`), NOT the GDScript version (`player.gd`)!

### Evidence

1. **C# Player.cs log line** (line 557):
   ```csharp
   LogToFile($"[Player] Ready! Grenades: {_currentGrenades}/{MaxGrenades}");
   ```

2. **GDScript player.gd log line** (line 276):
   ```gdscript
   FileLogger.info("[Player] Ready! Ammo: %d/%d, Grenades: %d/%d, Health: %d/%d" % [...])
   ```

3. The user's log showed:
   - NO `[Player] Detecting weapon pose...` messages
   - NO `[Player] Detected weapon: Mini UZI...` messages
   - NO `[Player] Applied SMG arm pose...` messages

   These messages would appear if the weapon detection code was running, but **the C# Player.cs had no such code at all**.

### The Real Root Cause

The codebase has TWO independent player implementations:
1. **GDScript**: `scripts/characters/player.gd` + `scenes/characters/Player.tscn`
2. **C#**: `Scripts/Characters/Player.cs` + `scenes/characters/csharp/Player.tscn`

All previous fixes were applied to the **GDScript version**, but the user is using the **C# version**, which was completely missing:
- WeaponType enum
- Weapon detection logic
- Arm position offset application

### Files and Scene Paths
| Implementation | Script | Scene |
|----------------|--------|-------|
| GDScript | `scripts/characters/player.gd` | `scenes/characters/Player.tscn` |
| C# | `Scripts/Characters/Player.cs` | `scenes/characters/csharp/Player.tscn` |

### Fix Applied

Added the complete weapon pose detection system to `Player.cs`:

```csharp
#region Weapon Pose Detection

private enum WeaponType
{
    Rifle,      // Default - extended grip (e.g., AssaultRifle)
    SMG,        // Compact grip (e.g., MiniUzi)
    Shotgun     // Similar to rifle but slightly tighter
}

private WeaponType _currentWeaponType = WeaponType.Rifle;
private bool _weaponPoseApplied = false;
private int _weaponDetectFrameCount = 0;
private const int WeaponDetectWaitFrames = 3;

private static readonly Vector2 SmgLeftArmOffset = new Vector2(-10, 0);
private static readonly Vector2 SmgRightArmOffset = new Vector2(3, 0);

#endregion
```

Detection is triggered from `_PhysicsProcess()` after waiting 3 frames, identical to the GDScript approach.

### Lesson Learned

When a codebase has multiple implementations (GDScript + C#) of the same component:
1. Always identify WHICH implementation the user is using before applying fixes
2. Check log message formats to identify the running version
3. Apply fixes to ALL implementations, or clearly document which version is being fixed
