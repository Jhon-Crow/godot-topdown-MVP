# Case Study: Issue #337 - Enemy Sound Detection Analysis

## Problem Statement

Enemies poorly orient by sound - they should more accurately determine the player's position by sound from a distance. Periodically enemies remain in IDLE state even when an M16 is firing in an adjacent room.

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/337

## Executive Summary

This case study analyzes the enemy AI sound detection system and identifies three root causes for poor sound orientation:

1. **Aggressive intensity threshold** - At ~500 pixels, sounds fall below the minimum threshold
2. **Sound pressure vs intensity mismatch** - Using inverse square law (1/r²) instead of 1/r for sound pressure
3. **State-based reaction blocking** - Enemies in combat-related states completely ignore gunshots

## System Architecture

### Sound Propagation System

The `SoundPropagation` autoload singleton (`scripts/autoload/sound_propagation.gd`) manages gameplay-affecting sounds separate from audio playback.

#### Sound Types and Ranges

| Sound Type | Range (pixels) | Wall Propagation |
|-----------|----------------|------------------|
| GUNSHOT | 1469 (viewport diagonal) | No |
| EXPLOSION | 2200 (1.5x viewport) | No |
| RELOAD | 900 | Yes (through walls) |
| EMPTY_CLICK | 600 | Yes (through walls) |
| RELOAD_COMPLETE | 900 | Yes (through walls) |
| FOOTSTEP | 180 | No |
| IMPACT | 550 | No |

#### Intensity Calculation

The system uses **inverse square law** for intensity:

```gdscript
# In sound_propagation.gd:205-213
func calculate_intensity(distance: float) -> float:
    if distance <= REFERENCE_DISTANCE:  # 50 pixels
        return 1.0
    var intensity := pow(REFERENCE_DISTANCE / distance, 2.0)
    return clampf(intensity, 0.0, 1.0)
```

Formula: `intensity = (50 / distance)²`

#### Minimum Intensity Threshold

```gdscript
const MIN_INTENSITY_THRESHOLD: float = 0.01
```

Sounds below this intensity are not propagated to listeners.

### Enemy Sound Reception

Enemies receive sounds via `on_sound_heard_with_intensity()` in `scripts/objects/enemy.gd:721-873`.

#### State-Based Reaction Logic

```gdscript
if _current_state == AIState.IDLE:
    should_react = intensity >= 0.01  # Always investigate
elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
    should_react = intensity >= 0.3   # Only loud nearby sounds
else:
    should_react = false  # Ignore during active combat
```

## Root Cause Analysis

### Root Cause 1: Aggressive Intensity Threshold

**Finding:** The inverse square law with REFERENCE_DISTANCE=50 pixels creates very aggressive falloff.

| Distance (px) | Intensity | Above Threshold? |
|---------------|-----------|------------------|
| 50 | 1.00 | Yes |
| 100 | 0.25 | Yes |
| 150 | 0.11 | Yes |
| 224 | 0.05 | Yes |
| 354 | 0.02 | Yes |
| 445 | 0.01 | Barely |
| 500 | 0.01 | At threshold |
| 707 | 0.005 | No |
| 1200 | 0.0017 | No |

**Impact:** At distances > 500 pixels, gunshots fall below the threshold and enemies don't receive the sound notification at all.

**Evidence from logs:**
```
[01:43:11] [ENEMY] [Enemy1] Heard gunshot at (454.55, 767.57), source_type=0, intensity=0.01, distance=445
[01:43:19] [ENEMY] [Enemy4] Heard gunshot at (825.17, 1338.79), source_type=0, intensity=0.01, distance=440
```

### Root Cause 2: Wrong Physical Model

**Finding:** The system uses inverse square law (`1/r²`) for sound, but this describes **sound intensity** (power per area), not **sound pressure** (what we actually hear).

According to physics research:
- Sound **intensity** falls off as `1/r²`
- Sound **pressure** (perceived loudness) falls off as `1/r`

