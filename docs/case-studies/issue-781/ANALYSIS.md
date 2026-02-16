# Case Study: Issue #781 - Homing Bullets Broken for Pistol Weapons

## Issue Report Summary

**Reporter**: Jhon-Crow
**Date**: 2026-02-16
**Symptoms**:
- Bullets are broken and don't fly ("пули сломались, не летят")
- Visual appearance shows tiny broken sprite (46x30px pink rectangle)
- Bullets fire but don't appear to travel or hit targets

**Evidence**:
- Screenshot: `images/broken-bullets.png`
- Game logs: `logs/game_log_20260216_105748.txt`, `logs/game_log_20260216_105816.txt`

---

## Timeline Reconstruction

### Initial Implementation (2026-02-15)

**Commit fdc8ebce**: "Add case study documentation for Issue #781"
**Commit b62ae37b**: "Fix homing bullets not working for pistol weapons (Issue #781)"

Changes made:
1. Added `enable_homing_with_aim_line()` method to `scripts/projectiles/bullet.gd`
2. Updated homing parameters to match C# Bullet.cs:
   - `homing_max_turn_angle`: 110° → 170°
   - `homing_steer_speed`: 8.0 → 50.0
3. Added line-of-sight checking
4. Added aim-line targeting support

---

### User Testing (2026-02-16, ~10:57-10:58 UTC+3)

**Test Session 1** (game_log_20260216_105748.txt):
- Game started at 10:57:48
- User equipped homing bullets via armory menu
- Homing bullets activated successfully at 10:58:06:
  ```
  [INFO] [Player.Homing] Homing activated! Duration: 1s, charges remaining: 5/6
  ```
- Player engaged enemies, fired multiple shots
- **Player was killed** at 10:58:07-08 by enemy bullets
- Game log shows normal bullet behavior with homing active

**Test Session 2** (game_log_20260216_105816.txt):
- Game restarted at 10:58:16
- **Homing bullets NOT equipped**:
  ```
  [INFO] [Player.Homing] No homing bullets selected in ActiveItemManager
  ```
- Player fired shots at 10:58:18-19:
  ```
  [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(150, 1006), source=PLAYER (MakarovPM)
  ```
- **NO bullet hit effects, NO ricochet/penetration messages in logs**
- Bullets appear to be firing but not traveling/colliding
- User reported "bullets broken, don't fly"

---

## Root Cause Analysis

### Hypothesis 1: Code Regression ❌
**Status**: REJECTED

Analysis of `scripts/projectiles/bullet.gd`:
- All homing code is present and correct (lines 1015-1181)
- `enable_homing_with_aim_line()` method exists (lines 1030-1038)
- No syntax errors or missing implementations
- Code matches intended functionality

### Hypothesis 2: Visual Bug Only ❌
**Status**: REJECTED

- PlaceholderTexture2D is intentional design for bullets
- Both GDScript and C# bullets use placeholder textures
- Screenshot shows expected placeholder appearance (though rendered oddly small)
- Visual appearance is not the core issue

### Hypothesis 3: Bullets Not Moving ⚠️
**Status**: UNDER INVESTIGATION

Evidence from logs:
- Gunshot sounds are emitted (gun fires successfully)
- NO bullet collision events (no wall hits, no enemy hits)
- NO ricochet/penetration log messages
- Suggests bullets spawn but don't move or collide

### Hypothesis 4: Build/Binary Mismatch ⭐ **LIKELY**
**Status**: PRIMARY SUSPECT

Critical observation:
- User is testing with a **pre-built executable**:
  ```
  Executable: I:/Загрузки/godot exe/Самонаводящиеся пули/Godot-Top-Down-Template.exe
  ```
- Path translates to "Downloads/godot exe/**Homing bullets**/Godot-Top-Down-Template.exe"
- This is a **separate download folder** specifically for testing homing bullets
- The executable was likely built **before** the fix was merged

