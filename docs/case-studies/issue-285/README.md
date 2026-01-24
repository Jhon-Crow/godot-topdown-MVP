# Case Study: Issue #285 - Casing Refinements

## Overview

This case study documents the implementation of refinements to the bullet casing system that was introduced in PR #275. The issue requested three specific improvements to the casing behavior:

1. Reduce casing dimensions (2x smaller width, 10% smaller length)
2. Make the casing ejection animation faster
3. Delay shotgun casing ejection until after cocking the bolt (pump up action)

## Timeline of Events

### 2026-01-23 22:38 UTC - PR #275 Merged
- PR #275 introduced bullet casing ejection for all weapons
- Casings were spawned immediately upon firing
- Three caliber-specific sprites created:
  - Rifle: 8x16 px (brass/gold)
  - Pistol: 8x12 px (silver)
  - Shotgun: 10x20 px (red shell)
- Ejection speed: 150-250 pixels/sec
- All weapons ejected casings immediately when firing

### 2026-01-23 (shortly after merge) - Issue #285 Created
User feedback identified three areas for improvement:
1. Casings too large visually
2. Ejection animation too slow
3. Shotgun casing timing unrealistic (should eject during pump action, not on firing)

## Root Cause Analysis

### Issue 1: Casing Dimensions Too Large
**Root Cause:** Initial sprite sizes were chosen for visibility but appeared oversized in gameplay.

**Analysis:**
- Original dimensions were determined empirically during PR #275 development
- No reference to real-world scale or existing game assets
- User feedback indicated they were visually distracting

**Evidence:**
- User specifically requested "2x smaller width, 10% smaller length"
- Current sprites: Rifle 8x16, Pistol 8x12, Shotgun 10x20

### Issue 2: Ejection Animation Too Slow
**Root Cause:** Conservative ejection velocity range (150-250 px/sec) made the motion feel sluggish.

**Analysis:**
From `Scripts/AbstractClasses/BaseWeapon.cs:423`:
```csharp
float ejectionSpeed = (float)GD.RandRange(150.0f, 250.0f);
```

This low speed combined with the auto-land timer (2 seconds) made casings appear to float rather than being forcefully ejected.

**Evidence:**
- `scripts/effects/casing.gd:24`: `const AUTO_LAND_TIME: float = 2.0`
- Low initial velocity means casings take longer to reach their final position
- Linear damping of 3.0 slows them down quickly

### Issue 3: Shotgun Casing Timing Unrealistic
**Root Cause:** All weapons used the same `SpawnCasing()` call in `BaseWeapon.Fire()`, but shotguns work differently.

**Analysis:**
Real shotgun mechanics:
1. Fire shot (shell remains in chamber)
2. Pump action UP - extracts spent shell
3. Pump action DOWN - chambers new round

Current implementation (before fix):
1. Fire shot → casing spawned immediately
2. Pump action UP - no casing
3. Pump action DOWN - chamber round

**Evidence:**
From `Scripts/Weapons/Shotgun.cs:1201` (before fix):
```csharp
// Fire all pellets
FirePelletsAsCloud(fireDirection, pelletCount, spreadRadians, halfSpread, projectileScene);

// Spawn casing
SpawnCasing(fireDirection, WeaponData?.Caliber);  // ❌ Wrong timing!

// Set action state - needs manual pump cycling
ActionState = ShotgunActionState.NeedsPumpUp;
```

The casing was spawned before the pump action, but mechanically it should be spawned during the pump up action.

From `Scripts/Weapons/Shotgun.cs:838-847` (pump up action handler):
```csharp
case ShotgunActionState.NeedsPumpUp:
    if (isDragUp)
    {
        // Eject spent shell (pull pump back/up)
        ActionState = ShotgunActionState.NeedsPumpDown;
        PlayPumpUpSound();
        // ❌ No casing spawn here!
    }
```

## Solution Implementation

### Fix 1: Reduce Casing Dimensions

