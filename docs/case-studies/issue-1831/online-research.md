# Online Research

## Godot UI Layering

Source: https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html

Godot's `CanvasLayer` is the appropriate base for global HUD overlays because `CanvasItem` descendants under a `CanvasLayer` are drawn in that layer. This matches the requirement that the unlock notification appear at the top of the screen independent of the active level scene.

Implementation decision: make the notification manager an autoloaded `CanvasLayer` with a high layer value.

## Godot UI Controls

Source: https://docs.godotengine.org/en/stable/classes/class_control.html

Godot's `Control` class is the base for UI-related nodes. The existing Armory UI is built from `Control` descendants such as `PanelContainer`, `MarginContainer`, `HBoxContainer`, `TextureRect`, and `Label`, so the toast should stay in the same UI family.

Implementation decision: build the toast from `PanelContainer` plus a row containing the Armory `TextureRect` and a wrapping `Label`.

## Godot Tweens

Source: https://docs.godotengine.org/en/stable/classes/class_tween.html

Godot `Tween` is designed for interpolating numerical properties, which is exactly what the slide-in/slide-out animation needs: the toast's `position.y` and `modulate.a`.

Implementation decision: create a fresh tween per notification and kill any in-progress tween before starting a new sequence.

## Godot ShaderMaterial

Source: https://docs.godotengine.org/en/stable/classes/class_shadermaterial.html

Godot `ShaderMaterial` lets UI elements render with custom shader code and shader parameters. The project already has `gold_shine.gdshader`, so the notification can reuse that instead of adding a new effect system.

Implementation decision: add a full-rect `ColorRect` overlay using `gold_shine.gdshader` with `horizontal_sweep = true` and a shorter cycle for the toast.

## Steam Achievement Reference

Source: https://partner.steamgames.com/doc/features/achievements

Steamworks documents achievement names and icons as localized display metadata and notes that the Steam overlay shows a notification panel for unlocked achievements.

Implementation decision: mirror the pattern locally by showing a compact panel with a recognizable icon and localized item name, while preserving this repo's own Armory unlock flow.
