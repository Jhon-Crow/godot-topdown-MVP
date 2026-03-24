# Case Study: Dash Active Item (Issue #1071)

## Issue Summary

Add an active item — **Dash** — inspired by Hyper Light Drifter's dash mechanic.

**Requirements from issue:**
- Unlimited charges (no charge limit)
- Cooldown: 1.2 seconds between dashes
- During dash, all damage sources are ignored (invincibility frames)
- Reference: Hyper Light Drifter dash

## Reference Analysis: Hyper Light Drifter Dash

### Core Design Principles

Hyper Light Drifter's dash is the primary defensive tool in combat. Because enemies cannot be stunned by normal attacks, the gameplay loop revolves around:
1. Attack enemies with a few quick strikes
2. Dash away to avoid counterattacks
3. Reposition and repeat

The dash creates an "economy of time" — each action (slash, dash, shoot) has a fixed cost and output, making mastery about understanding timing and positioning.

### Technical Details (from community research)

- **I-frames**: The dash grants invincibility frames at the start of the dash animation. These were added via a patch after community feedback that the dash didn't feel protective enough.
- **Chain dashing**: An upgradeable ability allowing multiple consecutive dashes with precise timing input.
- **Direction**: Player dashes in the direction of movement input, or facing direction if stationary.
- **Limitations**: Cannot attack during dash (except for a special "dash stab" move). The dash commits the player to a fixed distance.

