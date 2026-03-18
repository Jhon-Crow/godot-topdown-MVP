# Case Study: Issue #1121 — Invisible Enemies (Stealth Enemies) in Labyrinth Complex

## Issue Summary

**Title:** добавь врага с невидимостью (Add enemy with invisibility)

**Reported:** 2026-03-18T00:05:24Z by @Jhon-Crow (project owner)

**Requirement (translated from Russian):**
> Add 2 such enemies to the Labyrinth Complex map.
> Make them start in the SEARCHING state from the very beginning.
> They must be invisible from the start (under the player's Invisibility effect, visually).
> They must exit invisibility only when shooting or throwing a grenade.
> Implement it.

**PR:** [#1122](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1122)

---

## Timeline / Sequence of Events

| Time (UTC) | Event |
|---|---|
| 2026-03-18 00:05:24 | Issue #1121 opened by @Jhon-Crow |
| 2026-03-18 00:06:07 | Branch `issue-1121-daf4945b4edc` created, initial scaffolding commit (`ec3d4d74`) |
| 2026-03-18 00:06:10 | First CI run on scaffolding — all checks pass (only .gitkeep present) |
| 2026-03-18 00:12:33 | Commit `bc21dbff` — feature implementation: 2 invisible enemies added, exports added to `enemy.gd`, unit tests, initial analysis.md |
| 2026-03-18 00:12:39 | CI run on `bc21dbff` — **Architecture Best Practices FAILED** |
| 2026-03-18 00:12:50 | CI log shows: `enemy.gd` exceeded the 5000-line limit at **5112 lines** |
| 2026-03-18 00:13:16 | Commit `bc2cc82d` — revert initial `.gitkeep` commit |
| 2026-03-18 00:13:19 | CI run on `bc2cc82d` — **Architecture Best Practices still FAILED** (revert did not fix `enemy.gd` line count) |
| 2026-03-18 00:15:39 | Auto-restart triggered (iteration 1) to address CI failure |
| 2026-03-18 00:26:08 | Commit `56a286e9` — `EnemyInvisibilityComponent` extracted, `enemy.gd` reduced from 5112 → 4993 lines |
| 2026-03-18 00:26:13 | CI run on `56a286e9` — **all 6 checks pass** ✅ |
| 2026-03-18 00:29:08 | PR marked ready-to-merge |
| 2026-03-18 00:42:30 | @Jhon-Crow requests: (1) more transparency / slower waves on enemy cloak, (2) full case study analysis |
| 2026-03-18 00:43:11 | AI work session started to address feedback |
| 2026-03-18 ~00:50 | Shader updated: `shimmer_intensity` uniform added; enemy component sets `ripple_speed=0.6`, `shimmer_intensity=0.05` |

---

## Root Cause Analysis

### Problem 1: enemy.gd exceeded 5000-line architecture limit

**Root cause:** The initial implementation added ~112 lines of invisibility cloak logic (shader application, reveal timer, re-cloak, death handling) directly into `enemy.gd`, which was already at 4,993+ lines before the change.

**Evidence from CI log (`arch-check-bc21dbff.log`):**
```
##[error]Script exceeds 5000 lines (5112 lines). Refactoring required.
```

**Threshold defined in CI workflow:**
```bash
MAX_LINES=5000  # Will be reduced to 800 as refactoring progresses
CRITICAL_THRESHOLD=4500  # 90% of MAX_LINES - pre-emptive warning (Issue #328)
```

**Resolution:** Extracted all invisibility logic into a new component `scripts/components/enemy_invisibility_component.gd`. This follows the established component pattern already used for other enemy features. After extraction, `enemy.gd` dropped to **4993 lines** (below 5000).

### Problem 2: Enemy cloak visually too obvious

**Root cause:** The invisibility shader was designed for the player's suit, where being noticeable helps the player track their own position. With `ripple_speed=2.5` (fast, active animation) and a bright blue shimmer tint at `0.15` intensity, enemies using the same shader were easy to spot — contradicting the stealth gameplay intention.

**Resolution:** Added a `shimmer_intensity` uniform to `invisibility_cloak.gdshader` (default `1.0` preserves player experience) and set per-enemy values via `EnemyInvisibilityComponent`:
- `ripple_speed = 0.6` (4× slower than player default of 2.5)
- `shimmer_intensity = 0.05` (20× less visible shimmer than player default)

This makes enemies nearly indistinguishable from the background while still using the same shader infrastructure.

---

## Architecture Analysis

### Existing Invisibility System (Player — Issue #673)

| Component | Role |
|---|---|
| `scripts/effects/invisibility_suit_effect.gd` | Manages player cloak lifecycle |
| `scripts/shaders/invisibility_cloak.gdshader` | Predator-style chromatic aberration distortion |
| `scripts/ui/invisibility_hud.gd` | HUD display for player cloak |
| `assets/audio/invisibility_activation.wav` | Audio cue |
| `assets/audio/invisibility_deactivation.wav` | Audio cue |

The player shader uses:
- `mix_amount`: `0.0` = fully visible, `1.0` = fully cloaked
- `distortion_strength`: pixel offset for chromatic ripple (default `28.0`)
- `ripple_speed`: animation speed (default `2.5`)
- `shimmer_intensity` (added in this PR): blue tint visibility (default `1.0`)

### New Enemy Invisibility System (Issue #1121)

| Component | Role |
|---|---|
| `scripts/components/enemy_invisibility_component.gd` | Enemy-specific cloak lifecycle |
| `scripts/objects/enemy.gd` (modified) | Two new exports: `start_invisible`, `initial_state` |
| `scenes/levels/Labyrinth2Level.tscn` (modified) | Two new invisible enemy instances |
| `tests/unit/test_invisible_enemy.gd` | Unit tests for export defaults and behavior |

**Enemy cloak parameters (vs player):**

| Parameter | Player default | Enemy value |
|---|---|---|
| `mix_amount` | animated 0→1 | `1.0` (fully cloaked at spawn) |
| `ripple_speed` | `2.5` | `0.6` |
| `shimmer_intensity` | `1.0` | `0.05` |
| `distortion_strength` | `28.0` | `28.0` (unchanged) |

### Enemy Export Pattern

This PR follows the established export pattern from prior issues:

| Issue | Export added |
|---|---|
| #604 | `@export var is_grenadier: bool` |
| #752 | `@export var is_teleporter: bool` |
| #1034 | `@export var has_force_field: bool` |
| **#1121** | `@export var start_invisible: bool`, `@export var initial_state: AIState` |

---

## CI Check Results Summary

### Run on `bc21dbff` (first feature commit) — FAILED

| Workflow | Result |
|---|---|
| Architecture Best Practices | ❌ FAILED — `enemy.gd` at 5112 lines (limit: 5000) |
| Gameplay Critical Systems Validation | ✅ Pass |
| C# and GDScript Interoperability Check | ✅ Pass |
| C# Build Validation | ✅ Pass |
| Run GUT Tests | ✅ Pass |
| Build Windows Portable EXE | ✅ Pass |

**Key error:**
```
##[error]Script exceeds 5000 lines (5112 lines). Refactoring required.
```

### Run on `56a286e9` (refactored) — ALL PASS

| Workflow | Result |
|---|---|
| Architecture Best Practices | ✅ Pass |
| Gameplay Critical Systems Validation | ✅ Pass |
| C# and GDScript Interoperability Check | ✅ Pass |
| C# Build Validation | ✅ Pass |
| Run GUT Tests | ✅ Pass |
| Build Windows Portable EXE | ✅ Pass |

CI logs saved to: `./docs/case-studies/issue-1121/ci-logs/`

---

## Proposed Solutions / Alternatives

### 1. Stealth Visibility Tuning (Implemented)
Separate `shimmer_intensity` and `ripple_speed` per-entity. Already done in this PR. Allows fine-grained control: player cloak is flashy and noticeable (helps player orientation), enemy cloak is subtle and slow (true stealth).

### 2. Component-Based Architecture for Enemy Behaviors (Implemented)
Extracting `EnemyInvisibilityComponent` follows the established component pattern in `scripts/components/`. This is the correct long-term direction as `enemy.gd` approaches the 5000-line limit:
- `enemy.gd` currently at 4993 lines (7 lines from limit)
- The CI also warns at 800 lines and 4500 lines ("critical threshold")
- Future features must continue to extract logic into components

**Recommended next step:** Issue #328 mentions reducing MAX_LINES target to 800 over time. `enemy.gd` will need to be split into multiple components as part of an ongoing refactor.

### 3. Dedicated InvisibleEnemy Scene (Not Taken)
A `InvisibleEnemy.tscn` subclass would be self-contained but adds file overhead and breaks from the existing export-based customization pattern. The export approach is more flexible for level designers.

### 4. Godot Built-in Modulate / Alpha (Rejected)
Setting `modulate.a = 0.0` on the enemy would make them fully transparent with no visual cue. While simpler, it doesn't match the aesthetic of the player's Predator-style cloak and removes gameplay readability (impossible to track even with attention).

### 5. Third-Party Invisibility Libraries / Resources
- **Godot Shaders (godotshaders.com):** Several community shaders implement similar chromatic aberration / distortion effects. The current custom implementation is equivalent in quality.
- **Godot 4 Visibility Notifier2D:** Could detect when an invisible enemy enters the camera frustum and trigger partial reveal hints — a potential future enhancement for accessibility.
- **NavMesh + SEARCHING state:** The existing `AIState.SEARCHING` already handles pathfinding behavior. No external library needed.

---

## Files Changed in PR #1122

| File | Change |
|---|---|
| `scripts/shaders/invisibility_cloak.gdshader` | Added `shimmer_intensity` uniform |
| `scripts/components/enemy_invisibility_component.gd` | **New file** — extracted invisibility logic |
| `scripts/objects/enemy.gd` | Added `start_invisible`/`initial_state` exports, `_invisibility` component usage |
| `scenes/levels/Labyrinth2Level.tscn` | Added 2 invisible enemies, updated count 15→17 |
| `tests/unit/test_invisible_enemy.gd` | **New file** — unit tests |
| `docs/case-studies/issue-1121/analysis.md` | This file |

---

## References

- **Issue #673:** Player invisibility suit (origin of `invisibility_cloak.gdshader`)
- **Issue #322:** SEARCHING AI state implementation
- **Issue #328:** Architecture refactor — reducing MAX_LINES target from 5000 to 800
- **Issue #604:** `is_grenadier` export pattern
- **Issue #752:** `is_teleporter` export pattern
- **Issue #1034:** `has_force_field` export pattern
- **PR #1122:** Implementation PR for this issue
- **CI logs:** `./docs/case-studies/issue-1121/ci-logs/`
