# Case Study: Issue #1336 — Sniper Enemy Laser Sight

## Issue Summary

**Title:** update враг снайпер (update sniper enemy)

**Description:**
Добавь лазерный прицел на винтовку врага снайпера.
ВАЖНО: лазер должен всегда указывать то место, куда будет стрелять враг (совпадать с будущим трассером).

(Add a laser sight to the sniper enemy's rifle.
IMPORTANT: the laser must always point where the enemy will shoot — matching the future tracer.)

---

## Data Collection

### Existing Sniper Implementation (pre-fix)

| Component | File | Purpose |
|-----------|------|---------|
| AI behaviour | `scripts/components/enemy_sniper_component.gd` | Standoff range, blind-fire (Issues #1163, #1171) |
| Hitscan shooting | Same file, `shoot_sniper_hitscan()` | Instant raycast avoids tunnelling at 10000px/s |
| Tracer rendering | Same file, `_spawn_sniper_tracer()` | Fading smoke Line2D from muzzle to endpoint |
| Weapon config | `scripts/components/weapon_config_component.gd` | Type 7: 3s cooldown, 5-round mag, 0 spread |
| Enemy integration | `scripts/objects/enemy.gd` | `_execute_shoot()` dispatches to sniper hitscan |
| Scene | `scenes/objects/Enemy.tscn` | Base enemy with EnemyModel/WeaponMount hierarchy |

### Shooting Direction Flow

The bullet direction chain in `enemy.gd._execute_shoot()`:
1. `_get_weapon_forward_direction()` — determines actual barrel direction
2. `_get_bullet_spawn_position(weapon_forward)` — muzzle world position
3. `_sniper_component.shoot_sniper_hitscan(direction, bullet_spawn_pos)` — fires hitscan
4. `_spawn_sniper_tracer(spawn_pos, bullet_end_point)` — renders tracer

The laser must use **steps 1-2** to ensure it always matches the future tracer (step 4).

### Existing Laser/Line2D Patterns in Codebase

| Pattern | File | Technique |
|---------|------|-----------|
| Weapon laser sights | `trajectory_glasses_effect.gd` | Toggle `LaserSight` Line2D child visibility |
| Sniper tracer | `enemy_sniper_component.gd` | Dynamic Line2D, top_level=true, fade-out coroutine |
| Bullet trail | `SniperBulletEnemy.tscn` | Trail Line2D child on Area2D bullet |
| Replay ghost | `replay_system.gd` | Persistent Line2D with point updates |

### External Research: Laser Sights in Games

Laser sights in top-down shooters commonly use:
- **Line2D / LineRenderer** — thin line from muzzle, raycast to find endpoint
- **RayCast2D** — built-in node for continuous collision detection
- Typical visual: thin red line (1-3px), semi-transparent, with brighter dot at endpoint
- Key constraint: must update every frame to track weapon rotation
- Common approach: raycast against walls only (not characters) to show where bullet will hit terrain

Godot-specific approaches:
- `Line2D` with `top_level = true` for world-space coordinates
- `PhysicsRayQueryParameters2D.create()` for per-frame raycasts (same API as hitscan)
- Using `_process()` (not `_physics_process()`) for smoother visual updates

---

## Root Cause Analysis

The sniper enemy had no visual indicator of where it would shoot. Players had no way to anticipate incoming sniper fire, making it feel unfair — especially given the 50 damage hitscan that penetrates up to 2 walls.

---

## Solution

### Approach: Persistent Line2D with Per-Frame Raycast

Added a laser sight as a persistent `Line2D` child of the `EnemySniperComponent`:

1. **Created in `_ready()`** — single Line2D instance, reused every frame (no GC pressure)
2. **Updated in `_process()`** — uses `_get_weapon_forward_direction()` and `_get_bullet_spawn_position()` from `enemy.gd` to compute muzzle position and direction
3. **Raycasts against walls** (collision layer 4) to find the endpoint, matching hitscan behaviour
4. **Hidden when enemy dies** — checks `enemy._is_alive`

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Same direction methods as `_execute_shoot()` | Guarantees laser matches future tracer (issue requirement) |
| `_process()` not `_physics_process()` | Smoother visual updates; laser is visual-only, no physics |
| Raycast walls only (layer 4), not characters | Standard laser sight behaviour; avoids spoiling character positions through cover |
| Semi-transparent red (alpha 0.4-0.7) | Visible but not overwhelming; brighter dot at endpoint |
| `top_level = true` | World-space positioning, same as tracer |
| `z_index = 9` (below tracer at 10) | Laser visible but tracer renders on top when shot fires |
| Width 1.5px with taper curve | Thin enough to look like a laser, not a beam weapon |

### Files Changed

| File | Change |
|------|--------|
| `scripts/components/enemy_sniper_component.gd` | Added laser sight constants, `_create_laser_sight()`, `_process()`, `_update_laser_sight()` |
| `tests/unit/test_sniper_laser_sight.gd` | New test file: constants, creation, visibility, structure |

---

## Testing

### Unit Tests (`test_sniper_laser_sight.gd`)

- Constants validation (range, width, color, wall layer)
- Line2D creation on `_ready()` (type, name, top_level, point count, width, z_index)
- Visibility rules (hidden when enemy is null/dead)
- Pre-ready state (null before `_ready()`)

### Manual Testing Checklist

- [ ] Laser visible from sniper muzzle in-game
- [ ] Laser tracks weapon rotation smoothly
- [ ] Laser stops at walls (collision layer 4)
- [ ] Laser matches tracer direction when shot fires
- [ ] Laser hidden after enemy death
- [ ] No performance impact (single Line2D update per frame)
