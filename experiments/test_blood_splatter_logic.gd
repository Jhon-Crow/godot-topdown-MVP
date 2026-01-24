## Experiment: Test Blood Splatter Logic
# This script tests the blood splatter spawning logic without running the full game

extends Node

func _ready():
    print("Testing blood splatter logic...")

    # Mock ImpactEffectsManager
    var impact_manager = preload("res://scripts/autoload/impact_effects_manager.gd").new()

    # Test spawning blood effect for lethal hit
    print("Testing lethal hit...")
    impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true)

    # Test spawning blood effect for non-lethal hit
    print("Testing non-lethal hit...")
    impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, false)

    print("Test completed.")