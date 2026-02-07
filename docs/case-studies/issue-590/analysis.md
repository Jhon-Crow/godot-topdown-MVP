# Issue #590: Fix Memory Replay Mode - Case Study

## Issue Summary

Three bugs reported in memory replay mode:
1. Bloody footprints from player/enemy walking not appearing during memory replay
2. Last chance and explosion effects activating unstably (turning on/off in wrong modes)
3. Player trail behind the player ghost should be 3x wider

## Timeline of Events (from game_log_20260207_172626.txt)

1. **17:26:26** - Game starts, all systems initialize (BloodyFeet, ReplayManager, effects managers)
2. **17:26:26** - Replay recording begins with 10 enemies
3. **17:26:28** - First combat: Enemy3 killed, blood effects spawn
4. **17:26:39** - LastChance effect triggers during gameplay (grenade explosion in power fantasy mode)
5. **17:26:42** - Player steps in blood, 12 footprints spawn (first batch)
6. **17:26:47** - Enemies 8, 9 step in blood
7. **17:26:49** - Player steps in blood again (second batch), Enemy7 steps in blood
8. **17:27:06** - Recording stops: 2393 frames, 36.69s, **70 footprints recorded**
9. **17:27:10** - Replay playback starts in Ghost mode
10. **17:27:11** - User switches to Memory mode
11. **17:27:21** - User sets 4x speed
12. **17:27:27** - Only 14/70 footprints spawned before user switches back to Ghost mode
13. **17:27:33** - **BUG**: During Ghost mode replay, PowerFantasy triggers LastChance grenade effect, setting all nodes to PROCESS_MODE_ALWAYS
14. **17:27:34** - User switches back to Memory mode, then immediately to Ghost mode
15. **17:28:05** - User tries Memory mode again at 4x speed, 14/70 footprints spawn
16. **17:28:08** - User switches to Ghost, then exits

## Root Cause Analysis

### Bug 1: Invisible Footprints in Memory Replay

**Root Cause**: `RecordNewFootprints()` captured position, rotation, and scale, but NOT the footprint's `Modulate` (color/alpha) or which foot type (left/right).

During replay, `SpawnFootprintsUpToTime()` instantiated the `BloodFootprint.tscn` scene but never called:
- `set_foot()` - which assigns the boot print texture (without this, the Sprite2D has NO texture = invisible)
- `set_blood_color()` - which sets the blood color tint
- `set_alpha()` - which sets the transparency

The `blood_footprint.gd` script's `_ready()` loads textures into static variables but does NOT assign any texture to `self.texture`. The texture is only assigned when `set_foot(is_left)` is called by `BloodyFeetComponent`.

**Evidence**: Log shows "Spawned 14 replay footprints" but user reported they weren't visible.

### Bug 2: Effects Activating in Wrong Replay Mode

**Root Cause**: `PlayFrameEvents()` called `TriggerReplayPowerFantasyGrenade()`, `TriggerReplayPowerFantasyKill()`, `TriggerReplayHitEffect()`, and `TriggerReplayPenultimateEffect()` regardless of the current replay mode (Ghost or Memory).

In Ghost mode (stylized red/black/white filter), these effects should NOT activate because:
- They modify Engine.TimeScale, conflicting with replay timing
- They apply visual overlays that conflict with the Ghost filter
- They modify node process modes (PROCESS_MODE_ALWAYS) on scene nodes

**Evidence**: Log at 17:27:33 shows PowerFantasy triggering LastChance during Ghost mode, setting 50+ nodes to PROCESS_MODE_ALWAYS.

### Bug 3: Player Trail Too Narrow

**Root Cause**: The player trail segment size was `Mathf.Max(2.0, 8.0 * alpha)` giving a maximum of 8px width. The issue requested 3x wider visibility.

## Fixes Applied

### Fix 1: Footprint Visibility (ReplayManager.cs)
- Added `Modulate` (Color) and `IsLeft` (bool) fields to `FootprintSnapshot`
- `RecordNewFootprints()` now captures `sprite2D.Modulate` and detects foot type from texture path
- `SpawnFootprintsUpToTime()` now calls `set_foot()`, `set_alpha()`, and `set_blood_color()` on spawned footprints
- Fallback sprites use recorded modulate color instead of hardcoded dark red

### Fix 2: Mode-Guarded Effects (ReplayManager.cs)
- Added `if (_currentMode != ReplayMode.Memory) return;` guard to:
  - `TriggerReplayHitEffect()`
  - `TriggerReplayPenultimateEffect()`
  - `TriggerReplayPowerFantasyKill()`
  - `TriggerReplayPowerFantasyGrenade()`
- Effects now only activate in Memory mode, keeping Ghost mode clean

### Fix 3: Wider Player Trail (ReplayManager.cs + replay_system.gd)
- C# ReplayManager: Player trail size changed from `Mathf.Max(2.0, 8.0 * alpha)` to `Mathf.Max(6.0, 24.0 * alpha)` (3x wider)
- GDScript replay_system.gd: Line2D trail width changed from `3.0` to `9.0` (3x wider) for consistency

## Files Changed
- `Scripts/Autoload/ReplayManager.cs` - All three fixes
- `scripts/autoload/replay_system.gd` - Trail width fix for GDScript version
