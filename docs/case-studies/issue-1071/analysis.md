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

## Files Modified

| File | Change |
|------|--------|
| `scripts/autoload/active_item_manager.gd` | Added DASH enum, data, unlock, has_dash() |
| `scripts/effects/dash_effect.gd` | **New** — Dash logic controller |
| `scenes/effects/DashEffect.tscn` | **New** — Dash effect scene |
| `scripts/characters/player.gd` | Added init, input, immunity, movement override |
| `tests/unit/test_dash_effect.gd` | **New** — Unit tests |

## Testing

Unit tests cover:
- Enum registration and data integrity
- Mock ActiveItemManager integration
- Unlock status (freely available)
- Constants validation (cooldown, duration, speed)
- Unlimited charges behavior
- Damage immunity logic (active/inactive states)
- Afterimage visual parameters
- Direction normalization
