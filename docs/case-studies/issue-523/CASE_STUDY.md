# Case Study: Issue #523 - Fix ASVK Sniper Rifle

- **Repository:** Jhon-Crow/godot-topdown-MVP
- **Issue:** #523
- **Pull Request:** #532
- **Branch:** issue-523-08f8133b19e3

## Summary

Issue #523 requested a comprehensive redesign of the ASVK sniper rifle mechanics. The initial implementation covered 9 requirements (bolt-action reload, smoke trail, slow rotation, larger casings, ASVK sounds, tutorial, removed laser sight). After the initial PR was created, user testing revealed several additional issues and refinements needed in a second feedback round.

## Timeline of Events

### Round 1: Initial Issue (2026-02-06)

**Original requirements (Russian → English):**

1. Outside aiming, rifle should rotate very slowly (~4x less sensitivity) → **Initially implemented with 0.25 factor**
2. Tracer should be smoke trail (instant appear, fade) not bullet-like → **Implemented as Line2D with gradient fade**
3. Bolt cycling conflicts with walking - remove walking from arrows → **Initially blocked ALL movement**
4. Replace reload with bolt-action: Left→Down→Up→Right → **Implemented as 4-step BoltActionStep enum**
5. Add ASVK sniper training on Tutorial map → **Added sniper detection in tutorial_level.gd**
6. 12.7x108mm casings should be larger than M16 casings → **Added effect_scale support in casing.gd**
7. Remove laser sight → **Removed LaserSight node and code**
8. Eject casing on step 2 (Down arrow) → **SpawnCasing called during step 2**
9. Add ASVK-specific sounds → **Added 5 sound constants (shot + 4 bolt steps)**

### Round 2: First Feedback (2026-02-06T22:03)

User tested the implementation and reported:

