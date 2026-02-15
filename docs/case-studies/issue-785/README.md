# Case Study: Animated Item Opening in Armory (Issue #785)

## Problem Statement

The armory menu currently has a basic unlock mechanism where holding LMB for 1.5 seconds unlocks locked items. However, this lacks visual and audio feedback to make the experience engaging and satisfying. The issue requests making the item opening animation visually appealing with good sound design.

## Research Findings

### Best Practices for Case/Loot Box Opening Animations

Based on research from various sources:

#### Visual Effects & Dynamics ([Roblox DevForum](https://devforum.roblox.com/t/what-makes-a-good-loot-box-opening-animation/1999029))

1. **Physical impact** - Make the case visually react when opening (e.g., shaking, breaking open)
2. **Camera movement** - Rotate or move the camera dynamically during reveal (not applicable for 2D UI)
3. **Rarity-specific animations** - Different dramatic intensities for common versus legendary items
4. **Particle effects** - Use color-coded particles matching rarity tiers, with enhanced particle density for higher rarities
5. **Environmental effects** - Add lighting effects, glows, or flashes for added spectacle

#### Animation Variety
- Implement multiple opening sequences (e.g., item emerging with light effects)
- Randomize animations to make each opening feel unique and special

#### Timing & Anticipation
- Build sustained anticipation through layered sequences rather than immediate reveals
- Incorporate musical elements that develop tension
- Include bounce effects and momentum-based movements for impact

### Sound Design Principles ([Mercora - CS2 Case Opening](https://www.mercora.com/sound-design-in-cs2-case-opening-animations/))

1. **Audio Cues** - Brief sounds that signal specific actions (case start, progress, unlock)
2. **Anticipation Building** - Sound rising in pitch before reveal heightens suspense
3. **Layering** - Combine multiple sound elements simultaneously for depth
4. **Feedback** - Sound provides immediate feedback that reinforces player actions

### Technical Implementation in Godot 4 ([Godot Docs](https://docs.godotengine.org/en/stable/classes/class_tween.html))

1. **Tweens** - Use `create_tween()` for smooth code-based animations
2. **Chaining** - Sequential tween_property calls execute in order
3. **Parallel animations** - Use `set_parallel()` for simultaneous effects
4. **Easing** - Use transition types (TRANS_*) and ease types (EASE_*) for natural motion
5. **Particles** - Use GPUParticles2D for visual effects like sparks, glows

## Existing Codebase Patterns

### animated_score_screen.gd

This file provides an excellent reference implementation with:
- Sequential reveal animations
- Counting animations with pulsing effects
- Sound effects (generated beeps)
- Dramatic reveals with flashing backgrounds
- Proper use of tweens and timers
- Skip functionality for user control

### armory_menu.gd

Current unlock mechanism at lines 1183-1225:
- Timer-based hold detection (UNLOCK_HOLD_DURATION = 1.5s)
- No visual feedback during hold
- Instant slot rebuild after unlock
- No sound effects

## Proposed Solution

### Animation Design

**Phase 1: Hold Progress (0 - 1.5 seconds)**
- Visual progress indicator (circular progress or glow intensity)
- Slot shakes/pulses with increasing intensity
- Rising pitch audio cue building anticipation

**Phase 2: Unlock Reveal (0.3 - 0.5 seconds)**
- Case icon flashes bright white
- Scale animation (pop effect)
- Particle burst effect (sparks/glow)
- Success sound effect

**Phase 3: Item Reveal (0.5 - 0.8 seconds)**
- Case fades out while item fades in
- Item scales up with bounce effect
- Name label fades in
- Final celebratory sound

### Technical Implementation

1. **Progress Tracking**
   - Add progress bar overlay on slot during hold
   - Update visual every frame using timer callback

2. **Animation Effects**
   - Use tweens for smooth scale/rotation/alpha changes
   - Use ColorRect overlay for glow/flash effects
   - Consider GPUParticles2D for particle burst (optional)

3. **Sound Design**
   - Add new UI sound constants to AudioManager (or use generated beeps like animated_score_screen.gd)
   - Rising pitch during hold
   - Satisfying "unlock" sound on completion

### Files to Modify

1. `scripts/ui/armory_menu.gd` - Main implementation
2. `scripts/autoload/audio_manager.gd` - Add UI unlock sounds (optional)

## Implementation Plan

1. Add visual progress indicator during LMB hold
2. Add shaking/pulsing effect during hold
3. Implement unlock reveal animation sequence
4. Add sound effects (generated beeps similar to score screen)
5. Update slot rebuild to animate item reveal
6. Add unit tests for new functionality
