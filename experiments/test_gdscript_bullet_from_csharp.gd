extends Node2D
## Test script to verify GDScript bullet property setting from C# pattern
##
## This script simulates what C# weapon code does when spawning GDScript bullets:
## 1. Instantiate the bullet scene
## 2. Set properties via Set() with both PascalCase and snake_case
## 3. Add bullet to scene
##
## Run this script to verify bullets move correctly with properties set in
## the same order as C# weapon code.

const Bullet9mm = preload("res://scenes/projectiles/Bullet9mm.tscn")

func _ready() -> void:
	print("\n=== GDScript Bullet Property Test ===\n")

	# Test 1: Set direction and speed BEFORE adding to scene (like C# does)
	test_bullet_spawn_before_add_child()

	# Wait and then spawn another for comparison
	await get_tree().create_timer(0.5).timeout

	# Test 2: Set direction and speed AFTER adding to scene
	test_bullet_spawn_after_add_child()


func test_bullet_spawn_before_add_child() -> void:
	print("[Test 1] Setting properties BEFORE add_child()...")

	var bullet = Bullet9mm.instantiate()

	# Simulate C# weapon code pattern - try both cases
	var direction = Vector2(1, 0.5).normalized()  # Diagonal direction
	var speed = 2000.0

	# This is what C# code does
	bullet.set("Direction", direction)  # Should fail silently (PascalCase)
	bullet.set("direction", direction)   # Should succeed (snake_case)
	bullet.set("Speed", speed)           # Should fail silently (PascalCase)
	bullet.set("speed", speed)           # Should succeed (snake_case)

	# Set position
	bullet.global_position = Vector2(200, 200)

	# Now add to scene (this triggers _ready)
	add_child(bullet)

	# Check actual values
	print("  direction: ", bullet.direction)
	print("  speed: ", bullet.speed)
	print("  Expected direction: ", direction)
	print("  Expected speed: ", speed)
	print("  Match: ", bullet.direction == direction and bullet.speed == speed)
	print("")


func test_bullet_spawn_after_add_child() -> void:
	print("[Test 2] Setting properties AFTER add_child()...")

	var bullet = Bullet9mm.instantiate()
	var direction = Vector2(-1, 0.5).normalized()  # Different diagonal
	var speed = 1500.0

	# Set position first
	bullet.global_position = Vector2(200, 300)

	# Add to scene first (this triggers _ready)
	add_child(bullet)

	# Now set properties (after _ready has run)
	bullet.set("direction", direction)
	bullet.set("speed", speed)

	# Check actual values
	print("  direction: ", bullet.direction)
	print("  speed: ", bullet.speed)
	print("  Expected direction: ", direction)
	print("  Expected speed: ", speed)
	print("  Match: ", bullet.direction == direction and bullet.speed == speed)
	print("")


func _process(_delta: float) -> void:
	# Monitor bullets in scene
	var bullets = get_children().filter(func(c): return c.is_in_group("bullets") or "Bullet" in c.name)
	if bullets.size() > 0:
		for bullet in bullets:
			if bullet.has_method("get") and bullet.get("direction") != null:
				var pos = bullet.global_position
				var dir = bullet.get("direction")
				print("[Bullet] pos=", pos, " dir=", dir, " moving=", dir.length() > 0.5)