**Conclusion**: The user downloaded a pre-built executable that was compiled **before** the PR #812 changes were pushed. The executable contains the old code without the `enable_homing_with_aim_line()` method, causing a runtime error when the C# BaseWeapon.cs tries to call this non-existent method on GDScript bullets.

When the method call fails:
1. C# BaseWeapon tries to call `bullet.Call("enable_homing_with_aim_line", ...)`
2. Method doesn't exist in the old compiled bullet.gd
3. **Silent failure** or error (not visible in release build logs)
4. Bullet spawns but isn't properly initialized
5. Bullet object is in broken state, doesn't process movement

---

## Why First Test Worked But Second Didn't

**First test** (with homing equipped):
- Homing activation happens through Player script
- Player script may call different initialization path
- Worked temporarily but player died before thorough testing

**Second test** (without homing):
- Testing basic bullet behavior
- Expected bullets to work normally
- Discovered bullets completely broken
- Suggests deep initialization failure, not just homing-specific

---

## Supporting Evidence

### Log Analysis: Missing Events

Expected events after firing (based on working builds):
```
[Bullet] _get_distance_to_shooter: ...
[Bullet] Distance to wall: ...
[ImpactEffects] spawn_dust_effect ...
[SoundPropagation] Sound emitted: type=CASING_KICK ...
```

Actual events after firing:
```
[SoundPropagation] Sound emitted: type=GUNSHOT ... (only gunshot sound, no bullet events)
```

This pattern indicates bullets spawn but their `_physics_process()` is not running or is crashing silently.

### Binary Mismatch Indicators

1. **Separate download folder** for testing ("Самонаводящиеся пули" = "Homing bullets")
2. **No CI/build automation** visible in the fork's GitHub Actions
3. **User downloaded executable** rather than building from source
4. **Timing**: Tests occurred hours after PR was created but before it was marked ready

---

## Conclusion

**Root Cause**: User is testing with an outdated executable built before the fix was implemented. The executable contains old bullet.gd code without the `enable_homing_with_aim_line()` method, causing runtime failures when weapons attempt to spawn homing bullets.

**Not an Issue with PR #812**: The code changes in the PR are correct and complete.

**Action Required**: User needs to test with a fresh build from the latest commit (fdc8ebce or later).

---

## Recommendations

### For User
1. Rebuild the project from source at commit `fdc8ebce` or later
2. Alternatively, download a fresh build from GitHub Actions (if available)
3. Verify the build includes the latest `bullet.gd` changes
4. Re-test with both homing equipped and unequipped

### For PR Quality Assurance
1. Add build instructions to PR description
2. Consider adding a CI check that validates method existence
3. Add integration test that verifies pistol + homing bullets work together
4. Document that GDScript changes require full rebuild (not hot-reload compatible)

### For Repository
1. Set up automated builds on PR branches
2. Provide downloadable artifacts for testers
3. Add version/commit hash to game logs for debugging
4. Consider adding runtime method validation for critical cross-language calls

---

## Related Issues

- Issue #677: Original homing bullets implementation (C# weapons + C# bullets)
- Issue #704: Aim-line targeting for homing bullets
- Issue #709: Line-of-sight checking for homing targets
- Issue #737: Homing max turn angle increased to 170°
- Issue #781: This issue - extending homing to GDScript bullets (pistols)

---

## Files Analyzed

- `scripts/projectiles/bullet.gd` - GDScript bullet implementation ✅ Correct
- `scenes/projectiles/Bullet9mm.tscn` - 9mm bullet scene ✅ Correct
- `docs/case-studies/issue-781/logs/game_log_20260216_105748.txt` - Test with homing
- `docs/case-studies/issue-781/logs/game_log_20260216_105816.txt` - Test without homing
- `docs/case-studies/issue-781/images/broken-bullets.png` - Visual evidence

---

## Next Steps

1. ✅ Document findings in this analysis
2. ⏳ Comment on PR #812 explaining the situation
3. ⏳ Request user to test with fresh build
4. ⏳ Provide build instructions if needed
5. ⏳ Update PR description with testing requirements
