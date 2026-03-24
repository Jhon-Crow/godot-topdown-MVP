# Session Analysis - 2026-03-18 (Latest)

## User Feedback (2026-03-18 ~01:00 UTC)

From PR comment after testing build from commit `ccc42197`:

> "ракета летит, отлично (зафиксируй прогресс)"
> "теперь часть текста в experimental не влезает на экран (надписи слева, исправь)"
> "ракета не взрывается и не наносит урон (должна взрываться как подствольная граната по радиусу)"
> "ракета летит очень медленно (должна с самого начала лететь в 2 раза быстрее и ускоряться ещё больше в процессе полёта)"

**Translation:**
1. Rocket flies, excellent (commit progress)
2. Some text in experimental screen doesn't fit (labels on left, fix)
3. Rocket doesn't explode and doesn't deal damage (should explode like underbarrel grenade by radius)
4. Rocket flies too slowly (should fly 2x faster from start and accelerate even more during flight)

## Root Cause Analysis

### Issue 1: Rocket explosion not working

**Hypothesis**: The `body_entered` signal from Area2D collision detection may not be reliably firing when the Area2D moves via direct `position +=` assignment. While Godot 4 should handle this, exported builds may have subtle differences.

**Fix applied**: Added raycast-based collision detection in `_physics_process` as a reliable fallback. Each frame, a PhysicsRayQueryParameters2D is cast from previous position to current position. If it hits anything (wall, enemy, player), the explosion triggers.

This is more reliable than signal-based detection because:
- Works even if `body_entered` signal is missed
- Catches collisions when the bullet moves through thin geometry
- No timing issues with signal connection

### Issue 2: Rocket speed too slow

**Root cause**: Initial speed of 300 px/s was too slow. Real RPG-7 launches at ~115 m/s but for game feel, 2x speed is needed.

**Fix applied**:
- `rpg_speed_initial`: 300 → 600 px/s (2x as requested)
- `rpg_speed_max`: 800 → 1800 px/s (more dramatic acceleration)
- `rpg_accel_distance`: 1000 → 800 px (reaches max speed faster)
- `rpg_spawn_immunity`: 0.3 → 0.15s (reduced to allow faster collision detection at higher speed)

### Issue 3: Experimental screen text overflow

**Root cause**: Observed in 1920x1080 screenshot - left labels in HBoxContainers are cut off at left panel edge.

**Root cause**: Labels in HBoxContainers had `size_flags_horizontal = 3` (FILL+EXPAND) but no `autowrap_mode`, meaning they enforced their full text width as minimum size, overflowing container bounds.

Additionally, the PanelContainer used fixed pixel offsets (880px wide) which could be insufficient at different resolutions.

**Fix applied**:
- Changed PanelContainer from fixed pixel offsets to percentage-based anchors (10%-90% width, 5%-95% height) for screen-size independence
- Added `autowrap_mode = 2` to all HBoxContainer labels to prevent minimum text width enforcement

## Files Modified

- `scripts/projectiles/bullet.gd`: Raycast fallback for explosion, speed defaults updated
- `scenes/projectiles/RpgRocket.tscn`: Speed parameters updated (600/1800px, 0.15s immunity)
- `scenes/ui/ExperimentalMenu.tscn`: Percentage-based panel sizing, autowrap_mode on all labels
