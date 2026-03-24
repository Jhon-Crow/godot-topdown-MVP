# Case Study: Issue #1043 — Add Active Item "Breaching Charges"

## Summary

Issue #1043 requests a new active item called **Breaching Charges** (Пробивные заряды). The player carries 2 charges that can be attached to walls. After placement, pressing Space detonates the charge, creating a passage through the wall and stunning/blinding any enemies on the far side for 3 seconds.

---

## Requirements Analysis

| Requirement | Details |
|---|---|
| Number of charges | 2 per battle |
| Placement mechanic | Hold Space near a wall, release Space to attach the charge |
| Detonation mechanic | Once a charge is placed, press Space to detonate |
| Wall effect | Creates a passage (removes collision, hides visuals) |
| Enemy effect | Enemies within blast radius stunned AND blinded for 3 seconds |
| Unlock condition | Freely available from start (no unlock required) |

---

## Architecture Analysis

### Active Item System

The game has a well-established active item system:

- **`ActiveItemManager`** (`scripts/autoload/active_item_manager.gd`) — autoload singleton that tracks the selected active item type, item metadata (name, icon, description), and unlock state.
- **`player.gd`** — handles init + per-frame input for each active item. Each item follows a standard pattern: `_init_X()` in `_ready()` and `_handle_X_input(delta)` in `_physics_process()`.
- **Effect scripts** (`scripts/effects/`) — dedicated Node scripts for complex items (invisibility, trajectory glasses, force field). Simple passive items (breaker bullets, laser sight) only set a flag.

### Wall Structure

Walls in all levels are `StaticBody2D` nodes under `Environment/Walls` with:
- `collision_layer = 4` (bit 3, the "obstacles" layer)
- One or more `CollisionShape2D` or `CollisionPolygon2D` children

Creating a "passage" requires disabling these collision shapes. The wall can also have visual `Sprite2D`/`Polygon2D` children that should be hidden.

### Stun/Blind System

Enemies implement `apply_flashbang_effect(blindness_duration, stun_duration)` via `FlashbangStatusComponent`, which is the existing stun/blind system used by flashbang grenades. Reusing this ensures correct behavior integration (enemy AI respects `_is_blinded` and `_is_stunned` flags already).

---

## Implementation

### Files Modified/Created

| File | Change |
|---|---|
| `scripts/autoload/active_item_manager.gd` | Added `BREACHING_CHARGES` enum value (10), unlock entry, item data dict, and `has_breaching_charges()` method |
| `scripts/effects/breaching_charges_effect.gd` | **New** — effect controller handling placement, detonation, wall opening, enemy stun/blind |
| `scripts/characters/player.gd` | Added `_init_breaching_charges()` call in `_ready()`, `_handle_breaching_charges_input()` call in `_physics_process()`, and full implementation at end of file |
| `tests/unit/test_breaching_charges_effect.gd` | **New** — unit tests for all core mechanics |
| `docs/case-studies/issue-1043/case-study.md` | **New** — this document |

### Input State Machine

```
IDLE (charges > 0, no placed charge)
  │ Space held → _holding_for_placement = true
  │ Space released → try_place_charge()
  │   ├── wall found within 40px → place charge, transition to CHARGE_PLACED
  │   └── no wall → IDLE (no charge consumed)
  │
CHARGE_PLACED
  │ Space pressed → detonate()
  │   ├── disable wall CollisionShape2D (create passage)
  │   ├── hide wall visuals
  │   ├── stun+blind enemies in 150px radius for 3 seconds
  │   └── transition to IDLE (or OUT_OF_CHARGES if charges == 0)
  │
OUT_OF_CHARGES (charges == 0, no placed charge)
  └── no action possible (item exhausted for this battle)
```

### Wall Opening Mechanism

`_open_wall_passage(wall)` iterates the wall's children and disables all `CollisionShape2D` and `CollisionPolygon2D` nodes. It also hides any `CanvasItem` children for visual feedback. This is non-destructive (the node tree is not removed), preserving Godot's scene structure while making the area passable.

### Enemy Blast Effect

`_apply_blast_effects(det_pos)` finds all nodes in the `"enemies"` group within `STUN_RADIUS` (150 px) of the detonation point and calls `apply_flashbang_effect(3.0, 3.0)`. This reuses the exact same stun/blind component used by flashbang grenades.

---

## Alternatives Considered

### Alternative 1: TileMap-based Wall Removal
If walls were on a TileMap, setting a tile cell to -1 would remove it. However, walls in this game are hand-placed `StaticBody2D` nodes, so disabling collision shapes is the correct approach.

### Alternative 2: Spawning a "Hole" Overlay Sprite
Instead of hiding wall visuals, a dedicated "breach hole" sprite overlay could be spawned. This was deemed over-engineering for the current scope; simply hiding wall children achieves the required visual result.

### Alternative 3: Two-Phase Delay (Fuse Timer)
A timed fuse after placement was considered (auto-detonation after N seconds). The issue specification says "press Space to detonate", so manual detonation was implemented. A fuse timer could be added as a future enhancement.

---

## Testing

Unit tests (`tests/unit/test_breaching_charges_effect.gd`) cover:
- Constants match spec (MAX_CHARGES=2, STUN_DURATION=3s, STUN_RADIUS=150px, PLACEMENT_RADIUS=40px)
- Initial state (2 charges, no placed charge)
- Placement: consumes charge, sets flag, emits signals, fails with no wall or 0 charges
- Only one charge can be placed at a time
- Detonation: opens wall, emits signals, clears state, fails with no placed charge
- Cannot detonate twice
- Full lifecycle: use both charges, third placement fails
- ActiveItemManager data validation (name, description, enum value)
