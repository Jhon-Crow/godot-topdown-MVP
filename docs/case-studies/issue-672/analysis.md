# Case Study: Issue #672 — Teleportation Bracers Active Item

## Issue Summary

**Title:** добавь активный предмет — наручи телепортации (Add active item — teleportation bracers)

**Requirements:**
1. When activated (hold Space), a targeting reticle appears, similar to the grenade targeting, but with a player contour/silhouette at the endpoint
2. When the player releases Space, they teleport to the selected point
3. The player must not get stuck in walls (the reticle should skip over/through walls)
4. 6 charges (non-regenerating, no cooldown)

## Architecture Analysis

### Existing Systems Used

#### ActiveItemManager (`scripts/autoload/active_item_manager.gd`)
- Singleton managing active item selection via enum `ActiveItemType`
- Currently has `NONE` (0) and `FLASHLIGHT` (1)
- Provides data for armory UI (name, icon, description)
- The teleport bracers will be added as `TELEPORT_BRACERS` (2)

#### Player.cs Flashlight System (lines 590-628, 3736-3917)
- Pattern: `InitFlashlight()` called from `_Ready()`, `HandleFlashlightInput()` from `_PhysicsProcess()`
- Uses `ActiveItemManager` via `GetNodeOrNull("/root/ActiveItemManager")`
- The teleport bracers follow the same integration pattern

#### Grenade Simple Aiming System (lines 2592-2798)
- Provides trajectory preview while RMB is held
- `HandleSimpleGrenadeAimingState()` — shows trajectory, handles release
- `_Draw()` override — renders dashed trajectory line, landing indicator, effect radius
- The teleport targeting reticle reuses similar visual approach

#### Wall Detection (`GetSafeGrenadeSpawnPosition`, lines 3159-3201)
- Uses `PhysicsRayQueryParameters2D` with collision mask 4 (obstacles layer)
- Raycasts from player to target, finds wall intersection
- Returns safe position before wall with 5px margin
- Teleport bracers use the same approach but for the teleport destination

### Implementation Design

#### State Machine
```
TeleportState.Idle → (Space pressed) → TeleportState.Aiming → (Space released) → Teleport + Idle
```

#### Wall Avoidance Strategy
The issue says "the reticle should skip over/through walls". This means:
- Cast a ray from player to cursor position
- If wall is hit, find the point beyond the wall where there's clear space
- Use multiple raycasts to find valid positions past walls
- Clamp final position to ensure player doesn't end up inside geometry

#### Player Silhouette at Target
- Draw a simplified player outline (circle + body shape) at the target position
- Use semi-transparent coloring to indicate it's a preview
- Update position every frame while aiming

#### Charge System
- 6 charges, similar to `_currentGrenades` tracking
- Signal `TeleportChargesChanged(int current, int maximum)` for UI updates
- No cooldown — can teleport as fast as Space can be pressed/released

## Solution Components

| Component | File | Change Type |
|-----------|------|-------------|
| ActiveItemType enum | `active_item_manager.gd` | Add TELEPORT_BRACERS = 2 |
| Item data | `active_item_manager.gd` | Add data entry |
| Convenience method | `active_item_manager.gd` | Add `has_teleport_bracers()` |
| Player fields | `Player.cs` | Add teleport state, charges, etc. |
| Init method | `Player.cs` | Add `InitTeleportBracers()` |
| Input handler | `Player.cs` | Add `HandleTeleportBracersInput()` |
| Teleport execution | `Player.cs` | Add `ExecuteTeleport()` |
| Safe position | `Player.cs` | Add `GetSafeTeleportPosition()` |
| Visual rendering | `Player.cs` | Extend `_Draw()` for teleport reticle |
| Icon | `assets/sprites/weapons/` | Create placeholder icon |
| Tests | `tests/unit/` | Add teleport bracers tests |

## References

- Player collision shape: CircleShape2D with radius 16.0
- Obstacles are on collision layer 3 (mask value 4)
- Player collision_mask = 4 (collides with obstacles)
- Input action `flashlight_toggle` maps to Space key (physical_keycode 32)
- Active items share the same Space key — only one active item at a time
