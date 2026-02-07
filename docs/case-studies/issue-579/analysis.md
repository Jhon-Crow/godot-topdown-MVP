# Case Study: Issue #579 - Machete Enemy Type

## Problem Statement

Add a new enemy type: a machete-wielding melee combatant with distinct tactical behaviors:
1. Hides and approaches nearest cover (stealth approach)
2. Attempts to attack from behind or when player is under fire
3. In attacking state, dodges bullets instead of hiding
4. Create a Beach map with these enemies

## Architecture Analysis

### Existing Enemy System

The current enemy system (`scripts/objects/enemy.gd`, ~5000 lines) supports:
- **3 weapon types**: RIFLE (M16), SHOTGUN, UZI - all ranged
- **11 AI states**: IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING, EVADING_GRENADE
- **2 behavior modes**: PATROL, GUARD
- **GOAP planning**: Action-based decision making
- **Components**: VisionComponent, CoverComponent, ThreatSphere, GrenadeAvoidanceComponent, EnemyMemory

### Key Design Decision: Extend vs. New Script

**Option A: New separate script** - Creates code duplication, hard to maintain
**Option B: Extend existing enemy.gd** - Add MACHETE weapon type with melee-specific behaviors

**Chosen: Option B** - The existing enemy.gd already has sophisticated AI, cover system, flanking, and threat detection. Adding a new weapon type with behavioral overrides is cleaner than duplicating 5000 lines.

## Implementation Design

### 1. MACHETE Weapon Type (WeaponType.MACHETE = 3)

- No bullet_scene (melee only)
- No casing_scene
- Attack range: 80px (melee range)
- Attack cooldown: 1.5s
- Damage: 2 (higher than single bullet)
- Weapon sprite: machete_topdown.png
- No ammunition system (infinite melee)
- No reload mechanic

### 2. New AI Behaviors for Machete

#### Sneaking Approach (Modified PURSUING)
- Uses cover-to-cover movement like PURSUING but quieter
- Lower movement speed when near player (stealth)
- Prefers cover positions that approach from behind the player

#### Backstab Preference
- Calculates player's facing direction
- Prioritizes approach paths behind the player
- When player is engaged with other enemies (under fire), rushes in

#### Bullet Dodging (DODGING state)
- When in melee attack range and bullets enter threat sphere
- Instead of seeking cover, performs lateral dodge
- Quick side-step movement perpendicular to bullet direction
- Short dodge cooldown to prevent constant dodging

### 3. Beach Map

- Open outdoor level with scattered cover (palm trees, beach huts, rocks, barrels)
- Mix of machete enemies and ranged enemies
- Sandy terrain with water boundary
- Navigation mesh covering playable area

## Technical References

- WeaponConfigComponent: `scripts/components/weapon_config_component.gd`
- Enemy AI: `scripts/objects/enemy.gd`
- Cover System: `scripts/components/cover_component.gd`
- Threat Detection: `scripts/components/threat_sphere.gd`
- Level Template: `scenes/levels/BuildingLevel.tscn`
- Level Script: `scripts/levels/building_level.gd`

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Breaking existing enemies | MACHETE-specific code gated behind weapon_type check |
| State machine complexity | Reuse existing states where possible |
| CI validation failures | Follow architecture-check.yml patterns |
| Gameplay balance | Machete enemies are high-risk melee fighters |
