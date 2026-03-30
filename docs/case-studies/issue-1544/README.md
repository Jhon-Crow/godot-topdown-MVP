# Case Study: Issue #1544 - Weapon Selection Animation (Shake + Glint)

## Issue Description

**Title:** update анимация выбора оружия (update weapon selection animation)

**Request:**
When a weapon is selected in the Armory menu, it should:
1. **Shake slightly** — a small jitter/wobble animation to give tactile feedback
2. **Glint/shine** — a highlight/shine animation on the icon, like light reflecting off it

The effect should look "максимально приятно" (as pleasant/polished as possible).

Reference for pixel art 4-step animation technique: https://saint11.art/blog/pixel-art-tutorials/

## Relevant Files

| File | Role |
|------|------|
| `scripts/ui/armory_menu.gd` | Main armory menu script — handles all weapon slot creation and selection logic |
| `scenes/ui/ArmoryMenu.tscn` | Scene file (minimal, script-driven) |
| `resources/themes/neon_glow.gdshader` | Existing glow shader (for reference) |
| `scripts/shaders/flashbang_player.gdshader` | Example flash/brightness shader |

## Root Cause Analysis

### Current State

In `_on_slot_gui_input()` (line 1044), when a weapon is clicked and is unlocked:
1. `_pending_weapon_id` is set
2. `audio_manager.play_ui_click()` is called
3. `_highlight_selected_items()` updates the border color
4. **No animation plays** — the visual update is instantaneous

The `_highlight_selected_items()` function (line 1169) only changes the StyleBoxFlat border color. No motion or shine effect exists.

The `_animate_slot_reveal()` function (line 1633) has a scale-pop tween for unlock reveals, but this is never triggered on selection.

### What Is Missing

1. **Shake animation** — a position-based jitter tween on the slot or its VBoxContainer
2. **Glint/shine animation** — a brief brightness flash or diagonal light sweep over the icon

## Research: Pixel Art 4-Step Animation (saint11.art)

Pedro Medeiros' pixel art animation tutorial series describes principles applicable here:
- **Anticipation + Action + Follow-through + Settle** — the classic 4-beat pattern
- For a selection "bump": scale up slightly → scale down past normal → bounce back → settle
- For a glint: a bright diagonal highlight sweeps across the icon in 4 discrete frames

### Godot 4 Tween-Based Approach

Godot 4 `Tween` nodes support chained steps with `set_parallel(false)` for sequential animations and `set_parallel(true)` for parallel ones. The `set_trans()` and `set_ease()` options control the curve shape.

**Shake pattern (4 steps):**
1. Move slightly to the right (+3px) — fast (0.04s)
2. Move left past center (-5px) — fast (0.04s)
3. Move right (+2px) — fast (0.04s)
4. Return to center (0px) — slightly slower (0.06s, ease out)

**Glint pattern:**
A `ColorRect` overlay with a bright/white color and low alpha sweeps diagonally across the slot:
1. Start: position at left edge, alpha 0
2. Step 1: move to center, alpha rises to 0.6
3. Step 2: move to right edge, alpha falls to 0
4. Total duration: ~0.2s

### Godot Built-in Alternative: `ShaderMaterial` with `SCREEN_UV`

A CanvasItem shader can produce a diagonal scan line that moves from left to right based on a `time_offset` uniform. This is more expensive but more visually impressive.

### Simpler Alternative: Modulate Flash

The simplest approach: briefly set `slot.modulate = Color(2.0, 2.0, 2.0, 1.0)` (HDR-bright white) and tween it back to `Color(1, 1, 1, 1)` over ~0.15s. Combined with the shake, this produces a satisfying "punch" effect.

## Proposed Solution

### Implementation Plan

Implement `_play_weapon_selection_animation(slot: PanelContainer)` in `armory_menu.gd`:

```
func _play_weapon_selection_animation(slot: PanelContainer) -> void:
    var vbox = slot.get_child(0)  # VBoxContainer

    # --- SHAKE (position offset on vbox) ---
    vbox.pivot_offset = vbox.size / 2
    var original_pos = vbox.position
    var tween = create_tween()
    tween.set_parallel(false)
    tween.tween_property(vbox, "position:x", original_pos.x + 3.0, 0.04)
    tween.tween_property(vbox, "position:x", original_pos.x - 5.0, 0.04)
    tween.tween_property(vbox, "position:x", original_pos.x + 2.0, 0.04)
    tween.tween_property(vbox, "position:x", original_pos.x, 0.06).set_ease(Tween.EASE_OUT)

    # --- SCALE BUMP (parallel with shake) ---
    tween.set_parallel(true)
    vbox.scale = Vector2(1.15, 1.15)
    tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.18)
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

    # --- GLINT (modulate brightness flash on slot) ---
    tween.tween_property(slot, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.05)
    tween.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
        .set_ease(Tween.EASE_OUT)
```

Call this in `_on_slot_gui_input()` right after `_highlight_selected_items()`.

### Glint Overlay Approach (More Polished)

For a proper diagonal light sweep, add a `ColorRect` overlay child to the slot:
- White color, semi-transparent (alpha ~0.7)
- Clipped to slot bounds (`clip_contents = true` on a container)
- Rotated 30° to create diagonal appearance
- Tweened from x = -slot_width to x = slot_width in ~0.2s

This is the technique used in modern UI frameworks for "shimmer" effects.

## Known Components/Libraries for Similar Effects

| Component | Description | Relevance |
|-----------|-------------|-----------|
| Godot `Tween` | Built-in animation interpolation | Direct use for shake + scale |
| `CanvasItem.material` with ShaderMaterial | Per-node shader for glint effect | Advanced glint |
| `AnimationPlayer` | Timeline-based animation | Could be used but overkill for procedural UI |
| Godot `AudioStreamPlayer` + beep | Already used for unlock beeps | Could add a selection "click" sound |

## Files to Modify

| File | Change |
|------|--------|
| `scripts/ui/armory_menu.gd` | Add `_play_weapon_selection_animation()` and call it on selection |

## Implementation Notes

1. The animation should not block input — use `create_tween()` which runs asynchronously
2. Store active selection tweens to kill them if the same slot is clicked again quickly
3. The glint should run on the `TextureRect` (icon) for best visual effect, not the whole slot
4. The shake should use `position` offset, not `offset` (which affects layout)
5. The existing `_active_reveal_tweens` dictionary pattern can be reused to track selection tweens
