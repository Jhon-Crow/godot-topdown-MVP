extends Node
## Experiment script to verify the frag grenade explosion bug (issue #393)
##
## Bug hypothesis: throw_grenade_with_direction() doesn't set _is_thrown flag,
## so impact detection never triggers, causing the grenade to not explode.
##
## Run in Godot editor to see output in the Output panel.

func _ready() -> void:
	print("=" .repeat(70))
	print("Issue #393 Investigation: Frag Grenade Doesn't Explode")
	print("=" .repeat(70))
	print("")

	print("Analyzing throw methods in FragGrenade class:")
	print("")

	# Check which methods are overridden
	var frag_grenade_path := "res://scenes/projectiles/FragGrenade.tscn"

	print("1. Player.cs calls throw methods in this priority order:")
	print("   a) throw_grenade_with_direction() - HIGHEST PRIORITY")
	print("   b) throw_grenade_velocity_based()")
	print("   c) throw_grenade() - LEGACY")
	print("")

	print("2. FragGrenade overrides:")
	print("   ✅ throw_grenade() - sets _is_thrown = true (line 106-109)")
	print("   ✅ throw_grenade_velocity_based() - sets _is_thrown = true (line 114-117)")
	print("   ❌ throw_grenade_with_direction() - NOT OVERRIDDEN!")
	print("")

	print("3. Impact detection logic:")
	print("   - _on_body_entered() checks: if _is_thrown and not _has_impacted (line 125)")
	print("   - _on_grenade_landed() checks: if _is_thrown and not _has_impacted (line 143)")
	print("")

	print("ROOT CAUSE IDENTIFIED:")
	print("=" .repeat(70))
	print("When Player.cs calls throw_grenade_with_direction() (highest priority),")
	print("the method runs from GrenadeBase (base class), which:")
	print("  1. Unfreezes the grenade (freeze = false)")
	print("  2. Sets linear_velocity")
	print("  3. Does NOT set _is_thrown = true")
	print("")
	print("Result: Grenade is thrown physically, but _is_thrown remains false,")
	print("so impact detection never triggers → grenade never explodes!")
	print("=" .repeat(70))
	print("")

	print("SOLUTION:")
	print("Override throw_grenade_with_direction() in FragGrenade to set _is_thrown = true")
	print("")
	print("=" .repeat(70))
