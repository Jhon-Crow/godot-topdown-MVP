# Case Study: Issue #1336 — Sniper Enemy Laser Sight

## Problem Statement

The sniper enemy's laser sight did not align with where the bullets/tracers actually traveled. Additionally, the laser passed through the player instead of stopping at the player's body.

User feedback (translated from Russian):
1. "прицел всё ещё указывает не туда, куда летит трассер" — The laser sight still points in a different direction than the tracer flies.
2. "лазер проходит сквозь игрока" — The laser passes through the player.
3. "возможно не учитывается отклонение при стрельбе в слепую, лазер должен быть направлен туда, куда полетит трассер (строго)" — Blind fire deviation is not accounted for; the laser must strictly match the tracer.

## Timeline of Events

| Date | Event |
|------|-------|
| 2026-03-22 | Initial implementation: red laser sight added to sniper enemy |
| 2026-03-22 | PR #1341 opened, marked ready to merge |
| 2026-03-23 | Owner feedback: laser doesn't reach player on Docks map |
| 2026-03-23 | Fix: doubled laser length from 5000px to 10000px |
| 2026-03-23 | Owner feedback: laser doesn't point where tracer goes, passes through player |
| 2026-03-23 | Fix: changed raycast mask from 4 to 5 (walls+characters), excluded enemy collider |
| 2026-03-23 | Owner feedback: laser STILL doesn't match tracer direction |
| 2026-03-23 | Failed fix attempt 1: switched laser to visual barrel direction — bullets still went elsewhere |
| 2026-03-23 | Failed fix attempt 2: switched laser back to `_get_weapon_forward_direction()` — still mismatch |
| 2026-03-23 | Owner: "blind fire deviation not accounted for, laser must strictly match tracer" |
| 2026-03-23 | Unified laser, hitscan, and blind-fire to all use visual barrel direction |
| 2026-03-23 | Owner: "теперь лазера вообще нет" — laser completely invisible |
| 2026-03-23 | **Fix: re-parent laser CanvasItem nodes to enemy (CharacterBody2D) instead of EnemySniperComponent (Node), add debug logging, restore accidentally removed `bullet_damage_multiplier`** |
| 2026-03-23 | Owner: "сейчас всё ещё нет лазера" — laser still invisible with enemy node parenting |
| 2026-03-23 | Fix (Round 7): direct `_is_alive` access, scene root parenting via `call_deferred` |
| 2026-03-23 | Owner: "всё ещё нет лазера" — laser still invisible with scene root parenting |
| 2026-03-23 | Fix (Round 8): parent laser to enemy with `top_level=true` + synchronous `add_child()` |
| 2026-03-23 | Owner: "всё ещё не отображается лазер" — laser still not displaying |
| 2026-03-23 | Fix (Round 9): lazy creation during `_physics_process`, scene root parenting, removed PointLight2D |
| 2026-03-24 | Owner: "лазера у снайпера всё ещё нет" — laser still absent, with screenshot |
| 2026-03-24 | Fix (Round 10): exact SniperEnemyTracer pattern (top_level=true, real coords at creation, triple logging) |

## Data Sources

- `logs/game_log_20260323_102814.txt` — Game log from user testing (barrel-direction fix)
- `logs/game_log_20260323_104706.txt` — Game log confirming barrel-direction fix was still wrong
- `logs/game_log_20260323_110139.txt` — Game log with blind fire deviation analysis
- `logs/game_log_20260323_112851.txt` — Game log: laser completely invisible after unification fix
- Source code analysis of `enemy.gd` and `enemy_sniper_component.gd`
- Player M16 laser implementation in `AssaultRifle.cs` for comparison

## Root Cause Analysis

### The Dual Direction System

The enemy AI has **two separate direction systems** that diverge:

1. **Visual barrel direction** (`_weapon_sprite.global_transform.x.normalized()`): The direction the weapon model visually points. Rotates smoothly via `lerp_angle()` with `MODEL_ROTATION_SPEED * delta`, creating natural-looking rotation lag.

