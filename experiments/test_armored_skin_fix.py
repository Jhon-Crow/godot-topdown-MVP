"""
Experiment: Verify armored skin fix for Issue #1300
Tests that the fix correctly handles high-damage weapons (silenced pistol = 10 dmg)
not bypassing the armored skin trigger.
"""

HP_THRESHOLD = 2

def try_spawn_shards_OLD(current_health, incoming_damage=1):
    """Old behavior - only checks HP threshold"""
    if current_health > HP_THRESHOLD:
        return False  # armor does NOT trigger
    return True  # armor triggers

def try_spawn_shards_NEW(current_health, incoming_damage=1):
    """New behavior - also checks if hit is lethal"""
    # Trigger when HP is already low OR when this hit would be lethal (Issue #1300)
    if current_health > HP_THRESHOLD and current_health - incoming_damage > 0:
        return False  # armor does NOT trigger
    return True  # armor triggers

print("=== Armored Skin Trigger Test ===\n")

test_cases = [
    # (current_hp, damage, description)
    (5, 1,  "5 HP, 1 dmg (regular pistol) - should NOT trigger"),
    (2, 1,  "2 HP, 1 dmg (regular pistol at threshold) - should trigger"),
    (1, 1,  "1 HP, 1 dmg (at 1 HP) - should trigger"),
    (5, 10, "5 HP, 10 dmg (silenced pistol ONE-SHOT) - should trigger (BUG FIX)"),
    (3, 10, "3 HP, 10 dmg (silenced pistol) - should trigger (BUG FIX)"),
    (2, 10, "2 HP, 10 dmg (already at threshold) - should trigger"),
    (3, 2,  "3 HP, 2 dmg (dmg reduces to 1 HP, survives) - should NOT trigger"),
    (3, 3,  "3 HP, 3 dmg (exactly lethal) - should trigger"),
    (4, 3,  "4 HP, 3 dmg (reduces to 1 HP, survives) - should NOT trigger"),
    (4, 4,  "4 HP, 4 dmg (exactly lethal) - should trigger"),
]

print(f"{'HP':>4} {'Dmg':>4} | {'OLD':>5} | {'NEW':>5} | Description")
print("-" * 80)

bugs_fixed = 0
for hp, dmg, desc in test_cases:
    old = try_spawn_shards_OLD(hp, dmg)
    new = try_spawn_shards_NEW(hp, dmg)
    changed = " ** BUG FIXED **" if old != new else ""
    if old != new:
        bugs_fixed += 1
    print(f"{hp:>4} {dmg:>4} | {str(old):>5} | {str(new):>5} | {desc}{changed}")

print(f"\nBugs fixed by new logic: {bugs_fixed}")
print("\nKey fix: silenced pistol (10 dmg) vs armored enemy (3-5 HP) now properly triggers armor.")
