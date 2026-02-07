# Armory Icon Standard

This document defines the standard for weapon and item icons used in the armory menu.

## Icon Specifications

### Armory Icons (Menu Display)
- **Size**: 80×24 pixels (standard), 60×18 pixels (compact for smaller weapons like SMGs)
- **View**: Side view (profile)
- **Format**: PNG with transparency (RGBA)
- **Style**: Pixel art matching the game's aesthetic

### In-Game Weapon Sprites (Top-Down)
- **Size**: 64×16 pixels (held weapons), 44×12 pixels (compact weapons)
- **View**: Top-down perspective
- **Format**: PNG with transparency (RGBA)
- **Style**: Pixel art matching the game's aesthetic

## Color Palette

All weapon icons should use the following consistent color palette:

```python
COLORS = {
    'black': (30, 30, 30, 255),          # Outlines, deep shadows
    'dark_gray': (45, 45, 45, 255),      # Dark metal parts
    'medium_gray': (60, 60, 60, 255),    # Metal surfaces
    'light_gray': (70, 70, 70, 255),     # Highlighted metal
    'lighter_gray': (90, 90, 90, 255),   # Bright highlights
    'metal_dark': (35, 35, 40, 255),     # Dark metal (blued steel)
    'metal_medium': (50, 50, 55, 255),   # Medium metal
    'metal_light': (70, 70, 75, 255),    # Light metal highlights
    'wood_dark': (65, 45, 25, 255),      # Dark wood/polymer
    'wood_medium': (85, 60, 35, 255),    # Medium wood tone
    'wood_light': (100, 75, 45, 255),    # Light wood highlights
    'transparent': (0, 0, 0, 0),         # Background
}
```

## Design Guidelines

### 1. Consistency
- All armory icons should be in **side view** for consistency
- Use the same color palette across all weapons
- Maintain similar levels of detail

### 2. Clarity
- Icons should be easily recognizable at small sizes
- Key features of the weapon should be clearly visible
- Avoid excessive detail that becomes muddy at small scale

### 3. Proportions
- Maintain realistic proportions relative to the weapon's actual size
- Smaller weapons (pistols, SMGs) can use the compact 60×18 size
- Larger weapons (rifles, shotguns) should use the standard 80×24 size

### 4. Details to Include
- **Barrel**: Clearly visible, pointing right
- **Stock/Grip**: Appropriate to weapon type
- **Receiver/Body**: Main body of the weapon
- **Distinctive Features**: Suppressors, scopes, magazines, etc.
- **Sights**: Front and rear sights where appropriate

## Weapon Icon Sizes by Type

| Weapon Type | Armory Icon Size | Example |
|-------------|-----------------|---------|
| Assault Rifle (M16) | 80×24 | `m16_rifle.png` |
| Shotgun | 80×24 | `shotgun_icon.png` |
| Pistol (Silenced) | 80×24 | `silenced_pistol_icon.png` |
| SMG (Mini UZI) | 60×18 | `mini_uzi_icon.png` |
| Grenades | Variable | `flashbang.png`, `frag_grenade.png`, `defensive_grenade.png` |

## File Naming Convention

- **Armory Icons**: `{weapon_name}_icon.png` (e.g., `shotgun_icon.png`)
- **Top-Down Sprites**: `{weapon_name}_topdown.png` (e.g., `shotgun_topdown.png`)
- **Alternative Versions**: `{weapon_name}_{variant}.png` (e.g., `m16_simple.png`)

## Creating New Icons

### Using Python/PIL

Weapon icons should be created using Python scripts with the PIL/Pillow library for consistency and version control.

Example scripts can be found in the `experiments/` directory:
- `create_shotgun_sprites.py` - Example for creating shotgun icons
- `create_mini_uzi_icon.py` - Example for creating compact SMG icons
- `create_silenced_pistol_icon.py` - Example for creating pistol icons
- `create_m16_sprite.py` - Example for creating rifle icons

### Steps to Create a New Icon

1. Create a new Python script in `experiments/create_{weapon}_icon.py`
2. Use the standard color palette defined above
3. Define the icon size (80×24 or 60×18)
4. Draw the weapon in side view, pointing right
5. Save to both `experiments/` and `assets/sprites/weapons/`
6. Update `scripts/ui/armory_menu.gd` with the new icon path

### Example Template

```python
#!/usr/bin/env python3
from PIL import Image

COLORS = {
    'black': (30, 30, 30, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'transparent': (0, 0, 0, 0),
}

def create_weapon_icon():
    width, height = 80, 24
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Draw weapon components here
    # ...

    return img

if __name__ == '__main__':
    icon = create_weapon_icon()
    icon.save('experiments/weapon_icon.png')
    icon.save('assets/sprites/weapons/weapon_icon.png')
```

## Integration with Armory Menu

Icons are referenced in `scripts/ui/armory_menu.gd` in the `WEAPONS` dictionary:

```gdscript
"weapon_id": {
    "name": "Weapon Name",
    "icon_path": "res://assets/sprites/weapons/weapon_icon.png",
    "unlocked": true,
    "description": "Weapon description",
    "is_grenade": false
},
```

The armory menu displays icons at 64×64 pixels with `STRETCH_KEEP_ASPECT_CENTERED`, so icons will scale proportionally while maintaining their aspect ratio.

## Recent Changes

### Issue #510 (February 2026)
- **Mini UZI**: Reduced from 80×24 to 60×18 for better visual balance
- **Silenced Pistol**: Changed from top-down view (44×12) to side view (80×24) for consistency with other weapons

These changes establish a clearer standard where:
- All armory icons use **side view** perspective
- Compact weapons (SMGs) use **60×18** size
- Standard weapons (rifles, shotguns, pistols) use **80×24** size
