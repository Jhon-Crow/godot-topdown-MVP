# Shotgun Mechanics Research

## Online Research Summary

### Pellet Spread Implementation Approaches

1. **Random Spread within Cone**
   - Set direction to base angle ± half cone width randomly
   - Example: `direction = base_angle + random(-15, 15)` for 30° cone

2. **Fixed Pattern Spread**
   - Each pellet has predetermined offset
   - More skill-based, consistent patterns

3. **Common Variables**
   - Number of pellets (6-12 for 00 buckshot)
   - Spread angle (cone width in degrees)
   - Horizontal/vertical spread ratios

### Real Buckshot Ballistics (00 Buckshot)

**Spread Patterns:**
- Old rule: "1 inch per yard" - mostly busted by testing
- Actual: Most barrels produce ~0.5" per yard spread
- At 10 yards (~9m): ~8 inches spread (cylinder bore)
- At 15 yards (~14m): ~6 inches (FliteControl) to 10+ inches (standard)

**Pattern in Degrees (calculated):**
- 8" spread at 10 yards = ~2.3° spread angle
- 10" spread at 10 yards = ~2.9° spread angle
- Real shotguns have tighter patterns than games typically portray
- Games often use 15-30° for gameplay balance

### Ricochet Behavior

**Study Findings:**
- Research used 12-gauge with 00 buckshot
- Tested angles of incidence: 5°, 10°, 15°, 20°, 25°
- Ricochet angle generally lower than incidence angle
- Round/spherical projectiles (like buckshot) have high ricochet probability
- Low velocity projectiles more likely to ricochet

**2024 Research:**
- Pellets ricocheting at 10-30° create elongated elliptical marks
- Relationship between mark dimensions and impact angles documented

### Pump-Action Reload Mechanics

**Real Operation:**
1. Pull forend rearward - unlocks bolt
2. Bolt moves back - extracts spent shell
3. Ejector kicks shell out
4. Shell carrier lifts fresh shell from magazine tube
5. Push forend forward - chambers round

**Game Design Considerations:**
- "Shotgun Shootout" uses drag controls: "drag down to eject, drag up to load"
- Common issue: playing full reload animation even for partial reloads
- Tactical vs empty reload animations

### Issue Request Translation (Russian to English)

**Original (Russian):**
- дробовик = shotgun
- скорострельность = rate of fire
- полуавтоматический = semi-automatic
- дробь = pellets/shot
- разброс = spread
- рикошеты = ricochets
- тряска экрана = screen shake
- прицела = scope/sight
- зарядов = rounds/shells
- перезарядка = reload
- ПКМ = RMB (Right Mouse Button)
- СКМ = MMB (Middle Mouse Button)
- ЛКМ = LMB (Left Mouse Button)
- драгндроп = drag & drop

**Weapon Specifications:**
| Property | Value |
|----------|-------|
| Fire Mode | Semi-automatic (player skill limited) |
| Pellets per shot | 6-12 (random) |
| Spread angle | 15 degrees |
| Spread type | Always medium |
| Ricochet max angle | 35 degrees |
| Wall penetration | No |
| Screen shake | Large (single recoil) |
| Scope | None |
| Sound | Same as assault rifle |
| Magazine capacity | 8 shells |

**Reload Sequence:**
1. RMB drag down (open)
2. MMB → RMB drag down (load shell, repeat up to 8x)
3. RMB drag up (close)

**Fire Sequence:**
1. LMB (fire)
2. RMB drag up (cycle)
3. RMB drag down (ready)

## Sources

- [Unreal Engine Shotgun Tutorial](https://dev.epicgames.com/community/learning/tutorials/9y9n/unreal-engine-14-weapon-shot-count-and-spread-let-s-make-a-top-down-top-down-shooter)
- [Unity Shotgun Spread Discussion](https://discussions.unity.com/t/2d-top-down-shooter-shotgun-bullets-spread/58976)
- [Godot Shotgun Scatter](https://forum.godotengine.org/t/how-would-i-make-a-shotgun-scatter-bullets-in-godot/16488)
- [Buckshot Pattern Testing](https://www.thefirearmblog.com/blog/2014/07/04/myth-busting-1-per-yard-shotgun-pattern-spreads/)
- [Shotgun Pellet Ricochet Study](https://store.astm.org/jfs11425j.html)
- [2024 Ricochet Research](https://www.sciencedirect.com/science/article/abs/pii/S1355030624000704)
- [Pump Action Shotgun Mechanics](https://thegunzone.com/how-a-pump-shotgun-works-animation/)