> "обновись из main" — Merge from main (PR #528 scope system was merged)

> "в режиме прицеливания должна быть возможность немного (треть вьюпорта примерно) перемещаться дальше/ближе"
— In scope mode, allow ~1/3 viewport movement further/closer

> "выстрелы должны лететь в центр прицела (сейчас летят не туда)"
— Bullets should fly to crosshair center (currently go elsewhere)

> "сделай минимальную дальность прицела ещё на пол вьюпорта дальше"
— Increase minimum scope distance by half viewport

> "сделай чтоб из-за чувствительности чем дальше (скроллом) в режиме прицеливания отдаляется игрок тем сложнее было бы целиться"
— Sensitivity should scale with scope distance (farther = harder to aim)

### Round 3: Bug Reports (2026-02-06T22:07)

User attached 3 game log files and reported additional issues:

> "управление на wasd не должно блокироваться, только на стрелочки"
— WASD movement should NOT be blocked, only arrow keys

> "обучение для ASVK не работает (должен быть один выстрел, затем обучение зарядке, затем прицелу)"
— ASVK tutorial broken. Should be: one shot → reload training → scope training

> "дымного следа после выстрела нет"
— Smoke trail after shot is not visible

> "на сложности pawer fantasy у всего оружия (в том числе и снайперской винтовки) должен быть синий лазер"
— On Power Fantasy difficulty, all weapons (including sniper) should have blue laser

> "поворачивать винтовку вне прицеливания должно быть в 5 раз труднее"
— Non-aiming rotation should be 5x harder (not 4x as initially implemented)

## Root Cause Analysis

### Bug 1: WASD Blocked During Bolt Cycling

**Root Cause:** The bolt-action input used `Input.IsActionJustPressed("move_left")` etc., which respond to BOTH WASD and arrow keys (since both are bound to the same actions in project.godot). The `GetInputDirection()` method in Player.cs returned `Vector2.Zero` when `IsBoltCycling` was true, blocking ALL movement instead of just arrows.

**Fix:** Changed bolt-action input to use `Input.IsKeyPressed(Key.Left/Down/Up/Right)` for arrow-key-only detection with manual edge detection. Changed Player.cs to use `Input.IsPhysicalKeyPressed(Key.A/D/W/S)` for WASD-only movement during bolt cycling.

### Bug 2: Bullets Not Hitting Crosshair Center

**Root Cause:** The `_scopeMouseOffset` was applied to BOTH the camera offset (world-space) AND the crosshair screen position, creating a doubled effect. The aim target calculation (`GetScopeAimTarget()`) only accounted for one instance of `_scopeMouseOffset`, causing bullets to fly to a point that didn't match the crosshair's visual position.

**Fix:** Changed the crosshair to stay at viewport center (camera offset alone moves the world view), so the world position at the crosshair center matches `GetScopeAimTarget()`.

### Bug 3: Smoke Trail Not Visible

**Root Cause:** The tracer Line2D had `ZIndex = -1`, placing it behind game elements (likely behind the tilemap/ground layer).

**Fix:** Changed `ZIndex` to `10` to render above game elements. Also increased width from 6 to 8 for better visibility.

### Bug 4: Tutorial Not Working for Sniper

**Root Cause:** The tutorial required hitting ALL targets before advancing to reload step, but sniper should advance after one shot. Also, there was no scope training step in the tutorial flow.

**Fix:** Added `SCOPE_TRAINING` tutorial step. Sniper advances to reload after first hit, then to scope training after bolt cycle, then to grenade. Connected `ScopeStateChanged` signal.

### Bug 5: No Blue Laser in Power Fantasy

**Root Cause:** `SniperRifle._Ready()` unconditionally removed the LaserSight node without checking for Power Fantasy difficulty, unlike other weapons (MiniUzi, Shotgun) that conditionally create a blue laser.

**Fix:** Added Power Fantasy check using `should_force_blue_laser_sight()` and `get_power_fantasy_laser_color()` from DifficultyManager, following the same pattern as MiniUzi and Shotgun.

## Game Log Analysis

Three game log files were provided by the user:

| File | Duration | Level | Key Observations |
|------|----------|-------|-----------------|
| game_log_20260207_010500.txt | ~2 min | Tutorial (TestTier) | Clean execution, no errors |
| game_log_20260207_010828.txt | ~37 sec | BuildingLevel | SniperRifle shots detected, enemy AI responding |
| game_log_20260207_011021.txt | ~6 sec | BuildingLevel | Very short session, likely quick exit |

**Notable findings:**
- No crash messages or exceptions in any log
- Sound propagation working correctly (enemies detect sniper shots at 3000 range)
- C# GD.Print messages from SniperRifle not captured in game log (log format only captures GDScript prints)
- No explicit error messages about movement blocking, but the user's feedback confirms the issue existed

## Files Changed

| File | Changes |
|------|---------|
| `Scripts/Weapons/SniperRifle.cs` | Arrow-only bolt input, 5x sensitivity, Power Fantasy laser, visible smoke trail, scope fixes |
| `Scripts/Characters/Player.cs` | WASD-only movement during bolt cycling |
| `scripts/levels/tutorial_level.gd` | SCOPE_TRAINING step, first-hit advance, scope signal |

## Lessons Learned

1. **Input action mapping**: Godot's `Input.IsActionJustPressed()` responds to ALL keys bound to an action. When actions need to be split (arrows for one purpose, WASD for another), use raw key detection (`Input.IsKeyPressed(Key.X)` or `Input.IsPhysicalKeyPressed(Key.X)`).

2. **Camera + UI offset doubling**: When both the camera and a UI element are offset by the same value, the visual position shifts by 2x the offset in world space. Either keep the UI element at center (camera does the moving) or halve the offset for one of them.

3. **ZIndex matters**: Line2D effects with negative ZIndex can be hidden behind tilemaps or ground layers. Use positive ZIndex (10+) for visual effects that should be visible.

4. **Difficulty-specific features**: All weapons should check DifficultyManager in `_Ready()` for mode-specific features like Power Fantasy blue laser.

5. **Tutorial flow per weapon**: Different weapons need different tutorial sequences. The sniper needs: shoot → bolt-action reload → scope → grenade.
