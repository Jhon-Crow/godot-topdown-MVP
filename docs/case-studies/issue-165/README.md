# Case Study: Issue #165 - Penultimate Hit Effect

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/165
**Pull Request:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/166
**Date:** 2026-01-21

### Original Requirements (Russian)

> когда в игрока попадают и у него остаётся 1 или менее hp - время замедляется до 0.25 и цвета на экране становится насыщеннее в 3 раза а враги в 4.

### Translated Requirements

When the player is hit and has **1 HP or less** remaining:
- Time slows down to **0.25** (25% speed)
- Screen colors become **3x more saturated**
- Enemy colors become **4x more saturated**

### Additional Requirements (from PR feedback)

User feedback on 2026-01-21T06:47:25Z added:
- "не заметил изменений" (didn't notice any changes)
- "увеличь ещё и контрастность в 2 раза" (also increase contrast by 2x)
- "эффект должен длиться 3 секунды реального времени" (effect should last 3 real seconds)

User feedback on 2026-01-21T07:01:33Z added:
- "сделай замедление времени до 0.1" (make time slowdown to 0.1)
- "как будто всё ещё не работает" (it's like it's still not working)

## Timeline of Events

### Phase 1: Initial Implementation (2026-01-21 ~06:00 UTC)

1. Created `PenultimateHitEffectsManager` autoload singleton
2. Implemented time slowdown via `Engine.time_scale = 0.25`
3. Created saturation shader (`saturation.gdshader`)
4. Added enemy saturation via sprite modulate color manipulation
5. Registered autoload in `project.godot`
6. Added "enemies" group to enemy scenes

### Phase 2: User Testing (2026-01-21 06:47 UTC)

User tested the game and reported:
- **Effect not visible** - User didn't notice any visual changes
- **Missing contrast** - Requested 2x contrast increase
- **Duration too short** - Effect should last 3 real seconds

### Phase 3: Second User Test (2026-01-21 07:01 UTC)

User tested again with updated code:
- Log file: `logs/game_log_20260121_095700.txt`
- Result: Effect still not working
- Request: Change time slowdown from 0.25 to 0.1 (10x slowdown)

### Phase 4: Third User Test (2026-01-21 07:13 UTC)

User tested again after fixes and provided two logs:
- `game_log_20260121_100848.txt`
- `game_log_20260121_101232.txt`

Both logs showed:
```
[PenultimateHit] Found player: Player (class: CharacterBody2D)
[PenultimateHit] No HealthComponent found on player
[PenultimateHit] WARNING: Could not connect to any health signal!
[PenultimateHit] Connected to player Died signal (C#)
```

Result: **Logger was working, but signal connection was failing**.

### Phase 5: Final Root Cause Analysis (2026-01-21 07:14 UTC)

#### Root Cause #1 (CRITICAL): Dynamic HealthComponent Creation

The **true** root cause was that the C# `BaseCharacter` class dynamically creates `HealthComponent` in its `_Ready()` method:

```csharp
// In BaseCharacter.cs
protected virtual void InitializeHealthComponent()
{
    HealthComponent = GetNodeOrNull<HealthComponent>("HealthComponent");

    if (HealthComponent == null)
    {
        // Create a new health component dynamically
        HealthComponent = new HealthComponent();
        AddChild(HealthComponent);  // <-- Created at runtime!
    }
}
```

The `Player.tscn` scene does NOT have a pre-existing HealthComponent node. It's created at runtime by the C# script.

**Why `get_node_or_null("HealthComponent")` fails:**
1. When GDScript calls `_player.get_node_or_null("HealthComponent")`, it looks for a child node named "HealthComponent"
2. But in C#, `HealthComponent` is a **protected property** that holds a reference to a node
3. Even though the node gets added via `AddChild()`, the timing may be off
4. Furthermore, the approach of trying to find the node was fundamentally flawed

#### Root Cause #2: Wrong Signal Strategy

The code was trying to connect to `HealthComponent.HealthChanged` signal, but:
1. The `HealthComponent` node wasn't reliably accessible
2. The better approach is to use the **Player's own `Damaged` signal** which is emitted by `BaseCharacter`:

```csharp
// BaseCharacter emits this signal directly
[Signal]
public delegate void DamagedEventHandler(float amount, float currentHealth);

protected virtual void OnHealthDamaged(float amount, float currentHealth)
{
    EmitSignal(SignalName.Damaged, amount, currentHealth);
}
```

The `Damaged` signal includes the **current health** in its parameters, which is exactly what we need!

#### Previous Issues (Now Fixed)

1. **Logger path issue** - Fixed by using `/root/FileLogger` and `log_info()`
2. **Shader range clamping** - Fixed by extending hint_range to 10.0
3. **Missing contrast effect** - Added contrast_boost parameter

## Solution Implementation

### Fix #1 (CRITICAL): Use Player's Damaged Signal

The key fix was connecting to the Player's `Damaged` signal instead of trying to find the `HealthComponent`:

```gdscript
// BEFORE (broken - HealthComponent not accessible)
_health_component = _player.get_node_or_null("HealthComponent")
if _health_component and _health_component.has_signal("HealthChanged"):
    _health_component.HealthChanged.connect(_on_player_health_changed_float)

// AFTER (working - use Player's direct signal)
if _player.has_signal("Damaged"):
    _player.Damaged.connect(_on_player_damaged)
    _log("Connected to player Damaged signal (C#)")

## Callback for Damaged signal (float amount, float currentHealth)
func _on_player_damaged(amount: float, current_health: float) -> void:
    _log("Player damaged: %.1f damage, current health: %.1f" % [amount, current_health])
    _check_penultimate_state(current_health)
```

The `Damaged` signal is emitted directly by `BaseCharacter.cs` and includes the current health, which is exactly what we need to check for penultimate hit state.

### Fix #2: Extended Shader Range

Updated `saturation.gdshader`:

```gdshader
// AFTER (fixed)
uniform float saturation_boost : hint_range(0.0, 10.0) = 0.0;
uniform float contrast_boost : hint_range(0.0, 10.0) = 0.0;
```

### Fix #3: Added Contrast Effect

Added contrast calculation to the shader:

```gdshader
// Apply contrast adjustment
float contrast_factor = 1.0 + contrast_boost;
vec3 contrasted = (saturated - 0.5) * contrast_factor + 0.5;
```

### Fix #4: Real-Time Duration

Changed from instant end to 3-second real-time duration:

```gdscript
const EFFECT_DURATION_REAL_SECONDS: float = 3.0

func _process(_delta: float) -> void:
    if _is_effect_active:
        var current_time := Time.get_ticks_msec() / 1000.0
        var elapsed_real_time := current_time - _effect_start_time
        if elapsed_real_time >= EFFECT_DURATION_REAL_SECONDS:
            _end_penultimate_effect()
```

Using `Time.get_ticks_msec()` ensures the duration is not affected by `Engine.time_scale`.

### Fix #5: Corrected Logger Path

Fixed the logger reference:

```gdscript
func _log(message: String) -> void:
    var logger: Node = get_node_or_null("/root/FileLogger")
    if logger and logger.has_method("log_info"):
        logger.log_info("[PenultimateHit] " + message)
    else:
        print("[PenultimateHit] " + message)
```

## Final Configuration

| Parameter | Value | Meaning |
|-----------|-------|---------|
| Time Scale | 0.1 | 10% speed (10x slower) |
| Saturation Boost | 2.0 | 3x saturation (1 + 2) |
| Contrast Boost | 1.0 | 2x contrast (1 + 1) |
| Enemy Saturation | 4.0 | 4x saturation multiplier |
| Duration | 3.0 | 3 real seconds |

## Files Changed

1. `scripts/shaders/saturation.gdshader` - Extended range, added contrast
2. `scripts/autoload/penultimate_hit_effects_manager.gd` - Added logging, contrast, real-time duration

## Lessons Learned

1. **Use parent class signals, not child component signals** - The most reliable way to get health updates is via `BaseCharacter.Damaged` signal (emitted by the player itself), not via `HealthComponent.HealthChanged` (which may not be accessible from GDScript)
2. **Dynamically created nodes may not be accessible** - In Godot with C# and GDScript interop, nodes created in C# `_Ready()` may not be reliably accessible from GDScript autoloads due to timing issues
3. **Check what signals the node actually has** - Use `_player.has_signal("Damaged")` to verify signal existence before connecting
4. **Verify autoload names and method signatures** - The logger issue (`Logger` vs `FileLogger`, `info()` vs `log_info()`) caused silent failures with no visible error messages
5. **Always verify shader parameter ranges** - `hint_range` in Godot shaders clamps values, even when set programmatically
6. **Add logging from the start** - Makes debugging much easier, especially for effects that users can't verbally describe
7. **Clarify duration behavior** - "Effect lasts 3 seconds" can mean game time or real time; always specify
8. **Test with extreme values** - A saturation boost of 2.0 should be visually obvious; if not, something is wrong
9. **Study existing working code** - The `HitEffectsManager` provided a working pattern for screen effects; studying it helped understand the architecture

## Related Files

- [First game log from user testing](logs/game_log_20260121_093946.txt)
- [Second game log - effect still not working](game_log_20260121_095700.txt)
- [Initial solution draft log](logs/solution-draft-log-pr-166.txt)
