# Case Study: Issue #544 - Memory Replay Mode Visual/Audio Fidelity

## Problem Statement

The Memory (replay) mode in the game had 7 major deficiencies that degraded the replay viewing experience:

1. **Bullets not visible** - Ghost bullets were tiny (8x3 GradientTexture2D) and lacked trails
2. **No sounds** - Events array was declared but never populated or played back
3. **Wrong colors** - Ghost entities used flat white modulate, hiding health-based color changes
4. **No hit brightness effect** - HitEffectsManager was not triggered during replay
5. **Static floor** - Blood decals and casings were either all present or all absent
6. **Wrong player model** - Ghost modulate override (0.9 alpha white) masked health colors
7. **No player trail** - No visual trail following the player ghost

## Timeline of Events

1. **Initial replay system** - Recorded basic entity positions, rotations, and alive state
2. **Ghost entity system** - Instantiated scene copies with disabled scripts
3. **Issue #544 filed** - Seven specific visual/audio problems identified

## Root Cause Analysis

### Root Cause 1: Insufficient Recording Data

The replay system only recorded:
- Player: position, rotation, model_scale, alive (bool)
- Enemies: position, rotation, alive (bool)
- Bullets: position, rotation (no visual info)
- Events: declared but never populated

**Missing data:** health colors, sound events, floor state (blood/casings)

### Root Cause 2: Ghost Entity Visual Override

`_set_ghost_modulate()` applied `Color(1.0, 1.0, 1.0, 0.9)` to ALL nodes recursively.
This overrode any health-based color that could be applied later.

### Root Cause 3: No Event System

The `events` array in frame data was always empty. There was:
- No code to detect when shots were fired
- No code to detect when enemies were hit or killed
- No code to play back sounds during replay

### Root Cause 4: Bullet Visual Inadequacy

Ghost bullets used `GradientTexture2D` with 8x3 pixel dimensions - nearly invisible at game scale.
No trail system was implemented for ghost bullets, unlike real bullets which use Line2D trails.

### Root Cause 5: No Floor State Management

The replay did not:
- Record blood decal positions
- Record casing positions
- Clean the floor at replay start
- Progressively re-add floor effects during playback

## Solution

### Enhanced Recording (`_record_frame`)

| Data Point | Before | After |
|-----------|--------|-------|
| Player color | Not recorded | `body_sprite.modulate` per frame |
| Enemy color | Not recorded | `enemy_body.modulate` per frame |
| Sound events | Always empty | Detected via bullet count changes and color flash detection |
| Blood decals | Not recorded | Positions from `blood_puddle` group |
| Casings | Not recorded | Positions from `casings` group |

### Enhanced Playback

| Feature | Before | After |
|---------|--------|-------|
| Bullet visibility | 8x3 GradientTexture2D | 12x4 solid sprite + Line2D trail |
| Sounds | None | Shot, hit, death sounds via AudioManager |
| Entity colors | Flat white override | Per-frame health color from recording |
| Hit effects | None | HitEffectsManager.on_player_hit_enemy() on hits |
| Floor state | Static | Clean at start, progressive re-addition |
| Player model | White modulate override | Actual health-based colors |
| Player trail | None | Line2D with gradient fade (20 points) |

### Event Detection Algorithm

Sound events are detected by comparing consecutive frames:
1. **Shots**: `frame.bullets.size() > prev_frame.bullets.size()`
2. **Hits**: Enemy color becomes white (flash) - `color.r > 0.95 && color.g > 0.95 && color.b > 0.95`
3. **Deaths**: `prev_frame.enemies[i].alive && !frame.enemies[i].alive`

## Files Modified

| File | Changes |
|------|---------|
| `scripts/autoload/replay_system.gd` | Enhanced recording, playback, ghost creation, event system |

## Testing

Unit tests cover:
- Frame data creation with new fields
- Sound event detection (shots, hits, deaths)
- Color application to ghost sprites
- Floor cleanup and progressive re-addition
- Ghost bullet trail creation
- Player trail creation and management

## Lessons Learned

1. **Record visual state, not just spatial state** - Replay fidelity requires capturing the full visual representation (colors, effects) not just positions
2. **Event detection via state diff** - When direct event hooking is impractical, state comparison between frames can reliably detect events
3. **Don't override visual properties globally** - Ghost entity modulate should be per-sprite, not recursive on the entire tree
4. **Progressive state matters** - Floor effects (blood, casings) need temporal tracking for realistic replay
