# Issue #711: Enemies Should Shoot at Sound and Muzzle Flash

## Issue Summary (Russian Translation)
> 1. если враги слышат звук выстрелов близко - они должны давать короткую очередь по звуку.
> 2. если враг видит вспышку - должен дать несколько очередей туда, где увидел вспышку.

**Translation:**
1. If enemies hear gunfire sounds nearby - they should fire a short burst at the sound.
2. If an enemy sees a flash - they should fire several bursts toward where they saw the flash.

## Current State Analysis

### Existing Sound System
The codebase already has a comprehensive sound propagation system:

- **`scripts/autoload/sound_propagation.gd`**: Autoload singleton managing in-game sound events
  - Sound types: `GUNSHOT`, `EXPLOSION`, `FOOTSTEP`, `RELOAD`, `IMPACT`, `EMPTY_CLICK`, `RELOAD_COMPLETE`, `GRENADE_LANDING`, `CASING_KICK`
  - Propagation distances defined (e.g., gunshot ~1469px)
  - Intensity calculation using inverse square law

- **Enemy Sound Reaction**: Enemies already implement `on_sound_heard()` and `on_sound_heard_with_intensity()` methods
  - Currently reacts to reload sounds (confidence 0.7)
  - Reacts to empty click sounds (confidence 0.6)
  - Reacts to gunshots by entering COMBAT mode
  - Does NOT fire at the sound source location

### Existing Visual Detection System
- **`scripts/components/flashlight_detection_component.gd`**: Detects player's flashlight beam
  - Uses beam-in-FOV detection algorithm
  - Generates estimated player position from beam origin
  - Confidence level: 0.75

- **`EnemyMemory` class**: Tracks suspected player positions with confidence levels
  - Supports sound-based detection confidence levels
  - Decay system for confidence over time

### Missing Features
1. **Shooting at sound position**: Enemies hear sounds but don't suppress-fire toward the source
2. **Muzzle flash detection**: No system to detect player's muzzle flash from gunfire
3. **Suppression fire behavior**: No burst/suppression fire toward detected sound/flash positions

## Proposed Solution

### 1. Muzzle Flash Detection Component
Create `MuzzleFlashDetectionComponent` similar to `FlashlightDetectionComponent`:
- Detect bright flashes within FOV (muzzle flash lasts ~0.04s based on scene file)
- Register for flash events from player shooting
- Estimate player position based on flash location
- Apply appropriate confidence level (0.65 - lower than flashlight due to brief duration)

### 2. Sound-Based Suppression Fire
Modify enemy behavior when hearing gunshots:
- If sound is close enough (within suppression range, e.g., 500px)
- Fire 3-5 round burst toward the sound position
- Apply inaccuracy spread to simulate "blind" firing

### 3. Flash-Based Suppression Fire
When enemy sees muzzle flash but can't see player:
- Fire longer burst (5-10 rounds) toward flash position
- Multiple bursts over short duration
- Higher confidence in targeting due to visual confirmation

### Key Design Decisions

1. **Suppression vs Aimed Fire**:
   - Sound/flash-based fire should be suppressive (high inaccuracy)
   - Only switch to aimed fire when player becomes directly visible

2. **Cooldown System**:
   - Prevent infinite suppression fire
   - Global suppression cooldown per enemy (e.g., 2-3 seconds)

3. **Ammunition Consideration**:
   - Suppression fire consumes real ammunition
   - Enemies won't suppress if low on ammo

4. **State Machine Integration**:
   - New behavior doesn't require new states
   - Integrate into existing IDLE/COMBAT/PURSUING states
   - Add flags for "suppressing_sound" and "suppressing_flash"

## Implementation Plan

1. Create `MuzzleFlashDetectionComponent` class
2. Add muzzle flash emission to player's shooting code
3. Integrate flash detection into enemy's `_update_memory_and_detection()`
4. Add suppression fire logic to enemy's shooting code
5. Add configuration exports for suppression parameters
6. Write unit tests

## References

- Similar game mechanics: Counter-Strike (enemies react to sound), F.E.A.R. (suppression fire)
- Godot documentation: Area2D for flash detection, signals for events
- Existing PR examples: Issue #574 (flashlight detection), Issue #297 (memory system)
