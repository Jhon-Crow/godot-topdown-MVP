# Case Study: Issue #225 - UZI Balance Update - Screen Shake Improvements

## Summary

This issue addresses three balance changes to the Mini UZI's screen shake/recoil system to make sustained fire feel more impactful:

1. **Increase maximum screen shake deviation by 4x**
2. **Reduce screen shake dampening during continuous burst fire**
3. **Make screen shake intensity progressively increase with consecutive shots**

## Original Issue Requirements (Russian with Translation)

> увеличь максимальное отклонение экрана при тряске в 4 раза.
> (Translation: Increase maximum screen shake deviation by 4 times)

> отдача (отклонение экрана) не должна гаситься сильно пока очередь не прервана.
> (Translation: Recoil (screen deviation) should not dampen much while burst is not interrupted)

> увеличь дальность сотрясения экрана от следующей пули должна увеличиваться.
> (Translation: Increase the range - screen shake from subsequent bullets should increase)

## Technical Analysis

### Previous Implementation

The screen shake system was implemented in PR #126 with the following characteristics:

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MAX_SHAKE_OFFSET` | 50.0 pixels | Maximum camera offset from shake |
| Recovery | Constant | Full recovery based on `recovery_time` parameter |
| Intensity | Fire-rate based | `baseIntensity / fireRate * 10.0` |

**Problem:** With high fire rate weapons like the UZI (25 shots/sec), the accumulated shake was capped quickly at 50 pixels and dampened uniformly, making sustained fire feel less impactful.

### Mini UZI Context

From `MiniUziData.tres`:
- Fire rate: 25.0 shots/sec (2.5x faster than M16)
- Screen shake intensity: 15.0
- Screen shake min recovery time: 0.15s
- Screen shake max recovery time: 0.05s

The progressive spread system (implemented in PR #219) already scales from base spread (6°) to max spread (60°) over 10 bullets. The screen shake should mirror this progression.

## Solution Implementation

### 1. Increased Maximum Shake Offset (4x)

**File:** `scripts/autoload/screen_shake_manager.gd`

```gdscript
# Before
const MAX_SHAKE_OFFSET: float = 50.0

# After
const MAX_SHAKE_OFFSET: float = 200.0
```

This allows the camera to accumulate up to 200 pixels of offset during sustained fire, creating a more dramatic recoil effect.

### 2. Burst Suppression System

**File:** `scripts/autoload/screen_shake_manager.gd`

Added a "burst suppression" mechanism that detects continuous fire and reduces recovery during the burst:

```gdscript
## Time since last shake was added (for burst suppression).
var _time_since_last_shake: float = 0.0

## Time threshold to consider burst ended (in seconds).
const BURST_END_THRESHOLD: float = 0.15

## Recovery speed multiplier during active burst (0.0 = no recovery, 1.0 = full recovery).
const BURST_RECOVERY_MULTIPLIER: float = 0.15
```

**Logic:**
- When `add_shake()` is called, `_time_since_last_shake` is reset to 0
- In `_process()`, if `_time_since_last_shake < BURST_END_THRESHOLD`, recovery is multiplied by 0.15 (85% slower)
- Once firing stops for 150ms, full recovery resumes

This means:
- While firing continuously, recoil accumulates with minimal dampening
- When burst stops, camera recovers normally

### 3. Progressive Shake Intensity

**File:** `Scripts/Weapons/MiniUzi.cs`

Modified `TriggerScreenShake()` to scale intensity based on shot count:

```csharp
// Calculate spread ratio for progressive shake (matches progressive spread system)
float spreadRatio = Mathf.Clamp((float)_shotCount / ShotsToMaxSpread, 0.0f, 1.0f);

// Progressive shake intensity: increases from base to 4x as spread increases
// At first shot (spreadRatio=0): 1.0x intensity
// At max spread (spreadRatio=1): 4.0x intensity
float shakeMultiplier = 1.0f + spreadRatio * 3.0f;
float shakeIntensity = baseShakeIntensity * shakeMultiplier;
```

**Effect:**
- Shot 1: 1.0x shake intensity
- Shot 5: 2.5x shake intensity
- Shot 10+: 4.0x shake intensity

This creates a "ramp up" effect where the first few shots have manageable recoil, but sustained fire becomes increasingly hard to control.

## Changes Summary

### Files Modified

1. **`scripts/autoload/screen_shake_manager.gd`**
   - Increased `MAX_SHAKE_OFFSET` from 50.0 to 200.0
   - Added burst detection variables (`_time_since_last_shake`, `BURST_END_THRESHOLD`, `BURST_RECOVERY_MULTIPLIER`)
   - Modified `_process()` to reduce recovery during active burst
   - Modified `add_shake()` to reset burst timer

2. **`Scripts/Weapons/MiniUzi.cs`**
   - Modified `TriggerScreenShake()` to calculate progressive shake intensity
   - Shake multiplier scales from 1.0x to 4.0x based on shot count

3. **`tests/unit/test_screen_shake_manager.gd`**
   - Updated `test_shake_max_clamp()` test to use new max offset value (200.0)

## Balance Impact

### Before
| Shot # | Spread | Shake Intensity | Recovery |
|--------|--------|-----------------|----------|
| 1 | 6° | 6.0 px | 100% |
| 5 | 33° | 6.0 px | 100% |
| 10+ | 60° | 6.0 px | 100% |
| Max accumulated | - | 50 px cap | - |

### After
| Shot # | Spread | Shake Intensity | Recovery During Burst |
|--------|--------|-----------------|----------------------|
| 1 | 6° | 6.0 px (1.0x) | 15% |
| 5 | 33° | 15.0 px (2.5x) | 15% |
| 10+ | 60° | 24.0 px (4.0x) | 15% |
| Max accumulated | - | 200 px cap | - |

## Design Rationale

1. **4x Max Offset:** Matches the 4x progressive shake multiplier, allowing full accumulation potential
2. **15% Burst Recovery:** Allows minimal correction while firing to prevent complete loss of control, but maintains significant accumulated recoil
3. **150ms Burst Threshold:** Slightly longer than UZI's fire interval (40ms at 25 shots/sec) to ensure continuous fire is detected
4. **Progressive Intensity:** Rewards controlled burst fire over spray-and-pray

## Testing Notes

The unit tests verify:
- Shake intensity calculations based on fire rate
- Recovery time interpolation based on spread ratio
- Direction calculations (shake opposite to shooting direction)
- Accumulation behavior
- Maximum offset clamping (updated to 200.0)

Gameplay testing should verify:
1. First few UZI shots have manageable recoil
2. Sustained fire accumulates significant camera offset
3. Camera maintains offset while firing continues
4. Camera recovers smoothly after burst ends
5. Other weapons (M16, Shotgun) remain balanced

## Related Issues

- Issue #218: Mini UZI implementation (established progressive spread system)
- Issue #109: Screen shake implementation (original shake system)
