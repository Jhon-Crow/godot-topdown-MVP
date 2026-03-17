# Case Study: Issue #1111 — Add Unique Enemies Table in Experimental Menu

## Overview

| Field | Value |
|-------|-------|
| **Issue** | [#1111](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1111) |
| **PR** | [#1114](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1114) |
| **Author** | Jhon-Crow (owner) |
| **Branch** | `issue-1111-1d8925653ba7` |
| **Status** | In Review |

## Problem Statement

The game already had an "Unlock Table" in the Experimental menu showing which weapons/items are available per map. The request (in Russian) was:

> "добавь таблицу уникальных врагов в experimental по аналогии с таблицей анлоков (какие враги на каких картах)."
>
> *Translation: "Add a unique enemies table to experimental, similar to the unlock table (which enemies appear on which maps)."*

A follow-up comment (also from the owner) requested:

> "добавь в таблицу особенности врагов (например Силовое поле, Телепорт, джаммер и подобное)."
>
> *Translation: "Add enemy features to the table (e.g. Force Field, Teleport, Jammer, and similar)."*

---

## Timeline / Sequence of Events

| Date (UTC) | Event |
|---|---|
| 2026-03-17 ~19:00 | Issue #1111 opened by Jhon-Crow |
| 2026-03-17 19:43 | AI draft session completed; PR #1114 opened with initial enemies table (count columns only) |
| 2026-03-17 19:45 | PR marked ready to merge by monitoring bot |
| 2026-03-17 22:00 | Owner comments: add enemy features (Force Field, Teleport, Jammer), update from main, create case study |
| 2026-03-17 22:01 | AI work session started; PR converted to draft |
| 2026-03-17 22:xx | upstream/main merged into branch; features columns added; case study created (this document) |

---

## Root Cause Analysis

### Why weren't features included in the first draft?

The original issue description only requested a table showing *which enemies appear on which maps* — matching the Unlock Table structure. The feature columns (Grenadier, Teleport, Force Field, Jammer) were requested in a follow-up comment **after** the first draft was committed.

This is a standard iterative design pattern: the owner validated the basic structure first, then extended the requirements.

### How were enemy features discovered?

The enemy feature data was found by:

1. **Reading `scripts/objects/enemy.gd`** — exports reveal three boolean feature flags:
   - `is_grenadier: bool` (Issue #604) — enemy throws grenades
   - `is_teleporter: bool` (Issue #752) — enemy teleports when under fire
   - `has_force_field: bool` (Issue #1034) — enemy is invulnerable while force field is active

2. **Checking `scenes/objects/RadioJammerEnemy.tscn`** — a dedicated scene (added in Issue #1036) that extends the base enemy with a `RadioWaveEffect` component. The jammer blocks player active items within a 1000-unit radius.

3. **Scanning all level `.tscn` files** in `scenes/levels/` for these properties.

---

## Enemy Feature Inventory (per Map)

| Map | Rifle | Shotgun | UZI | Machete | PKM | Grenadier | Teleport | Force Field | Jammer |
|-----|-------|---------|-----|---------|-----|-----------|----------|-------------|--------|
| Labyrinth | 4 | 1 | — | — | — | — | — | — | — |
| Building | 9 | — | 1 | — | — | **YES** | — | — | — |
| Castle | 2 | 3 | 8 | — | — | — | — | — | — |
| Beach | 2 | 1 | — | 5 | — | — | — | — | — |
| Docks | 9 | 3 | 6 | 2 | — | **YES** | — | — | — |
| Labyrinth 2 | 10 | 2 | 2 | — | 1 | **YES** | — | — | — |
| City | 5 | 2 | 2 | — | — | — | **YES** | — | — |
| Decadence | 7 | 2 | — | 3 | — | — | — | — | **YES** |
| Polygon | 10 | — | — | — | — | — | — | — | — |
| Double Corridor | 13 | — | — | — | — | — | — | **YES** | — |
| Factory | 13 | — | — | — | — | — | — | — | — |

---

## Feature Descriptions

### Grenadier (`is_grenadier = true`)
- **Maps affected:** Building, Docks, Labyrinth 2
- **Mechanic:** Enemy carries grenades and throws them at the player based on 6 trigger conditions (line-of-sight, distance, cover blocking, etc.). Implemented in `Issue #363, #375, #604`.
- **Visual cue:** None specific (uses standard shotgun enemy model).
- **Threat level:** High — grenades bypass cover and can kill in confined spaces.

### Teleporter (`is_teleporter = true`)
- **Maps affected:** City
- **Mechanic:** Enemy uses `EnemyTeleportComponent` (Issue #752). When under fire without valid cover, the enemy teleports directly to its cover position. Also teleports during flanking. A backpack accessory is added to the model. After teleport, `reset_memory()` is called on all allies — enemies briefly enter confusion state (2s) so the player can use the escape window.
- **Visual cue:** Backpack sprite on enemy model.
- **Threat level:** Medium-High — unpredictable repositioning makes cover ineffective.

### Force Field (`has_force_field = true`)
- **Maps affected:** Double Corridor (RevolverLevel)
- **Mechanic:** Enemy uses `EnemyForceFieldComponent` (Issue #1034). While the force field is active (when player is in sight), all incoming bullets are blocked (`on_hit_with_bullet_info` returns early). A blue shield icon (`ShieldIcon` sprite) is shown on the enemy model. Field becomes inactive when the player is out of sight.
- **Visual cue:** Blue shield icon on enemy.
- **Threat level:** Very High — enemy is literally invulnerable while it can see you; only vulnerable when out of sight.

### Radio Jammer (`RadioJammerEnemy.tscn`)
- **Maps affected:** Decadence
- **Mechanic:** Implemented via `RadioWaveEffect` component (Issue #1036). Broadcasts a radio wave with 1000-unit radius. Within this radius, all player active items (including active item manager) are blocked/jammed. Enemy belongs to the `radio_jammers` group. A `JammerHUD` is shown to the player while inside the jammer field.
- **Visual cue:** Animated radio wave rings emanating from enemy; jammer HUD element on screen.
- **Threat level:** High — disables the player's tactical tool kit; must be prioritized.

---

## Solution Approach

### Changes Made

#### 1. `scripts/ui/enemies_table_menu.gd`
- Added `ENEMY_FEATURES` constant dictionary mapping each level scene path to a `[Grenadier, Teleport, ForceField, Jammer]` boolean array.
- Extended `_add_table_row()` to accept 4 additional boolean feature parameters.
- Added a vertical `VSeparator` between enemy-count columns and feature columns for visual separation.
- Feature columns render `YES` (in a distinct color per feature) or `—` (muted grey).
- Panel width increased from ±480px to ±580px to accommodate the extra columns.
- Description updated to mention special abilities.

#### 2. `scripts/ui/experimental_menu.gd` (already in previous commit, unchanged by this session)
- `@onready` ref, `preload`, signal connections added to open/close the enemies table overlay.

#### 3. `scenes/ui/EnemiesTableMenu.tscn` (already in previous commit, unchanged)
- Minimal scene wiring the script.

#### 4. `scenes/ui/ExperimentalMenu.tscn` (already in previous commit)
- `EnemiesTableContainer` row added with label, "Open" button, and description.

### Design Decisions

- **Static data** (not scanning scenes at runtime): Following the same pattern as the Unlock Table, enemy data is hardcoded as `const` dictionaries. This avoids runtime scene loading overhead and keeps the menu predictable.
- **Color coding**: Feature columns each get a distinct thematic color (Grenadier=orange-red, Teleport=purple, Force Field=cyan, Jammer=teal-green).
- **Visual divider**: A `VSeparator` between count columns and feature columns makes the two groups visually distinct.
- **"YES" vs checkmark**: Plain text `YES` is more readable at small sizes than Unicode symbols in a game font.

---

## Related Issues & PRs

| Issue | Title | Relevance |
|-------|-------|-----------|
| [#363, #375, #604](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/604) | Grenadier enemy system | Grenadier feature origin |
| [#752](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/752) | Teleporter enemy | Teleport feature origin |
| [#1034](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1034) | Force Field enemy | Force Field feature origin |
| [#1036](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1036) | Radio Jammer enemy | Jammer feature origin |
| [#1079](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1079) | Shield icon for force field enemies | Shield icon visual |
| [#1109, PR #1110](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1110) | Disable horizontal scroll in ExperimentalMenu | Same UI area |

---

## Possible Future Enhancements

1. **Runtime scanning**: Instead of hardcoded data, scan level scenes on demand to auto-populate counts. Would need to load scenes in background and parse node properties.
2. **Additional feature columns**: Pacifist enemies (`_pacifist` component, Issue #959), Flashlight enemies (Issue #824), Machine-gun suppression corridor behavior (Issue #1033).
3. **Sorting/filtering**: Allow clicking column headers to sort by count or feature.
4. **Localization**: Level names and feature names are currently hardcoded in English; should use Godot's localization system if the game adds i18n support.
5. **Per-enemy detail popup**: Clicking a cell could show detailed stats for that specific enemy on that map.

---

## Conclusion

The issue was straightforward to implement. The main technical challenge was accurately inventorying enemy features across all 11 levels — which required reading both `enemy.gd` (for feature flag definitions) and each level `.tscn` file (for which flags are set `true`). All feature data has been verified against the actual scene files.

The final table gives players a complete tactical reference for what to expect on each map: enemy type counts **and** special abilities in one view.