2. **Instant aim direction** (`_get_weapon_forward_direction()`): When `_can_see_player` is true, returns `(player.pos - enemy.pos).normalized()` — a direct geometric direction that ignores model rotation. When `_can_see_player` is false, falls back to the visual barrel direction.

```gdscript
func _get_weapon_forward_direction() -> Vector2:
    # Path A: When player IS visible — instant, perfect aim
    if _player and is_instance_valid(_player) and _can_see_player:
        return (_player.global_position - global_position).normalized()
    # Path B: When player is NOT visible — visual barrel
    if _weapon_sprite:
        return _weapon_sprite.global_transform.x.normalized()
```

### Why Previous Fixes Failed

**Attempt: Laser uses `_get_weapon_forward_direction()` (same as bullets)**
- When player visible: both laser and bullet use instant direction → both skip ahead of barrel
- Result: laser and tracer match each other, but BOTH diverge from the visual barrel
- User sees: barrel points left, laser goes straight, tracer goes straight → visually broken

**Attempt: Laser uses visual barrel direction**
- Laser follows the barrel (visually correct)
- But hitscan still uses `_get_weapon_forward_direction()` → instant aim direction
- Result: laser follows barrel, tracer goes somewhere else
- User sees: laser matches barrel, but tracer doesn't match laser → still broken

**Attempt: Back to `_get_weapon_forward_direction()` for laser**
- Same as first attempt — laser matches tracer but both diverge from barrel
- For blind fire: `fire_at_predicted_position()` adds ±3° random spread to bullets
- Laser doesn't account for this spread
- Result: even more mismatch during blind fire

### The Core Problem

The **visual model** and the **shooting system** operate on different direction systems. The model rotates smoothly (cosmetic), while bullets use instant geometric aim (gameplay). The `AIM_TOLERANCE_DOT = cos(30°)` check allows the enemy to fire when the barrel is up to 30° away from the target, making the divergence large and clearly visible.

Additionally, blind fire applied ±3° random spread on top of a snap rotation to the predicted position — creating further mismatch between the visible barrel direction and actual bullet direction.

### Comparison with Player M16 Laser

The player's M16 assault rifle laser (in `AssaultRifle.cs`) uses:
```csharp
Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);
```
The M16 laser follows the actual aim direction WITH recoil offset. Both the laser and the bullet use the same aim direction, and the weapon model directly follows the mouse cursor without interpolation lag. This means the M16 laser naturally matches both the barrel and the bullet.

## Correct Solution

**Unified all sniper shooting systems to use the visual barrel direction.** This ensures the laser, hitscan tracer, and blind-fire bullets all go in the same direction — the direction the barrel is actually pointing.

### Changes Made

1. **`get_visual_barrel_direction()`** — New function in `EnemySniperComponent` that always returns `_weapon_sprite.global_transform.x.normalized()`, the actual visual barrel direction.

2. **`_get_barrel_spawn_position()`** — New function that computes muzzle position from the visual barrel transform (unlike `_get_bullet_spawn_position()` which uses instant aim when player visible).

3. **Laser** (`update_laser_sight()`) — Now uses `get_visual_barrel_direction()` instead of `_get_weapon_forward_direction()`.

4. **Hitscan** (`shoot_sniper_hitscan()`) — Called from `_execute_shoot()` with the visual barrel direction and spawn position, so the tracer matches the laser.

5. **`_execute_shoot()` in enemy.gd** — For snipers specifically: computes barrel direction via `_sniper_component.get_visual_barrel_direction()`, checks barrel aim tolerance, and passes barrel direction to hitscan. Also adds a barrel-specific aim check so the sniper only fires when the barrel is actually pointed at the target.

6. **Blind fire** (`fire_at_predicted_position()`) — Removed model snap rotation and ±3° random spread. Now uses `get_visual_barrel_direction()` directly. The barrel is already smoothly rotating toward the predicted position via `_rotate_toward()`, providing natural inaccuracy.

### Why This Works

All three shooting paths now use the same direction source:
- **Laser**: `get_visual_barrel_direction()` → visual barrel
- **Hitscan**: barrel direction passed from `_execute_shoot()` → visual barrel
- **Blind fire**: `get_visual_barrel_direction()` → visual barrel