**Changes:**
1. Resized sprite files using ImageMagick:
   - Rifle: 8x16 → 4x14 (50% width, 87.5% length)
   - Pistol: 8x12 → 4x11 (50% width, 91.7% length)
   - Shotgun: 10x20 → 5x18 (50% width, 90% length)

2. Updated collision shape in `scenes/effects/Casing.tscn`:
   ```diff
   - size = Vector2(8, 16)
   + size = Vector2(4, 14)
   ```
   (Note: This uses rifle dimensions as the default; GDScript sets specific shapes per caliber)

**Commands Used:**
```bash
convert casing_rifle.png -resize 4x14! -filter point casing_rifle.png
convert casing_pistol.png -resize 4x11! -filter point casing_pistol.png
convert casing_shotgun.png -resize 5x18! -filter point casing_shotgun.png
```

**Rationale:**
- `-filter point` preserves pixel art style (no interpolation blur)
- Exact 50% width reduction as requested
- ~90% length (close to 10% reduction as requested)

### Fix 2: Increase Ejection Speed

**Changes:**
Modified `Scripts/AbstractClasses/BaseWeapon.cs:423-425`:
```diff
- float ejectionSpeed = (float)GD.RandRange(150.0f, 250.0f); // Random speed between 150-250 pixels/sec
+ float ejectionSpeed = (float)GD.RandRange(300.0f, 450.0f); // Random speed between 300-450 pixels/sec (2x faster)
```

**Rationale:**
- Doubled the speed range (2x faster)
- Maintains randomness for variation
- Creates more realistic "forceful ejection" feel
- Casings still land naturally due to linear damping (3.0)

### Fix 3: Delay Shotgun Casing Ejection

**Changes:**

1. Added field to store fire direction in `Scripts/Weapons/Shotgun.cs`:
   ```csharp
   /// <summary>
   /// Last fire direction (used to eject casing after pump up).
   /// </summary>
   private Vector2 _lastFireDirection = Vector2.Right;
   ```

2. Modified firing to store direction instead of spawning casing:
   ```diff
   + // Store fire direction for casing ejection after pump up
   + _lastFireDirection = fireDirection;

   - // Spawn casing
   - SpawnCasing(fireDirection, WeaponData?.Caliber);
   + // NOTE: Casing is NOT spawned here for shotgun - it's ejected during pump up action
   ```

3. Added casing spawn to pump up action handler (two locations):

   a) Normal drag gesture (`ProcessPumpActionGesture()`):
   ```diff
    case ShotgunActionState.NeedsPumpUp:
        if (isDragUp)
        {
            ActionState = ShotgunActionState.NeedsPumpDown;
            PlayPumpUpSound();
   +
   +        // Spawn casing when pump is pulled back (Issue #285)
   +        SpawnCasing(_lastFireDirection, WeaponData?.Caliber);
   ```

   b) Mid-drag gesture (`TryProcessMidDragGesture()`):
   ```diff
    case ShotgunActionState.NeedsPumpUp:
        if (isDragUp)
        {
            ActionState = ShotgunActionState.NeedsPumpDown;
            PlayPumpUpSound();
   +
   +        // Spawn casing when pump is pulled back (Issue #285)
   +        SpawnCasing(_lastFireDirection, WeaponData?.Caliber);
   ```

**Rationale:**
- Matches real shotgun mechanics (casing extracts during pump back)
- Uses stored direction since player aim may have changed between fire and pump
- Handles both regular drag and mid-drag gestures (shotgun has complex input system)
- Maintains all existing behavior for other weapon types

## Verification

### Files Modified
1. `assets/sprites/effects/casing_rifle.png` - Resized to 4x14
2. `assets/sprites/effects/casing_pistol.png` - Resized to 4x11
3. `assets/sprites/effects/casing_shotgun.png` - Resized to 5x18
4. `scenes/effects/Casing.tscn` - Updated collision shape size
5. `Scripts/AbstractClasses/BaseWeapon.cs` - Increased ejection speed
6. `Scripts/Weapons/Shotgun.cs` - Delayed casing ejection to pump action

