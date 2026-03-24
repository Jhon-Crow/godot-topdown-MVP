# Case Study: Issue #1317 — Pedestal Displays Suitcase Instead of Weapon Model in Roguelike

## Issue Overview

**Title:** fix пьедестал в рогалике (fix pedestal in roguelike)
**URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1317
**State:** Open
**Author:** Jhon-Crow

**Problem Statement:**
"Currently, undiscovered/locked items are displayed on the pedestal as a suitcase (should display the model)."

Screenshot shows: A pedestal in the roguelike treasure room displays a suitcase/briefcase icon for a "Снайперская винтовка" (Sniper Rifle) item instead of the actual weapon model/icon.

## Timeline / Sequence of Events

1. **Issue #1166** introduced the treasure pedestal system for the roguelike. Part of this fix (Bug 1) was to pre-select a specific weapon and show its actual icon rather than a generic case icon. A `WEAPON_ICON_PATHS` dictionary was added to `roguelike_level.gd`.

2. **Issue #1180** added fake-3D volumetric pedestal visuals.

3. **Issue #1299** added the floating animation for the item icon on the pedestal.

4. **The bug**: When the `WEAPON_ICON_PATHS` dictionary was populated, the `"sniper"` entry was incorrectly set to `"res://assets/sprites/weapons/weapon_case_icon.png"` (the suitcase icon) instead of the actual sniper rifle sprite.

## Root Cause Analysis

**File:** `scripts/levels/roguelike_level.gd`
**Line:** 1364

```gdscript
const WEAPON_ICON_PATHS: Dictionary = {
    "makarov_pm":    "res://assets/sprites/weapons/makarov_pm_icon.png",
    "m16":           "res://assets/sprites/weapons/m16_simple.png",
    "shotgun":       "res://assets/sprites/weapons/shotgun_icon.png",
    "mini_uzi":      "res://assets/sprites/weapons/mini_uzi_icon.png",
    "silenced_pistol": "res://assets/sprites/weapons/silenced_pistol_icon.png",
    "sniper":        "res://assets/sprites/weapons/weapon_case_icon.png",  // BUG: should be asvk_topdown.png
    "revolver":      "res://assets/sprites/weapons/revolver_icon.png",
    "ak_gl":         "res://assets/sprites/weapons/ak_gl_icon.png",
}
```

The `"sniper"` key maps to `weapon_case_icon.png` (the suitcase/briefcase image). All other weapons have correct icon paths.

**Evidence from armory_menu.gd (line 59):**
```gdscript
"sniper": {
    "name": "ASVK",
    "icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
    ...
}
```

The armory menu correctly uses `asvk_topdown.png` for the sniper weapon. The same icon should be used in the pedestal.

**Why was `weapon_case_icon.png` used?**
The sniper rifle is one of the weapons that requires unlocking (unlock condition: Polygon D+). It appears likely the author initially used the suitcase icon as a placeholder for "locked" weapons, but:
1. The pedestal code (`_pick_random_pedestal_item`) only offers weapons that are **already unlocked** (`GameManager.is_weapon_unlocked(weapon_id)`)
2. So an unlocked sniper rifle on the pedestal was still showing the placeholder suitcase icon

## Available Assets

The `assets/sprites/weapons/` directory contains:
- `asvk_topdown.png` — the ASVK sniper rifle top-down sprite (used in SniperRifle.tscn and armory_menu.gd)
- `weapon_case_icon.png` — generic suitcase/briefcase icon (used as fallback for locked/unknown weapons)

No dedicated `sniper_icon.png` exists, but `asvk_topdown.png` is the correct icon to use, consistent with the armory menu.

## Fix

Change line 1364 in `scripts/levels/roguelike_level.gd`:

```gdscript
# Before (wrong):
"sniper":        "res://assets/sprites/weapons/weapon_case_icon.png",

# After (correct):
"sniper":        "res://assets/sprites/weapons/asvk_topdown.png",
```

This aligns with how `armory_menu.gd` references the sniper weapon icon and ensures the actual weapon model is shown on the pedestal.

## Impact

- Low risk: single-line change in a constants dictionary
- Affects: treasure room pedestal display when sniper rifle is selected as the reward
- No test changes needed (the icon path correctness is a visual concern; existing tests mock the pedestal without checking specific icon files)
