# Case Study: Issue #1204 — Fix Player Arm Model (Right Arm Two-Part Joint)

## Problem Statement

**Original Issue (Russian):**
> эту проблему уже пытались решить, но не удалось (наверное есть записи)
> сейчас игрок выглядит как будто одной рукой (двухсоставной) тактически держит оружие.
> так и должна выглядеть правая рука (но сейчас две части руки считаются левой и правой рукой).
> по этому при броске гранаты двухсоставная рука разрывается в локте (выглядит неправильно).
> исправь это (другую двухсоставную руку пока не добавляй).

**Translation:**
> This problem has been tried to solve before, but failed (there should be records of it).
> Currently, the player looks like they're tactically holding the weapon with one two-part arm.
> The right arm SHOULD look like this (but currently the two parts are treated as "left" and "right" arm).
> This is why during grenade throw, the two-part arm separates at the elbow (looks wrong).
> Fix this (don't add another two-part arm yet).

## Timeline of Events

### Issue #96 (PR #186) — Add modular player model
- Player model was added with separate sprite nodes: `LeftArm` + `RightArm`
- `LeftArm` (position 24, 6) = shoulder/upper arm part
- `RightArm` (position -2, 6) = forearm/lower arm part
- Both are sprites forming the **right arm** (the front/dominant arm holding the weapon)
- Named incorrectly — they are semantically "left" and "right" nodes but both represent the RIGHT arm

### Issue #202 (PR #203) — Add grenade throwing animation
- Grenade throw animation added, animating both `LeftArm` and `RightArm` independently
- Each sprite is lerped separately to its target position each frame

### Issue #448 (PR #449) — Attempt to fix arm naming and add left arm
- PR #449 is still OPEN (never merged)
- Multiple failed attempts to fix the elbow separation during grenade throw animation
- **Bug Fix #7**: Calculate forearm target = shoulder_target + fixed_offset → FAILED because lerp moves different percentages on each frame
- **Bug Fix #8**: Lerp shoulder first, then directly set forearm = shoulder.position + offset → Still failed per user feedback
- Root cause identified but wrong solution chosen

### Issue #1204 (this issue) — Fix the arm model
- New issue filed because PR #449 is stuck and could not be merged
- Request to fix the arm model properly
- Explicitly states NOT to add the other two-part arm yet

## Root Cause Analysis

### Why the arm separates during animation

The player model has two separate `Sprite2D` nodes as **siblings** in the scene tree:
- `LeftArm` (position 24, 6) — the shoulder/upper arm
- `RightArm` (position -2, 6) — the forearm

Both are children of `PlayerModel` at the same hierarchy level.

During grenade throw animation, `_update_grenade_animation()` calls:
```gdscript
_left_arm_sprite.position = _left_arm_sprite.position.lerp(left_arm_target, lerp_speed)
_right_arm_sprite.position = _right_arm_sprite.position.lerp(right_arm_target, lerp_speed)
```

**The fundamental problem with lerp for connected parts:**
- `lerp(start, end, t)` moves a **percentage** of the remaining distance each frame
- If shoulder has 10 pixels remaining and forearm has 14 pixels remaining, with `t=0.3`:
  - Shoulder moves 3 pixels → now 7 remaining
  - Forearm moves 4.2 pixels → now 9.8 remaining
- The ratio between their positions changes each frame → the joint SEPARATES

**Attempted fix (Bug Fix #7, #8):** After lerping the shoulder, directly set `forearm.position = shoulder.position + offset`. This works if BOTH sprites share the same coordinate space. However, since both are children of `PlayerModel` (same parent), their `position` values are in the same local space — so this should mathematically work. The reports of it not working suggest either:
1. The fix was applied incorrectly in the code path
2. There's a frame ordering issue (shoulder animated in grenade code, but forearm overwritten by walk animation code in same frame)

### The Proper Fix: Hierarchical Parenting

The correct Godot approach is to use the **scene hierarchy**. When `RightForearm` is made a **child of `RightShoulder`**, the forearm's `position` becomes **local** relative to its parent (the shoulder). The forearm automatically follows the shoulder because the shoulder's transform is applied first.

**With hierarchical parenting:**
```
PlayerModel (Node2D)
├── Body (Sprite2D)
├── RightShoulder (Sprite2D)  ← animate this
│   └── RightForearm (Sprite2D)  ← local position stays constant; follows shoulder automatically
├── Armband (Sprite2D)
├── Head (Sprite2D)
└── WeaponMount (Node2D)
```

**Animation code becomes trivial:**
```gdscript
# Only animate the shoulder — forearm follows automatically!
_right_shoulder_sprite.position = _right_shoulder_sprite.position.lerp(shoulder_target, lerp_speed)
_right_shoulder_sprite.rotation = lerpf(_right_shoulder_sprite.rotation, shoulder_rot, lerp_speed)
# No need to animate forearm separately — it inherits parent transform
```

This is the standard game development pattern for articulated characters (used by Unity, Godot, Unreal, etc.).

## Solution

### 1. Rename sprite assets
- `player_left_arm.png` → `player_right_shoulder.png`
- `player_right_arm.png` → `player_right_forearm.png`

### 2. Update scene files (Player.tscn and csharp/Player.tscn)
- Rename `LeftArm` → `RightShoulder`
- Rename `RightArm` → `RightForearm`
- Make `RightForearm` a **child of `RightShoulder`** (not sibling)
- Set `RightForearm` local position = old_absolute_position - old_shoulder_position
  - Old: `RightShoulder` at (24, 6), `RightForearm` at (-2, 6)
  - New: `RightShoulder` at (24, 6), `RightForearm` local at (-26, 0)

### 3. Update player.gd
- Change `_left_arm_sprite`/`_right_arm_sprite` references to `_right_shoulder_sprite`/`_right_forearm_sprite`
- Remove all code that animates `_right_arm_sprite` (forearm) separately
- Only animate `_right_shoulder_sprite` (shoulder) — the forearm follows automatically
- Remove `_forearm_shoulder_offset` variable (no longer needed)
- Update comments to reflect correct naming

### 4. Update Scripts/Characters/Player.cs
- Same changes as player.gd: rename references, remove forearm animation

### 5. Update other scripts
- `scripts/components/death_animation_component.gd` — passes `_left_arm_sprite`/`_right_arm_sprite` by reference from player
- `scripts/autoload/last_chance_effects_manager.gd` — iterates over PlayerModel children
- `scripts/autoload/penultimate_hit_effects_manager.gd` — iterates over PlayerModel children
- `Scripts/Autoload/ReplayManager.cs` — uses `GetNodeOrNull<Node2D>("LeftArm")`

## References

- Issue #448: "fix исправь и доработай модели игрока и врага" (previous attempt)
- PR #449: "fix: add 4-part arm structure with proper naming for player and enemy models (Issue #448)" — OPEN, never merged
- Issue #202, PR #203: "Add grenade throwing animation system"
- Issue #96, PR #186: "Add modular player model with separate body parts"
- Godot Docs: [Cutout Animation](https://docs.godotengine.org/en/stable/tutorials/animation/cutout_animation.html) — recommends hierarchical parenting for articulated sprites
