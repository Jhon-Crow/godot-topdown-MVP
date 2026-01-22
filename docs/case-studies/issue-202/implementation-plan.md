# Implementation Plan: Grenade Throwing Animation

## Overview

This document provides a detailed technical implementation plan for adding composite grenade throwing animations to the Godot Top-Down Template.

---

## Phase 1: Animation Infrastructure

### 1.1 Add Animation Constants and Enums

Add to `scripts/characters/player.gd`:

```gdscript
# ============================================================================
# Grenade Animation System
# ============================================================================

## Grenade animation phase state machine.
enum GrenadeAnimPhase {
    NONE,           # Normal arm positions (walking/idle)
    GRAB_GRENADE,   # Left hand moves to chest
    PULL_PIN,       # Right hand pulls pin (quick snap)
    HANDS_APPROACH, # Right hand moves toward left hand
    TRANSFER,       # Grenade moves to right hand, left returns
    WIND_UP,        # Dynamic wind-up based on drag
    THROW,          # Throwing motion
    RETURN_IDLE     # Arms return to normal
}

## Current grenade animation phase.
var _grenade_anim_phase: int = GrenadeAnimPhase.NONE

## Animation phase duration tracker.
var _grenade_anim_timer: float = 0.0

## Target position for left arm during grenade animation.
var _left_arm_grenade_target: Vector2 = Vector2.ZERO

## Target position for right arm during grenade animation.
var _right_arm_grenade_target: Vector2 = Vector2.ZERO

## Current wind-up intensity (0.0 to 1.0).
var _wind_up_intensity: float = 0.0

## Previous mouse position for velocity calculation.
var _prev_mouse_pos: Vector2 = Vector2.ZERO
```

### 1.2 Add Animation Position Constants

```gdscript
# Arm position offsets for grenade animation phases (relative to base position)
const GRENADE_ANIM_DURATION_GRAB := 0.2       # Time to reach chest
const GRENADE_ANIM_DURATION_PULL_PIN := 0.15  # Quick pin pull
const GRENADE_ANIM_DURATION_APPROACH := 0.2   # Hands coming together
const GRENADE_ANIM_DURATION_TRANSFER := 0.15  # Handoff
const GRENADE_ANIM_DURATION_THROW := 0.2      # Throw animation
const GRENADE_ANIM_DURATION_RETURN := 0.3     # Return to idle

# Arm target positions (X is forward, Y is lateral in player-local space)
const ARM_OFFSET_CHEST := Vector2(-15, -8)          # Left arm to chest
const ARM_OFFSET_PIN := Vector2(-8, -12)            # Right arm to pin position
const ARM_OFFSET_TOGETHER := Vector2(5, 0)          # Meeting point for handoff
const ARM_OFFSET_WIND_UP_MIN := Vector2(10, 8)      # Minimum wind-up
const ARM_OFFSET_WIND_UP_MAX := Vector2(35, 18)     # Maximum wind-up
const ARM_OFFSET_THROW := Vector2(-25, -5)          # Throw follow-through

# Arm rotation angles (degrees)
const ARM_ROTATION_GRAB := -15.0
const ARM_ROTATION_PIN := -10.0
const ARM_ROTATION_WIND_UP_MAX := 45.0
const ARM_ROTATION_THROW := -30.0
```

---

## Phase 2: Core Animation Function

### 2.1 Main Animation Update Function

```gdscript
## Updates grenade animation based on current phase and intensity.
## Called every physics frame during grenade operations.
func _update_grenade_animation(delta: float) -> void:
    if _grenade_anim_phase == GrenadeAnimPhase.NONE:
        return

    _grenade_anim_timer -= delta

    match _grenade_anim_phase:
        GrenadeAnimPhase.GRAB_GRENADE:
            _animate_grab_grenade(delta)
        GrenadeAnimPhase.PULL_PIN:
            _animate_pull_pin(delta)
        GrenadeAnimPhase.HANDS_APPROACH:
            _animate_hands_approach(delta)
        GrenadeAnimPhase.TRANSFER:
            _animate_transfer(delta)
        GrenadeAnimPhase.WIND_UP:
            _animate_wind_up(delta)
        GrenadeAnimPhase.THROW:
            _animate_throw(delta)
        GrenadeAnimPhase.RETURN_IDLE:
            _animate_return_idle(delta)
```

### 2.2 Individual Phase Animations

