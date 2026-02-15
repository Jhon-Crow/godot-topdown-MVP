# Case Study: Issue #785 - Make Armory Items Openable (Case Opening System)

## Issue Summary

**Original Request (Russian):**
- сделать открытие кейса максимально приятным (визуально и по звуку) - найти лучшие практики
- для отладки сделать чтоб при запуске собранного exe всё кроме пм и светошумовой гранаты было закрыто
- и открывалось по зажатию значка соответствующего кейса LMB

**Translated Requirements:**
1. Make case opening as pleasant as possible (visually and sonically) - find best practices
2. For debugging: when running built exe, everything except PM (Makarov pistol) and flashbang grenade should be locked
3. Items should be opened/unlocked by holding LMB on the corresponding case icon

## Research: Best Practices for Case Opening UX

### Visual Design Principles

Based on research from [Roblox Developer Forum](https://devforum.roblox.com/t/what-makes-a-good-loot-box-opening-animation/1999029) and industry practices:

1. **Build-Up and Anticipation**
   - Don't jump directly to reveal - create tension
   - Progressive animation sequences enhance dopamine response

2. **Visual Dynamics**
   - Camera movement or element rotation creates dynamism
   - Impact effects (particles, glow, shake) heighten excitement
   - Entrance animations (bounce, slide) add polish

3. **Rarity-Specific Variations**
   - Different animation intensity for different item tiers
   - Particles matching rarity tiers (color-coding)
   - More dramatic reveals for valuable items

4. **Particle Enhancement**
   - Tasteful particles throughout sequence, not just at reveal
   - Color-coded effects for visual feedback

### Sound Design Principles

From [Mercora's analysis of CS2 case opening animations](https://www.mercora.com/sound-design-in-cs2-case-opening-animations/):

1. **Layering Technique**
   - Combine multiple audio elements for depth
   - Base sounds + texture layers + electronic sweeps

2. **Progressive Buildup**
   - Sound anticipation builds emotional investment
   - Crescendo of audio cues at reveal moment

3. **Immediate Feedback**
   - Audio confirms player actions
   - Makes interactions feel intuitive and rewarding

4. **Core Components**
   - Audio cues: Brief signals marking specific actions
   - Background scores: Emotional foundations
   - Atmospheric sounds: Ambient immersion elements

### Godot 4 Implementation Techniques

From [GDQuest Looting Course](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/looting/the_chest_open_animation):

1. **Animation Approaches**
   - AnimationPlayer for sequence-based animations
   - Tween for programmatic smooth transitions
   - Combined approach for complex effects

2. **Keyframe Structure**
   - Start position (closed state)
   - Intermediate position (opening)
   - Final position (open/revealed)

3. **Property Animation**
   - Position (movement)
   - Rotation (lid flip)
   - Scale (emphasis/bounce)
   - Modulation (color/glow)

## Proposed Solution Architecture

### 1. UnlockManager Autoload

New singleton to manage item unlock states:
- Persists unlock state to user://unlock_state.cfg
- Tracks unlocked weapons, grenades, and active items
- Provides API for checking/setting unlock state
- Emits signals when items are unlocked

### 2. Case Opening Animation System

Components in armory_menu.gd:
- Progress bar overlay during hold-to-unlock
- Tween-based animation sequence on unlock
- Particle effects for visual feedback
- Sound integration via AudioManager

### 3. Default Unlock State

By default (fresh install or debug):
- **Weapons:** Only "makarov_pm" unlocked
- **Grenades:** Only FLASHBANG unlocked
- **Active Items:** NONE unlocked (or all locked except base)

### 4. Audio Integration

New sounds needed in AudioManager:
- `CASE_OPEN_START` - Initial click when hold begins
- `CASE_OPEN_PROGRESS` - Looping sound during hold
- `CASE_OPEN_SUCCESS` - Reward sound on unlock
- `CASE_OPEN_REVEAL` - Item reveal flourish

## Implementation Plan

1. Create UnlockManager autoload with persistence
2. Modify armory_menu.gd FIREARMS/GRENADE_DATA to read from UnlockManager
3. Implement hold-to-unlock interaction on locked case icons
4. Add progress bar and animation tweens
5. Integrate sound effects
6. Set default unlock state for debug builds
7. Write unit tests

## Related Files

- `scripts/ui/armory_menu.gd` - Main UI implementation
- `scripts/autoload/grenade_manager.gd` - Reference for manager pattern
- `scripts/autoload/progress_manager.gd` - Reference for persistence pattern
- `scripts/autoload/audio_manager.gd` - Audio playback system

## References

- [Roblox Dev Forum: Loot Box Animation Best Practices](https://devforum.roblox.com/t/what-makes-a-good-loot-box-opening-animation/1999029)
- [Mercora: Sound Design in CS2 Case Opening](https://www.mercora.com/sound-design-in-cs2-case-opening-animations/)
- [GDQuest: Chest Opening Animation in Godot 4](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/looting/the_chest_open_animation)
- [Godot 4 Loot Box Demo](https://pigeonivy.itch.io/godot-4-loot-box-demo)
