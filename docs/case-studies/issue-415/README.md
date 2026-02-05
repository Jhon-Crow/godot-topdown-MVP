# Case Study: Issue #415 - Animated Statistics Display (Hotline Miami 2 Style)

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/415

**Title:** пункты статистики должны появляться постепенно (как в hotline miami 2)
(Statistics items should appear gradually like in Hotline Miami 2)

## Requirements (Translated from Russian)

1. **Sequential reveal**: Statistics items should appear one after another, only after the previous animation completes
2. **Counting animation**: The final number for each item should animate from 0 to its value with rhythmic pulsing (color change and slight size increase)
3. **Sound effects**: A retro-style filling sound should play during the animation
4. **Final rank reveal**: The rank should appear after all items with animation:
   - First, fullscreen with a flashing contrasting background
   - Then shrink and settle into its position (below items, slightly to the right)

## Reference: Hotline Miami 2 Scoring System

### Score Categories (from Hotline Miami Wiki)
- **Kills**: 1000 points for executions, 800 for melee, 600 for ranged
- **Combo Points**: Bigger combos = more points (main factor for grade)
- **Flexibility**: Varying killing methods
- **Mobility**: Distance traveled
- **Boldness**: Being seen by enemies, punching, etc.
- **Time Bonus**: Quicker times = higher bonus
- **Special**: Character-specific bonuses

### Grades System
- **S**: Roughly 2.6x the Grade C Score (highest rank, flashing red)
- **A+, A, A-**: Green changing to white text
- **B+, B, B-**: Yellow text
- **C+, C, C-**: Blue text
- **D+, D, D-**: Red text
- **F+, F**: Red text

### Visual Animation Details (from research)
- Text "pops" using layered characters effect
- Justice font used for combo counter and UI elements
- Colors change based on score: red (F,D) → blue (C,B-) → yellow (B,A) → green→white (A+,S) → flashing (S)

## Previous Implementation Attempt (PR #430)

### Issues Reported
From PR #430 feedback:
1. Statistics were not visible
2. Rank appeared in the far left corner instead of correct position
3. Rank letter color should depend on rank
4. Arpeggio sound should be major key

### Logs Referenced
- game_log_20260203_181812.txt
- game_log_20260203_181921.txt

## Current Implementation

The current `building_level.gd` has a `_show_score_screen()` function (lines 770-893) that displays:
- Static title "LEVEL CLEARED!"
- Static rank display with color
- Static total score
- Score breakdown table (KILLS, COMBOS, TIME, ACCURACY, SPECIAL KILLS, DAMAGE)
- Restart hint

**What's missing:**
- Sequential reveal animation
- Number counting from 0
- Pulsing/color effects during counting
- Sound effects
- Dramatic fullscreen rank reveal with flashing background

## Implementation Plan

### 1. Sequential Animation System
- Use tweens with sequential delays
- Each row waits for previous animation to complete
- Emit signal when row animation completes

### 2. Counting Animation
- Animate numbers from 0 to final value over ~0.5-1 second
- During counting: pulse color (white → highlight → white)
- Slight scale pulse (1.0 → 1.1 → 1.0)
- Speed up counting as value gets higher (acceleration effect)

### 3. Sound Effects
- Use existing AudioManager with new beep sounds
- Play ascending pitch beeps during counting
- Final "ding" when number lands
- Major arpeggio for rank reveal

### 4. Rank Reveal Animation
- Create fullscreen ColorRect with flashing colors
- Show large rank letter in center
- Animate: scale down + move to final position
- Flash colors: cycle through contrasting colors quickly

## Technical Approach

### New Methods to Add
```gdscript
func _animate_score_item(label: Label, value: int, delay: float) -> void
func _animate_counting(label: Label, target: int, duration: float) -> void
func _pulse_label(label: Label) -> void
func _reveal_rank_dramatic(rank: String, container: Control) -> void
func _flash_background(overlay: ColorRect, duration: float) -> void
```

### Sound Integration
```gdscript
func _play_counting_beep(pitch: float) -> void
func _play_rank_reveal_arpeggio() -> void
```

## Sources

- [Hotline Miami Wiki - Scoring](https://hotlinemiami.fandom.com/wiki/Scoring)
- Previous PR #430 feedback
- Issue #415 description
