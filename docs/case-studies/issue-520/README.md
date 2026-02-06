# Case Study: Issue #520 - ASVK Sniper Rifle Scope/Aiming System

**Repository**: `Jhon-Crow/godot-topdown-MVP`
**Issue**: #520
**Pull Request**: #528
**Branch**: `issue-520-2af4a666a08c`

## Summary

Issue #520 requested adding an ASVK (ASVK) anti-materiel sniper rifle with a comprehensive scope/aiming system to a Godot top-down game. The implementation spanned multiple iterations: first the base weapon mechanics (bolt-action, penetration, tracer trail), then the scope system (RMB activation, crosshair overlay, camera offset, zoom, sway), and finally refinements based on user feedback. A key complication was the user testing an older exported build that did not contain the latest scope code, leading to "nothing changed" feedback that required log analysis to diagnose.

## Timeline of Events

### 1. Issue Created

User (Jhon-Crow) created issue #520 requesting an ASVK sniper rifle with the following specifications:

- **Caliber**: 12.7x108mm ammunition, 50 damage per shot
- **Penetration**: Passes through 2 walls and through enemies
- **Bullet speed**: Infinite (instant hit) with a smoky dissipating tracer trail
- **Handling**: Very high turn sensitivity, 5-round magazine
- **Reload**: Bolt-action charging sequence (Down -> Left -> Down -> Up arrow keys)
- **Scope system** (additional feature):
  - RMB scope with crosshair overlay
  - Camera offset beyond viewport
  - Mouse wheel zoom (1x to 3x)
  - Distance-based scope sway

### 2. First Comment from Jhon-Crow

> "сейчас реализуй основной функционал без прицеливания"
> ("For now implement the main functionality without aiming/scoping")

The base weapon was implemented first: bolt-action mechanics, penetrating bullets (SniperBullet.cs), smoky tracer trail, laser sight, sound effects, and screen shake.

### 3. Second Comment from Jhon-Crow

> "теперь выполни дополнительный пункт"
> ("Now implement the additional feature")

This triggered the scope system implementation.

### 4. PR #528 Created (Commit `9ce3def`)

The scope/aiming system was implemented with:

- **RMB scope activation** via `ActivateScope()` / `DeactivateScope()` in `SniperRifle.cs`
- **Crosshair overlay** as a `CanvasLayer` with mil-dot reticle, outer circle, and scope ring
- **Camera offset** beyond the viewport in the aim direction, scaled by zoom distance
- **Mouse wheel zoom** from 1x to 3x in 0.25x steps
- **Programmed sine-wave scope sway** that scaled with distance (`BaseScopeSwayAmplitude * effectiveZoomDistance`)
- **Input routing** in `Player.cs` to handle RMB for scope (taking priority over grenade mechanics), mouse wheel for zoom, and mouse motion for fine-tuning

### 5. First Feedback from Jhon-Crow (3 items)

1. > "в режиме прицеливания должна быть возможность немного (треть вьюпорта примерно) перемещаться дальше/ближе"

   Need ability to move approximately 1/3 viewport closer or further while scoped (mouse fine-tune for distance adjustment).

2. > "пули должны лететь в центр прицела (сейчас летят не туда)"

   Bullets should fly to the crosshair center. They were going in the wrong direction.

3. > "сделай минимальную дальность прицела ещё на пол вьюпорта дальше"

   Increase the minimum scope distance by half a viewport.

### 6. Fixes Applied (Commit `c1fa0e7`)

All 3 items were addressed in a single commit:

- **Mouse fine-tune**: Added `AdjustScopeFineTune()` method that projects mouse motion onto the aim direction to adjust scope distance by up to 1/3 viewport (`ScopeMouseFineTuneRange = 0.33f`)
- **Bullet aim to crosshair**: `GetScopeAimTarget()` was created to calculate the world-space position the crosshair is pointing at; `Player.cs` was updated to fire toward this target when scope is active
- **Minimum distance increased**: `MinScopeZoomDistance` changed from `0.5f` to `1.0f` viewport multiplier

### 7. Second Feedback from Jhon-Crow (Latest)

Three parts:

1. > "как будто ничего не изменилось"
   > ("It seems like nothing changed")

   The user attached two game log files. Analysis (see Root Cause Analysis below) revealed the user was testing an older release build that did not contain the scope code.

2. Two game log files were attached:
   - `game_log_20260207_000305.txt`
   - `game_log_20260207_000454.txt`

3. > "убери запрограммированное раскачивание прицела и сделай чтоб в режиме прицеливания была повышена чувствительность, и чем дальше прицел - тем выше"
   > ("Remove the programmed scope sway and make it so that in scope mode the sensitivity is increased, and the further the scope -- the higher the sensitivity")

   Clear design direction: replace programmed oscillation with player-driven mouse sensitivity that scales with distance.

## Root Cause Analysis

### The "Nothing Changed" Problem