```gdscript
## Animate left arm reaching to chest for grenade.
func _animate_grab_grenade(delta: float) -> void:
    var lerp_speed := 8.0 * delta
    var target := _base_left_arm_pos + ARM_OFFSET_CHEST

    if _left_arm_sprite:
        _left_arm_sprite.position = _left_arm_sprite.position.lerp(target, lerp_speed)
        _left_arm_sprite.rotation = lerp_angle(
            _left_arm_sprite.rotation,
            deg_to_rad(ARM_ROTATION_GRAB),
            lerp_speed
        )

    # Check if phase complete (timer or position threshold)
    if _grenade_anim_timer <= 0 or _left_arm_sprite.position.distance_to(target) < 1.0:
        _advance_to_next_anim_phase()


## Animate right arm pulling the pin.
func _animate_pull_pin(delta: float) -> void:
    var lerp_speed := 12.0 * delta
    var target := _base_right_arm_pos + ARM_OFFSET_PIN

    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(target, lerp_speed)
        _right_arm_sprite.rotation = lerp_angle(
            _right_arm_sprite.rotation,
            deg_to_rad(ARM_ROTATION_PIN),
            lerp_speed
        )

    if _grenade_anim_timer <= 0:
        _advance_to_next_anim_phase()


## Animate both hands coming together for handoff.
func _animate_hands_approach(delta: float) -> void:
    var lerp_speed := 10.0 * delta

    # Both arms move toward center meeting point
    var left_target := _base_left_arm_pos + ARM_OFFSET_TOGETHER
    var right_target := _base_right_arm_pos + ARM_OFFSET_TOGETHER

    if _left_arm_sprite:
        _left_arm_sprite.position = _left_arm_sprite.position.lerp(left_target, lerp_speed)
        _left_arm_sprite.rotation = lerp_angle(_left_arm_sprite.rotation, 0.0, lerp_speed)

    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(right_target, lerp_speed)
        _right_arm_sprite.rotation = lerp_angle(_right_arm_sprite.rotation, 0.0, lerp_speed)

    if _grenade_anim_timer <= 0:
        _advance_to_next_anim_phase()


## Animate grenade transfer - left arm returns, right holds grenade.
func _animate_transfer(delta: float) -> void:
    var lerp_speed := 10.0 * delta

    # Left arm returns to base
    if _left_arm_sprite:
        _left_arm_sprite.position = _left_arm_sprite.position.lerp(_base_left_arm_pos, lerp_speed)
        _left_arm_sprite.rotation = lerp_angle(_left_arm_sprite.rotation, 0.0, lerp_speed)

    # Right arm holds position (grenade now in right hand)
    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(
            _base_right_arm_pos + ARM_OFFSET_TOGETHER,
            lerp_speed * 0.5  # Slower, holding position
        )

    if _grenade_anim_timer <= 0:
        _advance_to_next_anim_phase()


## Animate dynamic wind-up based on drag intensity.
func _animate_wind_up(delta: float) -> void:
    # Calculate wind-up intensity from mouse drag
    _update_wind_up_intensity()

    # Interpolate between min and max wind-up positions
    var wind_up_offset := ARM_OFFSET_WIND_UP_MIN.lerp(
        ARM_OFFSET_WIND_UP_MAX,
        _wind_up_intensity
    )
    var wind_up_rotation := lerpf(0.0, ARM_ROTATION_WIND_UP_MAX, _wind_up_intensity)

    var lerp_speed := 15.0 * delta  # Responsive to input

    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(
            _base_right_arm_pos + wind_up_offset,
            lerp_speed
        )
        _right_arm_sprite.rotation = lerp_angle(
            _right_arm_sprite.rotation,
            deg_to_rad(wind_up_rotation),
            lerp_speed
        )

    # Left arm stays relaxed during wind-up
    if _left_arm_sprite:
        _left_arm_sprite.position = _left_arm_sprite.position.lerp(_base_left_arm_pos, lerp_speed)
        _left_arm_sprite.rotation = lerp_angle(_left_arm_sprite.rotation, 0.0, lerp_speed)


## Animate the throwing motion.
func _animate_throw(delta: float) -> void:
    var lerp_speed := 20.0 * delta  # Fast, snappy throw

    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(
            _base_right_arm_pos + ARM_OFFSET_THROW,
            lerp_speed
        )
        _right_arm_sprite.rotation = lerp_angle(
            _right_arm_sprite.rotation,
            deg_to_rad(ARM_ROTATION_THROW),
            lerp_speed
        )

    if _grenade_anim_timer <= 0:
        _set_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE)


## Animate arms returning to idle/walking positions.
func _animate_return_idle(delta: float) -> void:
    var lerp_speed := 6.0 * delta

    var left_done := false
    var right_done := false

    if _left_arm_sprite:
        _left_arm_sprite.position = _left_arm_sprite.position.lerp(_base_left_arm_pos, lerp_speed)
        _left_arm_sprite.rotation = lerp_angle(_left_arm_sprite.rotation, 0.0, lerp_speed)
        left_done = _left_arm_sprite.position.distance_to(_base_left_arm_pos) < 0.5

    if _right_arm_sprite:
        _right_arm_sprite.position = _right_arm_sprite.position.lerp(_base_right_arm_pos, lerp_speed)
        _right_arm_sprite.rotation = lerp_angle(_right_arm_sprite.rotation, 0.0, lerp_speed)
        right_done = _right_arm_sprite.position.distance_to(_base_right_arm_pos) < 0.5

    if (left_done and right_done) or _grenade_anim_timer <= 0:
        _grenade_anim_phase = GrenadeAnimPhase.NONE
```

