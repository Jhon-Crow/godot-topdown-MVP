extends GutTest
## Regression tests for Issue #1275 — navigation bake must be awaited in _ready().
##
## The _setup_navigation() function is a coroutine (it contains `await`), so
## callers in _ready() must use `await _setup_navigation()` to ensure the
## navmesh is fully baked before enemies start navigating. Without `await`,
## enemies compute paths on the un-baked navmesh (a plain rectangle with no
## wall cutouts), causing paths to go straight through walls.


## List of all level scripts that must await _setup_navigation().
const LEVEL_SCRIPTS: Array[String] = [
	"res://scripts/levels/arena_level.gd",
	"res://scripts/levels/beach_level.gd",
	"res://scripts/levels/building_level.gd",
	"res://scripts/levels/castle_level.gd",
	"res://scripts/levels/city_level.gd",
	"res://scripts/levels/decadence_level.gd",
	"res://scripts/levels/docks_level.gd",
	"res://scripts/levels/factory_level.gd",
	"res://scripts/levels/labyrinth_level.gd",
	"res://scripts/levels/labyrinth2_level.gd",
	"res://scripts/levels/revolver_level.gd",
	"res://scripts/levels/roguelike_level.gd",
	"res://scripts/levels/test_tier.gd",
]


## Every level script that calls _setup_navigation() must use `await`.
## Without await, the navmesh bake completes asynchronously AFTER enemies
## have already started navigating with the un-baked mesh (Issue #1275).
func test_all_levels_await_setup_navigation() -> void:
	for script_path in LEVEL_SCRIPTS:
		var file := FileAccess.open(script_path, FileAccess.READ)
		if file == null:
			pass_test("Script %s not accessible in test environment (OK)" % script_path)
			continue
		var content := file.get_as_text()
		file.close()

		# Find all calls to _setup_navigation() and ensure each uses await.
		# A bare call (without await) looks like: \t_setup_navigation()
		# A correct call looks like: \tawait _setup_navigation()
		var has_bare_call := false
		var lines := content.split("\n")
		for i in range(lines.size()):
			var line := lines[i].strip_edges()
			# Skip the function definition line
			if line.begins_with("func "):
				continue
			# Skip comments
			if line.begins_with("#"):
				continue
			if "_setup_navigation()" in line and "await" not in line:
				has_bare_call = true
				break

		assert_false(
			has_bare_call,
			"%s must use 'await _setup_navigation()' — not bare call (Issue #1275)" % script_path
		)


## The _setup_navigation() function must contain an await (making it a coroutine).
## This test ensures the function remains a coroutine, which would make bare calls
## a race condition if someone removes the await from the caller.
func test_setup_navigation_is_coroutine() -> void:
	for script_path in LEVEL_SCRIPTS:
		var file := FileAccess.open(script_path, FileAccess.READ)
		if file == null:
			pass_test("Script %s not accessible in test environment (OK)" % script_path)
			continue
		var content := file.get_as_text()
		file.close()

		# Extract the _setup_navigation function body
		var func_start := content.find("func _setup_navigation()")
		if func_start == -1:
			continue
		var func_body := content.substr(func_start, 1000)
		assert_true(
			"await" in func_body,
			"%s: _setup_navigation() must be a coroutine (contain await) — Issue #1275" % script_path
		)
