# Case Study: Issue #202 - Add Grenade Throwing Animation

## Executive Summary

This case study documents the analysis and implementation plan for a composite grenade throwing animation system for the Godot Top-Down Template project. The feature request describes a multi-step animation sequence that responds to player input, including pin pulling, hand-to-hand transfer, wind-up swing, and throw phases.

**Issue**: [#202](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/202)
**Pull Request**: [#203](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/203)
**Status**: ✅ Implementation Complete (2026-01-22)

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Requirements Analysis](#requirements-analysis)
3. [Current Implementation Analysis](#current-implementation-analysis)
4. [Timeline of Events](#timeline-of-events)
5. [Technical Implementation](#technical-implementation)
6. [Industry Best Practices Research](#industry-best-practices-research)
7. [Root Cause Analysis](#root-cause-analysis)
8. [Proposed Solution Architecture](#proposed-solution-architecture)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Lessons Learned](#lessons-learned)
11. [References](#references)

---

## Implementation Summary (2026-01-22)

### Current Status: Iteration 2 - Animation Refinement

**Latest Update (2026-01-22 07:45 UTC)**: Second iteration addressing user feedback on animation visual issues.

### User Feedback (Iteration 2)

**Feedback from @Jhon-Crow (translated from Russian):**
1. **Arms should be below the weapon when grabbing grenade** - Fixed by adjusting z-index during grenade operations
2. **Arms are detached from forearms (should bend at elbow, not detach)** - Fixed by reducing position offsets and using rotation
3. **Second hand should not be on the weapon during wind-up** - Fixed with new `ArmLeftRelaxed` position

### Changes Made in Iteration 2

| Issue | Root Cause | Fix Applied |
|-------|------------|-------------|
| Arms above weapon | Z-index was 2 during grenade ops | Set z-index to 0 (below weapon z=1) |
| Arms "detaching" | Position offsets too large (e.g., -15, -8) | Reduced to small offsets (e.g., -4, 3) |
| Second hand on weapon | Left arm returned to base during wind-up | New `ArmLeftRelaxed` position (-6, 5) |

### Technical Changes

**Animation Position Constants (reduced offsets):**
```csharp
// OLD: Large offsets caused visual detachment
ArmLeftChest = new Vector2(-15, -8)
ArmRightWindMax = new Vector2(35, 18)

// NEW: Small offsets keep arms connected
ArmLeftChest = new Vector2(-4, 3)
ArmRightWindMax = new Vector2(8, 5)
```

**Animation Rotation Constants (elbow bending):**
```csharp
// Rely on rotation to simulate elbow bending
ArmRotGrab = -20.0f      // Inward bend
ArmRotWindMin = 15.0f    // Arm pulled back
ArmRotWindMax = 35.0f    // Maximum wind-up
```

**Z-Index Management:**
```csharp
// During grenade ops: arms below weapon
SetGrenadeAnimZIndex() -> arms z-index = 0

// Normal state: arms above body
RestoreArmZIndex() -> arms z-index = 2
```

---

### Previous Update (2026-01-22 07:15 UTC)

The animation system has now been ported to the C# Player class, which is the version actually used by the game.

### Root Cause of "Animation Not Visible" Issue

The initial implementation added animation code to `scripts/characters/player.gd` (GDScript), but the game levels actually use `Scripts/Characters/Player.cs` (C#). Investigation of the scene files revealed:

| Level | Player Scene | Script Used |
|-------|--------------|-------------|
| BuildingLevel.tscn | csharp/Player.tscn | Player.cs |
| TestTier.tscn | csharp/Player.tscn | Player.cs |
| csharp/TestTier.tscn | csharp/Player.tscn | Player.cs |

This is why the user's game logs showed grenade state machine messages (which were in both versions) but NO animation-related log messages.

### What Was Implemented

The complete procedural animation system for grenade throwing has been implemented in **both** `scripts/characters/player.gd` AND `Scripts/Characters/Player.cs`. Key features:

1. **Animation Phase System** (`GrenadeAnimPhase` enum):
   - `NONE` - Normal/idle state
   - `GRAB_GRENADE` - Left hand moves to chest
   - `PULL_PIN` - Right hand pulls pin
   - `HANDS_APPROACH` - Hands coming together
   - `TRANSFER` - Grenade passes to right hand
   - `WIND_UP` - Dynamic wind-up based on drag
   - `THROW` - Throwing motion
   - `RETURN_IDLE` - Arms return to normal

2. **Weapon Sling System**:
   - Weapon automatically lowers when handling grenade
   - Weapon rotates to "hang on strap" position
   - Smooth transitions using lerp interpolation

3. **Dynamic Wind-up**:
   - Wind-up intensity (0.0-1.0) based on mouse drag distance
   - Velocity bonus for more responsive feel
   - Arm position and rotation scale with intensity

4. **Code Location**:
   - GDScript: Lines 868-1429 in `scripts/characters/player.gd`
   - C#: Grenade Animation region in `Scripts/Characters/Player.cs`

### Animation Logging

Animation phase changes are now logged for debugging:
```
[Player.Grenade.Anim] Phase changed to: GRAB_GRENADE (duration: 0.20s)
[Player.Grenade.Anim] Phase changed to: PULL_PIN (duration: 0.15s)
...
[Player.Grenade.Anim] Animation complete, returning to normal
```

---

## Problem Statement

### Original Issue (Russian)

> составная анимация:
> первый шаг - левой рукой с груди берёт гранату,
> в момент первого драгндропа (активации) - правой рукой выдёргивает чеку.
> при зажатии ПКМ подносит правую руку к левой (к руке с гранатой),
> при отпускании G - оставляет гранату в правой руке (передал)
> при замахе - замахивается (сила и скорость замаха в анимации зависит от силы и скорости замаха игрока),
> при броске - бросок.

### English Translation

> Composite animation:
> First step - with left hand takes grenade from chest,
> At the moment of first drag-and-drop (activation) - with right hand pulls out the pin.
> When holding RMB brings right hand to left hand (to the hand with grenade),
> When releasing G - leaves grenade in right hand (transferred)
> During wind-up - swings back (strength and speed of swing in animation depends on strength and speed of player's swing),
> During throw - throw.

### Core Problem

The current grenade system has **functional mechanics** but lacks **visual feedback through character animation**. The existing system uses:
- A 2-step input mechanic (G key + RMB drag to activate timer, then G+RMB release sequence to aim and throw)
- Physics-based throw velocity from drag distance
- Grenade spawning at player position

However, there is **no arm movement or hand animation** to communicate these actions visually to the player, reducing game feel and immersion.

---

## Requirements Analysis

### Functional Requirements

| ID | Requirement | Priority | Description |
|----|-------------|----------|-------------|
| FR-1 | Left hand grabs grenade from chest | High | Initial pickup animation |
| FR-2 | Right hand pulls pin on first activation | High | Pin pull on drag-right gesture |
| FR-3 | Right hand approaches left hand when RMB held | High | Preparation for handoff |
| FR-4 | Grenade transfers to right hand on G release | High | Visual handoff animation |
| FR-5 | Wind-up animation scales with input intensity | High | Dynamic swing based on drag speed/distance |
| FR-6 | Throw animation on release | High | Final throwing motion |

### Animation State Mapping to Current Input System

| Current Input State | Animation Required |
|---------------------|-------------------|
| `GrenadeState.IDLE` + G pressed | Left hand reaches to chest |
| First drag-right complete | Right hand pulls pin |
| `GrenadeState.TIMER_STARTED` + RMB press | Right hand moves toward left |
| `GrenadeState.WAITING_FOR_G_RELEASE` | Hands together, preparing transfer |
| G released (→ `AIMING`) | Grenade in right hand, left hand returns |
| RMB held + dragging | Wind-up/swing animation |
| RMB released | Throw animation |

### Non-Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| NFR-1 | Animations must blend smoothly with existing walking animation | High |
| NFR-2 | Must work with player model rotation (facing mouse) | High |
| NFR-3 | Should not interfere with weapon mounting system | Medium |
| NFR-4 | Animation intensity should feel responsive to player input | High |

---

## Current Implementation Analysis

### Player Character Structure

The player uses a modular sprite system:

```
Player (CharacterBody2D)
├── PlayerModel (Node2D) - rotates to face mouse
│   ├── Body (Sprite2D) - z_index: 1
│   ├── LeftArm (Sprite2D) - z_index: 4, position: (24, 6)
│   ├── RightArm (Sprite2D) - z_index: 4, position: (-2, 6)
│   ├── Head (Sprite2D) - z_index: 3
│   └── WeaponMount (Node2D) - position: (0, 6)
└── Camera2D
```

### Existing Animation System

The player already has a **procedural walking animation** (`_update_walk_animation`) that:
- Uses sine waves to create bobbing motion
- Animates body, head, and arms independently
- Stores base positions and applies offsets
- Smoothly interpolates back to idle when stopping

```gdscript
# Walking animation intensity parameter
@export var walk_anim_intensity: float = 1.0

# Animation applies offsets to base positions
var body_bob := sin(_walk_anim_time * 2.0) * 1.5 * walk_anim_intensity
var arm_swing := sin(_walk_anim_time) * 3.0 * walk_anim_intensity
```

### Current Grenade State Machine

```gdscript
enum GrenadeState {
    IDLE,                 # No grenade action
    TIMER_STARTED,        # Step 1 complete: timer running, G held
    WAITING_FOR_G_RELEASE,# Step 2 in progress: G+RMB held
    AIMING                # Step 2 complete: only RMB held, ready to throw
}
```

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `scripts/characters/player.gd` | 1149 | Player controller with grenade logic |
| `scripts/projectiles/grenade_base.gd` | 294 | Base grenade physics and behavior |
| `scenes/characters/Player.tscn` | 78 | Player scene with sprite structure |

---

## Timeline of Events

### Issue Analysis Phase

| Timestamp (UTC) | Event |
|-----------------|-------|
| 2026-01-22 04:21 | Issue #202 created by @Jhon-Crow |
| 2026-01-22 04:21 | Branch `issue-202-b083913c28e6` created |
| 2026-01-22 04:21 | Draft PR #203 created |
| 2026-01-22 04:22 | AI solver process initiated |
| 2026-01-22 04:22+ | Codebase exploration and research |
| 2026-01-22 03:29 | AI Solution Draft Log posted (PR#203 comment) |
| 2026-01-22 03:55 | User @Jhon-Crow feedback: Animation not working |
| 2026-01-22 03:56 | AI Work Session restarted for implementation |

### User Feedback Analysis (2026-01-22)

**Original feedback (Russian):**
> новая анимация не добавилась (или добавилась но не проигрывается из-за конфликта языков).
> в идеале при проигрывании этой анимации оружие должно повисать вниз стволом на ремне (груди персонажа), чтобы руками работать с гранатой.

**Translation:**
> The new animation wasn't added (or was added but isn't playing due to language conflict).
> Ideally when this animation plays, the weapon should hang down by its strap on the character's chest, so that hands can work with the grenade.

**Key Additional Requirements Identified:**
1. **Weapon sling mode** - When handling grenade, weapon should be lowered/slung on chest
2. **Both hands free** - Arms need to be completely free from weapon for grenade operations

---

## Game Log Analysis (2026-01-22)

### Log Files Analyzed

| File | Timestamp | Duration | Key Events |
|------|-----------|----------|------------|
| `game_log_20260122_065207.txt` | 06:52:07 - 06:52:26 | 19 seconds | 3 grenade throws, scene resets |
| `game_log_20260122_065247.txt` | 06:52:47 - 06:53:17 | 30 seconds | Weapon switch, shooting, 2 grenade throws |

### Grenade Interaction Timeline (Log 1)

```
06:52:08 - Step 1 started: G held, RMB pressed at (244.44, 1137.79)
06:52:08 - Grenade created at (0, 0) (frozen)
06:52:08 - Timer activated! 4.0 seconds until explosion
06:52:08 - Step 1 complete! Drag: (420.25, -14.03)
06:52:10 - G released - dropping grenade at feet
           [Player died, scene reset]

06:52:11 - Step 1 started: G held, RMB pressed
06:52:11 - Step 1 complete! Drag: (487.68, -8.68)
06:52:11 - Step 2 part 1: G+RMB held
06:52:12 - Step 2 complete: G released, RMB held - now aiming
06:52:13 - Throwing! Direction: (-0.14, -0.99), Drag distance: 472.19
06:52:13 - Player rotated for throw: 0 -> -1.71
06:52:13 - Thrown! Direction/Speed: 944.4
06:52:14 - Grenade landed at (375.08, 720.28)
```

### Critical Finding: NO Animation Logs

**Analysis of logs reveals:**
1. ✅ Grenade state machine working correctly
2. ✅ All input states transitioning properly
3. ✅ Grenade physics (throw, land, explode) functional
4. ❌ **NO animation-related log messages present**
5. ❌ **No arm position changes logged**

### Root Cause Identified

The previous solution draft **only added documentation** (README.md, implementation-plan.md) but **did not implement the actual animation code** in `player.gd`.

**Evidence:**
- Player.gd contains walking animation system (lines 361-413)
- Player.gd contains grenade state machine (lines 800-1149)
- **No grenade animation phase enum exists**
- **No `_update_grenade_animation()` function exists**
- **Arm positions are never modified during grenade operations**

---

## Technical Implementation

### Animation Approach Options

Based on research, there are three main approaches for implementing the grenade animation:

#### Option A: Procedural Animation (Recommended)

Extend the existing procedural animation system by adding position/rotation tweens for arms based on grenade state.

**Pros:**
- Consistent with existing walking animation system
- Allows dynamic adjustment based on input intensity
- No external assets required
- Full control over animation timing

**Cons:**
- More complex code
- Requires careful tuning

#### Option B: AnimationPlayer with State Machine

Create keyframe animations in Godot and use AnimationTree with state machine.

**Pros:**
- Visual animation editing
- Standard Godot pattern
- Easier to iterate on timing

**Cons:**
- Less dynamic (fixed animations)
- Requires sprite sheet or separate animation assets
- More complex asset pipeline

#### Option C: Hybrid Approach

Use AnimationPlayer for fixed phases (pin pull, throw) and procedural for dynamic phases (wind-up).

**Pros:**
- Best of both worlds
- Professional-quality fixed animations
- Dynamic wind-up

**Cons:**
- Most complex to implement
- Requires careful blending between systems

### Recommended Implementation: Procedural Animation

Based on the existing codebase architecture, **Option A (Procedural)** is recommended because:

1. The codebase already uses procedural animation for walking
2. The wind-up phase explicitly requires dynamic animation based on player input
3. No external animation assets are available
4. Maintains consistency with the tactical, responsive feel of the game

---

## Industry Best Practices Research

### Multi-Step Grenade Mechanics in Games

Research from CS:GO and other tactical shooters reveals standard patterns:

| Game | Pin Pull | Cook | Throw Styles | Wind-up |
|------|----------|------|--------------|---------|
| CS:GO | Automatic on activate | Manual hold | Multiple (underhand, overhand, medium) | Fixed |
| Insurgency | Button hold | Manual | Variable power | Distance-based |
| This Project | First drag activation | Timer starts | Drag-to-aim | Dynamic (requested) |

### Animation Sequencing

From game design research:

> "In a standard left-click throw: the pin is pulled, the spoon is released, and then the arm is pulled back. If you hold down left click, you pause the animation before the grenade is thrown but the fuse continues."
> — CS:GO Advanced Grenade Mechanics Guide

### Procedural Animation in Godot

From Godot documentation and community resources:

- **RemoteTransform2D** can be used for arm layering in 2D character rigs
- **Tween nodes** or `create_tween()` provide smooth interpolation
- **Inverse Kinematics** can be used for hand-to-target reaching, though may be overkill for 2D top-down

---

## Root Cause Analysis

### Why Is Animation Needed?

| Factor | Analysis |
|--------|----------|
| **Visual Feedback Gap** | Current grenade system works mechanically but provides no visual indication of what the character is doing |
| **Game Feel** | Players cannot see the multi-step process, reducing tactical awareness |
| **Input Mapping Clarity** | Complex input sequence (G+RMB drag, G+RMB hold, G release, RMB drag+release) needs visual reinforcement |
| **Immersion** | Character appears static during grenade operations |

### Why Dynamic Wind-up?

The issue explicitly states:
> "при замахе - замахивается (сила и скорость замаха в анимации зависит от силы и скорости замаха игрока)"
> "during wind-up - swings back (strength and speed of swing in animation depends on strength and speed of player's swing)"

This requires:
- Tracking mouse movement velocity during aiming phase
- Mapping velocity to arm position/rotation
- Smooth interpolation between rest and full wind-up

---

## Proposed Solution Architecture

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Player Controller                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────────────┐    ┌────────────────────────────────┐ │
│  │    GrenadeState Machine │    │     GrenadeAnimationController │ │
│  │    (existing)           │───>│          (new)                 │ │
│  │                         │    │                                │ │
│  │  - IDLE                 │    │  - _anim_phase: AnimPhase      │ │
│  │  - TIMER_STARTED        │    │  - _left_arm_target: Vector2   │ │
│  │  - WAITING_FOR_G_RELEASE│    │  - _right_arm_target: Vector2  │ │
│  │  - AIMING               │    │  - _wind_up_intensity: float   │ │
│  └─────────────────────────┘    │                                │ │
│                                 │  + update_animation(delta)     │ │
│  ┌─────────────────────────┐    │  + set_phase(phase)            │ │
│  │    Arm Sprites          │<───│  + set_wind_up(intensity)      │ │
│  │                         │    └────────────────────────────────┘ │
│  │  - LeftArm.position     │                                       │
│  │  - LeftArm.rotation     │                                       │
│  │  - RightArm.position    │                                       │
│  │  - RightArm.rotation    │                                       │
│  └─────────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Animation Phases

```gdscript
enum GrenadeAnimPhase {
    NONE,           # Normal arm positions (walking/idle)
    GRAB_GRENADE,   # Left hand moves to chest
    PULL_PIN,       # Right hand pulls pin (quick snap)
    HANDS_APPROACH, # Right hand moves toward left hand
    TRANSFER,       # Grenade moves to right hand
    WIND_UP,        # Dynamic wind-up based on drag
    THROW,          # Throwing motion
    RETURN_IDLE     # Arms return to normal
}
```

### Arm Position Constants

```gdscript
# Target positions for each animation phase (relative to base positions)
const ARM_POS_CHEST := Vector2(-20, -5)           # Left hand at chest (grenade pickup)
const ARM_POS_PIN_PULL := Vector2(-10, -10)       # Right hand near grenade for pin
const ARM_POS_HANDS_TOGETHER := Vector2(0, 0)     # Hands meeting point
const ARM_POS_WIND_UP_MAX := Vector2(30, 15)      # Maximum wind-up position
const ARM_POS_THROW_FORWARD := Vector2(-40, 0)    # Throw follow-through
```

### Dynamic Wind-up Calculation

```gdscript
func _calculate_wind_up_intensity() -> float:
    # Get current and previous mouse positions
    var current_mouse := get_global_mouse_position()
    var mouse_velocity := (current_mouse - _previous_mouse_position) / delta
    _previous_mouse_position = current_mouse

    # Calculate intensity from drag distance from aim start
    var drag_vector := current_mouse - _aim_drag_start
    var drag_distance := drag_vector.length()

    # Normalize to 0-1 range based on max expected drag
    var max_drag := 500.0  # pixels
    return clampf(drag_distance / max_drag, 0.0, 1.0)
```

---

## Implementation Roadmap

### Phase 1: Core Animation Infrastructure

1. Add animation phase enum and state variables
2. Create arm target position constants
3. Implement `_update_grenade_animation()` function
4. Add smooth interpolation using `lerp()` or tweens

### Phase 2: State-to-Animation Mapping

1. Hook animation phase changes to grenade state transitions
2. Implement each animation phase:
   - GRAB_GRENADE: Left arm to chest
   - PULL_PIN: Right arm quick movement
   - HANDS_APPROACH: Both arms meeting
   - TRANSFER: Left arm back, right arm holds position
   - WIND_UP: Dynamic arm position based on drag
   - THROW: Follow-through animation
   - RETURN_IDLE: Smooth return to base positions

### Phase 3: Dynamic Wind-up

1. Track mouse velocity during AIMING state
2. Calculate wind-up intensity
3. Interpolate arm position based on intensity
4. Add rotation to arm sprites for natural motion

### Phase 4: Polish and Integration

1. Blend with walking animation
2. Tune timing and feel
3. Add rotation animation to player model during throw
4. Test with different throw distances and speeds

### Estimated Scope

| Component | Lines of Code | Complexity |
|-----------|---------------|------------|
| Animation phase enum and constants | ~30 | Low |
| `_update_grenade_animation()` function | ~100-150 | Medium |
| State-to-phase mapping | ~50 | Low |
| Dynamic wind-up calculation | ~40 | Medium |
| Arm rotation handling | ~30 | Low |
| Integration with existing code | ~50 | Medium |
| **Total** | **~300-350** | Medium |

---

## Lessons Learned

### From Codebase Analysis

1. **Existing procedural animation** provides a good pattern to follow
2. **Player model rotation** must be considered for arm positioning
3. **Walking animation** needs to be suspended or blended during grenade actions
4. **Sprite z-index** hierarchy already handles arm layering

### From Research

1. **Multi-step grenades** in professional games use distinct visual phases
2. **Dynamic wind-up** requires tracking input velocity, not just position
3. **Procedural animation** is preferred for input-responsive effects
4. **Tweens** provide smooth interpolation for phase transitions

---

## References

### Game Design & Animation

- [CS:GO Advanced Grenade Throwing Mechanics](https://steamcommunity.com/sharedfiles/filedetails/?id=1106790511) - Multi-step grenade mechanics
- [ARMA 3 Animated Grenade Throwing](https://steamcommunity.com/workshop/filedetails/?id=2935338016) - Extended grenade system with swing/wind-up
- [Unreal Engine 5 Grenade Tutorial](https://dev.epicgames.com/community/learning/tutorials/PZnV/) - Animation + mechanics implementation

### Godot Animation

- [Godot 4 AnimationTree State Machine](https://kidscancode.org/godot_recipes/4.x/animation/using_animation_sm/index.html) - KidsCanCode
- [Godot Animation Documentation](https://docs.godotengine.org/en/stable/tutorials/animation/introduction.html) - Official docs
- [2D Arm IK in Godot](https://forum.godotengine.org/t/arm-in-2d-top-down-game/104629) - Forum discussion
- [Grabbing and Throwing Mechanics](https://forum.godotengine.org/t/help-me-with-grabbing-and-throwing-mechanic/122183) - Godot Forum

### Project Resources

- [Issue #202 Data](./logs/issue-data.json) - Raw issue JSON
- [PR #203 Data](./logs/pr-data.json) - Pull request JSON

---

## Appendix: Issue Translation Details

### Animation Step Breakdown

| Russian | English | Input Trigger |
|---------|---------|---------------|
| левой рукой с груди берёт гранату | left hand takes grenade from chest | G key pressed |
| правой рукой выдёргивает чеку | right hand pulls out the pin | First drag-right complete |
| подносит правую руку к левой | brings right hand to left | RMB press while G held |
| оставляет гранату в правой руке | leaves grenade in right hand | G release (RMB still held) |
| замахивается | swings back (wind-up) | RMB drag |
| бросок | throw | RMB release |

---

*Case study compiled on 2026-01-22*
*Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/202*
*Pull Request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/203*
