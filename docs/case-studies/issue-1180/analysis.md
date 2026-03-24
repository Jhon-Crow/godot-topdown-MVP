# Case Study: Issue #1180 — Fix roguelike treasure room pedestal

## Issue Summary

The issue reports three problems with the treasure room pedestal in the roguelike mode:

1. **Pedestal image doesn't change** — The weapon icon shown on the pedestal should update
   when the player swaps weapons (old weapon placed back on pedestal).

2. **Weapon swap-back doesn't work** — Swapping PM → M16 works, but swapping back M16 → PM
   doesn't work (or the icon doesn't update to reflect the new item on the pedestal).

3. **Pedestal looks flat** — The base platform should look like a 3D/volumetric object
   (at least have shadows/highlights to suggest depth).

## Root Cause Analysis

### Bug 1 & 2: Pedestal icon not updating on swap-back

**Location:** `scripts/levels/roguelike_level.gd`

In `_spawn_treasure_pedestal()` (line ~1173), the `TextureRect` for the item icon
is created **without setting a `name` property**:

```gdscript
var icon_rect := TextureRect.new()
icon_rect.texture = icon_tex
# ... NO icon_rect.name = "ItemIcon" here!
pedestal.add_child(icon_rect)
```

But in `_apply_pedestal_weapon()` (line ~1319), the code tries to find this node
by name to update the texture:

```gdscript
var icon_rect: TextureRect = pedestal.get_node_or_null("ItemIcon")
if icon_rect and old_weapon_id in WEAPON_ICON_PATHS:
    var tex: Texture2D = load(WEAPON_ICON_PATHS[old_weapon_id]) as Texture2D
    if tex:
        icon_rect.texture = tex
```

Since the node was never named "ItemIcon", `get_node_or_null("ItemIcon")` always
returns `null`, so the texture never updates.

The same issue affects the icon update in `_apply_pedestal_active_item()` — though
that function only updates the `ItemLabel`, not the icon itself.

**Fix:** Add `icon_rect.name = "ItemIcon"` when creating the TextureRect in
`_spawn_treasure_pedestal()`.

### Bug 3: Flat pedestal appearance

The pedestal base is rendered as a single `ColorRect` (flat rectangle). To make it
look volumetric/3D, we need to add:
- A darker "shadow" rectangle below and slightly offset (simulates depth)
- A lighter "highlight" strip at the top (simulates light hitting the top edge)
- An optional side face (darker rectangle offset to one side)

This is a classic "fake isometric" / "fake 3D" technique used in 2D games.

## Files to Modify

- `scripts/levels/roguelike_level.gd` — main fix location

## Solution

1. In `_spawn_treasure_pedestal()`:
   - Set `icon_rect.name = "ItemIcon"` so it can be found by name on swap.
   - Replace single `ColorRect` base with a 3-layer fake-3D pedestal:
     - Bottom shadow layer (dark brown/grey, offset down-right)
     - Front face (current warm gold color)
     - Top highlight (lighter strip at top edge)

2. In `_apply_pedestal_active_item()`:
   - Also update the icon texture when an active item pedestal shows a displaced item
     (for consistency, though active items may not have the same icon-find issue).

## Related Code

- PR #1167 (issue #1166): introduced the treasure room + pedestal system
- The pedestal is built entirely in code (no .tscn scene file)
- Weapon icons are in `assets/sprites/weapons/`
- `WEAPON_ICON_PATHS` dictionary maps weapon IDs to icon paths

## Testing Approach

1. Start roguelike mode, clear all combat rooms, enter treasure room
2. Verify pedestal shows correct weapon/item icon
3. Walk to pedestal → weapon swaps → old weapon icon shown on pedestal
4. Walk back to pedestal → can swap back → correct icon shown again
5. Verify pedestal looks 3D/volumetric
