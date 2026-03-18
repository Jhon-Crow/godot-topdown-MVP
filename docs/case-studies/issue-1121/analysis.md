# Case Study: Issue #1121 — Invisible Enemies (Stealth Enemies) in Labyrinth Complex

## Issue Summary

Add 2 enemies with invisibility to the **Labyrinth Complex** (`Labyrinth2Level`) map:
- Start in **SEARCHING** state (actively searching from the beginning)
- Are **invisible from the start** (using the same Predator-style cloak shader as the player)
- **Reveal themselves** only when shooting or throwing grenades
- Return to **invisible** after action

## Related Components

### Existing Invisibility System (Player)
- `scripts/effects/invisibility_suit_effect.gd` — Manages the player's invisibility cloak
- `scripts/shaders/invisibility_cloak.gdshader` — The Predator-style chromatic distortion shader
- Uses a `ShaderMaterial` with parameter `mix_amount` (0.0 = visible, 1.0 = fully cloaked)
- Applied recursively to all `CanvasItem` children of the player model

### Enemy AI System
- `scripts/objects/enemy.gd` — Main enemy AI (4000+ lines)
- `AIState` enum includes `SEARCHING` — enemy methodically searches an area
- `_transition_to_searching(center: Vector2)` — transitions to SEARCHING state
- `_execute_shoot(target_pos)` — called whenever a shot fires
- `_execute_grenade_throw(tgt)` — called when grenade is thrown
- Existing exports: `is_grenadier`, `is_teleporter`, `has_force_field`

### Labyrinth Complex Map
- `scenes/levels/Labyrinth2Level.tscn` — "LABYRINTH COMPLEX" level
- Has 15 enemies + 1 machine gunner (16 total)
- Player spawns at lower portion of the map

## Solution Design

### New Enemy Exports (enemy.gd)
```gdscript
@export var start_invisible: bool = false  ## Start with invisibility cloak (Issue #1121)
@export var initial_state: AIState = AIState.IDLE  ## Initial AI state (Issue #1121)
```

### Invisibility Implementation
- On `_ready()`: if `start_invisible`, apply invisibility shader to all enemy model sprites with `mix_amount = 1.0`
- Track with `_is_enemy_invisible: bool` and `_reveal_timer: float`
- **Reveal** (set `mix_amount = 0.0`): when `_execute_shoot()` or `_execute_grenade_throw()` is called
- **Re-hide** (set `mix_amount = 1.0`): after `REVEAL_DURATION` seconds (e.g. 2.0s)
- If `initial_state == AIState.SEARCHING`: call `_transition_to_searching(global_position)` in `_ready()` after init

### Shader Application
Reuse the same `invisibility_cloak.gdshader` and approach from `InvisibilitySuitEffect`:
- Recursively find all `CanvasItem` children of `EnemyModel`
- Apply `ShaderMaterial` with `mix_amount` parameter
- Store originals to restore on death

### New Enemies in Labyrinth2Level
Add 2 enemies with:
- `start_invisible = true`
- `initial_state = 15` (AIState.SEARCHING = index 15 in enum)
- Positioned in different rooms for threat variety
- `destroy_on_death = true`, `enable_flanking = true`, `enable_cover = true`

## Alternatives Considered

1. **Separate InvisibleEnemy scene**: More complex, would require a new tscn file and script. The existing enemy architecture with exports is cleaner.

2. **Alpha transparency only**: Simpler but doesn't match the existing "invisible player" visual. The shader approach is consistent.

3. **Level script initialization**: Setting state in labyrinth2_level.gd via `get_node()` calls. Less clean than using an export variable.

## References

- Issue #673: Player invisibility suit implementation
- Issue #322: SEARCHING state implementation
- Issue #604: is_grenadier export pattern
- Issue #752: is_teleporter export pattern
- Issue #1034: has_force_field export pattern