---

## Phase 3: Wind-up Intensity Calculation

```gdscript
## Calculate wind-up intensity from mouse drag during aiming.
func _update_wind_up_intensity() -> void:
    if _grenade_state != GrenadeState.AIMING:
        _wind_up_intensity = 0.0
        return

    var current_mouse := get_global_mouse_position()
    var drag_vector := current_mouse - _aim_drag_start
    var drag_distance := drag_vector.length()

    # Maximum expected drag distance (viewport width)
    var viewport := get_viewport()
    var max_drag := 800.0  # Default
    if viewport:
        max_drag = viewport.get_visible_rect().size.x * 0.6

    # Calculate intensity (0.0 to 1.0)
    _wind_up_intensity = clampf(drag_distance / max_drag, 0.0, 1.0)

    # Optional: Add velocity-based modifier for more dynamic feel
    var mouse_velocity := (current_mouse - _prev_mouse_pos).length()
    _prev_mouse_pos = current_mouse

    # Boost intensity slightly when moving mouse fast
    var velocity_boost := clampf(mouse_velocity / 50.0, 0.0, 0.2)
    _wind_up_intensity = clampf(_wind_up_intensity + velocity_boost, 0.0, 1.0)
```

---

## Phase 4: Phase Transition Helpers

```gdscript
## Set the grenade animation phase with appropriate timer.
func _set_grenade_anim_phase(phase: int) -> void:
    _grenade_anim_phase = phase

    match phase:
        GrenadeAnimPhase.GRAB_GRENADE:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_GRAB
        GrenadeAnimPhase.PULL_PIN:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_PULL_PIN
        GrenadeAnimPhase.HANDS_APPROACH:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_APPROACH
        GrenadeAnimPhase.TRANSFER:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_TRANSFER
        GrenadeAnimPhase.THROW:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_THROW
        GrenadeAnimPhase.RETURN_IDLE:
            _grenade_anim_timer = GRENADE_ANIM_DURATION_RETURN
        GrenadeAnimPhase.WIND_UP:
            _grenade_anim_timer = 999.0  # Indefinite until throw
        _:
            _grenade_anim_timer = 0.0


## Advance to the next animation phase in sequence.
func _advance_to_next_anim_phase() -> void:
    match _grenade_anim_phase:
        GrenadeAnimPhase.GRAB_GRENADE:
            _set_grenade_anim_phase(GrenadeAnimPhase.PULL_PIN)
        GrenadeAnimPhase.PULL_PIN:
            # Wait for state machine - HANDS_APPROACH triggered by RMB
            pass
        GrenadeAnimPhase.HANDS_APPROACH:
            # Wait for state machine - TRANSFER triggered by G release
            pass
        GrenadeAnimPhase.TRANSFER:
            _set_grenade_anim_phase(GrenadeAnimPhase.WIND_UP)
        GrenadeAnimPhase.THROW:
            _set_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE)
        GrenadeAnimPhase.RETURN_IDLE:
            _grenade_anim_phase = GrenadeAnimPhase.NONE
```

---

## Phase 5: Integration with Grenade State Machine

### 5.1 Modify `_handle_grenade_idle_state()`

Add animation trigger when grenade preparation starts:

