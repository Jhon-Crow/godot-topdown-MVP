# Case Study: Issue #1131 — RPG Rocket Wall Penetration

## Problem Statement

When an RPG rocket hits a wall, it should **punch a hole through the wall** (as the active item "Breaching Charges" / Пробивные заряды does) instead of just exploding on the surface.

**Original behavior:** Rocket impacts wall → explosion visual + damage → wall intact.
**Required behavior:** Rocket impacts wall → explosion visual + damage → **wall has a carved passage at the impact point** (same size as breaching charges: 120 px wide).

---

## Game Log Analysis (`game_log_20260318_040301.txt`)

The provided log captures a play session on `LabyrinthLevel` in which the RPG enemy fires multiple rockets. All confirmed hits on walls produce only explosion effects with no wall modification:

| Timestamp | Event | Wall hit | Outcome |
|-----------|-------|----------|---------|
| 04:03:35 | `[RpgRocket] Raycast impact on WallLeft at (64, 474.919)` | `WallLeft` (StaticBody2D) | Explosion only — no passage |
| 04:03:59 | `[RpgRocket] Raycast impact on WallLeft at (64, 1023.326)` | `WallLeft` (StaticBody2D) | Explosion only — no passage |
| 04:03:45 | `[RpgRocket] Impact on CoverWide3 (type: StaticBody2D)` | Cover object | Explosion only — no passage |
| 04:03:51 | `[RpgRocket] Impact on CrateSquare3 (type: StaticBody2D)` | Crate | Explosion only — no passage |

Importantly, no `[BreachingCharges]` log lines appear at all in the session — the player did not have breaching charges selected — confirming that **only the RPG rocket needs to be modified** to open passages.

---

## Root Cause

In `scripts/projectiles/rpg_rocket.gd`, the `_on_body_entered` / `_on_body_entered_via_raycast` callback calls `_explode()` on wall contact. The `_explode()` function:
1. Applies damage in radius (line 216–243)
2. Spawns explosion visual (line 219)
3. Scatters casings (line 222)

There is **no call** to any wall-opening or passage-carving logic. The `_open_wall_passage()` function exists only in `scripts/effects/breaching_charges_effect.gd` and is not shared.

---

## Real-World Research Summary

### RPG-7 PG-7V warhead physics

- Uses **HEAT (High-Explosive Anti-Tank) shaped charge** — the Monroe/Munroe effect.
- A copper-lined conical cavity focuses ~20% of the explosive energy into a hypervelocity copper jet that **physically penetrates** the target.
- The remaining ~80% radiates outward as conventional blast.
- **Against masonry / brick walls:** penetrates up to 2 m (PG-7V baseline). Standard interior walls (20–40 cm) are always penetrated.
- **Against thin wood/drywall:** destroyed entirely.
- **Fuze:** piezoelectric point-impact, triggers on contact. Arms at ~5 m from muzzle.