**Reference:** [GameDev.net - Inverse square law for sound falloff](https://www.gamedev.net/forums/topic/674921-inverse-square-law-for-sound-falloff/)

Using `1/r` instead of `1/r²`:

| Distance (px) | Current (1/r²) | Proposed (1/r) |
|---------------|----------------|----------------|
| 100 | 0.25 | 0.50 |
| 224 | 0.05 | 0.22 |
| 445 | 0.01 | 0.11 |
| 1000 | 0.0025 | 0.05 |
| 1469 | 0.0012 | 0.034 |

### Root Cause 3: State-Based Reaction Blocking

**Finding:** Enemies in combat-related states completely ignore gunshot sounds.

**Affected states:** COMBAT, SEEKING_COVER, IN_COVER, SUPPRESSED, PURSUING, ASSAULT, SEARCHING

**Evidence from logs:**
```
[01:58:51] [ENEMY] [Enemy1] State: COMBAT -> RETREATING
[01:58:51] [ENEMY] [Enemy1] State: RETREATING -> IN_COVER
[01:58:51] [ENEMY] [Enemy1] State: IN_COVER -> SUPPRESSED
...
[01:58:55] [ENEMY] [Enemy1] Heard gunshot at (548.74, 713.91), source_type=0, intensity=0.01, distance=441
```

Enemy1 heard the gunshot (logged), but because it was in SUPPRESSED state, `should_react = false` and no state transition occurred.

**Code reference:** `enemy.gd:845-848`
```gdscript
else:
    # In combat-related states, only react to very loud sounds
    # This prevents enemies from being distracted during active combat
    should_react = false
```

## Timeline Reconstruction

### Scenario: Adjacent Room Gunfire Ignored

1. **T=0** - Player enters Room 1, enemies 5-7 are in Room 2 (~1200+ pixels away)
2. **T=1** - Player fires M16 at position (450, 780)
3. **T=1.001** - Sound propagation calculates intensity for Enemy5 at (1700, 350):
   - Distance = sqrt((1700-450)² + (350-780)²) = 1324 pixels
   - Intensity = (50/1324)² = 0.0014 (below 0.01 threshold)
4. **T=1.002** - Enemy5 is NOT notified (below_threshold counter increments)
5. **Result** - Enemy5 remains in IDLE despite M16 firing in adjacent room

### Scenario: Enemy in Combat Ignores New Gunshots

1. **T=0** - Enemy1 enters combat with player
2. **T=1** - Enemy1 retreats to cover, state = IN_COVER
3. **T=2** - Enemy1 becomes SUPPRESSED
4. **T=3** - Player fires at position (548, 714)
5. **T=3.001** - Enemy1 at (300, 350) receives sound:
   - Distance = 441 pixels
   - Intensity = 0.01 (at threshold)
   - State = SUPPRESSED
   - `should_react = false` (combat state)
6. **Result** - Enemy1 logs "Heard gunshot" but doesn't investigate

## Log Analysis Summary

### From game_log_20260125_014246.txt

- Total gunshot events: 200+
- Enemy state transitions from IDLE: 13
- "below_threshold" sounds: ~50% of notifications

### From game_log_20260125_014817.txt

- Total gunshot events: 300+
- Scene resets: 15+ (LastChance effect + player deaths)
- Memory reset events: 10+ per scene reset
- Enemies hearing gunshots but not reacting due to state: numerous

## Proposed Solutions

### Solution 1: Use Sound Pressure Model (1/r)

Change intensity calculation from `1/r²` to `1/r`:

```gdscript
func calculate_intensity(distance: float) -> float:
    if distance <= REFERENCE_DISTANCE:
        return 1.0
    # Use 1/r for sound pressure (perceived loudness)
    var intensity := REFERENCE_DISTANCE / distance
    return clampf(intensity, 0.0, 1.0)
```

**Impact:** At 1200 pixels, intensity becomes 0.042 instead of 0.0017 (24x louder)

### Solution 2: Lower Minimum Threshold for IDLE Enemies

Add IDLE-specific handling in sound propagation:

```gdscript
# In enemy.gd, lower threshold for IDLE state
if _current_state == AIState.IDLE:
    should_react = intensity >= 0.005  # Lower threshold for alert enemies
```

Or propagate all sounds to IDLE enemies regardless of threshold.

### Solution 3: Allow Suppressed/Cover Enemies to React to Very Loud Sounds

Add reaction for enemies in defensive states:

```gdscript
if _current_state == AIState.IDLE:
    should_react = intensity >= 0.01
elif _current_state in [AIState.FLANKING, AIState.RETREATING]:
    should_react = intensity >= 0.3
elif _current_state in [AIState.IN_COVER, AIState.SUPPRESSED, AIState.SEEKING_COVER]:
    # React to very loud sounds even in defensive states
    should_react = intensity >= 0.5
else:
    # Active combat states still ignore sounds
    should_react = false
```

### Solution 4: Improve Sound Direction Accuracy

Currently enemies store `_last_known_player_position = position` where position is the exact sound source. For better gameplay:

- Add position error based on distance
- Use memory system confidence to affect accuracy
- Consider walls/obstacles for sound direction perception

## Recommended Implementation

1. **Primary fix:** Change to `1/r` sound pressure model (Solution 1)
2. **Secondary fix:** Lower IDLE threshold to 0.005 (Solution 2)
3. **Optional enhancement:** Allow defensive state reactions (Solution 3)

## References

### Industry Best Practices

- [AI for Unity - Emulating Real-World Senses](https://hub.packtpub.com/ai-unity-game-developers-emulate-real-world-senses/)
- [Unreal Engine - AI Perception System](https://dev.epicgames.com/documentation/en-us/unreal-engine/ai-perception-in-unreal-engine)
- [Thief: The Dark Project - AI Sensory System](https://www.gamedeveloper.com/programming/building-an-ai-sensory-system-examining-the-design-of-i-thief-the-dark-project-i-)
- [GameDev.net - Inverse Square Law Discussion](https://www.gamedev.net/forums/topic/674921-inverse-square-law-for-sound-falloff/)

### Codebase Files

- `scripts/autoload/sound_propagation.gd` - Sound propagation system
- `scripts/objects/enemy.gd` - Enemy AI and sound reception
- `scripts/ai/enemy_memory.gd` - Enemy memory system
- `tests/unit/test_sound_propagation.gd` - Unit tests

## Appendix: Log File Summary

| Log File | Lines | Duration | Key Events |
|----------|-------|----------|------------|
| game_log_20260125_014246.txt | 3,813 | ~3 min | Normal gameplay, frequent respawns |
| game_log_20260125_014520.txt | 2,886 | ~3 min | Normal gameplay |
| game_log_20260125_014817.txt | 15,845 | ~7 min | Extended session, many LastChance events |
| game_log_20260125_015847.txt | 1,444 | ~1 min | Short session, focused testing |
