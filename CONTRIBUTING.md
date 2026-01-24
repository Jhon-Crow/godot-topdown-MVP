# Contributing to Godot Top-Down Template

Thank you for your interest in contributing! This document provides guidelines to help maintain code quality and prevent common issues.

## Table of Contents

- [Development Setup](#development-setup)
- [Testing Guidelines](#testing-guidelines)
- [Common Issues to Avoid](#common-issues-to-avoid)
- [Pull Request Checklist](#pull-request-checklist)
- [Architecture Guidelines](#architecture-guidelines)

## Development Setup

1. Clone the repository
2. Open in Godot Engine 4.3+ (with .NET support for C# features)
3. Run existing tests before making changes: `make test` or use the GUT addon

## Testing Guidelines

### Running Tests

Tests are located in `tests/unit/` and `tests/integration/`. Run them using:

1. **In Godot**: Open the GUT addon panel and click "Run All"
2. **Command Line**: Use the CI workflow command:
   ```bash
   godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -ginclude_subdirs -gexit
   ```

### Writing Tests

- **Every new feature MUST have tests** covering its core functionality
- **Every bug fix MUST have a regression test** preventing the bug from returning
- Use mock classes to test logic without requiring Godot scene tree
- Follow the existing test patterns in `tests/unit/`

### Test Coverage Requirements

The following areas have comprehensive test coverage:

| Component | Test File | Coverage |
|-----------|-----------|----------|
| Audio Manager | `test_audio_manager.gd` | Sound playback, pools |
| Difficulty Manager | `test_difficulty_manager.gd` | Settings, levels |
| Enemy AI | `test_enemy.gd` | States, behaviors |
| GOAP Planner | `test_goap_planner.gd` | Planning, actions |
| Player | `test_player.gd` | Movement, shooting |
| Health Component | `test_health_component.gd` | Damage, healing |
| Vision Component | `test_vision_component.gd` | Detection, LOS |
| Cover Component | `test_cover_component.gd` | Cover finding |
| Grenade System | `test_grenade_base.gd` | Timer, throw physics |
| Status Effects | `test_status_effects_manager.gd` | Blindness, stun |
| Shrapnel | `test_shrapnel.gd` | Movement, ricochet |

## Common Issues to Avoid

Based on historical issues, please pay special attention to these areas:

### 1. Self-Damage Bugs (Issue #241)
**Problem**: Player bullets damaging the player
**Solution**: Always use `shooter_id` tracking for projectiles
```gdscript
# Good: Track who fired the projectile
var shooter_id: int = -1
func _on_body_entered(body):
    if body.get_instance_id() == shooter_id:
        return  # Don't hit shooter
```

### 2. Shotgun Reload Regressions (Issues #213, #229, #232, #243)
**Problem**: Shotgun reload functionality breaking after unrelated changes
**Solution**:
- Always run `test_magazine_inventory.gd` after weapon changes
- Test both Simple and Sequence reload modes
- Verify MMB + RMB interaction for shell loading

### 3. Enemy Fire Rate Issues (Issue #228)
**Problem**: Enemies ignoring weapon fire rate limits
**Solution**: Use the weapon's `shoot_cooldown` property
```gdscript
# Good: Respect fire rate
if _shoot_timer >= weapon.shoot_cooldown:
    shoot()
    _shoot_timer = 0.0
```

### 4. Feature Regression (Issue #232)
**Problem**: Fixed functionality breaking in later commits
**Solution**:
- Write regression tests for every bug fix
- Run full test suite before committing
- Check closed issues for functionality that must be preserved

### 5. C# Build Failures (Issue #302, PR #275)
**Problem**: C# compilation errors cause ".NET assemblies not found" in exports
**Solution**:
- Always run `dotnet build` locally before pushing C# changes
- Check CI workflow `csharp-validation.yml` for build status
- When modifying C# method signatures, search for all call sites

```bash
# Always verify C# builds before pushing
dotnet build

# Search for method usages before changing signatures
grep -rn "MethodName" Scripts/
```

### 6. C#/GDScript Interoperability Issues (Issue #302)
**Problem**: C# and GDScript components getting out of sync
**Solution**:
- Keep duplicate implementations intentional and documented
- Use `interop-check.yml` CI workflow to detect issues
- When calling C# from GDScript, use `node.call("MethodName")`

```gdscript
# Good: Safe cross-language call
if node.has_method("TakeDamage"):
    node.call("TakeDamage", damage_amount)

# Bad: Assumes C# method exists
node.TakeDamage(damage_amount)  # May crash if C# failed to compile
```

### 7. Enemy AI Breaking (Issues #104, #296, #157, PR #308)
**Problem**: Changes that completely break enemy behavior - enemies not moving, not taking damage, not detecting player
**Solution**:
- Never remove or rename critical methods: `_ready`, `_physics_process`, `on_bullet_hit`, `_die`, `_check_player_visibility`
- Preserve required state variables: `_is_alive`, `_current_health`, `_current_state`, `_player`, `_can_see_player`
- Maintain all AIState enum values (IDLE, COMBAT, SEEKING_COVER, etc.)
- Test enemy behavior after ANY changes to `scripts/objects/enemy.gd` or `scripts/ai/`
- Check `gameplay-validation.yml` CI workflow for issues

```gdscript
# Critical: Always check _is_alive in state updates
func _physics_process(delta: float) -> void:
    if not _is_alive:
        return
    # ... rest of behavior

# Critical: _die() must emit signal for proper counting
func _die() -> void:
    _is_alive = false
    died.emit()  # Required for enemy counting!
```

### 8. Game Counter Breaking (Issue #127)
**Problem**: Enemy counters, ammo counters, or game state breaking after changes
**Solution**:
- Ensure `died` signal is emitted when enemy dies
- Verify signal connections in GameManager/autoloads
- Test that game properly ends after clearing all enemies
- Test ammo display updates correctly during combat

```gdscript
# Critical: Always emit signals for counter updates
func _die() -> void:
    _is_alive = false
    died.emit()  # GameManager listens for this!
    died_with_info.emit(is_ricochet, is_penetration)

func shoot() -> void:
    _current_ammo -= 1
    ammo_changed.emit(_current_ammo, _reserve_ammo)  # UI listens for this!
```

### 9. Game Crashes (Issue #155)
**Problem**: Changes causing the game to crash
**Solution**:
- Always add null checks before accessing nodes or properties
- Verify PackedScene resources exist before instantiating
- Use `is_instance_valid()` before accessing potentially freed nodes
- Add error handling for file/resource loading

```gdscript
# Good: Safe scene instantiation
if bullet_scene:
    var bullet = bullet_scene.instantiate()
    get_tree().root.add_child(bullet)

# Good: Safe node access
if is_instance_valid(_player):
    var dir = global_position.direction_to(_player.global_position)
```

## Pull Request Checklist

Before submitting a PR, verify:

- [ ] **Tests pass**: All unit and integration tests pass
- [ ] **New tests added**: For new features or bug fixes
- [ ] **CI passes**: All workflows pass (`test.yml`, `architecture-check.yml`, `csharp-validation.yml`, `interop-check.yml`, `gameplay-validation.yml`)
- [ ] **C# builds locally**: Run `dotnet build` for C# changes
- [ ] **No regressions**: Related functionality still works
- [ ] **Code follows style**: snake_case for GDScript, PascalCase for C#
- [ ] **Line limits**: Scripts under 5000 lines (target: 800)
- [ ] **class_name declared**: For components and AI states

### Before Merging

1. Verify all CI checks are green
2. Test the specific functionality affected
3. Test related functionality that might be impacted
4. Run the game and verify gameplay is not broken

## Architecture Guidelines

### File Organization

```
scripts/
├── autoload/      # Singleton managers (AudioManager, GameManager, etc.)
├── ai/            # AI systems (GOAP, states)
├── characters/    # Character scripts
├── components/    # Reusable components (HealthComponent, etc.)
├── effects/       # Visual effects
├── objects/       # Game objects (enemies, targets)
├── projectiles/   # Bullets, grenades, shrapnel
├── ui/            # UI scripts
└── data/          # Data definitions (calibers, etc.)
```

### Naming Conventions

- **GDScript files**: `snake_case.gd`
- **C# files**: `PascalCase.cs`
- **Scenes**: `PascalCase.tscn`
- **Resources**: `snake_case.tres`

### Component Pattern

Use reusable components for common functionality:

```gdscript
# Good: Use component
var health_component := HealthComponent.new()
health_component.set_max_health(100)
add_child(health_component)

# Bad: Inline health logic
var health := 100
func take_damage(amount):
    health -= amount
    # Duplicated health logic...
```

### Autoload Access

Always use null checks when accessing autoloads:

```gdscript
# Good: Safe access
var audio_manager = get_node_or_null("/root/AudioManager")
if audio_manager and audio_manager.has_method("play_sound"):
    audio_manager.play_sound("res://sound.wav")

# Bad: Direct access
AudioManager.play_sound("res://sound.wav")  # Crashes if autoload missing
```

## CI/CD Workflows

### test.yml
Runs GUT tests on push/PR to ensure functionality is preserved.

### architecture-check.yml
Verifies:
- Script line counts (max 5000 lines)
- class_name declarations in components
- Required folder structure
- snake_case naming convention

### csharp-validation.yml
**Protection against C# build failures** (Issue #302):
- Validates C# code compiles with `dotnet build`
- Verifies assembly DLL is produced
- Catches errors that would cause ".NET assemblies not found" in exports

### interop-check.yml
**Protection against C#/GDScript integration issues** (Issue #302):
- Detects duplicate implementations across languages
- Checks scene signal connections to C# scripts
- Validates autoload references
- Warns about potential interoperability issues

### gameplay-validation.yml
**Protection against critical gameplay breaking** (Issue #308):
- Validates enemy AI state machine integrity (required states, methods, variables)
- Detects dangerous code patterns (infinite loops, division by zero risks)
- Checks health component structure
- Validates counter/state reset signals
- Verifies scene-script references exist
- Warns when critical gameplay files are modified

This workflow was added to prevent issues like:
- PR #104, #296: Enemy AI completely broken (not moving, not taking damage)
- PR #127: Game counters broken (enemy count, ammo count)
- PR #155: Game crashes
- PR #157: Enemy vision/detection broken

## Getting Help

- Check existing issues for similar problems
- Review closed issues for context on past fixes
- Ask questions in the issue tracker before making large changes

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).
