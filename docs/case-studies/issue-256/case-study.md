# Case Study: Issue #256 - Grenade Throwing Physics Change Not Applied

## Summary
User reported that the velocity-based grenade throwing physics changes were not applied to the game build they tested.

## Timeline of Events

### 2026-01-22 17:46:27
- Commit `e39784b` created: "Implement realistic velocity-based grenade throwing physics"
- Changes applied to:
  - `scripts/characters/player.gd` (134 changes)
  - `scripts/projectiles/grenade_base.gd` (57 changes)
  - `scenes/projectiles/FlashbangGrenade.tscn` (+3 lines)
  - `scenes/projectiles/FragGrenade.tscn` (+3 lines)
  - `tests/unit/test_grenade_base.gd` (143 changes)

### 2026-01-22 17:48:31
- Commit `0df23ec` created: "Revert Initial commit with task details"
- Only affected `CLAUDE.md` file (7 lines removed)
- **Did NOT revert the physics implementation**

### 2026-01-22 19:59:17 - 19:59:59 (User Testing)
- User tested the game (logs show Godot 4.3-stable)
- Log evidence shows OLD system was running:

```
[19:59:37] [INFO] [Player.Grenade] Step 2 complete: G released, RMB held - now aiming, drag and release RMB to throw
[19:59:38] [INFO] [Player.Grenade] Throwing! Direction: (0.98640007, 0.1643619), Drag: 44,69977 (adjusted: 402,29794)
```

- **Expected log messages from NEW system:**
```
[Player.Grenade] Step 2 complete: G released, RMB held - now aiming (velocity-based throwing enabled)
[Player.Grenade] Velocity-based throw! Mouse velocity: ...
```

## Root Cause Analysis

### Primary Finding: Build Not Updated

The user tested with a game build that **predates commit e39784b**. Evidence:

1. **Log message comparison:**
   - Old message: `"now aiming, drag and release RMB to throw"`
   - New message: `"now aiming (velocity-based throwing enabled)"`

2. **Throwing log comparison:**
   - Old format: `"Throwing! Direction: ..., Drag: ... (adjusted: ...)"`
   - New format: `"Velocity-based throw! Mouse velocity: ..., Swing distance: ..."`

3. **Method call evidence:**
   - Old system calls: `throw_grenade(direction, drag_distance)`
   - New system calls: `throw_grenade_velocity_based(mouse_velocity, swing_distance)`

### Why the Old Build Was Used

Possible reasons:
1. **Godot project not rebuilt** - The source code was updated in the repository, but the game executable was built before the changes were committed
2. **Export not refreshed** - Godot requires explicit re-export to update the executable
3. **C# rebuild not triggered** - If C# scripts are involved, they require explicit rebuild

### Code Verification

The current repository state (commit `0df23ec`) contains all the velocity-based physics code:

```
$ grep "velocity-based throwing enabled" scripts/characters/player.gd
Line 1336: FileLogger.info("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming (velocity-based throwing enabled)")

$ grep "throw_grenade_velocity_based" scripts/projectiles/grenade_base.gd
Line 165: func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
```

## Log Files Analysis

### File: game_log_20260122_195917.txt
- Duration: 19:59:17 - 19:59:21 (4 seconds)
- No grenade throws logged
- Only game initialization

### File: game_log_20260122_195927.txt
- Duration: 19:59:27 - 19:59:59 (32 seconds)
- Multiple grenade throws logged
- All throws show OLD drag-based system:
  - Line 116: `Drag: 44,69977 (adjusted: 402,29794)`
  - Line 143: `Drag: 508,61328 (adjusted: 3840)`
  - Line 169: `Drag: 138,50829 (adjusted: 1246,5746)`
  - Line 211: `Drag: 88,34544 (adjusted: 795,109)`

## Proposed Solutions

### Immediate Fix
1. **Rebuild the game** - Export a new build from Godot editor after pulling the latest code
2. **Verify log messages** - After rebuilding, test and confirm the new log format appears:
   ```
   [Player.Grenade] Step 2 complete: G released, RMB held - now aiming (velocity-based throwing enabled)
   [Player.Grenade] Velocity-based throw! Mouse velocity: (X, Y) (Z px/s), Swing distance: N
   ```

### Debug Enhancement (Recommended)
Add more prominent debug logging at game startup to show which throwing system is active, making it immediately clear which version is running.

## Conclusion

The code changes ARE present in the repository and correctly implemented. The issue is that the user's test build was compiled before the changes were merged. A simple rebuild of the game project will resolve this issue.