### Expected Behavior After Fix

#### For All Weapons:
- ✅ Casings appear smaller (50% width, ~10% shorter length)
- ✅ Casings eject faster (2x speed increase)
- ✅ Casings still land naturally and remain on ground

#### For Shotgun Specifically:
- ✅ Fire shot → No casing appears
- ✅ Pump RMB drag UP → Casing ejects to the right
- ✅ Pump RMB drag DOWN → Chamber next round
- ✅ Casing uses the direction from when shot was fired

#### For Other Weapons (Rifle, Pistol):
- ✅ Fire shot → Casing ejects immediately (unchanged behavior)
- ✅ No pump action required

### Testing Recommendations

1. **Visual Size Test:**
   - Fire weapons and observe casing size relative to weapons/player
   - Verify casings are noticeably smaller than before
   - Confirm they're still visible enough to see the effect

2. **Ejection Speed Test:**
   - Fire weapons and observe ejection speed
   - Verify casings move faster and feel more "snappy"
   - Confirm they still land naturally (not flying off screen)

3. **Shotgun Timing Test:**
   - Fire shotgun → verify NO casing appears
   - Drag RMB UP (pump action) → verify casing ejects
   - Fire at different angles, pump at different angles → verify casing uses fire direction
   - Test both normal drag and mid-drag pump gestures

4. **Regression Test:**
   - Test rifle and pistol still eject casings immediately on fire
   - Verify all casings use correct sprites (brass, silver, red)
   - Confirm casings persist on ground (no despawn)

## Lessons Learned

### Design Insights
1. **Weapon-specific behavior requires conditional logic** - The shotgun's mechanical difference (pump action) required special handling that wasn't needed for semi-automatic weapons.

2. **User feedback on "feel" is valuable** - The technical implementation in PR #275 was correct, but the user's subjective experience (size, speed) highlighted areas for polish.

3. **Storing context for delayed actions** - The `_lastFireDirection` field demonstrates the pattern of storing state when an action will be split across multiple frames/gestures.

### Technical Patterns

1. **ImageMagick for pixel art resizing:**
   ```bash
   convert sprite.png -resize 4x14! -filter point sprite.png
   ```
   - `!` forces exact dimensions (ignores aspect ratio)
   - `-filter point` preserves hard pixel edges

2. **Override pattern for weapon-specific behavior:**
   - `BaseWeapon.SpawnCasing()` provides default behavior
   - `Shotgun.Fire()` can skip the call and defer to later
   - Same method signature, different timing

3. **State machine for complex weapons:**
   - Shotgun uses `ShotgunActionState` enum to track mechanical state
   - Each state transition can trigger appropriate effects (sound, particles, casings)
   - Multiple input paths (drag, mid-drag) converge on same state handlers

### Code Quality Notes

1. **Comments explain "why"**: Added note in Shotgun.cs explaining why casing isn't spawned in Fire()
2. **Issue references**: Marked changes with `(Issue #285)` for traceability
3. **Preserved existing behavior**: Changes only affect shotgun casing timing; all else unchanged

## Related Issues and PRs

- **PR #275** - Original casing implementation
- **Issue #262** - Context for PR #275 (the .NET assembly bug that was fixed alongside casings)
- **Issue #285** - This case study (casing refinements)

## Conclusion

All three requested improvements have been implemented:

1. ✅ **Casings reduced to 50% width, ~90% length** (2x smaller width, 10% smaller length as requested)
2. ✅ **Ejection speed doubled** (300-450 px/sec instead of 150-250 px/sec)
3. ✅ **Shotgun casing ejection delayed to pump action** (mechanically accurate timing)

The changes improve visual polish and realism while maintaining the core functionality introduced in PR #275. The shotgun-specific behavior demonstrates proper separation of concerns between the base weapon class and specialized weapon implementations.
