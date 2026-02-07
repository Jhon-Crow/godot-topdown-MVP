# Case Study: Issue #461 - Architecture Review and Improvement

## Timeline

- **Issue Created**: Issue #461 requested a full architecture review: check for unused code blocks, move disabled features to experimental settings, create abstract classes if needed, and remove unused soldier assets.
- **Analysis Completed**: Deep analysis of 72 GDScript files, 47 scenes, 9 resources, and all assets.
- **Fix Implemented**: Removed unused code/assets, moved debug features to ExperimentalSettings, cleaned up deprecated methods.

## Root Cause Analysis

The codebase had accumulated technical debt through natural development:

1. **Unused Assets**: Three legacy soldier sprites (`soldier.png`, `soldier_officer.png`, `soldier_spear.png`) remained from before the modular character sprite system was implemented. No code, scene, or resource referenced them.

2. **Dead Code**: Legacy `_sprite` variables in `player.gd` (line 89) and `enemy.gd` (line 124) were kept "for compatibility" but never used - all code uses the modular `_body_sprite`, `_head_sprite`, etc.

3. **Test Artifacts**: `test_impact_effects_manager.gd` (6 lines, just prints) and `minimal_impact_effects_manager.gd` (59 lines, stub methods) were created during debugging but never registered as autoloads.

4. **Deprecated Methods**: Four deprecated methods in `impact_effects_manager.gd` were kept "for backwards compatibility" but had zero callers: `_create_grenade_flash()`, `_create_grenade_light()`, `_player_has_line_of_sight_to()`, `_player_has_line_of_sight_to_legacy()`.

5. **Debug Features Not in Experimental Settings**: Debug mode (F7) and invincibility (F6) in `game_manager.gd` were developer features accessible in exported builds without persistence or UI toggles.

6. **Empty Process Function**: `main.gd` had an empty `_process()` function causing unnecessary per-frame overhead.

## Architecture Assessment

### Strengths
- **Component-based design**: Good use of components (`HealthComponent`, `AmmoComponent`, `DeathAnimationComponent`, `GrenadeAvoidanceComponent`, etc.)
- **GOAP AI system**: Well-structured `GOAPAction` base class and `GOAPPlanner` with A* search
- **ExperimentalSettings pattern**: Clean singleton with persistence, signals, and UI menu
- **Grenade class hierarchy**: Proper abstract base `GrenadeBase` with `FragGrenade`, `DefensiveGrenade`, `FlashbangGrenade` subclasses
- **Caliber data resources**: Good use of `.tres` resources for weapon/caliber data
- **CI architecture checks**: Automated line count, naming, and structure validation

### Areas for Future Improvement
- **Monolithic scripts**: `enemy.gd` (4999 lines) and `player.gd` (2725 lines) would benefit from further component extraction
- **Unused state pattern**: `EnemyState` base class, `IdleState`, `PursuingState` exist but `enemy.gd` uses enum-based state machine instead
- **Code duplication**: Walking animation code is nearly identical between player.gd and enemy.gd
- **Deprecated throw_grenade()**: Still used as fallback in player.gd and enemy_grenade_component.gd

## Changes Made

### Removed (unused code and assets)
| Item | Type | Reason |
|------|------|--------|
| `soldier.png` | Asset | Not referenced by any code, scene, or resource |
| `soldier_officer.png` | Asset | Not referenced by any code, scene, or resource |
| `soldier_spear.png` | Asset | Not referenced by any code, scene, or resource |
| `_sprite` in player.gd | Variable | Legacy alias for `_body_sprite`, never used |
| `_sprite` in enemy.gd | Variable | Legacy alias for `_body_sprite`, never used |
| `test_impact_effects_manager.gd` | File | Test stub, not registered as autoload |
| `minimal_impact_effects_manager.gd` | File | Debug stub, not registered as autoload |
| `_create_grenade_flash()` | Method | Deprecated, zero callers |
| `_create_grenade_light()` | Method | Deprecated, zero callers |
| `_player_has_line_of_sight_to()` | Method | Deprecated, zero callers |
| `_player_has_line_of_sight_to_legacy()` | Method | Deprecated, zero callers |
| `_get_player()` in impact_effects_manager.gd | Method | Only used by removed deprecated methods |
| `_process()` in main.gd | Method | Empty function causing per-frame overhead |

### Added (experimental settings integration)
| Item | Description |
|------|-------------|
| `debug_mode_enabled` in ExperimentalSettings | Persisted debug mode setting |
| `invincibility_enabled` in ExperimentalSettings | Persisted invincibility setting |
| Debug Mode checkbox in ExperimentalMenu | UI toggle for F7 debug mode |
| Invincibility checkbox in ExperimentalMenu | UI toggle for F6 invincibility |
| `_sync_from_experimental_settings()` in GameManager | Restores debug/invincibility state on startup |

## Proposed Solutions for Future Work

### 1. Player Script Decomposition
Extract from the 2725-line `player.gd` into components:
- `PlayerGrenadeComponent` (~800 lines of grenade logic)
- `PlayerReloadComponent` (~200 lines of reload logic)
- `PlayerShootingComponent` (shooting mechanics)
- `PlayerAnimationComponent` (walking/grenade/reload animations)

### 2. Enemy Script Decomposition
Extract from the 4999-line `enemy.gd`:
- Adopt the existing `EnemyState` pattern (replace enum-based state machine)
- Extract `EnemySoundComponent` (sound handling)
- Extract shared `WalkAnimationComponent` (eliminate duplication with player)
- Extract shared `CasingPusherComponent` (eliminate duplication with player)

### 3. Existing Tools and Libraries
- **gdtoolkit** (`pip3 install "gdtoolkit==4.*"`): GDScript linter and formatter for CI
- **GdPlanningAI**: Advanced GOAP framework for Godot (alternative to custom implementation)
- **Godot 4.5 `@abstract` annotation**: When available, formalize abstract classes

## Files Changed
- `assets/sprites/characters/soldier.png` (deleted)
- `assets/sprites/characters/soldier_officer.png` (deleted)
- `assets/sprites/characters/soldier_spear.png` (deleted)
- `scripts/autoload/test_impact_effects_manager.gd` (deleted)
- `scripts/autoload/minimal_impact_effects_manager.gd` (deleted)
- `scripts/characters/player.gd` (removed legacy `_sprite`)
- `scripts/objects/enemy.gd` (removed legacy `_sprite`)
- `scripts/main.gd` (removed empty `_process()`)
- `scripts/autoload/impact_effects_manager.gd` (removed deprecated methods)
- `scripts/autoload/experimental_settings.gd` (added debug/invincibility settings)
- `scripts/autoload/game_manager.gd` (delegate to ExperimentalSettings)
- `scripts/ui/experimental_menu.gd` (added debug/invincibility toggles)
- `scenes/ui/ExperimentalMenu.tscn` (added toggle UI elements)

## References
- [Godot Project Organization Best Practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)
- [Entity-Component Pattern in Godot (GDQuest)](https://www.gdquest.com/tutorial/godot/design-patterns/entity-component-pattern/)
- [GDScript Toolkit for linting](https://github.com/Scony/godot-gdscript-toolkit)
- [GOAP AI Architecture](https://github.com/godotengine/godot-proposals/issues/4954)