The visual barrel direction is the single source of truth. The laser shows it continuously, the hitscan tracer shows it when fired, and blind-fire bullets follow it too. The sniper is now slightly less accurate (no more instant aim bypassing model rotation), but the laser sight accurately shows where the shot will go — which is the whole point of having a laser sight.

### Collision Layer Reference

| Layer | Bit Value | Used For |
|-------|-----------|----------|
| 1 | 1 | Player character |
| 2 | 2 | Enemy characters |
| 3 | 4 | Walls/Obstacles |

Laser raycast mask: **5** (binary `101`) = Layer 1 (player) + Layer 3 (walls)

## Round 6: Laser Completely Invisible

### Problem
After the unification fix (commit a8f1dd54), the laser sight became completely invisible. No laser was visible at all during gameplay.

### Analysis
The laser `Line2D` nodes were created as children of `EnemySniperComponent`, which extends `Node` (NOT `Node2D`). In Godot 4.3, `CanvasItem` nodes (like `Line2D`) added as children of a plain `Node` may silently fail to render, even with `top_level = true`.

The rendering chain was: `Enemy (CharacterBody2D)` → `SniperComponent (Node)` → `Line2D (top_level=true)`. While the `Line2D` had a `CanvasItem` ancestor (the Enemy), the intermediate `Node` breaks the canvas item inheritance chain in some Godot versions.

The player's M16 laser (`AssaultRifle.cs`) avoids this by adding the `Line2D` directly to the weapon node (`AddChild(_laserSight)`), which is a `Node2D`.

### Fix
Re-parent laser nodes to `enemy` (the `CharacterBody2D`) instead of `self` (the `EnemySniperComponent` Node). This ensures the `Line2D` is a direct child of a `CanvasItem`, guaranteeing proper rendering.

Also added debug logging to `_create_laser_sight()` and `update_laser_sight()` to help diagnose future issues.

### Additional Fix: Accidental Removal of `bullet_damage_multiplier`
The unification commit accidentally removed the `@export var bullet_damage_multiplier` and its usage in `_spawn_projectile()`. This has been restored.

## Lessons Learned

1. **Visual model and shooting must use the same direction**: When a laser sight is present, it reveals any gap between the visual barrel and the actual aim direction. The only correct fix is to make all systems — laser, bullets, and visual model — agree on direction.

2. **Don't fight the visual model**: Using instant geometric aim while the model rotates smoothly creates a fundamental contradiction that no amount of laser logic can resolve. The solution is to make the bullets follow the barrel, not vice versa.

3. **Remove compensating complexity**: Blind fire had ±3° spread added on top of a snap rotation. By using the visual barrel direction (which already provides natural inaccuracy through smooth interpolation), the extra spread and snap become unnecessary.

4. **Study the reference implementation**: The player's M16 laser works because both the laser and bullets use the same aim direction with no model interpolation lag. The sniper fix achieves the same result by unifying the direction source.

5. **CanvasItem nodes need CanvasItem parents**: In Godot 4, `Line2D` (a `CanvasItem`) should be parented to another `CanvasItem` (like `Node2D`, `CharacterBody2D`) rather than a plain `Node`. While `top_level = true` handles transform independence, the rendering pipeline needs a proper canvas item chain for reliable rendering.

6. **Watch for unrelated regressions**: The unification commit accidentally removed `bullet_damage_multiplier` — an unrelated exported variable. Always diff against the base branch to check for accidental removals.

## Round 7: Laser Still Invisible (2026-03-23, user feedback)