The game logs provided by the user reveal a **stale build** problem. The evidence:

**Log file headers** (both files):
```
Debug build: false
Engine version: 4.3-stable (official)
Executable: I:/Загрузки/godot exe/снайперка/Godot-Top-Down-Template.exe
```

The user was running a release (non-debug) exported build from a local directory (`снайперка` = "sniper rifle" in Russian).

**Sniper rifle was selected and fired** (from `game_log_20260207_000305.txt`):
```
[00:03:11] [GameManager] Weapon selected: sniper
[00:03:31] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1229.722), source=PLAYER (SniperRifle), range=3000, listeners=30
[00:03:40] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 1250), source=PLAYER (SniperRifle), range=3000, listeners=20
```

The sniper was selected and fired 6 times in session 1 and 7 times in session 2.

**ZERO scope activation messages in both logs.** The code contains:
```csharp
GD.Print($"[SniperRifle] Scope activated. Zoom distance: {_scopeZoomDistance:F1}x");
GD.Print("[SniperRifle] Scope deactivated.");
```

These `GD.Print()` calls execute in both debug and release builds in Godot. If the scope code were present in the build, pressing RMB would produce `[SniperRifle] Scope activated` in the log. The complete absence of these messages means **the exported build predates the scope commits** (`9ce3def` and `c1fa0e7`).

### Conclusion

The user exported the game before the scope changes were committed and pushed. The "nothing changed" feedback was accurate for their build -- it literally did not contain the scope code. This is a **build verification** gap, not a code bug.

## Changes Made in Current Session

Based on the user's design feedback (remove programmed sway, add distance-based sensitivity), the following changes were made:

### 1. Removed Programmed Scope Sway

Eliminated the sine-wave oscillation system:
- Removed `BaseScopeSwayAmplitude` constant
- Removed `ScopeSwaySpeed` constant
- Removed `_scopeSwayTime` accumulator
- Removed `_scopeSwayOffset` vector
- Removed the sine/cosine sway calculation from `UpdateScope()`

The scope position is now driven entirely by player mouse input.

### 2. Added Distance-Based Mouse Sensitivity

New constant in `SniperRifle.cs`:
```csharp
private const float BaseScopeSensitivityMultiplier = 2.0f;
```

The effective sensitivity multiplier is:
```
effectiveSensitivity = BaseScopeSensitivityMultiplier * EffectiveScopeZoomDistance
```

This produces the following scaling:
| Zoom Distance | Effective Sensitivity | Feel |
|---|---|---|
| 1.0x (minimum) | 2.0x normal | Moderate amplification |
| 1.5x (default) | 3.0x normal | Comfortable for mid-range |
| 2.0x | 4.0x normal | Faster crosshair movement |
| 3.0x (maximum) | 6.0x normal | Very responsive for long range |

### 3. Crosshair Follows Mouse

The crosshair position is now driven by `_scopeMouseOffset`, which accumulates mouse movement with amplified sensitivity:

```csharp
// In AdjustScopeFineTune():
float sensitivityMultiplier = BaseScopeSensitivityMultiplier * EffectiveScopeZoomDistance;
_scopeMouseOffset += mouseMotion * sensitivityMultiplier;
```

The crosshair position in the overlay:
```csharp
// In UpdateScopeOverlayPosition():
_scopeCrosshair.Position = viewportSize / 2 + _scopeMouseOffset;
```

### 4. Bullets Aim at Actual Crosshair

`GetScopeAimTarget()` includes the mouse offset so bullets fire toward where the crosshair actually is:

```csharp
public Vector2 GetScopeAimTarget()
{
    Vector2 viewportSize = viewport.GetVisibleRect().Size;
    float baseDistance = viewportSize.Length() * 0.5f;
    Vector2 aimTarget = GlobalPosition
        + _aimDirection * baseDistance * EffectiveScopeZoomDistance
        + _scopeMouseOffset;
    return aimTarget;
}
```

In `Player.cs`, when scope is active, firing direction is calculated from the scope target:
```csharp
if (sniperRifle != null && sniperRifle.IsScopeActive)
{
    Vector2 scopeTarget = sniperRifle.GetScopeAimTarget();
    shootDirection = (scopeTarget - GlobalPosition).Normalized();
}
```

### 5. Mouse Offset is Clamped

The crosshair offset is limited to prevent it from going completely off-screen:

```csharp
_maxScopeMouseOffset = viewportSize.Length() * 0.15f * EffectiveScopeZoomDistance;
_scopeMouseOffset = _scopeMouseOffset.LimitLength(_maxScopeMouseOffset);
```

This gives 15% of viewport diagonal multiplied by zoom distance, providing a reasonable movement range that scales with zoom.

## Key Files Changed

| File | Purpose |
|---|---|
| `Scripts/Weapons/SniperRifle.cs` | Scope system logic: sway removal, sensitivity multiplier, mouse offset tracking, crosshair positioning, aim target calculation |
| `Scripts/Characters/Player.cs` | Input routing: RMB for scope activation, mouse wheel for zoom, mouse motion for `AdjustScopeFineTune()`, bullet direction override when scoped |

