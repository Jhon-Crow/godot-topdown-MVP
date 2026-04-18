# Case Study: Issue #1627 Snow And Blood Footprints

## Current User-Visible Problem

The Winter Forest should leave normal oval snow dents while walking on snow. After stepping in a blood puddle on snow, the next two snow dents should be red/bloody snow dents, then footprints should return to normal white snow dents. The latest PR feedback says the game still shows ordinary snow footprints after blood puddles.

## Collected Data

- `logs/game_log_20260418_000122.txt` — user-attached runtime log from Windows build, 1,851 lines.
- `sources/issue-comments.json` — paginated issue comments for issue #1627.
- `sources/pr-1720.json` — PR metadata and discussion snapshot.
- `sources/pr-review-comments.json` — paginated inline PR comments.

The GitHub attachment was downloaded with authenticated `curl -L -H "Authorization: token $(gh auth token)"` and stored locally under this case-study folder.

## Timeline Reconstruction

1. Original issue requested snow texture, snow footprints, and blood interacting with snow.
2. First implementation added snow footprint spawning but used boot-shaped/red-tinted assets, so tracks looked bloody and foot-shaped.
3. Follow-up changed snow tracks to oval snow-print textures.
4. Follow-up required blood on snow to produce red oval snow dents, not normal boot-shaped blood prints, and not duplicate snow plus blood prints.
5. Follow-up narrowed expected behavior to exactly 2 red snow footprints after stepping in blood, then normal snow footprints.
6. Several fixes tried to arm `SnowyFeetComponent` from `BloodyFeetComponent.blood_contact`, but user screenshots/logs still showed normal snow prints after blood.
7. The latest attached log confirms `BloodyFeetComponent` and `SnowyFeetComponent` initialize on Winter Forest and blood contact events happen, but contact colors are logged as white: `Stepped in blood! 2 footprints to spawn, color: (1, 1, 1, 1)`.

## Evidence From Log

Relevant runtime sequence from `game_log_20260418_000122.txt`:

- Lines 409-411: `BloodyFeetComponent` initializes for `Player` on Winter Forest.
- Lines 485-490: `SnowyFeetComponent` initializes for player and enemies.
- Lines 519-523: player blood and snow detectors are created.
- Lines 997, 1787, 1794, 1811, 1814, 1818, 1820, 1822, 1827, 1831, 1836, 1844: player repeatedly steps in blood on snow, but the logged color is `(1, 1, 1, 1)`.
- Lines 1025, 1791, 1796, 1813, 1815, 1819, 1821, 1824, 1828, 1832, 1837, 1846: blood runs out on snow very quickly.

The white color is inconsistent with a red blood puddle. It means the detector frequently used the child `Area2D` (`PuddleArea`) color instead of the parent `BloodDecal` sprite color. `Area2D` defaults to white `modulate`, so red snow footprints were tinted white and looked like ordinary snow footprints.

## Root Causes

### Root Cause 1: Child Area Color Lookup

`BloodDecal` is a `Sprite2D` with the actual red visual color. Its child `PuddleArea` is an `Area2D` used only for overlap detection. `BloodyFeetComponent._on_area_entered()` can receive either the parent decal or the child area. Previous `_get_puddle_color()` returned `CanvasItem.modulate` directly from the received node. When the received node was `PuddleArea`, the color was `(1, 1, 1, 1)`, so `SnowBloodFootprint` was tinted white.

Fix: when the received node is an `Area2D` whose parent is in `blood_puddle`, resolve color from the parent decal.

### Root Cause 2: Invisible Snow Blood Counter Drain

On snow, `BloodyFeetComponent._spawn_footprint()` intentionally does not render regular boot-shaped blood footprints because `SnowyFeetComponent` owns snow rendering. However, it still decremented `_blood_level` every `step_distance`. If its movement counter fired before `SnowyFeetComponent` spawned a print, the blood state could reach zero before any red snow footprint was rendered.

Fix: `BloodyFeetComponent` no longer decrements snow blood state invisibly. `SnowyFeetComponent` calls `consume_snow_blood_step()` only after it renders a red snow footprint.

## Online/External Research

Godot 4 `Area2D` documentation confirms that `Area2D` detects overlapping `CollisionObject2D` nodes and tracks currently overlapping objects. It also confirms `area_entered` requires `monitoring = true`, and the other object's collision layer must be in the monitoring area's mask. This supports the existing detector architecture but also explains why the callback naturally receives the collision child area rather than the visual parent decal.

Source: https://docs.godotengine.org/en/stable/classes/class_area2d.html

## Solution Options Considered

1. Make `SnowBloodDecal` interactive again by adding it to `blood_puddle`.
   Rejected because previous requirements explicitly said blood absorbed by snow should not behave as a reusable wet puddle.

2. Let `BloodyFeetComponent` render red snow prints directly.
   Rejected because it reintroduces duplicate ownership and risks both snow and blood components spawning at once.

3. Keep `SnowyFeetComponent` as the single renderer for snow, and make `BloodyFeetComponent` only detect/hold/consume blood state.
   Chosen because it matches the visual rule: one footprint per snow step, either red or white.

## Implemented Fix

- `scripts/components/bloody_feet_component.gd`
  - `_get_puddle_color()` resolves child `PuddleArea` contact to parent `BloodDecal` color.
  - `on_snow` path no longer decrements `_blood_level` inside `_spawn_footprint()`.
  - Added `consume_snow_blood_step()` for `SnowyFeetComponent` to call after rendering a red snow footprint.

- `scripts/components/snowy_feet_component.gd`
  - Calls `BloodyFeetComponent.consume_snow_blood_step()` immediately after spawning a red snow footprint.

- `tests/unit/test_bloody_feet_component.gd`
  - Covers child area color lookup.
  - Covers that on-snow `_spawn_footprint()` does not drain blood before rendering.
  - Covers explicit post-render snow blood consumption.

- `tests/unit/test_snowy_feet_component.gd`
  - Covers red snow footprints consuming blood only after rendering.

## Expected Behavior After Fix

- Step on clean snow: one normal white oval snow dent per step interval.
- Step in blood on snow: next 2 snow dents are red oval snow dents using the parent blood decal color.
- After those 2 rendered red snow dents: normal white oval snow dents resume.
- No duplicate ordinary snow plus blood footprints are spawned for the same step.