```gdscript
func _handle_grenade_idle_state() -> void:
    if Input.is_action_pressed("grenade_prepare") and _current_grenades > 0:
        # Start grab animation when G is first pressed
        if Input.is_action_just_pressed("grenade_prepare"):
            _set_grenade_anim_phase(GrenadeAnimPhase.GRAB_GRENADE)

        if Input.is_action_just_pressed("grenade_throw"):
            _grenade_drag_start = get_global_mouse_position()
            _grenade_drag_active = true

        if _grenade_drag_active and Input.is_action_just_released("grenade_throw"):
            var drag_end := get_global_mouse_position()
            var drag_vector := drag_end - _grenade_drag_start

            if drag_vector.x > 20.0:
                _start_grenade_timer()
                # Pin pull animation is now in PULL_PIN phase
            else:
                # Reset animation if cancelled
                _set_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE)

            _grenade_drag_active = false
    else:
        _grenade_drag_active = false
        # If G released without activation, return to idle
        if _grenade_anim_phase == GrenadeAnimPhase.GRAB_GRENADE:
            _set_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE)
```

### 5.2 Modify `_handle_grenade_timer_started_state()`

```gdscript
func _handle_grenade_timer_started_state() -> void:
    if not Input.is_action_pressed("grenade_prepare"):
        # G released - drop grenade
        _drop_grenade_at_feet()
        _set_grenade_anim_phase(GrenadeAnimPhase.RETURN_IDLE)
        return

    if Input.is_action_just_pressed("grenade_throw"):
        _grenade_state = GrenadeState.WAITING_FOR_G_RELEASE
        _is_preparing_grenade = true
        # Start hands approaching animation
        _set_grenade_anim_phase(GrenadeAnimPhase.HANDS_APPROACH)
```

### 5.3 Modify `_handle_grenade_waiting_for_g_release_state()`

```gdscript
func _handle_grenade_waiting_for_g_release_state() -> void:
    if not Input.is_action_pressed("grenade_throw"):
        _grenade_state = GrenadeState.TIMER_STARTED
        _is_preparing_grenade = false
        # Return to post-pin-pull state
        _set_grenade_anim_phase(GrenadeAnimPhase.PULL_PIN)
        return

    if not Input.is_action_pressed("grenade_prepare"):
        _grenade_state = GrenadeState.AIMING
        _aim_drag_start = get_global_mouse_position()
        _prev_mouse_pos = _aim_drag_start  # Initialize for velocity tracking
        # Trigger transfer animation, then wind-up
        _set_grenade_anim_phase(GrenadeAnimPhase.TRANSFER)
```

### 5.4 Modify `_throw_grenade()`

```gdscript
func _throw_grenade(drag_end: Vector2) -> void:
    # ... existing throw logic ...

    # Trigger throw animation
    _set_grenade_anim_phase(GrenadeAnimPhase.THROW)

    # ... rest of existing code ...
```

### 5.5 Add Animation Update to `_physics_process()`

```gdscript
func _physics_process(delta: float) -> void:
    if not _is_alive:
        return

    # ... existing movement code ...

    # Update grenade animation (before walking animation)
    _update_grenade_animation(delta)

    # Update walking animation (will be blended/overridden by grenade animation)
    if _grenade_anim_phase == GrenadeAnimPhase.NONE:
        _update_walk_animation(delta, input_direction)

    # ... rest of existing code ...
```

---

## Testing Checklist

- [ ] Grab animation plays when G is pressed
- [ ] Pin pull animation plays after successful drag-right
- [ ] Hands approach when RMB pressed (timer started)
- [ ] Transfer happens when G released (RMB still held)
- [ ] Wind-up scales with drag distance
- [ ] Throw animation plays on release
- [ ] Arms return to idle after throw
- [ ] Walking animation resumes after throw
- [ ] Cancel path (releasing G early) returns to idle
- [ ] Animation blends with player rotation

---

## Tuning Parameters

These values should be adjusted through playtesting:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `GRENADE_ANIM_DURATION_GRAB` | 0.2s | Time for left arm to reach chest |
| `GRENADE_ANIM_DURATION_PULL_PIN` | 0.15s | Quick pin pull duration |
| `GRENADE_ANIM_DURATION_APPROACH` | 0.2s | Hands meeting time |
| `GRENADE_ANIM_DURATION_TRANSFER` | 0.15s | Handoff duration |
| `GRENADE_ANIM_DURATION_THROW` | 0.2s | Throw follow-through |
| `GRENADE_ANIM_DURATION_RETURN` | 0.3s | Return to idle |
| `ARM_OFFSET_*` | Various | Position offsets for each phase |
| `ARM_ROTATION_*` | Various | Rotation angles for each phase |

---

*Implementation plan created on 2026-01-22*
