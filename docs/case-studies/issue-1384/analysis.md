# Case Study: Issue #1384 — Sniper Laser Sight Too Short & Misaligned with Crosshair

## Overview

**Issue title:** лазе снайперской винтовки должен быть неограниченной длинны (sniper rifle laser sight should be unlimited length)
**Reported:** 2026-03-23
**Reporter:** Jhon-Crow
**Description (translated):** "The sniper rifle laser (from the passive item or Power Fantasy mode) should be unlimited length."
**Follow-up feedback:** "The laser must match the crosshair (currently there's significant divergence at distance)" and "In aiming mode with the laser, the laser must pass through the center of the crosshair."
**Log file:** [game_log_20260323_135901.txt](game_log_20260323_135901.txt)

---

## Evidence: Code Analysis

### Sniper Rifle Configuration

From `Scripts/Weapons/SniperRifle.cs`:
- **Weapon range:** 5000px (from `WeaponData.Range`)
- **Non-aiming sensitivity factor:** `0.04f` (25x slower rotation than normal weapons)
- **Scope zoom distance:** 1.5x–4.0x viewport diagonal
- **Scope sensitivity multiplier:** 8x base × zoom level

### Game Log Evidence

The attached log (`game_log_20260323_135901.txt`, 1143 lines) is from a **Power Fantasy** difficulty session on the Labyrinth level:
- `[13:59:01] Loaded difficulty: Power Fantasy (value: 3)` — Power Fantasy mode confirmed (laser sight is enabled)
- `[13:59:16] Equipped SniperRifle (ammo: 5/5)` — sniper rifle was in use
- `[13:59:01] Debug build: false` — release build, no laser-specific debug output available
- Multiple weapon switches and shots recorded, confirming active gameplay testing

---

## Timeline / Sequence of Events

### Problem 1 — Laser Length Limited to Viewport (Original Report)

**Root cause:** `UpdateLaserSight()` computed `maxLaserLength` from the viewport diagonal:
```csharp
// BEFORE (broken):
Vector2 viewportSize = viewport.GetVisibleRect().Size;
float maxLaserLength = viewportSize.Length(); // ~2203px at 1920×1080
```

The viewport diagonal at 1920×1080 is approximately 2203px — less than half the weapon's 5000px range. The laser appeared "cut short" even in open areas with no obstacles.

**Fix (commit 7258d194):** Replaced viewport-based length with weapon range:
```csharp
// AFTER (fixed):
float maxLaserLength = WeaponData?.Range ?? 5000.0f;
```

### Problem 2 — Laser Diverges from Crosshair in Hip-Fire Mode

**Root cause:** The sniper rifle has `NonAimingSensitivityFactor = 0.04f`, meaning the gun barrel (`_aimDirection`) rotates 25× slower than mouse movement. The original laser used `_aimDirection` for its beam direction:
```csharp
// BEFORE (broken):
Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);
```

When the player moves the mouse quickly, `_aimDirection` lags far behind the cursor. At the weapon's 5000px range, even a 2° angular gap produces a ~175px spatial divergence — visually, the laser and crosshair point at completely different targets.

**Fix (commit 336fb1b1):** Replaced `_aimDirection` with direct mouse position:
```csharp
// AFTER (fixed):
Vector2 toMouse = GetGlobalMousePosition() - GlobalPosition;
Vector2 laserDirection = toMouse.LengthSquared() > 0.001f
    ? toMouse.Normalized()
    : _aimDirection;
```

### Problem 3 — Laser Misaligned in Scope/Aiming Mode

**Root cause:** The fix from Problem 2 used `GetGlobalMousePosition()` in all cases, including scope mode. However, in scope mode:

1. The camera is offset far from the player along `_aimDirection` (up to 4× viewport diagonal).
2. The scope crosshair is drawn at **screen center** (viewport center), which corresponds to `_playerCamera.GetScreenCenterPosition()` in world coordinates.
3. The mouse cursor position (`GetGlobalMousePosition()`) is **not** at screen center — the scope uses a separate `_scopeMouseOffset` system for fine-tuning, and the actual mouse position is irrelevant.

Result: the laser pointed at the mouse cursor's world position while the crosshair was at screen center — a completely different world location when the camera is offset by thousands of pixels.

**Fix (commit 09a65339):** In `UpdateLaserSight()`, determine the target based on scope state:
```csharp
// AFTER (fixed):
Vector2 targetPoint = _isScopeActive
    ? GetScopeAimTarget()   // World position at screen center (where crosshair is)
    : GetGlobalMousePosition(); // Mouse cursor position (hip-fire crosshair)

Vector2 toTarget = targetPoint - GlobalPosition;
Vector2 laserDirection = toTarget.LengthSquared() > 0.001f
    ? toTarget.Normalized()
    : _aimDirection;
```

`GetScopeAimTarget()` returns `_playerCamera.GetScreenCenterPosition()` — the exact world position that the scope crosshair represents. The laser now always passes through the crosshair in both modes.

---

## Root Cause Analysis

The core issue is an **abstraction mismatch** between three different "where is the player aiming?" systems in the sniper rifle:

| System | Source | Updates | Use Case |
|--------|--------|---------|----------|
| `_aimDirection` | Mouse → angle → clamped rotation | Every frame, 25× slow | Gun barrel direction, sprite rotation |
| `GetGlobalMousePosition()` | OS mouse cursor → viewport → world | Instant | Hip-fire crosshair target |
| `GetScopeAimTarget()` | Camera center + offsets | Every frame via camera | Scope crosshair target |

The laser sight was originally coupled to `_aimDirection` (Problem 2), then overcorrected to always use `GetGlobalMousePosition()` (Problem 3). The correct approach is context-sensitive: use the mouse position in hip-fire, and the scope aim target in scope mode.

### Why the Problem Wasn't Caught Earlier

1. The laser sight is only active in Power Fantasy mode (a special difficulty setting).
2. The scope was added later as a separate feature — laser and scope interactions weren't tested together.
3. Testing without the scope showed the fix for Problem 2 working correctly (laser aligned with cursor).
4. The divergence in scope mode only becomes apparent at high zoom distances (1.5x–4x viewport), which requires specific gameplay testing.

---

## Resolution Summary

| Commit | Problem | Fix |
|--------|---------|-----|
| `7258d194` | Laser limited to viewport diagonal (~2203px) | Use `WeaponData.Range` (5000px) instead |
| `336fb1b1` | Laser diverges from cursor due to slow `_aimDirection` | Point laser at `GetGlobalMousePosition()` directly |
| `09a65339` | Laser misaligned in scope mode (cursor ≠ crosshair) | Use `GetScopeAimTarget()` in scope, `GetGlobalMousePosition()` in hip-fire |

All three fixes target `UpdateLaserSight()` in `Scripts/Weapons/SniperRifle.cs`.
