# Case Study: Issue #141 - Realistic Ricochet Mechanics

## Timeline of Events

### Initial Request (Issue #141)
**Date:** 2026-01-20

The repository owner requested:
1. Add realistic ricochets (like Arma 3) to the M16-like weapon with 5.45 caliber
2. Both player and enemies should have ricochet capability
3. Design the system to be extensible for future weapons

### Initial Solution Draft
**Cost:** ~$8.79 (public pricing) / ~$6.57 (Anthropic pricing)

The initial solution implemented:
- CaliberData resource class for configurable ballistic properties
- Angle-based ricochet probability (shallow angles more likely)
- Velocity and damage reduction after ricochet
- Maximum ricochet limit (2 ricochets)
- Ricochet sound effect integration

### Owner Feedback (PR #150 Comment)
**Date:** 2026-01-20T22:41:11Z

The owner (Jhon-Crow) provided feedback in Russian:
1. "нет рикошета у оружия игрока" - No ricochet for player's weapon
2. "сделай неограниченное количество рикошетов" - Make unlimited ricochets
3. "сделай чтоб рикошеты под углами близкими к 90 градусов случались реже" - Ricochets at angles close to 90° should happen less often
4. "сделай чтоб пули после рикошета исчезали когда пролетят максимум длину вьюпорта" - Bullets should disappear after traveling max viewport length post-ricochet

### Improvement Session
**Date:** 2026-01-20T22:48Z onwards

Addressed all feedback:
1. Changed `max_ricochets` from 2 to -1 (unlimited)
2. Changed probability calculation from linear to quadratic interpolation
3. Added viewport-based lifetime for post-ricochet bullets

### Second Round of Feedback (PR #150 Comment)
**Date:** 2026-01-20T23:03:35Z

After testing, the owner reported:
1. "всё ещё не работает рикошет у оружия игрока" - Ricochet still not working for player's weapon
2. "проверь, возможно это потому что оно на C#" - Check if it's because it's C#
3. "используй случайный звук рикошета" - Use random ricochet sounds (рикошет 1-4.mp3)

### Third Round of Feedback (PR #150 Comment)
**Date:** 2026-01-20T23:19:13Z

After testing the C# implementation, the owner reported critical bugs:
1. "пуля не должна так сильно замедляться от рикошета" - Bullet should not slow down so much from ricochet
2. "при стрельбе игрока под острым углом рикошет летит обратно в игрока - это не правильно, рикошет должен работать реалистично (в сторону стрельбы)" - When player shoots at grazing angle, ricochet flies back toward player - this is wrong, ricochet should work realistically (in shooting direction)
3. "шанс рикошета у игрока работает не правильно - при стрельбе под 90 градусов - постоянные рикошета, а при стрельбе по касательной - нет (должно быть точно наоборот)" - Ricochet chance is wrong - at 90° there's constant ricochets, at grazing angles there's none (should be exactly opposite)

Attached logs:
- `game_log_20260121_021408.txt`
- `game_log_20260121_021725.txt`
- `game_log_20260121_021939.txt`

## Root Cause Analysis

### Issue 1: "No ricochet for player's weapon" - THE CRITICAL FINDING

**Investigation:** The owner's suspicion was correct! Upon deep investigation:

1. The repository has **two separate bullet implementations**:
   - `scripts/projectiles/bullet.gd` (GDScript) - Has ricochet mechanics
   - `Scripts/Projectiles/Bullet.cs` (C#) - **Did NOT have ricochet mechanics**

2. The player uses **C# weapons** (`Scripts/Weapons/AssaultRifle.cs`) which spawn **C# bullets** (`scenes/projectiles/csharp/Bullet.tscn`)

3. The ricochet mechanics were only implemented in the GDScript bullet!

**Root Cause:** The codebase uses a hybrid C#/GDScript architecture:
- Player and their weapons: C# (`Scripts/` folder, `scenes/*/csharp/` scenes)
- Enemies and their weapons: GDScript (`scripts/` folder, `scenes/*/` scenes)

The initial ricochet implementation only modified `bullet.gd`, which **enemies use**, but **not** `Bullet.cs` which **the player uses**.

**Resolution:** Port the complete ricochet mechanics from `bullet.gd` to `Bullet.cs`:
- Added all ricochet configuration constants
- Added viewport diagonal calculation
- Added post-ricochet distance tracking
- Added `TryRicochet()`, `PerformRicochet()`, and helper methods
- Integrated with AudioManager for ricochet sounds

This is a critical lesson about **dual-language codebases**: features must be implemented in BOTH languages if both are used for the same game objects.

### Issue 2: Limited Ricochets (Max 2)
**Root Cause:** The initial implementation used `max_ricochets = 2` as a reasonable default based on Arma 3 inspiration.

**Resolution:** Changed to `max_ricochets = -1` (unlimited) in both:
- `bullet.gd` DEFAULT_MAX_RICOCHETS constant
- `caliber_545x39.tres` resource file
- `caliber_data.gd` default value

### Issue 3: CRITICAL BUG - Impact Angle Calculation Inverted
**Root Cause:** The `_calculate_impact_angle()` function used `acos(dot(direction, -normal))` which calculated the angle **from the normal** instead of **from the surface plane**.

**What was happening:**
```
Perpendicular/direct hit: direction parallel to -normal → dot = 1 → acos(1) = 0°
Grazing hit: direction perpendicular to -normal → dot = 0 → acos(0) = 90°
```

But the rest of the code expected:
```
Grazing hit: 0° (high ricochet probability)
Direct hit: 90° (low/no ricochet probability)
```

This meant:
1. **Probability was completely inverted** - direct hits had high ricochet chance, grazing had none
2. **Ricochet seemed to bounce wrong** - because ricochets were happening at wrong angles

**Resolution:** Changed the formula to calculate the GRAZING angle using `asin(|dot(direction, normal)|)`:
```
Grazing hit: direction perpendicular to normal → |dot| ≈ 0 → asin(0) = 0°
Direct hit: direction parallel to normal → |dot| ≈ 1 → asin(1) = 90°
```

This critical bug was present in BOTH `bullet.gd` AND `Bullet.cs`.

### Issue 4: Velocity Loss Too High
**Root Cause:** The velocity retention was set to 60% (0.6), meaning each ricochet kept only 60% of the bullet's speed.

**Resolution:** Changed to 85% (0.85) velocity retention for a more realistic feel where bullets don't slow down as dramatically.

### Issue 5: Ricochets at 90° Angles Too Common (Linear vs Quadratic)
**Root Cause:** The original probability calculation used linear interpolation:
```
probability = base_probability * (1 - angle/max_angle)
```

At 50% of max angle, this gives 50% of base probability.

**Resolution:** Changed to quadratic interpolation:
```
probability = base_probability * (1 - angle/max_angle)²
```

At 50% of max angle, this gives only 25% of base probability, making ricochets at steeper angles significantly rarer.

### Issue 6: Post-Ricochet Bullet Lifetime
**Root Cause:** Bullets had only time-based lifetime (3 seconds), not distance-based.

**Resolution:** Added viewport-based post-ricochet lifetime:
- Calculate viewport diagonal on bullet initialization
- After each ricochet, set max travel distance based on:
  - Viewport diagonal (base distance)
  - Impact angle factor (shallow angles = longer travel)
- Track distance traveled since last ricochet
- Destroy bullet when distance exceeds calculated maximum

## Technical Implementation Details

### Files Modified (Initial Implementation)
1. `scripts/projectiles/bullet.gd` - Core ricochet mechanics (GDScript)
2. `scripts/data/caliber_data.gd` - Caliber resource class
3. `resources/calibers/caliber_545x39.tres` - 5.45x39mm caliber config
4. `tests/unit/test_ricochet.gd` - Unit tests

### Files Modified (C# Port - Second Round)
1. `Scripts/Projectiles/Bullet.cs` - Ported ricochet mechanics to C#
2. `scripts/autoload/audio_manager.gd` - Added random ricochet sound support

### Key Algorithms

#### Quadratic Probability Curve
```gdscript
var normalized_angle := impact_angle_deg / max_angle
var angle_factor := (1.0 - normalized_angle) * (1.0 - normalized_angle)
return base_probability * angle_factor
```

#### Viewport-Based Post-Ricochet Distance
```gdscript
var angle_factor := 1.0 - (impact_angle_deg / 90.0)
angle_factor = clampf(angle_factor, 0.1, 1.0)
_max_post_ricochet_distance = _viewport_diagonal * angle_factor
```

## Cost Summary

| Session | Public Pricing | Anthropic Pricing |
|---------|---------------|-------------------|
| Initial Draft | $8.79 | $6.57 |
| Auto-restart 1 | $0.69 | $0.36 |
| Final Solution | $0.69 | $0.36 |
| Improvement Session | TBD | TBD |
| **Total** | ~$10.17+ | ~$7.29+ |

## Lessons Learned

1. **CRITICAL - Dual-Language Codebases:** When a codebase uses both C# and GDScript (common in Godot), you MUST check which language is used for each game system. Features implemented in one language won't automatically work for game objects using the other language.

2. **Scene Paths Matter:** Check `scenes/*/csharp/` vs `scenes/*/` to understand which implementation a game object uses. The C# versions use different scenes with different scripts.

3. **User Reports Are Gold:** When the user suspected "maybe because it's C#", that insight led directly to the root cause. Always investigate user suspicions thoroughly.

4. **Probability Curves:** Linear interpolation for probability often doesn't feel right to users. Quadratic or exponential curves better match human perception.

5. **Distance vs Time Lifetime:** For projectiles, distance-based lifetime (especially post-collision) often makes more sense than time-based for game feel.

6. **Unlimited Options:** Sometimes "unlimited" is a better default than a specific limit, especially for features that users want to experience.

7. **CRITICAL - Verify Angle Calculations:** When working with angles in physics, be very careful about which reference frame you're using. The difference between "angle from normal" (acos) and "angle from surface" (asin/90°-acos) can completely invert your physics behavior. Always verify with concrete examples:
   - Test perpendicular case: what angle do you get?
   - Test grazing/parallel case: what angle do you get?
   - Do these match your expectations for the rest of the code?

8. **Test Physics with User Input:** Physics bugs often only manifest during actual gameplay. Unit tests may pass while the behavior is completely wrong because the test expectations were also based on the buggy mental model.

## Files Included in This Case Study

- `initial-solution-draft-log.txt` - Log from the first AI solution session
- `auto-restart-1-log.txt` - Log from the auto-restart session
- `solution-draft-final-log.txt` - Log from the final solution draft
- `logs/game_log_20260121_021408.txt` - Game log showing inverted ricochet behavior
- `logs/game_log_20260121_021725.txt` - Game log showing continued issues
- `logs/game_log_20260121_021939.txt` - Game log with additional testing
- `README.md` - This analysis document

## Key Algorithms (Corrected)

### Impact Angle Calculation (CORRECTED)
The calculation now correctly computes the GRAZING angle:

```gdscript
# OLD (BUGGY): angle from normal
var dot := direction.normalized().dot(-surface_normal.normalized())
return acos(dot)  # 0° at direct hit, 90° at grazing - WRONG!

# NEW (CORRECT): grazing angle from surface
var dot := absf(direction.normalized().dot(surface_normal.normalized()))
return asin(dot)  # 0° at grazing, 90° at direct hit - CORRECT!
```

### Velocity Retention (ADJUSTED)
```
OLD: velocity_retention = 0.6  (too aggressive, 40% speed lost)
NEW: velocity_retention = 0.85 (better feel, 15% speed lost)
```

## Fourth Round of Feedback (PR #150 Comment)
**Date:** 2026-01-20T23:33:40Z

The owner reported additional requirements:
1. "5.45 под острыми углами должен со 100% шансом рикошетить (у игрока и врагов.)" - 5.45 at sharp angles should ricochet with 100% chance (for both player and enemies)

Attached logs:
- `logs/game_log_20260121_023018.txt`
- `logs/game_log_20260121_023229.txt`

Additional feedback from comment at 2026-01-20T23:23:50Z:
- "так же рикошеты игрока должны иметь возможность наносить урон игроку" - Player ricochets should be able to damage the player

### Issue 7: Ricochet Probability Not 100% at Grazing Angles
**Root Cause:** The `base_ricochet_probability` was set to 70% (0.7), meaning even at optimal grazing angles, there was still a 30% chance of no ricochet.

**Resolution:** Changed `base_ricochet_probability` to 100% (1.0) in:
- `resources/calibers/caliber_545x39.tres`
- `scripts/data/caliber_data.gd` (default value)
- `scripts/projectiles/bullet.gd` (DEFAULT_BASE_RICOCHET_PROBABILITY)
- `Scripts/Projectiles/Bullet.cs` (BaseRicochetProbability)
- `tests/unit/test_ricochet.gd` (updated test expectations)

Now at optimal grazing angles (0°), 5.45x39mm ammunition will **always** ricochet. The quadratic curve still reduces probability at steeper angles.

### Issue 8: Player Cannot Be Damaged By Their Own Ricochets
**Root Cause:** Both bullet implementations explicitly blocked self-damage by checking if the hit target's parent matched the shooter ID:

```gdscript
# Old code (bullet.gd)
if parent and shooter_id == parent.get_instance_id():
    return  # Don't hit the shooter
```

```csharp
// Old code (Bullet.cs)
if (parent != null && ShooterId == parent.GetInstanceId())
{
    return; // Don't hit the shooter
}
```

This prevented ALL self-damage, including from ricocheted bullets, which is unrealistic.

**Resolution:** Modified both implementations to only block self-damage for **direct** shots, but allow ricocheted bullets to damage the shooter:

```gdscript
# New code (bullet.gd)
if parent and shooter_id == parent.get_instance_id() and not _has_ricocheted:
    return  # Don't hit the shooter with direct shots
```

```csharp
// New code (Bullet.cs)
if (parent != null && ShooterId == parent.GetInstanceId() && !_hasRicocheted)
{
    return; // Don't hit the shooter with direct shots
}
```

This enables realistic gameplay where careless shooting can result in self-damage from ricochets, adding tactical depth to combat.

## Updated Probability Settings

| Setting | Previous Value | New Value | Reason |
|---------|---------------|-----------|--------|
| `base_ricochet_probability` | 0.7 (70%) | 1.0 (100%) | User feedback: 5.45 should always ricochet at grazing angles |
| Self-damage from ricochets | Disabled | Enabled | User feedback: realistic self-damage |

## Files Modified (Fourth Round)

1. `resources/calibers/caliber_545x39.tres` - Updated base_ricochet_probability to 1.0
2. `scripts/data/caliber_data.gd` - Updated default base_ricochet_probability to 1.0
3. `scripts/projectiles/bullet.gd` - Updated DEFAULT_BASE_RICOCHET_PROBABILITY to 1.0, enabled ricochet self-damage
4. `Scripts/Projectiles/Bullet.cs` - Updated BaseRicochetProbability to 1.0f, enabled ricochet self-damage
5. `tests/unit/test_ricochet.gd` - Updated test expectations for 100% probability
