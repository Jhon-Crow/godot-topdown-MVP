# Case Study: Issue #247 - Grenade Trajectory Debug Visualization Not Working

## Issue Description
**Issue**: [#247](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/247) - Add grenade throw trajectory debug visualization

**Problem Reported**: The trajectory visualization does not work ("не работает" / "doesn't work"). The user suspected a language conflict with C#.

## Timeline of Events

1. **Initial Request**: User requested grenade throw trajectory debug visualization during drag-and-drop aiming when debug mode (F7) is enabled.

2. **First Implementation** (PR #248): Trajectory visualization code was added to `scripts/characters/player.gd` (GDScript version).

3. **User Testing**: User tested the build and reported it doesn't work, suspecting C# language conflict.

4. **Investigation**: Analysis of logs and codebase revealed the root cause.

## Root Cause Analysis

### Finding: Wrong Player Script Modified

The project has **dual implementations** of the Player character:

| Version | Scene File | Script File |
|---------|------------|-------------|
| GDScript | `scenes/characters/Player.tscn` | `scripts/characters/player.gd` |
| C# | `scenes/characters/csharp/Player.tscn` | `Scripts/Characters/Player.cs` |

**The user is using the C# version** of the game:
- `scenes/levels/csharp/TestTier.tscn` references `res://scenes/characters/csharp/Player.tscn`
- This loads `Scripts/Characters/Player.cs` as the player script

**The trajectory visualization was only added to** `scripts/characters/player.gd` (GDScript), which is **not used** by the C# levels.

### Why Logs Showed Debug Toggle Working

From `game_log_20260122_153200.txt`:
```
[15:32:05] [INFO] [GameManager] Debug mode toggled: ON
[15:32:19] [INFO] [GameManager] Debug mode toggled: OFF
[15:32:20] [INFO] [GameManager] Debug mode toggled: ON
```

The F7 debug toggle works because:
- `GameManager` is a GDScript autoload (`scripts/autoload/game_manager.gd`)
- It handles the F7 key input and emits `debug_mode_toggled` signal
- Both GDScript and C# can receive this signal

However, the C# Player.cs was never modified to:
1. Listen for the `debug_mode_toggled` signal
2. Implement the `_Draw()` override for trajectory visualization

### Signal Interop Between GDScript and C#

Godot supports cross-language signal connections, but:
- The C# Player class must explicitly connect to the signal
- C# uses `_Draw()` method override (not `_draw()` like GDScript)
- The signal connection syntax differs in C#

## Technical Details

### GDScript Implementation (in player.gd)
```gdscript
func _connect_debug_mode_signal() -> void:
    var game_manager = get_node_or_null("/root/GameManager")
    if game_manager:
        if game_manager.has_signal("debug_mode_toggled"):
            game_manager.debug_mode_toggled.connect(_on_debug_mode_toggled)

func _draw() -> void:
    if not _debug_mode_enabled:
        return
    if _grenade_state != GrenadeState.AIMING:
        return
    # ... drawing code
```

### Required C# Implementation (in Player.cs)
```csharp
private bool _debugModeEnabled = false;

private void ConnectDebugModeSignal()
{
    var gameManager = GetNodeOrNull<Node>("/root/GameManager");
    if (gameManager != null && gameManager.HasSignal("debug_mode_toggled"))
    {
        gameManager.Connect("debug_mode_toggled", Callable.From<bool>(OnDebugModeToggled));
    }
}

private void OnDebugModeToggled(bool enabled)
{
    _debugModeEnabled = enabled;
    QueueRedraw();
}

public override void _Draw()
{
    if (!_debugModeEnabled) return;
    if (_grenadeState != GrenadeState.Aiming) return;
    // ... drawing code
}
```

## Solution

The fix requires implementing the trajectory visualization directly in the C# Player class (`Scripts/Characters/Player.cs`) since that's what the C# game version uses.

## Lessons Learned

1. **Check which script version is actually used**: In mixed-language Godot projects, always verify which version of a component is loaded by examining scene files.

2. **Log analysis is valuable**: The logs showed debug mode was toggling correctly, which narrowed down the problem to the Player script rather than GameManager.

3. **User intuition was correct**: The user correctly suspected a "language conflict" - though it wasn't a technical interop issue, it was that the wrong language version was modified.

## Files Referenced

- `game_log_20260122_153200.txt` - User's game log showing F7 toggle working
- `scripts/characters/player.gd` - GDScript Player (trajectory code added here)
- `Scripts/Characters/Player.cs` - C# Player (needs trajectory code added)
- `scenes/characters/csharp/Player.tscn` - C# Player scene (used by the game)
- `scenes/levels/csharp/TestTier.tscn` - Tutorial level (uses C# Player)
