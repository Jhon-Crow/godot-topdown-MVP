# Issue 1885: Unlock Toast Layout

## Problem

Unlock notifications previously placed the generic unlock message and item name
in one label, for example `Открыт предмет Бронированная кожа !`. Longer item,
weapon, and grenade names can exceed the available toast width and become hard to
read.

## Repository Findings

- The toast is built programmatically in
  `scripts/autoload/unlock_notification_manager.gd`.
- The experimental menu already provides a manual `show_unlock_notification`
  path for checking long sample names.
- Existing regression tests in `tests/unit/test_unlock_notification_manager.gd`
  cover text content, animation opacity, shine layering, and explicit exported
  layout sizing.

## External Research

- Godot 4 `RichTextLabel` supports BBCode sizing such as `[font_size]`, which
  could render a smaller item name inside one text node.
- A two-label layout is still preferable here because the current toast already
  uses `Label` controls, has explicit fallback shadow labels for exported builds,
  and needs predictable sizing inside fixed toast dimensions.

Reference:
https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html

## Considered Solutions

1. Keep one `Label` and enable wrapping.
   This reduces clipping risk but still gives the item name the same visual
   priority as the generic message.

2. Replace the label with one `RichTextLabel` using BBCode font size tags.
   This supports mixed sizes but would introduce a different text control and
   require extra care around BBCode escaping and minimum sizing.

3. Use a vertical text stack: generic unlock line above a smaller item-name
   label.
   This matches the issue request, keeps existing `Label` behavior, and gives
   tests direct access to each line.

## Implemented Approach

The toast now renders:

- first line: generic text, for example `Открыт предмет !`;
- second line: item, weapon, or grenade name in a smaller font.

The shadow fallback labels mirror the same two-line structure, preserving the
existing exported-build visibility guard.
