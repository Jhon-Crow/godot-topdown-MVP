# Case Study: Issue #204 - Add Shotgun Sounds

## Issue Summary
**Issue URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/204
**Title**: добавить звуки дробовику (Add shotgun sounds)
**Status**: Resolved

## Problem Statement
The shotgun weapon in the game was using placeholder M16 sounds instead of proper shotgun-specific sounds. The issue requested:
1. Random shotgun shot sounds (4 variants)
2. Action open/close sounds for pump-action mechanism
3. Shell ejection sound only after the action opens (and only if a shot was fired)

## Timeline of Events

### Initial State
- Shotgun implementation existed in `Scripts/Weapons/Shotgun.cs`
- AudioManager had no shotgun sound support
- Shotgun was using `play_m16_shot()` as a placeholder
- All shotgun sound assets were already present in `assets/audio/`

### Resolution Process
1. **Research Phase**: Analyzed codebase structure, found assault rifle as reference implementation
2. **AudioManager Update**: Added shotgun sound constants, preloading, and convenience methods
3. **Shotgun.cs Update**: Replaced placeholder sounds with proper shotgun sounds and implemented timing logic

## Root Cause Analysis

The shotgun was implemented before its sound assets were integrated into the AudioManager. The original implementation used a placeholder comment:
```csharp
// Use M16 shot as placeholder until shotgun-specific sound is added
```

This was intentional temporary code awaiting sound integration.

## Solution Details

### Files Modified

1. **scripts/autoload/audio_manager.gd**
   - Added shotgun sound constants (shots, action open/close, shell, empty click, load shell)
   - Added volume constants for shotgun sounds
   - Added preloading for all shotgun sounds
   - Added convenience methods: `play_shotgun_shot()`, `play_shotgun_action_open()`, `play_shotgun_action_close()`, `play_shell_shotgun()`, `play_shotgun_empty_click()`, `play_shotgun_load_shell()`

2. **Scripts/Weapons/Shotgun.cs**
   - Added `_hasFiredBeforeActionOpen` flag to track shot state
   - Updated `PlayShotgunSound()` to use proper shotgun shot sound
   - Added `PlayActionOpenWithShellEject()` async method with proper timing
   - Added `PlayActionCloseSound()` method
   - Updated `PlayEmptyClickSound()` to use shotgun-specific empty click

### Sound Assets Used
Located in `assets/audio/`:
- `выстрел из дробовика 1.wav` - Shotgun shot 1
- `выстрел из дробовика 2.wav` - Shotgun shot 2
- `выстрел из дробовика 3.wav` - Shotgun shot 3
- `выстрел из дробовика 4.wav` - Shotgun shot 4
- `открытие затвора дробовика.wav` - Action open
- `закрытие затвора дробовика.wav` - Action close
- `падение гильзы дробовик.mp3` - Shell ejection
- `выстрел без патронов дробовик.mp3` - Empty click
- `зарядил один патрон в дробовик.mp3` - Shell loading

### Sound Timing Sequence
When shotgun fires:
1. `0ms`: Shotgun shot sound plays immediately
2. `100ms`: Action open sound plays (pump-action pulling back)
3. `250ms`: Shell ejection sound plays (only if a shot was fired)
4. `300ms` (ActionCycleTime): Action close sound plays (pump-action pushing forward)

## Key Implementation Details

### Shell Ejection Logic
The `_hasFiredBeforeActionOpen` boolean ensures the shell casing sound only plays when:
- A shot was actually fired (not just cycling the action manually)
- The action opens after firing

This follows the real-world behavior of a pump-action shotgun where the spent shell ejects during the pump-back motion.

### Pattern Consistency
The implementation follows the existing M16/assault rifle pattern established in the codebase:
- GDScript AudioManager with pooled AudioStreamPlayer2D nodes
- C# weapon scripts calling AudioManager through node references
- Positional audio at weapon's GlobalPosition

## Testing Notes
Due to the nature of this change (audio integration), testing requires:
1. Running the game
2. Equipping the shotgun
3. Firing to hear random shot + action cycle sounds
4. Listening for shell ejection timing
5. Emptying magazine to hear empty click sound

## Lessons Learned
1. Placeholder code should be clearly documented (which it was in this case)
2. Following existing patterns (like M16 implementation) ensures consistency
3. Async sound timing can be achieved with Godot's timer signals in C#

## References
- Assault rifle sound implementation in `Scripts/Weapons/AssaultRifle.cs`
- AudioManager pattern in `scripts/autoload/audio_manager.gd`
- Original issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/204