### Sources
- [Steam Community: Invincibility Frames Discussion](https://steamcommunity.com/app/257850/discussions/0/152390014795968493/)
- [Steam Community: Dash Mechanics Discussion](https://steamcommunity.com/app/257850/discussions/0/142260895144923564/)
- [Game Wisdom: HLD Analysis](https://game-wisdom.com/analysis/hyper-light-drifter)
- [HLD Wiki: Abilities and Upgrades](https://hyperlightdrifter.fandom.com/wiki/Abilities_and_Upgrades)

## Implementation Design

### Approach

The implementation follows the existing active item pattern in this codebase:
1. **ActiveItemManager** registration (enum, data, has_check)
2. **Effect script** (`dash_effect.gd`) containing all dash logic
3. **Effect scene** (`DashEffect.tscn`) for instantiation
4. **Player integration** (init, input handler, damage immunity check)

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| I-frame scope | Full dash duration | Issue specifies "all damage sources ignored during dash" — simpler than partial i-frames |
| Cooldown | 1.2 seconds | Matches issue specification exactly |
| Charges | Unlimited | Matches issue specification |
| Direction fallback | Mouse cursor | When no movement input, dash toward mouse — intuitive for top-down games |
| Speed multiplier | 4x normal | Fast enough to feel impactful, not so fast it clips through walls |
| Duration | 0.15 seconds | Short burst matching HLD's quick dash feel |
| Visual feedback | Afterimage trail | Light blue tinted ghosts that fade out — references HLD's visual style |
| Activation | Press Space | Consistent with other press-based active items |

### Architecture

```
ActiveItemManager (autoload)
  └── DASH enum entry (type 20)
  └── has_dash() check method
  └── ACTIVE_ITEM_DATA entry (name, icon, description)

DashEffect (Node, child of Player)
  └── Manages dash state, cooldown, velocity override
  └── Spawns afterimage visual effects
  └── Exposes is_dashing() for damage immunity check

Player (CharacterBody2D)
  └── _init_dash() — instantiates DashEffect scene
  └── _handle_dash_input() — reads Space press, activates dash
  └── is_dash_active() — queries DashEffect for immunity
  └── on_hit_with_info() — checks is_dash_active() before applying damage
  └── _physics_process() — skips normal movement during dash
```

### Damage Immunity Flow

```
on_hit_with_info() called
  → is_dash_active()? YES → return (no damage)
  → is_force_field_active()? ...
  → _invincibility_enabled? ...
  → Apply damage normally
```

## Bug Report: Dash Not Working (2026-03-23)

### Timeline of Events

1. **Initial implementation** — Dash was implemented only in GDScript (`player.gd`, `dash_effect.gd`)
2. **Testing** — Unit tests passed (GDScript-based tests)
3. **User report** — Repo owner reported "не работает" (doesn't work) with game log attached

### Root Cause Analysis

The game uses **two player implementations**: a GDScript version (`scripts/characters/player.gd` with `scenes/characters/Player.tscn`) and a C# version (`Scripts/Characters/Player.cs` with `scenes/characters/csharp/Player.tscn`). **All level scenes reference the C# Player.tscn**, meaning the GDScript player.gd is never used in actual gameplay.

The initial dash implementation was added only to the GDScript `player.gd`, not to the C# `Player.cs`. Evidence from the game log:

```
[11:14:12] [Player.ItemPickup] active_item_changed received: type=20
[11:14:12] [Player.ItemPickup] De-equipping all active item subsystems before re-init
[11:14:12] [Player.ItemPickup] All active item subsystems de-equipped
[11:14:12] [Player.ItemPickup] No player-side init required for item type 20
```

The C# `OnActiveItemPickedUp` switch statement had no `case 20` for DASH, so it fell through to the `default` branch which logged "No player-side init required". This meant:
- No `DashEffect` scene was instantiated
- No input handling for Space key to trigger dash
- No movement override during dash
- No damage immunity check

### Fix Applied

Added complete dash integration to `Scripts/Characters/Player.cs`:
1. `case 20: InitDash()` in `OnActiveItemPickedUp` switch
2. `InitDash()` call in `_Ready()` for initial load
3. Dash cleanup in `DeequipAllActiveItems()`
4. `HandleDashInput()` call in `_PhysicsProcess()`
5. Movement override: skip `ApplyMovement()` when `IsDashActive()`, use `MoveAndSlide()` only
6. Damage immunity: `IsDashActive()` check at top of `TakeDamage()`

The C# implementation delegates to the existing GDScript `DashEffect` node via `Call()`, following the same pattern as force field (`is_force_field_active()` → `_forceFieldEffect.Call("is_protecting")`).

### Logs

- `game_log_20260323_111404.txt` — Original bug report game log

## Files Modified

| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | Added DASH enum, data, unlock, has_dash() |
| `scripts/effects/dash_effect.gd` | **New** — Dash logic controller |
| `scenes/effects/DashEffect.tscn` | **New** — Dash effect scene |
| `scripts/characters/player.gd` | Added init, input, immunity, movement override |
| `Scripts/Characters/Player.cs` | Added init, input, immunity, movement override (C# — the actual runtime player) |
| `tests/unit/test_dash_effect.gd` | **New** — Unit tests |

## Bug Report: Dash Direction and Trail (2026-03-24)

### User Report

Owner reported two issues:
1. **Dash direction conflict** — dash follows WASD movement direction, but should follow **aim/cursor direction**
2. **Missing visual trail** — no motion blur/afterimage effect visible during dash

### Root Cause Analysis: Dash Direction

Both `HandleDashInput()` (C# in `Player.ActiveItems.cs:5286`) and `_handle_dash_input()` (GDScript in `player.gd:4624`) used `GetInputDirection()` / `_get_input_direction()` as the primary direction source. This returns the WASD keyboard input vector. The mouse cursor was only used as a fallback when stationary.

Evidence from game log — dash directions match exact cardinal/diagonal vectors:
```
[Dash] Activated! Dir: (1.00, 0.00)     ← pure right (D key)
[Dash] Activated! Dir: (0.00, -1.00)    ← pure up (W key)
[Dash] Activated! Dir: (0.71, -0.71)    ← diagonal (W+D keys)
```

These are normalized WASD inputs, not mouse aim vectors (which would have arbitrary floating-point components).

**Fix**: Changed both C# and GDScript to always use `(GetGlobalMousePosition() - GlobalPosition).Normalized()` as the dash direction. This matches the owner's expectation: "dash should only follow aim direction."

### Root Cause Analysis: Missing Afterimage Trail

Two issues identified:

1. **z_index too low** — `ghost_container.z_index = _player.z_index - 1` placed afterimages one layer below the player. If the player's z_index was 0 (default), the ghosts rendered at -1, potentially behind the tilemap/floor layer, making them invisible.

2. **No immediate first afterimage** — The afterimage spawn timer started at 0 and only spawned after accumulating enough delta time (0.0375s interval). At 60fps, the first afterimage appeared on frame 2-3, meaning the ghost at the dash origin point was missed.

**Fix**:
- Changed z_index to match `_player.z_index` (same layer, not below)
- Spawn first afterimage immediately on `activate()` before any physics frames
- Increased `AFTERIMAGE_LIFETIME` from 0.35s to 0.4s for more visible persistence
- Increased `AFTERIMAGE_ALPHA` from 0.6 to 0.7 for better visibility
- Added diagnostic logging to `_spawn_afterimage()` for future debugging

### Logs

- `game_log_20260324_060424.txt` — Bug report game log showing direction values

## Testing

Unit tests cover:
- Enum registration and data integrity
- Mock ActiveItemManager integration
- Unlock status (freely available)
- Constants validation (cooldown, duration, speed)
- 3-charge chain-dash behavior
- Damage immunity logic (active/inactive states)
- Afterimage visual parameters
- Direction normalization
