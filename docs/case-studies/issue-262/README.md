# Case Study: Issue #262 - Bullet Casing Ejection System

## Overview
This case study documents the implementation and troubleshooting of bullet casing ejection when weapons fire in the Godot Top-Down MVP game.

## Issue Description
**Original Issue**: "при стрельбе из оружия должны вылетать гильзы соответствующих патронов (в момент проигрывания соответствующего звука). гильзы должны оставаться лежать на полу (не удаляться)."

**Translation**: "When firing weapons, bullet casings of the corresponding cartridges should be ejected (at the moment the corresponding sound plays). The casings should remain lying on the floor (not be deleted)."

**Additional Requirements**:
- Casings should eject to the right of the weapon
- Casings should have caliber-specific sprites (brass for rifle, silver for pistol, red for shotgun)
- Shotgun shells should be red in color

## Timeline of Events

### Initial Implementation (Previous PR)
- Basic casing ejection system was implemented
- Casings were ejected but appeared as pink rectangles (missing sprites)
- Ejection direction was incorrect
- No caliber-specific sprites

### Feedback Round 1 (2026-01-23T17:07:22Z)
- User reported: "гильзы должны выбрасываться вправо от оружия. сейчас у гильз нет спрайта (просто розовый прямоугольник). для патронов разных калибров и дроби должны быть разные спрайты гильз. гильзы дроби должны быть красного цвета."
- Provided game log: `game_log_20260123_201124.txt`

### Fixes Applied
1. **Fixed Pink Rectangle Issue**: Replaced `PlaceholderTexture2D` with actual PNG sprites
2. **Fixed Ejection Direction**: Corrected rotation formula for Godot's Y-down coordinate system
3. **Added Caliber-Specific Sprites**:
   - `casing_rifle.png` - Brass/gold color (8x16 px)
   - `casing_pistol.png` - Silver color (8x12 px)
   - `casing_shotgun.png` - Red shell with brass base (10x20 px)

### Feedback Round 2 (2026-01-23T17:25:08Z)
- User reported: "в архиве с exe нет папки с .NET assemblies, так что при запуске ошибка."
- Translation: "in the exe archive there is no folder with .NET assemblies, so there is an error when running."

### Root Cause Analysis - .NET Assembly Issue

#### Investigation Findings
- Project uses mixed GDScript and C# code
- Export settings had `dotnet/embed_build_outputs=true`
- Despite this setting, .NET assemblies were not embedded in the exe
- Main branch export_presets.cfg does not have `dotnet/embed_build_outputs` setting at all

#### Technical Analysis
- Godot 4.3-stable with C# support
- When `binary_format/embed_pck=true` and `dotnet/embed_build_outputs=true`, .NET assemblies should be embedded
- However, the embedding was not working correctly
- Setting `dotnet/embed_build_outputs=false` should create a separate dll folder

#### Solution Applied
- Changed `dotnet/embed_build_outputs=false` in export_presets.cfg
- This should create a separate folder with .NET assemblies alongside the exe

## Files Modified

### Core Implementation
- `Scripts/AbstractClasses/BaseWeapon.cs` - Fixed ejection direction calculation
- `scripts/data/caliber_data.gd` - Added casing_sprite property
- `scripts/effects/casing.gd` - Updated appearance logic to use sprites
- `scenes/effects/Casing.tscn` - Replaced placeholder with actual sprite
- `resources/calibers/caliber_*.tres` - Added casing sprite references
- `assets/sprites/effects/casing_*.png` - New sprite assets

### Export Fixes
- `export_presets.cfg` - Set `dotnet/embed_build_outputs=false`

### Compatibility Fixes
- Multiple script files - Fixed Godot 4.3 type inference issues
- Test files - Fixed GUT assertion methods

## Test Results

### Casing Functionality Tests
- [x] Fire assault rifle and verify brass casings eject to the right
- [x] Fire Mini Uzi and verify silver casings eject to the right
- [x] Fire shotgun and verify red shell casings eject to the right
- [x] Verify casings remain on the ground permanently
- [x] Test at various weapon orientations (up, down, left, right)

### Export Tests
- [ ] Verify exported exe includes .NET assemblies folder
- [ ] Verify exported exe runs without errors

## Technical Details

### Ejection Direction Fix
**Problem**: Original code used `Vector2(direction.Y, -direction.X)` which was incorrect for Godot's Y-down coordinate system.

**Solution**: Changed to `Vector2(-direction.Y, direction.X)` for correct "right side" perpendicular calculation.

### Sprite Implementation
- Added `casing_sprite` property to `CaliberData` resource
- Updated `casing.gd` to load sprites from CaliberData with fallback to colored rectangles
- Created three sprite variants for different calibers

### Export Configuration
- `binary_format/embed_pck=true` - Embeds game data in exe
- `dotnet/embed_build_outputs=false` - Creates separate .NET assemblies folder

## Lessons Learned

1. **Godot Export Settings**: `dotnet/embed_build_outputs=true` may not work reliably with `binary_format/embed_pck=true`
2. **Coordinate Systems**: Always verify vector calculations against Godot's Y-down coordinate system
3. **Mixed Language Projects**: C# code requires special handling during export
4. **Sprite Assets**: Placeholder textures appear as pink rectangles - always use actual sprites

## Future Considerations

- Monitor Godot updates for improved .NET embedding support
- Consider automated testing for export configurations
- Document export settings for different platforms

## References

- Game log: `game_log_20260123_201124.txt`
- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/262
- Pull Request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/275