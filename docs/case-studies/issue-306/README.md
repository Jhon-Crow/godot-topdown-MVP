# Case Study: Issue #306 - Add Realistic Field of View for Enemies

## Issue Summary

Issue #306 requested adding a realistic field of view (FOV) limitation for enemies. The original issue title is in Russian: "добавить реалистичный угол зрения врагам" (add realistic field of view to enemies).

The issue referenced PR #156 which contained a comprehensive FOV implementation that should be analyzed and integrated.

## Timeline of Events

### Development Timeline

**January 24, 2026**

1. **~18:30 UTC** - Issue #306 created requesting FOV feature from PR #156
2. **~19:32 UTC** - Initial PR #325 submitted with FOV implementation
3. **~19:32 UTC** - CI checks completed:
   - 5 checks passed (Windows Export, C# Build, Interop, Gameplay, Unit Tests)
   - 1 check **FAILED**: Architecture Best Practices (enemy.gd exceeds 5000 lines)
4. **~20:38 UTC** - User reports: "враги опять полностью сломались" (enemies are completely broken again)
5. **~20:39 UTC** - Work session started to investigate and fix

### Root Cause Analysis

#### Problem 1: CI Failure - File Size Limit Exceeded

**What happened:**
- `scripts/objects/enemy.gd` on main branch: 4995 lines
- Our FOV changes added net 5 lines → 5000 lines (at limit)
- Main branch added 3 more lines (reload sound) → merge would create 5003 lines
- CI limit is 5000 lines maximum

**Evidence from CI logs:**
```
##[error]Script exceeds 5000 lines (5003 lines). Refactoring required.
Found 1 script(s) exceeding line limit.
```

#### Problem 2: Enemies "Completely Broken"

**Root Cause: Slow Rotation Speed**

The FOV implementation introduced a fundamental change to enemy rotation behavior:

| Behavior | Original Code | New Code |
|----------|--------------|----------|
| Rotation | **Instant** (`global_rotation = target_angle`) | **Slow interpolation** (3.0 rad/s) |
| Time for 180° turn | 0 frames | ~1 second |
| Combat responsiveness | Immediate | Significantly delayed |

**Code comparison:**

*Original (`_update_enemy_model_rotation` in upstream/main):*
```gdscript
# INSTANT rotation - enemies immediately face the player
_enemy_model.global_rotation = target_angle
```

*New (PR #325):*
```gdscript
# SLOW rotation - enemies take time to turn
const MODEL_ROTATION_SPEED: float = 3.0  # 172 deg/s
# ...
if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
    new_rotation = _target_model_rotation
elif angle_diff > 0:
    new_rotation = current_rotation + MODEL_ROTATION_SPEED * delta
else:
    new_rotation = current_rotation - MODEL_ROTATION_SPEED * delta
_enemy_model.global_rotation = new_rotation
```

**Why this breaks enemies:**
1. Enemies can't track moving players fast enough
2. The `_shoot()` function requires enemies to be aimed at the player before shooting
3. With 3.0 rad/s rotation, enemies fall behind and may never catch up
4. In combat scenarios, enemies appear unresponsive or "frozen"

## Proposed Solution

### Fix 1: Hybrid Rotation System

**Principle:** Use instant rotation for combat, smooth rotation only for idle scanning.

```gdscript
func _update_enemy_model_rotation() -> void:
    if not _enemy_model:
        return

    var target_angle: float
    var use_smooth_rotation := false

    if _player != null and _can_see_player:
        # Combat: INSTANT rotation to face player
        target_angle = (_player.global_position - global_position).normalized().angle()
    elif velocity.length_squared() > 1.0:
        # Movement: INSTANT rotation to face movement direction
        target_angle = velocity.normalized().angle()
    elif _current_state == AIState.IDLE and _idle_scan_targets.size() > 0:
        # Idle scanning: SMOOTH rotation for realistic head turning
        target_angle = _idle_scan_targets[_idle_scan_target_index]
        use_smooth_rotation = true
    else:
        return

    if use_smooth_rotation:
        # Apply smooth rotation for scanning
        var delta := get_physics_process_delta_time()
        var current_rotation := _enemy_model.global_rotation
        var angle_diff := wrapf(target_angle - current_rotation, -PI, PI)
        if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
            _enemy_model.global_rotation = target_angle
        elif angle_diff > 0:
            _enemy_model.global_rotation = current_rotation + MODEL_ROTATION_SPEED * delta
        else:
            _enemy_model.global_rotation = current_rotation - MODEL_ROTATION_SPEED * delta
    else:
        # Instant rotation for combat/movement
        _enemy_model.global_rotation = target_angle

    # Handle sprite flipping (same for both modes)
    var aiming_left := absf(_enemy_model.global_rotation) > PI / 2
    if aiming_left:
        _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
    else:
        _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

### Fix 2: Reduce File Size

To stay under 5000 lines after merging with main (which adds 3 lines), we need to remove at least 8 lines. Options:
1. Remove redundant comments (already done - reduced by ~140 lines)
2. Condense empty lines between functions
3. Remove unused variables/constants if any exist

## Technical Implementation Details

### FOV System (Working Correctly)

The FOV feature itself is correctly implemented:

| Component | Status |
|-----------|--------|
| FOV angle calculation | ✓ Correct (dot product method) |
| Experimental settings toggle | ✓ Correct (disabled by default) |
| FOV cone visualization | ✓ Correct (F7 debug) |
| Settings persistence | ✓ Correct (ConfigFile) |

### IDLE Scanning (Working Correctly)

The passage detection and scanning system works:

| Component | Status |
|-----------|--------|
| Passage detection (raycasts) | ✓ Correct |
| Cluster angle averaging | ✓ Correct |
| 10-second scan interval | ✓ Correct |

### Files Changed

| File | Changes Made |
|------|-------------|
| `scripts/autoload/experimental_settings.gd` | NEW - Experimental settings manager |
| `scripts/ui/experimental_menu.gd` | NEW - Menu UI |
| `scenes/ui/ExperimentalMenu.tscn` | NEW - Menu scene |
| `scenes/ui/PauseMenu.tscn` | Added Experimental button |
| `scripts/ui/pause_menu.gd` | Handle Experimental menu |
| `scripts/objects/enemy.gd` | FOV + rotation + scanning |
| `project.godot` | ExperimentalSettings autoload |

## Logs and Artifacts

All logs are stored in `./docs/case-studies/issue-306/logs/`:

| File | Description |
|------|-------------|
| `solution-draft-log.txt` | Complete AI solution draft execution trace |
| `pr-156-diff.txt` | Full diff from reference PR #156 |
| `ci-failure-21320447773.log` | CI failure log showing line count error |

## How to Use FOV Feature (After Fix)

1. Press **Esc** during gameplay to open Pause Menu
2. Select **Experimental** button
3. Enable **Enemy FOV Limitation** checkbox
4. Resume game - enemies now have 100 degree vision
5. Press **F7** to visualize FOV cones:
   - **Green cone** = FOV active (100 degree vision)
   - **Gray cone** = FOV disabled (360 degree vision)

## Problem 3: "Still Not Working" - Zero Enemies Detected (RESOLVED)

### User Report (20:49 UTC):
> "всё ещё не работает" (still not working)
> Attached log: `game_log_20260124_234911.txt`

### Log Analysis:
```
[ScoreManager] Level started with 0 enemies
[SoundPropagation] Sound emitted: listeners=0
```

### Root Cause Found: GDScript Type Inference Error

**Discovery Method:** Analyzed CI import logs which revealed a parse error:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "global_fov_enabled" variable
because the value doesn't have a set type.
           at: GDScript::reload (res://scripts/objects/enemy.gd:3638)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

**Problematic Code (line 3638):**
```gdscript
var global_fov_enabled := experimental_settings and experimental_settings.has_method("is_fov_enabled") and experimental_settings.is_fov_enabled()
```

**Why It Failed:**
- GDScript's `:=` operator requires type inference
- The chained `and` expression with a nullable object check is ambiguous:
  - If `experimental_settings` is `null`, the expression returns `null` (falsy)
  - If truthy, it returns the result of `is_fov_enabled()` (bool)
- GDScript cannot determine a consistent type from this ambiguous expression

**The Fix (commit 3d26a88):**
```gdscript
var global_fov_enabled: bool = experimental_settings != null and experimental_settings.has_method("is_fov_enabled") and experimental_settings.is_fov_enabled()
```

Changes made:
1. Explicit `bool` type declaration instead of inference (`:=` → `: bool =`)
2. Changed `experimental_settings` → `experimental_settings != null` for explicit null check

**Result:**
- All 6 CI checks now pass
- enemy.gd script loads correctly
- Enemies are detected and tracked properly (10 enemies as expected)

### Why This Error Wasn't Caught Earlier

| Check | What It Tests | Why It Missed This |
|-------|---------------|-------------------|
| C# Build | Compiles C# code only | GDScript not evaluated |
| Interop Check | C#/GDScript interface compatibility | Not syntax checking |
| Gameplay Check | High-level gameplay rules | Script must load first |
| GUT Tests | Unit test execution | Tests ran before scene load |
| Architecture | Line counts, naming | Not GDScript syntax |
| Windows Export | Package creation | Export succeeded despite script error |

**Key Insight:** The GDScript parse error only manifests during Godot's scene import phase when the script is actually loaded. CI tests run in headless mode with mocked scenes, so the actual enemy.gd script was never fully loaded until runtime.

## References

- [Issue #306](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/306) - Original feature request
- [Pull Request #325](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/325) - Current implementation
- [Pull Request #156](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/156) - Reference implementation
- [Issue #66](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/66) - Related FOV request

## Problem 4: "Enemies Instantly Turn Outside FOV" (User Clarification Needed)

### User Report (21:54 UTC):
> "враги работают. враги мгновенно поворачиваются к игроку даже если он вне их поля зрения"
> (enemies work. enemies instantly turn towards the player even if he is outside their field of view)

### Log Analysis (game_log_20260125_005310.txt):

```
[ExperimentalSettings] ExperimentalSettings initialized - FOV enabled: false
[BuildingLevel] Found Environment/Enemies node with 10 children
[ScoreManager] Level started with 10 enemies
```

**Key Finding:** `FOV enabled: false`

The user tested with **FOV disabled** (default setting). This is expected behavior:

| FOV Setting | Enemy Vision | Behavior |
|-------------|--------------|----------|
| **Disabled** (default) | 360 degrees | Enemies see in all directions - instant turn is correct |
| **Enabled** | 100 degrees | Enemies only see in front cone |

### Resolution:
This is **not a bug** - it's expected default behavior. User needs to:
1. Press **Esc** → **Experimental** → Enable **Enemy FOV Limitation**
2. Then test again with FOV active

### Why FOV is Disabled by Default:

The FOV feature is experimental and disabled by default for several reasons:
1. **Backwards compatibility** - Existing gameplay behavior preserved
2. **Difficulty change** - Limited FOV significantly reduces game difficulty
3. **Testing period** - Feature needs validation before becoming default

## Merge Conflict Resolution (January 24, 2026 ~22:00 UTC)

### Conflict Source:
Upstream main added new features (Issue #322 - SEARCHING state) that conflicted with our FOV changes in enemy.gd.

### Resolution:
- ✅ Merged upstream/main successfully
- ✅ Preserved all FOV features from this branch
- ✅ Integrated new SEARCHING state from upstream
- ✅ Combined improved code comments from both branches

### Files Modified:
- `scripts/objects/enemy.gd` - Major merge (4993 lines after merge)
- Various CI workflow files and case study documents from upstream

## Status: RESOLVED (AWAITING USER CONFIRMATION)

All technical issues have been identified and fixed:

| Problem | Root Cause | Fix | Status |
|---------|------------|-----|--------|
| CI failure | enemy.gd > 5000 lines | Removed redundant comments/spacing | ✓ Fixed |
| Enemies broken | Slow rotation for all modes | Hybrid: instant for combat, smooth for idle | ✓ Fixed |
| 0 enemies detected | GDScript type inference error | Explicit `bool` type declaration | ✓ Fixed |
| Merge conflicts | Upstream changes | Resolved all conflicts manually | ✓ Fixed |
| "Instant turn" report | FOV was disabled | User education (enable FOV to test) | ⏳ Awaiting |

**Latest Commit:** `6f755be` - Merge upstream/main and resolve conflicts
**Ready for Testing:** Download latest Windows build from [GitHub Actions](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-306-47b23d61f66b)

### Testing Instructions:

1. **Download new build** from GitHub Actions (after CI completes)
2. **Enable FOV:**
   - Press **Esc** to open Pause Menu
   - Click **Experimental**
   - Check **Enemy FOV Limitation**
   - Click **Back**
3. **Verify FOV works:**
   - Press **F7** to see green vision cones
   - Approach enemies from behind - they should NOT see you
   - Walk into their vision cone - they SHOULD detect you

---

**Document Version**: 4.0
**Last Updated**: 2026-01-24
**Updated By**: AI Issue Solver (Claude Code)
