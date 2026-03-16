# Case Study: Issue #1071 — Active Item: Dash (Рывок)

## Issue Summary
**Title:** добавить активный предмет - рывок
**Author:** Jhon-Crow
**Requested Feature:** Add a dash active item for the player.

### Requirements (translated from Russian)
- Unlimited uses (no charge limit)
- Cooldown: 1.2 seconds between dashes
- During the dash, the player ignores all damage sources
- Reference: dash from Hyper Light Drifter

## Hyper Light Drifter Dash Analysis

Hyper Light Drifter (by Heart Machine, 2016) features one of the most celebrated dash mechanics in indie games:

### Key Properties
1. **Directional**: Dash in the current movement direction; if standing still, dash forward (in aim direction)
2. **Distance**: ~150–200px (short burst, not a teleport)
3. **Duration**: Very brief (~0.1–0.15s); near-instant
4. **Invincibility frames**: Full damage immunity for entire dash duration
5. **Visual**: Motion blur/trail behind the player; brief speed lines
6. **Cooldown**: Short cooldown (~0.5–1.2s), unlimited uses
7. **Chaining**: In HLD you can chain dashes; this issue requests 1.2s cooldown (no chaining)
8. **Sound**: Short whoosh/swipe sound on activation

### Gameplay Role
The dash is the primary mobility and survival tool: dodge incoming fire, reposition instantly,
escape flanking enemies. The key gameplay feel is **reactive invincibility** — you dash *through*
bullets rather than around them.

## Architecture Analysis

### Existing Active Item System
The game has a well-established pattern for active items:
- **ActiveItemManager** (`scripts/autoload/active_item_manager.gd`): Singleton managing enum + ACTIVE_ITEM_DATA dict
- **Player script** (`scripts/characters/player.gd`): `_init_*` and `_handle_*_input()` per item
- **Input**: Space key mapped to `flashlight_toggle` action
- **Progress Bar**: `ActiveItemProgressBar` shows cooldown/charges above player head

### Damage Protection Pattern
The force field (`is_force_field_active()`) pattern shows how to block damage:
```gdscript
# In on_hit_with_info():
if is_force_field_active():
    return  # blocked
```
The dash must add a similar `is_dashing()` check.

### Movement System
Player uses `CharacterBody2D` with velocity-based movement:
```gdscript
velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
move_and_slide()
```
Dash overrides velocity with a high-speed burst in the dash direction.

## Solution Design

### Approach
1. Implement dash entirely within `player.gd` (no separate scene needed — similar to homing bullets)
2. During dash: override velocity with `dash_direction * DASH_SPEED`
3. Invincibility: `_dash_active` flag checked in `on_hit_with_info()`
4. Cooldown: simple timer, no charge counter
5. Progress bar: continuous bar showing cooldown depletion
6. Visual: brief speed-line / motion-blur effect via modulate flash (or trail Line2D)
7. Audio: short whoosh sound if available, otherwise silent

### Constants
- `DASH_SPEED: float = 900.0` (3× max_speed of 300)
- `DASH_DURATION: float = 0.12` seconds
- `DASH_COOLDOWN: float = 1.2` seconds (per issue spec)
- Input: `flashlight_toggle` (Space key) — same as all other active items

### Components Modified
1. **`active_item_manager.gd`** — Add `DASH` enum entry + ACTIVE_ITEM_DATA
2. **`player.gd`** — `_init_dash()`, `_handle_dash_input()`, `_update_dash()`, `is_dashing()`, damage block
3. **`active_item_manager.gd`** — `has_dash()` helper

### Unlock Condition
Per the issue: "неограниченное количество" (unlimited uses) with cooldown. No special unlock — freely available from the start (like BFF Pendant, Breaker Bullets, Force Field).

## Known Libraries / Solutions

### Godot Built-in
- `CharacterBody2D.velocity` + `move_and_slide()` — native physics movement; dash is just a velocity override
- `get_tree().create_timer()` — usable for cooldown, but inline timer is simpler and cheaper
- No external library needed

### Reference Implementations
- Hyper Light Drifter: `velocity = dash_dir * DASH_SPEED` for a fixed duration; flag for i-frames
- Hotline Miami: Similar instant burst with brief i-frames
- Enter the Gungeon: "dodge roll" — longer animation, invincibility window

## Test Plan
1. Unit test: dash starts on Space, sets `_dash_active = true`
2. Unit test: damage is blocked while `_dash_active`
3. Unit test: cooldown prevents re-activation within 1.2s
4. Unit test: dash ends after `DASH_DURATION` seconds
5. Unit test: cooldown bar shows on activation, hides after cooldown
