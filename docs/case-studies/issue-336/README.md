# Case Study: Issue #336 - Set Maximum File Size to 2500 Lines

## Problem Description

The issue requests:
1. Set maximum allowed file size to 2500 lines in GitHub Actions
2. Refactor existing code to follow best practices

Currently, the `architecture-check.yml` workflow has:
- `MAX_LINES=5000` (hard limit causing CI errors)
- `WARN_LINES=800` (warning threshold)
- `CRITICAL_THRESHOLD=4500` (90% of max - pre-emptive warning)

## Current State Analysis

### Files Exceeding 2500 Lines

| File | Lines | Status |
|------|-------|--------|
| `scripts/objects/enemy.gd` | 5000 | **CRITICAL** - At current limit |
| `Scripts/Characters/Player.cs` | 3040 | **OVER** - Needs refactoring |

### Files Approaching the Limit

| File | Lines | Status |
|------|-------|--------|
| `scripts/characters/player.gd` | 2208 | OK (under 2500) |
| `Scripts/Weapons/Shotgun.cs` | 1621 | OK |
| `tests/unit/test_enemy.gd` | 1520 | OK (tests excluded) |
| `Scripts/Projectiles/Bullet.cs` | 1277 | OK |

## Root Cause Analysis

### Why Large Files Are Problematic

