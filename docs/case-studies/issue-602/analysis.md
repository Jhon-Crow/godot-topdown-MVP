# Issue #602: Add Enemy Status Effect Animations

## Problem Statement

Enemy status effects (stun and blindness from flashbang grenades) have no visual animation beyond color tinting. The issue requests:
1. **Dizziness animation when stunned** - visual indicator that enemy is disoriented
2. **Eye covering animation when blinded** - visual indicator that enemy cannot see

## Current State Analysis

### Status Effect System
- `StatusEffectsManager` (autoload) tracks blindness/stun durations per entity
- `enemy.gd` has `_is_blinded` and `_is_stunned` flags with `set_blinded()`/`set_stunned()` methods
- Flashbang grenades apply both effects (blindness=12s, stun=6s)
- When stunned: `velocity = Vector2.ZERO`, AI returns immediately from `_process_ai_state()`
- When blinded: `_can_see_player = false`, visibility check returns immediately

### Current Visual Feedback
- `StatusEffectsManager` applies color tinting but targets `entity.get_node_or_null("Sprite2D")` - **this doesn't match the enemy's modular sprite architecture** (Body, Head, LeftArm, RightArm under EnemyModel)
- Enemy has health-based color tinting via `_set_all_sprites_modulate()` which correctly targets all sprites

### Constraints
- `enemy.gd` is at 4998 lines (5000 line limit mentioned in #579 PR)
- Enemy uses modular sprite system: Body, Head, LeftArm, RightArm, WeaponSprite under EnemyModel Node2D
- Existing component pattern: DeathAnimationComponent, MacheteComponent, etc.

## Solution Design

### Architecture: StatusEffectAnimationComponent
Create a new component (following existing patterns) that handles visual animations for status effects. This keeps enemy.gd under the line limit and maintains separation of concerns.

### Stun Animation: Orbiting Stars
- Classic "seeing stars" cartoon effect - universally recognized
- 3 small stars orbit above the enemy's head position
- Stars drawn programmatically using `_draw()` (no new sprite assets needed)
- Yellow/gold color matching the stun tint convention
- Smooth orbit using sine/cosine with time accumulator

### Blind Animation: X Marks Over Eyes
- Two small X marks drawn over the enemy's head area
- Represents eyes being covered/unable to see
- White/yellow color for visibility
- Slight pulsing animation for visual clarity

### Implementation Approach
1. New file: `scripts/components/status_effect_animation_component.gd`
2. Component created and managed by enemy (like DeathAnimationComponent)
3. Uses `_draw()` override on Node2D for efficient rendering
4. Minimal integration code in enemy.gd (component setup + status update calls)
5. Also fix StatusEffectsManager to apply tints to modular enemy sprites

## Research References
- Classic "Circling Birdies" trope used in Street Fighter, Super Smash Bros.
- Godot `_draw()` API: `draw_circle()`, `draw_line()`, `draw_arc()` for programmatic shapes
- Accessibility best practice: combine shapes + animation + color (not color alone)