## Evidence from Game Logs

The game logs are preserved in the `logs/` subdirectory:

- `logs/game_log_20260207_000305.txt` -- First session (6 sniper shots, 0 scope messages)
- `logs/game_log_20260207_000454.txt` -- Second session (7 sniper shots, 0 scope messages)

Key observations from the logs:

1. **Build is release mode**: `Debug build: false` on line 8 of both logs
2. **Sniper was selected**: `[GameManager] Weapon selected: sniper` appears in both sessions
3. **Sniper was fired multiple times**: `SoundPropagation` entries show `source=PLAYER (SniperRifle)` with `range=3000`
4. **No scope messages at all**: Zero occurrences of "Scope activated", "Scope deactivated", "Scope zoom adjusted", or any scope-related log entries
5. **ASVK initialization message absent**: The code prints `[SniperRifle] ASVK initialized - bolt ready, laser sight enabled` in `_Ready()`, but this message does not appear in the logs, suggesting the C# SniperRifle class in the build is from an older version

## Lessons Learned

### 1. Build Verification is Critical

The user tested an older exported build that did not contain the latest scope changes, leading to "nothing changed" feedback that was technically correct for their binary. This wasted a feedback cycle.

**Mitigation**: A build timestamp or git commit hash displayed in the game HUD (or at minimum in the game log header) would allow both the developer and tester to immediately verify which version is being tested. For example:
```
[INFO] Build version: c1fa0e7 (2026-02-06 20:15:00 UTC)
```

### 2. Programmed Sway vs Player-Driven Sensitivity

The original implementation used sine-wave oscillation to simulate scope sway. The user's feedback was clear: they want the scope to be controlled entirely by the player's mouse input, not fighting against programmed oscillation.

**Design principle**: In action/competitive games, players prefer to control their own aim. Programmed sway feels like an artificial handicap rather than a skill-based mechanic. Distance-based sensitivity amplification (further = more responsive) feels more natural because it maps to the physical reality of small angular adjustments translating to larger positional changes at distance.

### 3. Clear Scope Feedback

The scope activation currently only shows a crosshair overlay. When the user reported "nothing changed," there was no easy way for them to confirm whether the scope was even activating.

**Improvement opportunities**:
- Audio feedback on scope activation/deactivation (scope click sound)
- Visual transition effect (brief zoom animation, vignette change)
- Persistent HUD indicator showing scope mode is active
- These would help testers quickly confirm whether a feature is working vs. simply not present in their build

### 4. Log Analysis as a Diagnostic Tool

The game's file-based logging system (`game_log_*.txt`) proved invaluable for remote debugging. By analyzing the absence of expected log messages, it was possible to diagnose the stale build problem without access to the user's machine. This underscores the importance of thorough logging at feature boundaries (activation, deactivation, state changes).

## Architecture Notes

### Scope System Data Flow

```
Player._UnhandledInput()
    |
    +-- InputEventMouseButton (RMB press)  --> SniperRifle.ActivateScope()
    +-- InputEventMouseButton (RMB release) --> SniperRifle.DeactivateScope()
    +-- InputEventMouseButton (WheelUp/Down) --> SniperRifle.AdjustScopeZoom()
    +-- InputEventMouseMotion              --> SniperRifle.AdjustScopeFineTune()
                                                 |
                                                 +-- Updates _scopeMouseFineTuneOffset (distance)
                                                 +-- Updates _scopeMouseOffset (crosshair position)

SniperRifle._Process()
    |
    +-- UpdateScope(delta)
         |
         +-- _playerCamera.Offset = GetScopeCameraOffset()
         +-- UpdateScopeOverlayPosition()
              |
              +-- _scopeCrosshair.Position = viewportCenter + _scopeMouseOffset

Player.Fire()
    |
    +-- if (sniperRifle.IsScopeActive)
         |
         +-- direction = (GetScopeAimTarget() - GlobalPosition).Normalized()
```

### Key Design Decisions

1. **RMB shared with grenades**: The sniper scope uses the same RMB input as the grenade throw system. `HandleSniperScopeInput()` in Player.cs runs first and returns `true` to consume the input, preventing grenade logic from activating when the sniper is equipped.

2. **CanvasLayer for overlay**: The scope overlay is created as a `CanvasLayer` at layer 10, ensuring it renders above the game world regardless of camera position. This avoids issues with the overlay drifting as the camera offsets during scope use.

3. **Mouse offset clamping**: The maximum crosshair drift is 15% of viewport diagonal times zoom distance. This prevents the crosshair from going completely off-screen while still allowing meaningful positional adjustment.

4. **Scope cleanup on `_ExitTree()`**: The scope overlay is removed if the weapon is removed from the scene tree (e.g., weapon swap), preventing orphaned UI elements.