### Symptom
User reports "сейчас всё ещё нет лазера" (there's still no laser). Game log `game_log_20260323_132404.txt` confirms:
- The sniper enemy (ContainerYardA_Sniper, weapon_type=7=SNIPER_RIFLE) IS active, enters COMBAT, fires shots
- **Zero** `[#1336]` log entries — meaning neither `_create_laser_sight()` nor `update_laser_sight()` produced any log output
- The sniper component's `process_combat()` also produced no `[#1163]` logs

### Root Cause Analysis

Three issues identified:

1. **`enemy.get("_is_alive")` returning null**: The `update_laser_sight()` method used `enemy.get("_is_alive")` to check if the enemy is alive. In GDScript 4, `Object.get()` can return `null` for properties depending on timing and internal state. Since `not null` evaluates to `true` in GDScript, this caused the laser to be **permanently hidden** — the function returned early at line 425-427 every single frame.

2. **Laser nodes parented to enemy CharacterBody2D**: While previous fix moved laser from `EnemySniperComponent` (Node) to `enemy` (CharacterBody2D), the enemy node exists in a deep scene hierarchy. Line2D nodes with `top_level=true` parented deep in node hierarchies can still fail to render in Godot 4.3 due to CanvasItem chain issues.

3. **Laser created for ALL enemies**: The `_create_laser_sight()` was called in `_ready()` unconditionally, creating laser nodes for every enemy type. For non-snipers, `update_laser_sight()` immediately hid them, but this was wasteful and created unnecessary nodes.

### Fix

1. **Direct property access**: Changed `enemy.get("_is_alive")` to `enemy._is_alive` — direct property access never returns null.

2. **Scene root parenting**: Changed laser parent from `enemy` to `enemy.get_tree().current_scene` (the scene root), using `call_deferred("add_child", ...)` to avoid tree modification during `_ready()`. Removed `top_level=true` since scene root local coordinates equal global coordinates.

3. **Gated creation**: Added `weapon_type == SNIPER_RIFLE` check in `_ready()` to only create laser for sniper enemies.

4. **Cleanup on exit**: Added `_exit_tree()` to `queue_free()` laser nodes since they're now parented to scene root, not the enemy — they won't be automatically freed when the enemy is freed.

5. **Console debugging**: Added `print()` statements (Godot stdout) alongside FileLogger calls to ensure debug output is visible regardless of FileLogger state.

### Data Sources
- `logs/game_log_20260323_132404.txt` — Game log confirming zero laser output

## Round 8: Laser Still Invisible (2026-03-23, user feedback)

### Symptom
User reports "всё ещё нет лазера" (still no laser). Game log `game_log_20260323_135513.txt` confirms:
- ContainerYardA_Sniper is active (enters COMBAT, fires at player)
- **Zero** `[#1336]` log entries from either `_create_laser_sight()` or `update_laser_sight()`
- Log timestamp 13:55 local (likely ~10:55 UTC), after commit `e877513c` at 10:37 UTC

### Root Cause Analysis

The Round 7 fix used `call_deferred("add_child", ...)` to parent laser nodes to `current_scene` (scene root). This has multiple failure modes:

1. **Deferred addition timing**: `call_deferred` schedules `add_child` for the end of the frame. During `_ready()` of the enemy, `current_scene` may not yet be fully initialized or may change during the deferred call.

2. **Scene transition**: If the level loads asynchronously or scene transitions occur, `current_scene` at deferred-call time may differ from `current_scene` at scheduling time.

3. **No error feedback**: `call_deferred` silently fails if the target node is freed before the deferred call executes. The laser nodes would exist in memory but never be added to the scene tree.

4. **update_laser_sight guard**: The `is_inside_tree()` check at line 435 would return `false` if the deferred add never succeeded, causing the entire update to be skipped silently.

### Fix

Adopted the same approach used by `SniperEnemyTracer` (which renders correctly):
- Parent laser `Line2D` nodes **directly to the enemy `CharacterBody2D`** using synchronous `add_child()` (no `call_deferred`)
- Set `top_level = true` on all laser `Line2D` and `PointLight2D` nodes so they use global coordinates
- Removed the `is_inside_tree()` guard (no longer needed since add_child is synchronous)

This is the simplest possible approach: the enemy node is a `CharacterBody2D` (a `CanvasItem`), so `Line2D` children will render correctly. `top_level = true` ensures coordinates are treated as global regardless of the enemy's position. When the enemy is freed, its children (including laser nodes) are automatically freed — no manual cleanup needed.

### Why This Should Work

The `SniperEnemyTracer` at line 327 of `enemy_sniper_component.gd` uses the exact same pattern:
```gdscript
tracer.top_level = true
tracer.position = Vector2.ZERO
# ...
current_scene.add_child(tracer)
```
Tracers render correctly. The laser now uses:
```gdscript
_laser_sight.top_level = true
# ...
enemy.add_child(_laser_sight)
```
Parenting to `enemy` directly is even safer than `current_scene` since the enemy is guaranteed to exist when `_ready()` runs.

### Data Sources
- `game_log_20260323_135513.txt` — Game log confirming zero laser output
- Comparison with SniperEnemyTracer implementation (proven to render correctly)

## Round 9: Laser Still Invisible (2026-03-23, user feedback)

### Symptom
User reports "всё ещё не отображается лазер" (laser still not displaying). Game log `game_log_20260323_154948.txt` confirms:
- F8-spawned sniper (weapon_type=7=SNIPER_RIFLE) IS active, enters COMBAT, fires and hits player
- **Zero** `[#1336]` log entries — neither creation nor update logged
- **Zero** `[#1163]` log entries — but this is expected (no retreat-distance log when player is at comfortable range)
- Sniper fires gunshots (SoundPropagation logs: range=1634 = sniper weapon_loudness)
- Game runs from exported exe (Debug build: false)

### Root Cause Analysis

After 8 rounds of fixes, three deeper issues were identified:

1. **Laser created during `_ready()` — too early**: All previous approaches called `_create_laser_sight()` from the EnemySniperComponent's `_ready()`. During `_ready()`:
   - `current_scene` may not be fully initialized (scene transitions, async loading)
   - `call_deferred` approaches silently fail if scene changes before deferred call executes
   - `enemy.add_child` with `top_level=true` may not render due to CanvasItem chain issues in Godot 4.3
   - No `print()` debugging was used, so failures were invisible in both stdout and FileLogger

2. **PointLight2D with procedural texture was risky**: Creating a 64x64 Image with pixel-by-pixel iteration and `ImageTexture.create_from_image()` during `_ready()` could silently fail or crash in release builds, potentially aborting the entire `_create_laser_sight()` function before the log line at the end.

3. **`top_level = true` on enemy children may not render**: While the SniperEnemyTracer uses `top_level=true`, it's parented to `current_scene` (scene root), NOT to the enemy. The tracer's `current_scene.add_child(tracer)` pattern is what actually works. Previous rounds incorrectly assumed that `enemy.add_child(laser)` + `top_level=true` would behave the same way.

### Fix (Round 9)

1. **Lazy creation**: Moved laser creation from `_ready()` to the first `update_laser_sight()` call. This runs during `_physics_process()` when the scene tree is guaranteed to be fully initialized, `current_scene` is valid, and FileLogger is ready.

2. **Scene root parenting (no top_level)**: Laser Line2D nodes are added to `current_scene` directly — the SAME pattern used by SniperEnemyTracer (which renders correctly). No `top_level=true` needed since scene root local coordinates equal global coordinates.

3. **Removed PointLight2D endpoint light**: Eliminated the procedural texture creation that could silently crash. The glow layers provide sufficient visual effect.

4. **Added print() debugging**: All creation and first-update paths now use `print()` (Godot stdout) in addition to FileLogger, ensuring debug output is visible regardless of FileLogger state.

5. **Retry mechanism**: If `current_scene` is null on first attempt (rare edge case), `_laser_created` is reset to `false` so creation retries on the next frame.

### Key Insight
The working reference implementations show the pattern:
- **Player M16 laser** (C#): `AddChild(_laserSight)` — child of weapon, local coordinates
- **SniperEnemyTracer** (GDScript): `current_scene.add_child(tracer)` — child of scene root, global coordinates
- **Previous laser attempts** (GDScript): `enemy.add_child(_laser_sight)` with `top_level=true` — this combination never worked

### Data Sources
- `game_log_20260323_154948.txt` — Game log confirming zero laser output after Round 8 fix
- `Scripts/Weapons/AssaultRifle.cs` — Working player M16 laser reference implementation
- `enemy_sniper_component.gd` lines 323-338 — Working SniperEnemyTracer implementation

## Round 10: Laser Still Invisible (2026-03-24, user feedback)

### Symptom
User reports "лазера у снайпера всё ещё нет" (sniper still has no laser). Screenshot shows sniper enemy without any laser beam. Game log `game_log_20260324_054152.txt` confirms:
- ContainerYardA_Sniper is active (weapon_type=7=SNIPER_RIFLE), enters COMBAT, fires shots
- **Zero** `[#1336]` log entries — neither creation nor update logged
- **Zero** `[SniperHitscan]` or `[#1163]` entries from the sniper component
- Sniper fires GUNSHOT events at 05:42:20 and 05:42:31 (confirmed via SoundPropagation)
- Release build (Debug build: false)

### Deep Investigation

Key finding: **Not a single log entry from the sniper component's `_log()` function appears in the game log.** The `_log()` function uses `log_to_file_fn` (a Callable bound to `enemy._log_to_file`), but no output from it ever appears. Meanwhile, `enemy._log_to_file()` works perfectly for other log calls made directly from `enemy.gd` (e.g., `Spawned at`, state transitions, death events).

This raises two hypotheses:
1. **Callable binding issue**: `log_to_file_fn.is_valid()` returns false, silently skipping all log output
2. **The code is running but logs don't include the specific triggered paths**: For hitscan without character hits, and combat without retreat, the `_log()` calls on those code paths simply aren't reached

We cannot distinguish between these hypotheses from the game log alone, since the specific log paths that would prove `_log()` works (retreat, blind-fire, hitscan hit) were not triggered in this gameplay session.

### Root Cause Hypothesis

The Round 9 laser creation code uses `current_scene.add_child(_laser_sight)` WITHOUT `top_level = true`. The SniperEnemyTracer (which renders) uses BOTH `current_scene.add_child(tracer)` AND `top_level = true`. The absence of `top_level` is a difference from the proven working pattern.

Additionally, Round 9 initialized the Line2D with `add_point(Vector2.ZERO)` × 2 (zero-length line), then updated positions in the same frame via `set_point_position()`. The tracer initializes with REAL coordinates at creation time: `tracer.add_point(from_pos); tracer.add_point(end_pos)`.

### Fix (Round 10)

Three changes to exactly mirror the SniperEnemyTracer:

1. **`top_level = true` + `position = Vector2.ZERO`**: Added to laser Line2D and all glow layers, exactly matching the tracer's properties. This ensures global coordinate rendering independent of parent transform.

2. **Real coordinates at creation time**: Instead of creating with `Vector2.ZERO` placeholders and updating later, the laser is now born with actual start/end positions computed from the barrel direction. This mirrors how the tracer is created with `from_pos` and `end_pos`.

3. **Triple-redundant logging**: The `_log()` function now uses three strategies to ensure messages appear:
   - Primary: `log_to_file_fn.call(message)` (bound callable)
   - Fallback: Direct `get_node_or_null("/root/FileLogger").log_enemy()` access
   - Always: `print()` to stdout
   This guarantees that if the laser code runs, we WILL see diagnostic output regardless of callable binding state.

### What This Tells Us If It Still Fails

If the user tests this build and:
- **No `[#1336]` entries in game log AND no `[SniperComponent]` in stdout**: `update_laser_sight()` is never called. Root cause is in `enemy.gd`'s `_physics_process` — the `weapon_type` check fails or `_sniper_component` is null for this enemy.
- **`[#1336]` entries appear but laser invisible**: The Line2D is being created and updated correctly but Godot's rendering pipeline doesn't show it. Would indicate a Godot 4.3 rendering bug with dynamically created Line2D nodes.
- **Laser appears**: Fix works.

### Data Sources
- `game_log_20260324_054152.txt` — Game log confirming zero laser output after Round 9 fix
- Screenshot showing sniper enemy without laser beam
- Comparison with SniperEnemyTracer properties (top_level, position, add_point pattern)
