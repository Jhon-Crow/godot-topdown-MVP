# Case Study: Issue #890 — Homing Bullets Scanner Sound Not Playing

## Summary

**Issue**: Add a quiet scanner looping sound that plays while the Homing Bullets item is equipped.
**Status**: Resolved (third attempt)
**Affected file**: `Scripts/Characters/Player.cs`
**Root cause**: WAV `LoopEnd` was left at default value 0, causing the loop to restart at sample 0 to 0 (silent loop after first play-through)

---

## Timeline of Events

### 2026-02-24 — First attempt (commit b0711e74)
- Added scanner loop to **GDScript** `scripts/characters/player.gd` only
- **Missed**: All actual game levels use `scenes/characters/csharp/Player.tscn`, which references `Scripts/Characters/Player.cs` (C#)
- Owner feedback: "звук не добавился, проверь C#" (sound wasn't added, check C#)

### 2026-02-24 — Second attempt (commit b0ba8a0c)
- Added scanner loop to **C# `Scripts/Characters/Player.cs`**
- Game log (game_log_20260225_001249.txt) confirms code executed: `[Player.Homing] Homing scanner loop started (Issue #890)`
- Owner feedback: "fix звук пока активен предмет не появился" (sound still not appearing)

### 2026-02-24 — Third attempt (this session)
- Deep analysis of WAV file structure and Godot 4 AudioStreamWav behavior
- **Root cause identified**: Missing `LoopEnd` and `LoopBegin` settings

---

## Root Cause Analysis

### Symptom
The game log shows `Play()` was called successfully, but the owner could not hear the scanner sound.

### Investigation Steps

1. **WAV file analysis**: File is valid PCM 16-bit mono 44100 Hz, 2 seconds, max amplitude 9830 (~30% of max). Audio data is present and non-silent.

2. **Code flow verification**: Log confirms `SetupHomingAudio()` runs, stream loads successfully, `Play()` is called.

3. **Godot WAV loop behavior**: In Godot 4, `AudioStreamWav` has three loop-related properties:
   - `LoopMode` — set to `Forward` in our code ✓
   - `LoopBegin` — default 0 (beginning) — not set in our code
   - `LoopEnd` — **default 0** — **NOT SET in our code** ✗

4. **The bug**: When `LoopEnd = 0` and `LoopMode = LOOP_FORWARD`, Godot loops from position 0 to position 0 — an empty loop. The audio plays through once (2 seconds), then the loop region is 0 samples long (silence).
   - Reference: [Godot issue #33141](https://github.com/godotengine/godot/issues/33141) — "Imported WAV AudioStreamSample has Loop End = 0"
   - This is a known Godot WAV import issue

5. **Both implementations had the bug**:
   - GDScript `player.gd:3099`: Sets `loop_mode` but not `loop_end`
   - C# `Player.cs:4757`: Sets `LoopMode` but not `LoopEnd`

### Evidence from Game Log

```
[00:13:11] [INFO] [Player.Homing] Homing activation sound loaded
[00:13:11] [INFO] [Player.Homing] Homing scanner loop started (Issue #890)
[00:13:11] [INFO] [Player.Homing] Homing bullets equipped, charges: 6/6
```

The sound was "started" but due to `LoopEnd = 0`, it:
- Played 2 seconds of audio (may have been heard very quietly at -18 dB)
- Then looped back to the empty loop region (0 samples), producing silence

---

## Fix

### C# (`Scripts/Characters/Player.cs`)

```csharp
var scannerStream = GD.Load<AudioStreamWav>(HomingScannerLoopPath);
if (scannerStream != null)
{
    scannerStream.LoopMode = AudioStreamWav.LoopModeEnum.Forward;
    // Calculate sample count for correct loop endpoint
    int bytesPerSample = (scannerStream.Format == AudioStreamWav.FormatEnum.Format16Bits) ? 2 : 1;
    int channels = scannerStream.Stereo ? 2 : 1;
    int totalSamples = scannerStream.Data.Length / (bytesPerSample * channels);
    scannerStream.LoopBegin = 0;
    scannerStream.LoopEnd = totalSamples;
    // ...
}
```

### GDScript (`scripts/characters/player.gd`)

```gdscript
if scanner_stream is AudioStreamWAV:
    scanner_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    var bytes_per_sample: int = 2 if scanner_stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
    var channels: int = 2 if scanner_stream.stereo else 1
    scanner_stream.loop_begin = 0
    scanner_stream.loop_end = scanner_stream.data.size() / (bytes_per_sample * channels)
```

---

## Additional Notes

- Volume at -18 dB is very quiet (about 12.6% of full volume). This is intentional per the design (ambient scanner hint, not dominant sound).
- The scanner plays continuously from level start while Homing Bullets are equipped — not just during activation.
- The activation sound (homing_activation.wav) correctly plays once per activation and does not need looping.

---

## Files Changed
- `Scripts/Characters/Player.cs` — Fixed `LoopEnd` and `LoopBegin`
- `scripts/characters/player.gd` — Fixed `loop_end` and `loop_begin` (for completeness)
- `docs/case-studies/issue-890/case-study.md` — This document
- `docs/case-studies/issue-890/game_log_20260225_001249.txt` — Game log from owner
