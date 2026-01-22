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

## Pull Request Checklist

Before submitting a PR, verify:

- [ ] **Tests pass**: All unit and integration tests pass
- [ ] **New tests added**: For new features or bug fixes
- [ ] **CI passes**: Both `test.yml` and `architecture-check.yml` workflows pass
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

## Getting Help

- Check existing issues for similar problems
- Review closed issues for context on past fixes
- Ask questions in the issue tracker before making large changes

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).
