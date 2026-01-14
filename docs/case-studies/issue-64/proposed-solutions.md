# Proposed Solutions for Issue #64

## Summary

The fire mode toggle sound does not play in the exported build, most likely due to the audio file having Cyrillic characters in its filename.

## Solution Options

### Solution 1: Rename Single Audio File (Recommended)

**Complexity**: Low
**Risk**: Low
**Scope**: Minimal change, only affects the fire mode toggle sound

#### Changes Required:

1. **Rename the audio file**:
   - From: `assets/audio/игрок изменил режим стрельбы (нажал b).wav`
   - To: `assets/audio/fire_mode_toggle.wav`

2. **Update AudioManager (`scripts/autoload/audio_manager.gd`)**:
   ```gdscript
   ## Fire mode toggle sound.
   const FIRE_MODE_TOGGLE: String = "res://assets/audio/fire_mode_toggle.wav"
   ```

#### Pros:
- Simple, minimal change
- Fixes the immediate issue
- Low risk of regression

#### Cons:
- Only fixes one file; other Cyrillic-named files may also fail in exports
- Changes the original filename (may affect version control history)

---

### Solution 2: Rename All Cyrillic Audio Files (Comprehensive)

**Complexity**: Medium
**Risk**: Low-Medium
**Scope**: All audio files with non-ASCII characters

#### Changes Required:

Rename all audio files with Cyrillic characters to ASCII equivalents:

| Original | New |
|----------|-----|
| `игрок изменил режим стрельбы (нажал b).wav` | `fire_mode_toggle.wav` |
| `взвод затвора m16 1.wav` | `m16_bolt_1.wav` |
| `взвод затвора m16 2.wav` | `m16_bolt_2.wav` |
| `взвод затвора m16 3.wav` | `m16_bolt_3.wav` |
| `взвод затвора m16 4.wav` | `m16_bolt_4.wav` |
| `m16 два выстрела подряд.wav` | `m16_double_shot_1.wav` |
| `m16  два выстрела подряд 2.wav` | `m16_double_shot_2.wav` |
| `игрок достал магазин (первая фаза перезарядки).wav` | `reload_mag_out.wav` |
| `игрок вставил магазин (вторая фаза перезарядки).wav` | `reload_mag_in.wav` |
| `полная зарядка m16.wav` | `m16_full_reload.wav` |
| `взвод затвора пистолета.wav` | `pistol_bolt.wav` |
| `кончились патроны в пистолете.wav` | `empty_click.wav` |
| `звук смертельного попадания.wav` | `hit_lethal.wav` |
| `звук попадания не смертельного попадания.wav` | `hit_non_lethal.wav` |
| `пуля попала в стену или укрытие (сделать по тише).wav` | `bullet_wall_hit.wav` |
| `пуля пролетела рядом с игроком.wav` | `bullet_near_player.wav` |
| `попадание пули в укрытие рядом с игроком.wav` | `bullet_cover_near_player.wav` |
| `падает гильза автомата.wav` | `shell_rifle.wav` |
| `падает гильза пистолета.wav` | `shell_pistol.wav` |

Then update all references in `audio_manager.gd`.

#### Pros:
- Comprehensive fix for all potential audio loading issues
- Ensures cross-platform compatibility
- Follows Godot best practices

#### Cons:
- More changes required
- Loses descriptive Cyrillic filenames
- Need to update all references in AudioManager

---

### Solution 3: Keep Cyrillic + Add Debug Logging (Investigation)

**Complexity**: Low
**Risk**: None
**Scope**: Diagnostic only

Before implementing a fix, add debug logging to confirm the root cause:

#### Changes Required:

1. **Update AudioManager to log loading failures**:
   ```gdscript
   func _preload_all_sounds() -> void:
       var all_sounds: Array[String] = []
       # ... existing code ...

       for path in all_sounds:
           if not _audio_cache.has(path):
               var stream := load(path) as AudioStream
               if stream:
                   _audio_cache[path] = stream
                   print("[AudioManager] Loaded: ", path)
               else:
                   push_error("[AudioManager] FAILED to load: ", path)
   ```

2. **Run exported build with console** and check logs

#### Pros:
- No permanent changes
- Confirms exact cause
- Can inform decision on which solution to implement

#### Cons:
- Doesn't fix the issue
- Requires manual testing

---

## Recommendation

**Implement Solution 1 first** (rename single file) as the most targeted fix with minimal risk.

If other audio issues are reported, proceed to **Solution 2** (rename all files).

**Solution 3** can be implemented alongside Solution 1 to gather diagnostic information for future issues.

---

## Implementation Steps for Solution 1

```bash
# 1. Navigate to audio directory
cd assets/audio

# 2. Rename the file
git mv "игрок изменил режим стрельбы (нажал b).wav" "fire_mode_toggle.wav"

# 3. Update audio_manager.gd (change line 56)
# const FIRE_MODE_TOGGLE: String = "res://assets/audio/fire_mode_toggle.wav"

# 4. Commit and test
git add .
git commit -m "Fix: Rename fire mode toggle audio to ASCII filename for export compatibility"
```

## Verification

After implementing the fix:

1. Build the project in Godot editor
2. Export to Windows
3. Run the exported .exe
4. Press B key to toggle fire mode
5. Verify sound plays

If sound still doesn't play, check console output for any loading errors.
