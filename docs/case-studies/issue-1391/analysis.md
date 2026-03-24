# Case Study: Issue #1391 — Обеспечь 100% покрытие тестами

## Summary

Issue #1391 requests achieving 100% test coverage for the Godot Top-Down MVP project,
with special attention to the experimental functionality that "keeps breaking",
and adding linters that forbid non-optimal constructs.

## Current State Analysis

### Project Statistics
- **Total GDScript source files**: 185
- **Total test files**: 164 (159 unit + 5 integration)
- **Files WITH test coverage**: ~101
- **Files WITHOUT test coverage**: ~84 (45% gap)

### Coverage Gap by Category

| Category | Total Files | Untested | Coverage |
|----------|------------|----------|----------|
| AI States | 4 | 3 | 25% |
| Autoload | 38 | 11 | 71% |
| Components | 30 | 22 | 27% |
| Effects | 20 | 17 | 15% |
| Levels | 14 | 10 | 29% |
| Projectiles | 12 | 5 | 58% |
| UI | 16 | 14 | 13% |
| Other | ~51 | 2 | 96% |

### Experimental Functionality

The experimental system consists of 3 files:
1. **`experimental_settings.gd`** — Settings manager with 25+ toggles (HAS tests)
2. **`experimental_menu.gd`** — UI menu for toggling experimental features (NO tests)
3. **`experimental_sample_item_popup.gd`** — Floating popup for item effects (NO tests)

The experimental_settings.gd already has comprehensive tests, but the UI layer
(experimental_menu.gd, experimental_sample_item_popup.gd) is untested, which
explains why "it keeps breaking" — UI regressions go undetected.

### Linting Status

- **No GDScript linter** is currently configured
- **No algorithmic complexity checks** exist
- Architecture-check.yml validates structure but not code quality
- No static analysis for performance anti-patterns

## Root Cause Analysis

### Why Experimental Features Keep Breaking

1. **UI layer untested**: The experimental_menu.gd (350+ lines) connects dozens of
   checkboxes, sliders, and buttons to experimental_settings.gd. Any signal
   connection error, renamed method, or UI restructuring breaks silently.

2. **No integration tests**: The connection between UI → settings → game behavior
   is only tested at the settings layer.

3. **No linting**: Non-optimal constructs (nested loops, redundant iterations,
   inefficient algorithms) can be introduced without detection.

## Solutions

### 1. Test Coverage (Implemented)

Write unit tests for all 84 untested source files, with priority on:
- Experimental UI components (experimental_menu.gd, experimental_sample_item_popup.gd)
- Components (22 files — largest gap)
- Effects (17 files)
- Levels (10 files)
- UI menus (14 files)
- AI states (3 files)
- Autoload managers (11 files)
- Projectiles (5 files)

### 2. GDScript Linter (Implemented)

Add a GDScript linter CI workflow that detects:
- Nested for/while loops (O(n²) or worse)
- Array.find() inside loops
- Duplicate dictionary lookups
- Unbounded while loops without break
- Large function bodies (>50 lines)
- Deep nesting (>4 levels)

### 3. Existing Tools and Libraries

| Tool | Purpose | Status |
|------|---------|--------|
| GUT (Godot Unit Testing) | Test framework | Already integrated |
| gdlint/gdtoolkit | GDScript linting | Not installed (CI-based alternative implemented) |
| architecture-check.yml | Structure validation | Already active |
| gameplay-validation.yml | Gameplay safety | Already active |

**gdtoolkit** (https://github.com/Scony/godot-gdscript-toolkit) is the standard
GDScript linter but requires Python installation. For CI simplicity, a shell-based
linter was chosen that runs without additional dependencies.

## References

- Issue #1391: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1391
- GUT Framework: https://github.com/bitwes/Gut
- gdtoolkit: https://github.com/Scony/godot-gdscript-toolkit
- Godot Testing Best Practices: https://docs.godotengine.org/en/stable/contributing/development/core_and_modules/unit_testing.html
