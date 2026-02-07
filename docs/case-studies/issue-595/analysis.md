# Issue #595: Add Weapon Model and Attack Animation for Machete Enemies

## Problem Statement

Issue #595 requests two enhancements for machete-wielding enemies:
1. **Visible weapon model** — The machete sprite should be visible on the enemy, not hidden
2. **Attack animation** — Enemies should have a windup → pause → strike animation when attacking

### Current State (Before Fix)

- Machete sprite exists (`assets/sprites/weapons/machete_topdown.png`, 64x16 PNG)
- Weapon sprite is **hidden** on machete enemies (`enemy.gd:417`: `_weapon_sprite.visible = false`)
- Melee attack is **instant** — damage applied immediately with no visual feedback
- Walking animation exists (procedural sine-wave arm swing) but no attack animation
- MacheteComponent handles all melee logic but has no animation state

### Reference

The issue includes a reference image showing a machete weapon model.
Animation specification: "замах (windup), небольшая пауза (brief pause), удар (strike)."

## Root Cause Analysis

The machete weapon system (Issue #579) was implemented with full combat AI (sneaking,
backstab, bullet dodging) but no visual representation or attack animation. The weapon
sprite was explicitly hidden because there was no animation system to display it during attacks.

## Solution Design

### Approach: Procedural Animation via MacheteComponent

Following the project's existing pattern of procedural animations (walking uses sine waves,
death uses keyframe interpolation), the machete attack animation is implemented as a
code-driven weapon rotation system in MacheteComponent.

### Animation Phases

1. **WINDUP** (0.25s): Weapon rotates backward (counter-clockwise) by 90° from idle
   - Right arm pulls back to prepare the swing
   - Slow, deliberate movement communicating the incoming attack

2. **PAUSE** (0.1s): Brief hold at windup peak
   - Creates anticipation and gives the player a reaction window
   - Weapon and arm stay at maximum windup position

3. **STRIKE** (0.15s): Fast forward swing through 180° arc
   - Weapon sweeps from behind the enemy through to the front
   - Damage is applied at the midpoint of the strike
   - Fast, aggressive motion with visual impact

4. **RECOVERY** (0.2s): Return to idle position
   - Smooth interpolation back to resting pose
   - Weapon visible and ready for next attack

### Technical Implementation

- **MacheteComponent** gains animation state machine (IDLE, WINDUP, PAUSE, STRIKE, RECOVERY)
- **WeaponMount** rotation is driven by the animation phase
- **Arm positions** are adjusted during the swing for visual coherence
- **Damage timing** moved from instant to strike-phase midpoint
- **Weapon visibility** enabled for machete enemies (sprite shown, not hidden)

### Files Modified

| File | Change |
|------|--------|
| `scripts/components/machete_component.gd` | Add animation state machine, swing phases |
| `scripts/objects/enemy.gd` | Show weapon sprite, integrate animation callbacks |
| `tests/unit/test_machete_component.gd` | Add animation state tests |

## References

- Issue #579: Original machete implementation (MacheteComponent, weapon config, AI behaviors)
- PR #580: Machete implementation merged with Beach level
- DeathAnimationComponent pattern: Procedural keyframe animation with phases
- Walking animation pattern: Sine-wave based procedural animation