Sources:
- [RPG-7 — Wikipedia](https://en.wikipedia.org/wiki/RPG-7)
- [HowStuffWorks — The RPG-7](https://science.howstuffworks.com/rpg3.htm)
- [Defense Update: RPG-7 multi-purpose weapon](https://defense-update.com/20060726_rpg-7rpg-7vrpg-7vr-rocket-propelled-grenade-launcher-multi-purpose-weapon.html)

### Game reference implementations

| Game | Mechanic |
|------|----------|
| **Red Faction (2001)** | Geo-Mod: real-time geometry deformation from explosives; rockets blow actual holes |
| **Battlefield: Bad Company 2** | Frostbite Destruction 2.0: rockets destroy wall panels, replaced by holes with dust/debris |
| **The Finals (2023)** | Voxel destruction: rockets erode voxel chunks, buildings can partially collapse |
| **CS2/CSGO** | Bullet penetration modifiers per material — no geometry destruction |

The consistent pattern: rocket → explosion effect → persistent hole in wall geometry (collision disabled/modified, visual updated).

Sources:
- [Battlefield Wiki: Destruction](https://battlefield.fandom.com/wiki/Destruction)
- [The Ringer: Destructible Environments](https://www.theringer.com/2024/02/02/video-games/destruction-video-games-battlefield-bad-company-red-faction-battlebit-teardown-the-finals)

### Existing codebase components

The game **already has all the infrastructure needed:**

1. **`scripts/effects/breaching_charges_effect.gd`** — `_open_wall_passage(wall, breach_world_pos)`: carves a 120 px passage in a StaticBody2D wall by modifying `CollisionShape2D` and splitting the visual `ColorRect`. Handles horizontal/vertical walls, thin walls, short walls, and corner fills.

2. **`scripts/effects/penetration_hole.gd`** — `PenetrationHole` Area2D: creates a small permanent hole for bullet penetration (different use case — for bullets, not rockets).

3. The existing `_on_body_entered` in `rpg_rocket.gd` already identifies `StaticBody2D` hits and has access to the `body` reference — exactly what `_open_wall_passage` needs.

---

## Proposed Solution

### Approach: Extract `_open_wall_passage` to a shared utility and call it from `rpg_rocket.gd`

**Instead of duplicating the wall-passage logic**, we extract `_open_wall_passage` (and its helpers `_split_visual_horizontal`, `_split_visual_vertical`, `_fade_wall_visuals`) into a new static utility class `WallBreach` (or a standalone autoloaded helper), then call it from both `breaching_charges_effect.gd` and `rpg_rocket.gd`.

**Alternative (simpler, chosen):** Since GDScript does not have easy static utility imports, duplicate only the minimal passage-opening logic into `rpg_rocket.gd` and factor a shared `_open_wall_passage` static method into a new `scripts/effects/wall_breach_helper.gd` script that both can use. Or, inline the wall breach logic directly in `rpg_rocket.gd` (same pattern as `breaching_charges_effect.gd`).

Given the codebase pattern (no global utility scripts for wall effects yet), the **chosen approach** is:
- Add a new helper class `WallBreachHelper` as an autoload-safe static helper in `scripts/effects/wall_breach_helper.gd`.
- Move `_open_wall_passage`, `_split_visual_horizontal`, `_split_visual_vertical`, `_fade_wall_visuals` to it.
- Refactor `breaching_charges_effect.gd` to delegate to the helper.
- Call the helper from `rpg_rocket.gd` when the impact body is a `StaticBody2D`.

### Configuration

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Passage width | 120 px | Same as `BREACH_PASSAGE_WIDTH` in breaching charges — consistent |
| Trigger condition | `body is StaticBody2D` | Walls are StaticBody2D; avoid triggering on CharacterBody2D or RigidBody2D |
| Impact position | `global_position` at time of explosion | Rocket explodes at collision boundary |

### Visual differences from breaching charges

Breaching charges: dust cloud + directional explosion cone + stun enemies.
RPG rocket: already has its own explosion flash + scorch mark + particle effects.
No additional dust effects needed — the existing explosion effect is sufficient.

---

## Files Modified

| File | Change |
|------|--------|
| `scripts/effects/wall_breach_helper.gd` | **New** — shared static wall-passage logic |
| `scripts/effects/breaching_charges_effect.gd` | Refactored to use `WallBreachHelper` |
| `scripts/projectiles/rpg_rocket.gd` | Added wall-passage creation on `StaticBody2D` impact |
| `tests/unit/test_rpg_wall_penetration.gd` | **New** — unit tests for RPG wall penetration |

---

## Testing Plan

1. Unit tests in `tests/unit/test_rpg_wall_penetration.gd`:
   - Rocket hitting StaticBody2D wall creates passage.
   - Rocket hitting CharacterBody2D (enemy) does NOT create passage.
   - Rocket hitting thin wall fades visual and disables collision.
   - Rocket hitting wide wall splits collision into two segments.

2. Manual verification in `LabyrinthLevel`:
   - Shoot RPG rocket into `WallLeft` — expect 120 px gap at impact point.
   - Shoot RPG rocket at enemy — wall behind enemy remains intact.
