# Case Study: Issue #1587 — Add Active Item: Combat Knife

## Issue Summary

**Title:** добавь активный предмет - Боевой нож (Add active item — Combat Knife)

**Author:** Jhon-Crow
**State:** OPEN
**Reference image:** Badge icon reference provided (horizontal knife silhouette)
**Animation reference:** https://saint11.art/blog/pixel-art-tutorials/

### Requirements

- Unlimited uses (no charges)
- On activation: fan/arc melee attack animation
- Any enemy hit during the strike receives **7 damage**
- Player activates via Space key (standard active-item key)

---

## Codebase Analysis

### Active Item System

The game uses a centralized `ActiveItemManager` autoload singleton (`scripts/autoload/active_item_manager.gd`) that:

- Maintains an `ActiveItemType` enum listing all items
- Holds `ACTIVE_ITEM_DATA` dict with name/icon/description per item
- Holds `unlocked_active_items` dict for unlock tracking
- Provides `has_<item_name>()` query methods for each item

The player C# class (`Scripts/Characters/Player.ActiveItems.cs`) initializes each item in `_Ready()` and handles Space-key input in `_Process()`.

### Existing Melee System

`scripts/components/machete_component.gd` implements enemy melee attack with phases:
- WINDUP (0.25s) → PAUSE (0.1s) → STRIKE (0.15s) → RECOVERY (0.2s)
- Damage applied mid-STRIKE phase
- Rotation: -90° windup → +90° strike end

This pattern is adapted for the player knife effect.

### Implementation Pattern (from Dash, Issue #1071)

Each active item follows:
1. GDScript effect script in `scripts/effects/`
2. Matching TSCN scene in `scenes/effects/`
3. `InitX()` + `HandleXInput()` C# methods in `Player.ActiveItems.cs`
4. `Init` call in `Player.cs` `_Ready()`, `Handle` call in `_Process()`
5. `OnActiveItemPickedUp()` case added
6. `has_x()` method in `active_item_manager.gd`
7. Enum entry + item data + unlock entry in `active_item_manager.gd`

---

## Solution Design

### Icon
A `combat_knife_icon.png` sprite file is needed in `assets/sprites/weapons/`.
The reference shows a horizontal knife silhouette badge. A pixel-art knife icon matching the existing 64×64 icon size convention is created.

### GDScript Effect Scene (`CombatKnifeEffect`)

`scripts/effects/combat_knife_effect.gd` — implements:
- **Unlimited uses, no charges, no cooldown** (other than animation duration)
- Attack range: ~70 pixels (close melee)
- Attack angle: 120° fan (±60° from facing direction)
- Phases: WINDUP → STRIKE → RECOVERY (shorter than machete, quicker feel)
- Damage: 7 to all enemies in arc during STRIKE phase
- Visual: `Line2D` arc sweep or `Polygon2D` flash matching pixel art style

### Player Integration

`Player.ActiveItems.cs` additions:
- `_combatKnifeEquipped` flag
- `_combatKnifeEffect` node reference
- `InitCombatKnife()` — loads scene, calls `initialize(player)`
- `HandleCombatKnifeInput()` — on Space JustPressed, calls `effect.activate(aim_direction)`

`Player.cs` additions:
- `InitCombatKnife()` call in `_Ready()`
- `HandleCombatKnifeInput()` call in `_Process()`

`OnActiveItemPickedUp()` — case 22 added.

### ActiveItemManager Changes

- New enum value: `COMBAT_KNIFE = 22`
- New unlock entry: `ActiveItemType.COMBAT_KNIFE: false`
  Unlock condition: reach melee range 10 times (or simpler: freely unlocked)
- New `ACTIVE_ITEM_DATA` entry with name, icon path, description
- New `has_combat_knife()` method

---

## Damage Application

Enemies are queried via `get_tree().get_nodes_in_group("enemies")`.
For each enemy in range + arc:
- Distance check: `<= KNIFE_RANGE` (70px)
- Angle check: angle from player facing direction `<= KNIFE_ARC_HALF` (60°)
- Wall check: optional Raycast2D (can skip for simplicity like some existing melee)
- Damage: `enemy.call("take_damage", 7.0)` (GDScript enemies) or cast to `IDamageable` (C# enemies)

---

## References

- Issue #1071 (Dash) — closest parallel: press-Space no-charges active item using GDScript effect
- Issue #595 (Machete attack animation) — animation phase pattern
- Issue #1325 — active_item_changed signal for roguelike pickup support
- https://saint11.art/blog/pixel-art-tutorials/ — pixel art animation reference cited in issue
