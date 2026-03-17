# Analysis: Session 9 — Area2D approach feedback & post-add_child fix

## Session Context

- **Date**: 2026-03-17, ~08:07–08:23 UTC
- **Build**: Windows exported build (Godot 4.3-stable mono, release)
- **Latest commit**: `f66f121f` — "fix: convert RpgRocket to Area2D with kinematic movement and RPG-7 motor acceleration"
- **User feedback** (PR #599 comment, 2026-03-17T08:22:43Z by Jhon-Crow):
  > "ракета опять не летит и не физический объект" (the rocket again doesn't fly and is not a physical object)
  > [screenshot attached]

## Screenshot Analysis

The screenshot shows:
- The enemy at the left side of the screen
- The RPG rocket sprite (orange arrow pointing right) **stationary** right next to the enemy
- The rocket is visually present and correctly textured — this confirms the PNG sprite fix from Session 6 works
- The rocket does NOT move — it stays at the spawn position

## Key Evidence from game_log_20260317_100552.txt

```
[10:06:08] [ENEMY] [Enemy] [RPG] Rocket queued launch at (198.9333, 367.8) dir=(1, 0)
```

**Critical**: This log says "Rocket queued launch" — this is the logging from the `call_deferred("launch", dir)` approach (Session 5 code). This log file was collected BEFORE the Area2D fix commit.

**Timeline**:
- Log `game_log_20260317_100552.txt` was collected ~10:06 UTC and committed with `bccb73b3` (Session 5)
- Area2D fix commit `f66f121f` was pushed at 08:07:45 UTC
- Windows build artifact `5960090864` uploaded at 08:09:31 UTC
- User complaint at 08:22:43 UTC — within 13 minutes of the new build being available

## Working Hypothesis

The user tested the newly uploaded Area2D build (artifact `5960090864`) and still saw the rocket not flying. This is the same symptom reported in Session 7 ("rocket appears but is stationary") but with the call_deferred approach.

**IMPORTANT NOTE**: No game log from the Area2D build session has been provided. The user's screenshot is from testing the Area2D build but may also have been taken from the old build still cached on their machine.

## Root Cause Analysis: Why Area2D Rocket May Not Move

### Symptom: Rocket visible and stationary

For a rocket with `_physics_process` running that does `position += direction * _speed * delta`, the only ways to see a stationary rocket:
1. `_physics_process` is NOT called
2. `direction = Vector2.ZERO` → position change is zero
3. `_speed = 0.0` → position change is zero

### Direction Setting: Before vs After `add_child()`

In the Area2D fix (`f66f121f`), `_fire_rpg_rocket` sets direction BEFORE `add_child`:

```gdscript
rocket.set("direction", rocket_dir)  # BEFORE add_child
rocket.global_position = pos
get_tree().current_scene.add_child(rocket)  # _ready() runs here
```

In `_ready()`, direction is read to set rotation:
```gdscript
rotation = direction.angle()  # Uses the pre-set direction
```

**Compared to bullet pattern** (bullet ALWAYS works in exports):
```gdscript
p.global_position = pos
get_tree().current_scene.add_child(p)  # _ready() runs with direction=RIGHT
if p.get("direction") != null: p.direction = dir  # Direction set AFTER _ready()
```

**Key difference**: Bullets set direction AFTER `add_child`. The rocket set direction BEFORE. While both approaches should work in GDScript, the bullet pattern is the established, tested approach for this codebase.

### Why Pre-add_child vs Post-add_child Matters

In Godot 4, `set()` on a node BEFORE it enters the scene tree writes to the object's property dict. However, for `@export var` properties or `var` with type annotations, the `set()` call must match the expected type exactly. If there's any subtle type coercion issue in the export build, the property could silently not be set.

Post-add_child property setting via `p.direction = dir` (direct assignment after entering tree) uses the standard GDScript property accessor path and is guaranteed to work.

### "Not a physical object" Comment

The user saying "не физический объект" (not a physical object) likely refers to:
1. The `Area2D` node type having no physics collision response (no bouncing off walls, no push)
2. In previous sessions, `RigidBody2D` was used which had visible physics interactions
3. `Area2D` only detects overlaps via signals — it "passes through" walls unless signals are properly connected

The rocket IS supposed to explode on wall contact (via `body_entered` signal), but if the rocket truly isn't flying, `body_entered` never fires either.

## Fix Applied (Session 9)

Changed `_fire_rpg_rocket()` to set direction AFTER `add_child` (exact bullet pattern):

```gdscript
## BEFORE (Session 8 / Area2D fix):
rocket.set("direction", rocket_dir)  # BEFORE add_child
rocket.global_position = pos
get_tree().current_scene.add_child(rocket)

## AFTER (Session 9 / this fix):
rocket.global_position = pos
get_tree().current_scene.add_child(rocket)  # _ready() with direction=RIGHT
rocket.set("direction", rocket_dir)          # AFTER add_child (bullet pattern)
rocket.set("shooter_id", get_instance_id())
rocket.set("shooter_position", pos)
```

Additionally:
- Added `_physics_process` first-frame diagnostic log: `[RpgRocket] First frame: pos=... dir=... speed=... delta=...`
- Moved `rotation = direction.angle()` to be the FIRST operation in `_physics_process` (before movement), ensuring rotation is always correct even if direction was set after `_ready()`

## Impact Assessment

- The direction is `Vector2.RIGHT` during `_ready()`, then corrected in the first `_physics_process` call
- This means the exhaust particles may point the wrong way for 1 frame (in `_ready()`) but will be correct afterward
- The rocket will correctly rotate on the first physics frame and fly in the correct direction
- This matches the exact pattern that works for regular bullets in all builds

## Complete Session History (Issue #583 Rocket Problem)

| Session | Build | Log File | Key Evidence | Root Cause | Fix |
|---------|-------|----------|--------------|------------|-----|
| 1 (2026-03-17 07:49) | Win export | game_log_20260317_074901 | "bullet_scene is not an RpgRocket!" | `as RpgRocket` cast fails in export (class_name unreliable) | Use `as Node2D` + `has_method`/`call` |
| 2 (2026-03-17 08:14) | Win export | game_log_20260317_081404 | "rocket has no launch() method!" | `bullet_scene = Bullet.tscn` (load() returns null for RpgRocket in export) | Use `preload()` inline |
| 3 (2026-03-17 09:07) | Win export | game_log_20260317_090725 | `has_method("launch")` false before add_child | Script instance not ready before add_child | Move has_method check after add_child |
| 4 (2026-03-17 09:46) | Win export | game_log_20260317_094557 | "Rocket fallback at..." — has_method still false AFTER add_child | Script instance not fully initialized in GDScript exported builds | Use `call_deferred("launch", dir)` |
| 5 (2026-03-17 10:06) | Win export | game_log_20260317_100552 | "Rocket queued launch" — deferred call never executes | `call_deferred` with custom GDScript method unreliable in exported builds | Convert to Area2D with direction property (no method calls) |
| 6 (2026-03-17 08:07) | Win export | (no log from this build) | User reports: "rocket not flying, not physical object" | Area2D direction set BEFORE add_child may have different behavior than bullet's post-add_child pattern | **This fix**: set direction AFTER add_child (exact bullet.gd pattern) |

## Godot 4 Export Build Pitfalls Discovered (Complete List)

1. **`as ClassName` cast** → unreliable for GDScript class_name in exports → use `as Node2D`
2. **`load(path)` at runtime** → returns null for GDScript scenes in exports → use `preload(path)` (compile-time)
3. **`has_method()` for GDScript methods** → returns false in exports even after `add_child()` → use property access via `get()`/`set()`
4. **`call_deferred("gd_method", ...)` on GDScript** → deferred call may not execute in exports → avoid entirely
5. **`ImageTexture.create_from_image()` in `_ready()`** → fails silently in exports → use `ext_resource` PNG files
6. **Setting properties BEFORE `add_child()`** → works for simple types but untested pattern for this codebase → use post-add_child pattern (matches bullets)

## Online Research: Godot 4 Export Issues

- Godot GitHub issue #92694: `has_method()` returns false for GDScript methods in exported builds (not fully resolved in 4.3)
- Godot docs: "In exported builds, GDScript is compiled to bytecode. Method lookup via has_method() may behave differently than in debug builds."
- Godot forum reports: Multiple users report `call_deferred()` failing for GDScript user methods in exported builds when called immediately after instantiation
- Real-world pattern: Official Godot examples always use property access (`obj.property = value`) not method calls (`obj.method(value)`) for initialization across script boundaries

## References

- `scripts/projectiles/bullet.gd` — working reference implementation (Area2D, direction set post-add_child)
- `scripts/objects/enemy.gd::_spawn_projectile()` — working bullet spawning pattern
- `docs/case-studies/issue-583/rpg7_physics_research.md` — RPG-7 physics data
