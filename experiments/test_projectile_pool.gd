extends Node
## Test script for the ProjectilePoolManager optimization (Issue #724).
##
## This script tests and benchmarks the object pooling system for projectiles.
## It compares performance between pooled and non-pooled bullet spawning.
##
## Usage:
##   Run this script as a standalone scene or attach to a test node.
##   Results are printed to the console.

## Number of bullets to spawn in each test iteration
const BULLETS_PER_TEST: int = 100

## Number of test iterations
const TEST_ITERATIONS: int = 10

## Results storage
var results: Dictionary = {
	"pooled_times": [],
	"instantiate_times": [],
	"pooled_avg_ms": 0.0,
	"instantiate_avg_ms": 0.0,
	"speedup_factor": 0.0,
}


func _ready() -> void:
	print("=" * 60)
	print("Projectile Pool Manager Test (Issue #724)")
	print("=" * 60)
	print("")

	# Wait for pool manager to be ready
	await get_tree().process_frame

	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pool_manager == null:
		push_error("ProjectilePoolManager not found! Make sure it's registered as autoload.")
		return

	# Run warmup test
	print("1. Testing Pool Warmup...")
	test_warmup(pool_manager)

	# Run pooled spawning test
	print("")
	print("2. Testing Pooled Bullet Spawning...")
	test_pooled_spawning(pool_manager)

	# Run instantiate spawning test (for comparison)
	print("")
	print("3. Testing Traditional Instantiate Spawning (for comparison)...")
	test_instantiate_spawning()

	# Calculate and print results
	print("")
	print("=" * 60)
	print("RESULTS")
	print("=" * 60)
	print_results()


## Tests the pool warmup performance.
func test_warmup(pool_manager: Node) -> void:
	# Force re-warmup by checking stats
	var stats: Dictionary = pool_manager.get_stats()
	print("  Pool already warmed up: %s" % stats.get("is_warmed_up", false))
	print("  Warmup time: %.2f ms" % stats.get("warmup_time_ms", 0.0))
	print("  Bullets available: %d" % stats.get("bullets_available", 0))
	print("  Shrapnel available: %d" % stats.get("shrapnel_available", 0))
	print("  Breaker shrapnel available: %d" % stats.get("breaker_available", 0))


## Tests spawning bullets using the pool system.
func test_pooled_spawning(pool_manager: Node) -> void:
	var bullets: Array[Node] = []

	for iteration in range(TEST_ITERATIONS):
		var start_time := Time.get_ticks_usec()

		# Spawn bullets from pool
		for i in range(BULLETS_PER_TEST):
			var bullet: Node = pool_manager.get_bullet()
			if bullet and bullet.has_method("pool_activate"):
				# Activate with random position and direction
				var pos := Vector2(randf_range(0, 1000), randf_range(0, 1000))
				var dir := Vector2.RIGHT.rotated(randf() * TAU)
				bullet.pool_activate(pos, dir, -1, null)
				bullets.append(bullet)

		var elapsed_us := Time.get_ticks_usec() - start_time
		var elapsed_ms := elapsed_us / 1000.0
		results["pooled_times"].append(elapsed_ms)
		print("  Iteration %d: %.3f ms for %d bullets" % [iteration + 1, elapsed_ms, BULLETS_PER_TEST])

		# Return bullets to pool
		for bullet in bullets:
			if bullet.has_method("pool_deactivate"):
				bullet.pool_deactivate()
		bullets.clear()

		# Wait a frame between iterations
		await get_tree().process_frame

	# Calculate average
	var total := 0.0
	for time in results["pooled_times"]:
		total += time
	results["pooled_avg_ms"] = total / results["pooled_times"].size()
	print("  Average: %.3f ms per %d bullets" % [results["pooled_avg_ms"], BULLETS_PER_TEST])


## Tests spawning bullets using traditional instantiation.
func test_instantiate_spawning() -> void:
	var bullet_scene: PackedScene = load("res://scenes/projectiles/Bullet.tscn")
	if bullet_scene == null:
		push_error("Could not load Bullet.tscn")
		return

	var bullets: Array[Node] = []
	var container := Node.new()
	add_child(container)

	for iteration in range(TEST_ITERATIONS):
		var start_time := Time.get_ticks_usec()

		# Spawn bullets via instantiation
		for i in range(BULLETS_PER_TEST):
			var bullet := bullet_scene.instantiate()
			bullet.visible = false  # Don't render for fair comparison
			bullet.set_physics_process(false)  # Don't process for fair comparison
			container.add_child(bullet)
			bullets.append(bullet)

		var elapsed_us := Time.get_ticks_usec() - start_time
		var elapsed_ms := elapsed_us / 1000.0
		results["instantiate_times"].append(elapsed_ms)
		print("  Iteration %d: %.3f ms for %d bullets" % [iteration + 1, elapsed_ms, BULLETS_PER_TEST])

		# Cleanup
		for bullet in bullets:
			bullet.queue_free()
		bullets.clear()

		# Wait a frame between iterations
		await get_tree().process_frame

	# Cleanup container
	container.queue_free()

	# Calculate average
	var total := 0.0
	for time in results["instantiate_times"]:
		total += time
	results["instantiate_avg_ms"] = total / results["instantiate_times"].size()
	print("  Average: %.3f ms per %d bullets" % [results["instantiate_avg_ms"], BULLETS_PER_TEST])


## Prints the final comparison results.
func print_results() -> void:
	print("")
	print("Pooled spawning average:      %.3f ms" % results["pooled_avg_ms"])
	print("Instantiate spawning average: %.3f ms" % results["instantiate_avg_ms"])

	if results["pooled_avg_ms"] > 0:
		results["speedup_factor"] = results["instantiate_avg_ms"] / results["pooled_avg_ms"]
		print("")
		print("Speedup factor: %.2fx faster with pooling" % results["speedup_factor"])

	print("")
	print("Estimated max bullets at 60 FPS (16.67ms frame budget):")
	print("  With pooling: ~%d bullets/frame" % int(16.67 / (results["pooled_avg_ms"] / BULLETS_PER_TEST)))
	print("  Without pooling: ~%d bullets/frame" % int(16.67 / (results["instantiate_avg_ms"] / BULLETS_PER_TEST)))

	# Print pool stats
	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pool_manager:
		print("")
		print("Pool Statistics:")
		var stats: Dictionary = pool_manager.get_stats()
		print("  Bullets created: %d" % stats.get("bullets_created", 0))
		print("  Bullets reused: %d" % stats.get("bullets_reused", 0))
		print("  Bullets recycled: %d" % stats.get("bullets_recycled", 0))


## Run as standalone test
static func run_test() -> void:
	var test := preload("res://experiments/test_projectile_pool.gd").new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.add_child(test)
