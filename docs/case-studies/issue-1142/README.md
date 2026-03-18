# Case Study: Issue #1142 — Player Visual Not Changed When Armored Skin Equipped

## Summary

**Issue**: Player character does not show a glassy armor visual overlay when the "Armored Skin" passive item is equipped, unlike enemies with Armored Skin which have a visible blue crystalline shader effect.

**Root Cause (Primary)**: The user's test binary was built from a pre-PR codebase that did not contain the `_apply_armored_skin_visual()` function. The fix was already implemented in PR #1149 but the user tested with an old executable.

**Root Cause (Secondary / Pre-existing)**: The `main` branch itself was missing `_apply_armored_skin_visual()` — it only had the HP bonus and shard-spawning mechanic from Issue #1045, with no visual overlay applied to the player at all.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| ~2026-03-18T05:52 | PR #1124 merged — introduced `armored_skin.gdshader` and applied it to enemy `ArmoredSkinComponent`. Player Armored Skin had no equivalent visual. |
| 2026-03-18T04:35 | PR #1149 (issue-1142 branch) — `_apply_armored_skin_visual()` added to `player.gd`, applying the shader to player sprites. |
| 2026-03-18T09:06:12 | User runs test session with `Godot-Top-Down-Template.exe` (Windows, debug=false, Godot 4.3-stable) |
| 09:06:13 | Game starts, Force Field selected as active item |
| 09:06:14 | `_init_armored_skin()` called → "No armored skin selected" (expected) |
| 09:06:19 | User opens Armory menu mid-game |
| 09:06:26 | User switches active item from Force Field → Armored Skin |
| 09:06:26 | Scene reload triggered |
| 09:06:27 | Player re-initializes, `_init_armored_skin()` called → "Armored skin active" |
| 09:06:27 | **No visual shader applied** — `_apply_armored_skin_visual()` not present in this binary |
| 09:06:32 | Shard-spawn mechanic triggers correctly (pre-existing from Issue #1045) |

---

## Evidence from Game Log

File: `game_log_20260318_090612.txt`

**Diagnostic log message mismatch** — the binary's log output differs from both the `main` branch and the PR branch:

| Source | Log message |
|--------|-------------|
| User's binary (log line 348) | `Armored skin active — shards will spawn when HP ≤2 and hit` |
| `main` branch (current) | `Armored skin active — shards will spawn at low HP` |
| PR #1149 branch | `Armored skin active — shards will spawn at low HP` |

This confirms the user's binary predates even the current `main` branch — it was a release build from an earlier commit.

**No shader log entries present**:

```
grep "Armor shader applied\|PlayerModel node not found\|WARNING.*armor\|WARNING.*Shader" game_log_20260318_090612.txt
```
→ No results. The `_apply_armored_skin_visual()` function simply did not exist in the tested build.

**Shader function exists on PR branch**:

```gdscript
# player.gd:4561
func _apply_armored_skin_visual() -> void:
    if not ResourceLoader.exists(ARMOR_SHADER_PATH):
        FileLogger.info("[Player.ArmoredSkin] WARNING: Shader not found: %s" % ARMOR_SHADER_PATH)
        return
    var shader: Shader = load(ARMOR_SHADER_PATH)
    ...
    var model: Node = get_node_or_null("PlayerModel")
    ...
    for child in model.get_children():
        if child is Sprite2D:
            var mat := ShaderMaterial.new()
            mat.shader = shader
            mat.set_shader_parameter("armor_opacity", 0.55)
            child.material = mat
            applied_count += 1
    FileLogger.info("[Player.ArmoredSkin] Armor shader applied to %d sprites" % applied_count)
```

---

## Scene Node Structure Analysis

`Player.tscn` node hierarchy under `PlayerModel`:

```
PlayerModel (Node2D)
├── Body       (Sprite2D)  ← shader applied
├── LeftArm    (Sprite2D)  ← shader applied
├── RightArm   (Sprite2D)  ← shader applied
├── Armband    (Sprite2D)  ← shader applied
├── Head       (Sprite2D)  ← shader applied
└── WeaponMount (Node2D)  ← skipped (not Sprite2D)
```

The `_apply_armored_skin_visual()` function iterates all children with `for child in model.get_children(): if child is Sprite2D` — this correctly applies to all 5 sprite nodes and skips WeaponMount.

---

## Root Cause Analysis

### Primary root cause: Stale binary
The user tested with a `Godot-Top-Down-Template.exe` release binary that was built from a commit predating both the current `main` branch fix and PR #1149. The new visual effect code was never executed.

### Secondary root cause: Missing feature in main branch
The `main` branch (pre-PR) had `_init_armored_skin()` that only:
1. Set `_armored_skin_active = true`
2. Logged "Armored skin active — shards will spawn at low HP"

It did NOT call any visual function — the player armor overlay was simply never implemented until PR #1149.

### Why the shard mechanic worked but the visual did not
The shard mechanic (`_spawn_armored_skin_shards()`) was introduced in Issue #1045 and was present in the old binary. The visual overlay (`_apply_armored_skin_visual()`) was the new work requested in Issue #1142.

---

## Solution

PR #1149 adds `_apply_armored_skin_visual()` to `scripts/characters/player.gd`, which:
- Loads `res://scripts/shaders/armored_skin.gdshader` (the same shader used by enemy `ArmoredSkinComponent`, introduced in PR #1124)
- Applies it to all `Sprite2D` children of `PlayerModel` with `armor_opacity = 0.55`
- Is called from `_init_armored_skin()` when Armored Skin is active

The fix requires building a new executable from the updated codebase.

---

## Additional Facts and Context

- **Shader reuse**: `armored_skin.gdshader` was originally created for enemies in PR #1124 (Issue #1123). The player shader application reuses the exact same shader file, ensuring visual consistency between player and enemy Armored Skin appearances.
- **Opacity**: `armor_opacity = 0.55` matches the enemy version. This was initially set to `0.3` (more subtle) but increased to `0.55` in commit `8286638b` to match enemy version per owner request.
- **No runtime signal needed**: The visual is applied during `_ready()` initialization after scene reload, which is the correct point — Armored Skin selection triggers a scene reload in this game.

---

## Second Test Log Analysis (game_log_20260318_102209.txt)

The user provided a second game log on 2026-03-18 at 10:22:09, after the PR was marked ready and a "fix is in PR" comment was posted.

**Finding: The user is still using the same old pre-PR binary.**

Evidence:

| Indicator | Value in log | Expected (PR branch) |
|-----------|-------------|----------------------|
| Log message at line 342 | `"Armored skin active — shards will spawn when HP ≤2 and hit"` | `"Armored skin active — shards will spawn at low HP"` |
| Sprites found (lines 314–317, 322–325 etc.) | Body, Head, LeftArm, RightArm (4 sprites) | Body, Head, LeftArm, RightArm, Armband (5 sprites) |
| `"Armor shader applied"` entries | **None** | Should appear each scene reload when Armored Skin is active |

**Timeline of second test session:**

| Time | Event |
|------|-------|
| 10:22:09 | Game starts with old binary |
| 10:22:11 | Player initializes — no Armored Skin selected ("No armored skin selected") |
| 10:22:16 | User opens Armory menu |
| 10:22:23 | User switches active item to Armored Skin |
| 10:22:23 | Scene reload triggered |
| 10:22:24 | `_init_armored_skin()` → "Armored skin active — shards will spawn when HP ≤2 and hit" (old binary message) |
| 10:22:24 | **No visual applied** — `_apply_armored_skin_visual()` not in this binary |
| 10:22:24–10:22:28 | Multiple scene reloads; same behavior repeats |

**Conclusion**: Both test logs confirm the same root cause — the user has not yet rebuilt from the PR branch. A new build from `issue-1142-4c23df595a38` is required to see the fix.

---

## How to Verify the Fix

### Option 1 — Download the pre-built CI artifact (recommended)

A Windows build from the PR branch (`issue-1142-4c23df595a38`) was automatically built by GitHub Actions CI.

1. Go to the CI run page: https://github.com/Jhon-Crow/godot-topdown-MVP/actions/runs/23233743387
2. Scroll to the bottom of the page — under **Artifacts**, download `windows-build`
3. Extract the zip, run `Godot-Top-Down-Template.exe`
4. Select "Armored Skin" in Armory
5. Verify:
   - Log contains `"[Player.ArmoredSkin] Armor shader applied to 5 sprites"`
   - Player character shows blue glassy crystal overlay, matching the enemy Armored Skin visual

> **Note**: The download link requires GitHub login. If you are logged in to GitHub, the artifact will download from the Actions page.

### Option 2 — Build from source

1. Check out branch `issue-1142-4c23df595a38`
2. Open the project in Godot 4.3
3. Export to a new `.exe` (or run directly from editor)
4. Select "Armored Skin" in Armory
5. Check that log contains `"Armor shader applied to 5 sprites"` and player shows the armor overlay

---

## Third User Report (2026-03-18 07:44) — "Still No Changes"

After the second log analysis, the user posted a third complaint: `"всё ещё нет изменений"` ("still no changes"), this time **without attaching a new game log**.

This confirms the user has not yet tried the new binary from the PR branch — they are running the same pre-existing old `.exe` and seeing no change, which is expected.

**Key insight**: Previous AI session responses correctly identified the root cause (old binary) but never provided a direct download link to the pre-built CI artifact. The user would need to either:
1. Download the `windows-build` artifact from the CI run (see "How to Verify the Fix" above), OR
2. Build the project from source themselves using Godot 4.3

Neither of these was clearly communicated with actionable download links until this update.

---

## Fourth User Report (2026-03-18 10:59) — Third Game Log with "No Changes"

The user posted a fourth report on 2026-03-18 at 10:59:25 with comment `"нет изменений"` ("no changes") and attached `game_log_20260318_105925.txt`.

**Notable detail**: The executable path in this log is:
```
I:/Загрузки/godot exe/Бронированная Кожа/Godot-Top-Down-Template.exe
```
`Загрузки` = "Downloads" in Russian. `Бронированная Кожа` = "Armored Skin" in Russian.

This strongly indicates the user created a new folder specifically for testing the Armored Skin feature (they moved or renamed the folder) — but placed the **same old `.exe`** inside it, rather than downloading the new CI artifact.

**Finding: The user is still running the same old pre-PR binary.**

Evidence comparison across all three logs:

| Indicator | Log 1 (09:06) | Log 2 (10:22) | Log 3 (10:59) | Expected (PR branch) |
|-----------|-------------|-------------|-------------|----------------------|
| Binary message | `"shards will spawn when HP ≤2 and hit"` | `"shards will spawn when HP ≤2 and hit"` | `"shards will spawn when HP ≤2 and hit"` | `"shards will spawn at low HP"` |
| Sprites found per init | 4 (no Armband) | 4 (no Armband) | 4 (no Armband) | 5 (includes Armband) |
| `"Armor shader applied"` | **None** | **None** | **None** | Should appear each init |
| Debug build | false | false | false | — |
| Engine version | 4.3-stable | 4.3-stable | 4.3-stable | — |

**Timeline of third test session (10:59):**

| Time | Event |
|------|-------|
| 10:59:25 | Game starts from `I:/Загрузки/godot exe/Бронированная Кожа/` (same old binary) |
| 10:59:26 | Player initializes — no Armored Skin selected ("No armored skin selected") |
| 10:59:29 | User opens Armory menu |
| 10:59:34 | User switches active item from None → Armored Skin |
| 10:59:34 | +1 HP bonus applied (health 5/5) |
| 10:59:34 | Scene reload triggered |
| 10:59:34 | `_init_armored_skin()` → **"Armored skin active — shards will spawn when HP ≤2 and hit"** (old binary message) |
| 10:59:34 | **No visual applied** — `_apply_armored_skin_visual()` not in this binary |
| 10:59:34–10:59:37 | Multiple scene reloads due to continued item switching; same behavior repeats 4 more times |
| 10:59:44 | Session ends after ~19 seconds |

**Conclusion**: All four reports (including three game logs) confirm the same root cause — the user consistently runs the old pre-PR executable. The fix is present in PR #1149, but the user needs to run a newly compiled binary.

**Root cause of the user's confusion**: The previous AI session comment instructed the user to download the artifact from `https://github.com/Jhon-Crow/godot-topdown-MVP/actions/runs/23233743387` but this is a link to a CI run from the *fork* (`konard/Jhon-Crow-godot-topdown-MVP`), which may require additional GitHub permissions or navigation to see the artifact. The user appears to have not found or successfully downloaded the new build.

---

## Files Referenced

| File | Role |
|------|------|
| `scripts/characters/player.gd` | Player logic — `_init_armored_skin()`, `_apply_armored_skin_visual()` |
| `scripts/shaders/armored_skin.gdshader` | GLSL shader producing the glassy crystal overlay |
| `scenes/characters/Player.tscn` | Player scene — defines `PlayerModel` and sprite hierarchy |
| `docs/case-studies/issue-1142/game_log_20260318_090612.txt` | First user-provided game session log (09:06:12) showing the bug |
| `docs/case-studies/issue-1142/game_log_20260318_102209.txt` | Second user-provided game session log (10:22:09) — same old binary confirmed |
| `docs/case-studies/issue-1142/game_log_20260318_105925.txt` | Third user-provided game session log (10:59:25) — same old binary confirmed; user created "Бронированная Кожа" folder but placed old `.exe` there |
