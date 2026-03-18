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

## Files Referenced

| File | Role |
|------|------|
| `scripts/characters/player.gd` | Player logic — `_init_armored_skin()`, `_apply_armored_skin_visual()` |
| `scripts/shaders/armored_skin.gdshader` | GLSL shader producing the glassy crystal overlay |
| `scenes/characters/Player.tscn` | Player scene — defines `PlayerModel` and sprite hierarchy |
| `docs/case-studies/issue-1142/game_log_20260318_090612.txt` | User-provided game session log showing the bug |