Based on research from [ESLint max-lines rule](https://eslint.org/docs/latest/rules/max-lines), [Quora discussions](https://www.quora.com/Is-it-normal-to-have-2-000-3-000-lines-of-code-in-a-single-file-for-large-projects), and [AI code editor optimization research](https://medium.com/@eamonn.faherty_58176/right-sizing-your-python-files-the-150-500-line-sweet-spot-for-ai-code-editors-340d550dcea4):

1. **Maintainability**: Large files are harder to understand, modify, and test
2. **Cognitive Load**: Developers must hold more context in memory
3. **AI Tool Limitations**: AI code editors perform better with files under 500 lines
4. **Code Review Difficulty**: Reviewing changes in large files is error-prone
5. **Merge Conflicts**: Larger files have higher probability of merge conflicts
6. **Single Responsibility Violation**: Usually indicates a class is doing too much

### Recommended File Size Limits

| Source | Recommended Limit | Context |
|--------|-------------------|---------|
| ESLint default | 300 lines | JavaScript/TypeScript |
| General best practice | 500-800 lines | Most languages |
| AI-optimized development | 150-500 lines | For AI-assisted coding |
| This project (proposed) | 2500 lines | GDScript/C# game code |

The 2500-line limit is more permissive than typical recommendations, acknowledging the unique challenges of game development where some files naturally grow larger.

## Detailed File Analysis

### enemy.gd (5000 lines) - Refactoring Required

The file contains 10 major responsibility areas that should be extracted:

#### Extractable Components

| Component | Lines | Responsibility |
|-----------|-------|----------------|
| EnemyCombatSystem | ~500 | Shooting, aiming, ammunition, reload |
| EnemyVisionSystem | ~450 | Player visibility, FOV, raycasting |
| EnemyCoverSystem | ~400 | Cover position finding, cover scoring |
| EnemyMovementController | ~350 | Navigation, wall avoidance, patrol |
| EnemyHealthSystem | ~250 | Health, damage, death |
| EnemyThreatSystem | ~200 | Threat detection, suppression |
| EnemyMemorySystem | ~200 | Memory, intel sharing |

**Projected Result**: Main file reduced from 5000 to ~2200 lines

### Player.cs (3040 lines) - Refactoring Required

The file has clear subsystems that can be extracted:

#### Extractable Components

| Component | Lines | Responsibility |
|-----------|-------|----------------|
| PlayerGrenadeSystem | ~550 | Grenade state machine, throwing, animation |
| PlayerReloadSystem | ~300 | Reload phases, animation, audio |
| PlayerDebugSystem | ~250 | Debug visualization, trajectory drawing |
| PlayerAnimationSystem | ~180 | Arm positions, weapon sling |
| PlayerWeaponSystem | ~100 | Weapon detection, pose application |

**Projected Result**: Main file reduced from 3040 to ~1600 lines

## Proposed Solutions

### Solution 1: Component-Based Extraction (Recommended)

Extract functionality into separate component classes following the composition pattern.

**Pros:**
- Clean separation of concerns
- Easier to unit test individual components
- Follows Single Responsibility Principle
- Reduces cognitive load when working on specific features

**Cons:**
- Requires careful interface design
- May introduce some coordination overhead
- Need to manage dependencies between components

### Solution 2: Partial Classes (C# only)

Use C# partial class feature to split Player.cs across multiple files.

**Pros:**
- Simple to implement
- No interface changes needed
- All code still belongs to same logical class

**Cons:**
- Only works for C# (not GDScript)
- Doesn't actually separate concerns
- Just splits the file, not the responsibilities

### Solution 3: State Machine Pattern

Extract AI states into separate state classes.

**Pros:**
- Natural fit for enemy AI
- Each state is independent and testable
- Easy to add new states

**Cons:**
- More complex architecture
- Requires state context passing
- May be overkill for some simpler states

## Implementation Plan

### Phase 1: Update CI Configuration (Immediate)

1. Modify `architecture-check.yml` to set `MAX_LINES=2500`
2. Set `WARN_LINES=1500` (60% of max)
3. Set `CRITICAL_THRESHOLD=2250` (90% of max)

### Phase 2: Extract GDScript Components

Create new files in `scripts/objects/` or `scripts/components/`:

```
scripts/
  objects/
    enemy.gd                      # Main file (~2200 lines)
    enemy_combat_system.gd        # Combat/shooting (~500 lines)
    enemy_vision_system.gd        # Vision/visibility (~450 lines)
    enemy_cover_system.gd         # Cover finding (~400 lines)
    enemy_movement_controller.gd  # Movement/navigation (~350 lines)
```

### Phase 3: Extract C# Components

Create new files alongside Player.cs:

```
Scripts/
  Characters/
    Player.cs                     # Main file (~1600 lines)
    PlayerGrenadeSystem.cs        # Grenade system (~550 lines)
    PlayerReloadSystem.cs         # Reload system (~300 lines)
    PlayerDebugSystem.cs          # Debug tools (~250 lines)
```

## Existing Components and Libraries

### GDScript Patterns in This Codebase

The project already uses component patterns in `scripts/components/`:
- `health_component.gd` - Reusable health management
- `death_animation_component.gd` - Death animation handling
- `vision_component.gd` - Vision detection

These can serve as templates for new components.

### Godot Best Practices

According to [Godot GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) and [GDQuest Guidelines](https://gdquest.gitbook.io/gdquests-guidelines/godot-gdscript-guidelines):

1. Use snake_case for file names
2. Keep files focused on single responsibilities
3. Use class_name for reusable components
4. Leverage signals for loose coupling
5. Prefer composition over inheritance

### C# Patterns

For C# components:
1. Use dependency injection for subsystem references
2. Expose public interface methods
3. Keep Godot signals in main class
4. Use partial classes as stepping stone if needed

## Test Plan

### Verification Steps

1. **CI Pipeline**: Verify all workflows pass after changes
2. **Gameplay Testing**: Test enemy AI behavior (movement, combat, cover)
3. **Player Testing**: Test player controls, grenades, reload
4. **Signal Verification**: Ensure all signals still emit correctly
5. **Performance**: No regression in frame rate or memory usage

### Automated Tests

- Run existing GUT tests: `tests/unit/test_enemy.gd`, `tests/unit/test_player.gd`
- Verify no new test failures introduced

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking enemy AI | Medium | High | Incremental extraction, test each component |
| Performance regression | Low | Medium | Profile before/after extraction |
| Merge conflicts | Low | Low | Complete in single PR |
| Incomplete extraction | Medium | Medium | Focus on highest-value components first |

## References

### Best Practices
- [ESLint max-lines Rule](https://eslint.org/docs/latest/rules/max-lines)
- [AI Code Editor File Size Optimization](https://medium.com/@eamonn.faherty_58176/right-sizing-your-python-files-the-150-500-line-sweet-spot-for-ai-code-editors-340d550dcea4)
- [Godot GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [GDQuest GDScript Guidelines](https://gdquest.gitbook.io/gdquests-guidelines/godot-gdscript-guidelines)

### Project-Specific
- Issue #328: Pre-emptive warning at 90% of MAX_LINES
- PR #323: Example of CI failure due to exceeding line limit
- `scripts/components/` - Existing component patterns to follow

## Implementation Status

### Phase 1: CI Configuration ✅ COMPLETED

The following changes were made to `.github/workflows/architecture-check.yml`:
- `MAX_LINES`: 5000 → 2500
- `WARN_LINES`: 800 → 1500
- `CRITICAL_THRESHOLD`: 4500 → 2250

### Phase 2: Component Templates ✅ CREATED

The following component templates have been created and are ready for integration:

#### GDScript Components (in `scripts/components/`)

| File | Lines | Status |
|------|-------|--------|
| `enemy_combat_system.gd` | 385 | ✅ Created |
| `enemy_vision_system.gd` | 266 | ✅ Created |
| `enemy_cover_system.gd` | 356 | ✅ Created |
| `enemy_movement_controller.gd` | 307 | ✅ Created |

#### C# Components (in `Scripts/Characters/PlayerSystems/`)

| File | Lines | Status |
|------|-------|--------|
| `PlayerGrenadeSystem.cs` | 457 | ✅ Created |
| `PlayerReloadSystem.cs` | 317 | ✅ Created |

### Phase 3: Integration 🔄 PENDING

The component files are ready but not yet integrated into the main files:

- `scripts/objects/enemy.gd` (5000 lines) - Needs to use the new GDScript components
- `Scripts/Characters/Player.cs` (3040 lines) - Needs to use the new C# components

Integration requires:
1. Instantiating components as child nodes
2. Replacing inline code with component method calls
3. Connecting component signals to main class handlers
4. Extensive gameplay testing to verify behavior

**Note**: Full integration is a separate task that requires careful testing to ensure no functionality is broken. The component templates provide the architecture for future refactoring.

## Conclusion

The 2500-line limit is achievable through systematic extraction of components. The refactoring will:

1. **Reduce enemy.gd** from 5000 to ~2200 lines (56% reduction)
2. **Reduce Player.cs** from 3040 to ~1600 lines (47% reduction)
3. **Improve maintainability** through better separation of concerns
4. **Enable easier testing** of individual subsystems
5. **Follow existing patterns** already established in the codebase
