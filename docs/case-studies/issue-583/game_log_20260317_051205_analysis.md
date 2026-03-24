# Analysis: RPG Rocket Static Rectangle Bug (2026-03-17)

## Session logs
- `game_log_20260317_051115.txt` — first test run (no RPG enemies in level)
- `game_log_20260317_051205.txt` — second test run (RPG enemies present, rocket fires)

## Observed behavior
User reported: "rocket fires but appears as a static rectangle and doesn't move"

## Evidence from log (game_log_20260317_051205.txt)
```
[05:12:12] Sound emitted: type=GUNSHOT, pos=(3662.674, 1399.289), source=ENEMY (RpgEnemy1), range=2500
[05:12:12] [ENEMY] [RpgEnemy1] State: COMBAT -> RETREATING
```
- Rocket IS fired (GUNSHOT at range=2500 = RPG sound range)
- Weapon switch to PM works (COMBAT → RETREATING)
- No `[Enemy][RPG] Rocket spawned` print visible → either log filtering or crash on spawn

## Root cause analysis

### Issue 1: Immediate explosion on spawn
The `RpgRocket._on_body_entered()` was triggering immediately when the rocket spawned
near the enemy's body or a wall:

```gdscript
if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
    _explode()
```

The enemy at (3700, 1400) is positioned near walls (enemy is behind cover with
"No valid flank position" warning). The muzzle position (3662, 1399) was likely
overlapping with a wall tile or triggering collision on the same frame as spawn.

When `_explode()` was called immediately:
1. `_has_exploded = true` was set
2. `_physics_process` skipped movement (`position += direction * speed * delta`)
3. The orange explosion flash (`_create_simple_explosion()`) appeared briefly
4. `queue_free()` called after 0.1s delay
5. User saw: static orange rectangle that didn't move

### Issue 2: Visual appearance (PlaceholderTexture2D)
The previous fix used `PlaceholderTexture2D` (orange 20×6 rect) which is a developer
placeholder. It:
- Renders as a solid colored rectangle
- Has no rocket-like shape
- Does not look like an RPG projectile

## Fixes applied

### Fix 1: Spawn immunity time (rpg_rocket.gd)
Added `spawn_immunity_time: float = 0.15` — rocket ignores collisions for the first
0.15 seconds after spawn. This matches the "point-blank penetration" pattern used
by bullet.gd for shots near the shooter.

```gdscript
func _on_body_entered(body: Node2D) -> void:
    if _time_alive < spawn_immunity_time:
        return  # Ignore collisions during spawn immunity
    ...
```

### Fix 2: Proper rocket texture (rpg_rocket.gd)
Replaced `PlaceholderTexture2D` with a programmatically generated rocket texture:
- 32×8px image with nose cone (orange), metallic body (grey), fin section, exhaust ring
- Applied via `_create_rocket_texture()` in `_ready()`
- Scale set to 2.0×2.0 in the scene for visibility

### Fix 3: Improved exhaust particles (RpgRocket.tscn)
- Increased particle count to 24 (from 18)
- Longer lifetime (0.3s) for visible trail
- Wider velocity range (80-180 px/s) for better flame appearance
- Trail gradient updated: bright yellow core → orange middle → transparent tail
- Trail width increased to 6.0px
- Trail length increased to 20 points

## Expected result
- Rocket travels visibly across the screen at 800px/s
- Rocket body looks like a metallic projectile with orange nose
- Orange/yellow flame exhaust trail behind the rocket
- Explosion on impact with walls or player
