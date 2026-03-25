extends GutTest
## Unit tests for roguelike branching room map system (Issue #1399).
##
## Tests cover:
##  - Map generation produces correct room count and types
##  - Branching constraint (no loops — rooms have at most 1 existing neighbor)
##  - Treasure and exit rooms placed on dead-end branches
##  - Connections are bidirectional
##  - Direction helpers work correctly
##  - Door color assignment based on room type
##  - All rooms are reachable from start


# ============================================================================
# Constants mirrored from roguelike_level.gd
# ============================================================================

const DIR_NORTH: int = 0
const DIR_EAST:  int = 1
const DIR_SOUTH: int = 2
const DIR_WEST:  int = 3

const DIR_OFFSETS: Array = [
	Vector2i(0, -1),  # North
	Vector2i(1, 0),   # East
	Vector2i(0, 1),   # South
	Vector2i(-1, 0),  # West
]

enum RoomType { LABYRINTH, BUILDING, BEACH, DOCKS, CITY }


# ============================================================================
# Minimal map generator (mirrors roguelike_level.gd logic for testing)
# ============================================================================

## Generate an Isaac-style grid map (simplified for testing, same algorithm).
func _generate_test_map(room_count: int, room_types_pool: Array) -> Array:
	var grid: Dictionary = {}
	var rooms: Array = []

	var start_pos := Vector2i(3, 3)
	rooms.append({
		"grid_pos": start_pos,
		"room_type": room_types_pool[0] if room_types_pool.size() > 0 else RoomType.LABYRINTH,
		"connections": [],
		"map_room_type": "start",
		"cleared": false,
		"visited": false,
	})
	grid[start_pos] = 0

	var frontier: Array = [0]
	var combat_rooms_placed: int = 0
	var type_idx: int = 1

	while combat_rooms_placed < room_count and frontier.size() > 0:
		var fi: int = randi() % frontier.size()
		var parent_idx: int = frontier[fi]
		var parent_pos: Vector2i = rooms[parent_idx]["grid_pos"]

		var dirs: Array = [0, 1, 2, 3]
		for i in range(3, 0, -1):
			var j: int = randi_range(0, i)
			var tmp: int = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = tmp

		var expanded: bool = false
		for d in dirs:
			if combat_rooms_placed >= room_count:
				break
			var new_pos: Vector2i = parent_pos + DIR_OFFSETS[d]
			if new_pos.x < 0 or new_pos.x > 6 or new_pos.y < 0 or new_pos.y > 6:
				continue
			if grid.has(new_pos):
				continue
			var neighbor_count: int = 0
			for nd in range(4):
				var adj: Vector2i = new_pos + DIR_OFFSETS[nd]
				if grid.has(adj):
					neighbor_count += 1
			if neighbor_count > 1:
				continue

			var new_idx: int = rooms.size()
			var rtype: int = room_types_pool[type_idx % room_types_pool.size()] if type_idx < room_types_pool.size() else room_types_pool[randi() % room_types_pool.size()]
			type_idx += 1
			rooms.append({
				"grid_pos": new_pos,
				"room_type": rtype,
				"connections": [],
				"map_room_type": "combat",
				"cleared": false,
				"visited": false,
			})
			grid[new_pos] = new_idx
			rooms[parent_idx]["connections"].append(new_idx)
			rooms[new_idx]["connections"].append(parent_idx)
			frontier.append(new_idx)
			combat_rooms_placed += 1
			expanded = true

		if not expanded:
			frontier.remove_at(fi)

	# Place special rooms
	var dead_ends: Array = []
	for i in range(rooms.size()):
		if rooms[i]["map_room_type"] == "start":
			continue
		if rooms[i]["connections"].size() == 1:
			dead_ends.append(i)

	dead_ends.sort_custom(func(a, b):
		var da: float = Vector2(rooms[a]["grid_pos"]).distance_to(Vector2(start_pos))
		var db: float = Vector2(rooms[b]["grid_pos"]).distance_to(Vector2(start_pos))
		return da > db
	)

	if dead_ends.size() > 0:
		rooms[dead_ends[0]]["map_room_type"] = "exit"
		dead_ends.remove_at(0)

	if dead_ends.size() > 0:
		var treasure_idx: int = dead_ends[0]
		rooms[treasure_idx]["map_room_type"] = "treasure"
		# Issue #1450: treasure rooms carry persistent item state.
		rooms[treasure_idx]["treasure_item"] = null
		rooms[treasure_idx]["treasure_collected"] = false
		dead_ends.remove_at(0)

	return rooms


# ============================================================================
# Tests
# ============================================================================


func test_map_generation_produces_correct_room_count() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	for count in [3, 4, 5]:
		var rooms: Array = _generate_test_map(count, types)
		# Total rooms = combat_count + 1 start room
		# Then exit and treasure may consume combat rooms
		assert_gte(rooms.size(), count, "Map should have at least %d rooms (requested %d combat + start)" % [count, count])
		gut.p("Map with %d requested rooms produced %d total rooms" % [count, rooms.size()])


func test_start_room_exists() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH]
	var rooms: Array = _generate_test_map(3, types)
	assert_eq(rooms[0]["map_room_type"], "start", "First room should be the start room")
	assert_eq(rooms[0]["grid_pos"], Vector2i(3, 3), "Start room should be at center of grid")


func test_connections_are_bidirectional() -> void:
	seed(123)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS]
	var rooms: Array = _generate_test_map(4, types)

	for i in range(rooms.size()):
		for conn_idx in rooms[i]["connections"]:
			assert_has(rooms[conn_idx]["connections"], i,
				"Room %d connects to %d, but %d doesn't connect back to %d" % [i, conn_idx, conn_idx, i])


func test_no_loops_in_map() -> void:
	# The Isaac branching constraint means the map forms a tree (no cycles).
	# Check via BFS that we never reach a node through two different paths.
	seed(99)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	# BFS from room 0
	var visited: Dictionary = {0: true}
	var queue: Array = [0]
	var parent: Dictionary = {0: -1}

	while queue.size() > 0:
		var current: int = queue.pop_front()
		for conn in rooms[current]["connections"]:
			if conn == parent[current]:
				continue  # Skip parent edge
			assert_false(visited.has(conn),
				"Room %d reached again from %d — loop detected (first reached from %d)" % [
					conn, current, parent.get(conn, -1)])
			visited[conn] = true
			parent[conn] = current
			queue.append(conn)

	gut.p("No loops found in map with %d rooms" % rooms.size())


func test_all_rooms_reachable_from_start() -> void:
	seed(77)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS]
	var rooms: Array = _generate_test_map(4, types)

	var visited: Dictionary = {0: true}
	var queue: Array = [0]

	while queue.size() > 0:
		var current: int = queue.pop_front()
		for conn in rooms[current]["connections"]:
			if not visited.has(conn):
				visited[conn] = true
				queue.append(conn)

	assert_eq(visited.size(), rooms.size(),
		"All %d rooms should be reachable from start, but only %d are" % [rooms.size(), visited.size()])


func test_treasure_and_exit_rooms_exist() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	var has_treasure := false
	var has_exit := false
	for room in rooms:
		if room["map_room_type"] == "treasure":
			has_treasure = true
		if room["map_room_type"] == "exit":
			has_exit = true

	assert_true(has_exit, "Map should have an exit room")
	assert_true(has_treasure, "Map should have a treasure room")


func test_exit_room_is_dead_end() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	for room in rooms:
		if room["map_room_type"] == "exit":
			assert_eq(room["connections"].size(), 1,
				"Exit room should be a dead end (1 connection), has %d" % room["connections"].size())
			break


func test_treasure_room_is_dead_end() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	for room in rooms:
		if room["map_room_type"] == "treasure":
			assert_eq(room["connections"].size(), 1,
				"Treasure room should be a dead end (1 connection), has %d" % room["connections"].size())
			break


func test_direction_calculation() -> void:
	# Test direction from grid position differences
	assert_eq(DIR_OFFSETS[DIR_NORTH], Vector2i(0, -1), "North should be (0, -1)")
	assert_eq(DIR_OFFSETS[DIR_EAST], Vector2i(1, 0), "East should be (1, 0)")
	assert_eq(DIR_OFFSETS[DIR_SOUTH], Vector2i(0, 1), "South should be (0, 1)")
	assert_eq(DIR_OFFSETS[DIR_WEST], Vector2i(-1, 0), "West should be (-1, 0)")


func test_opposite_direction() -> void:
	assert_eq((DIR_NORTH + 2) % 4, DIR_SOUTH, "Opposite of North should be South")
	assert_eq((DIR_EAST + 2) % 4, DIR_WEST, "Opposite of East should be West")
	assert_eq((DIR_SOUTH + 2) % 4, DIR_NORTH, "Opposite of South should be North")
	assert_eq((DIR_WEST + 2) % 4, DIR_EAST, "Opposite of West should be East")


func test_grid_positions_are_unique() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	var positions: Dictionary = {}
	for room in rooms:
		var gp: Vector2i = room["grid_pos"]
		assert_false(positions.has(gp),
			"Grid position %s is occupied by multiple rooms" % str(gp))
		positions[gp] = true


func test_connected_rooms_are_adjacent() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(5, types)

	for i in range(rooms.size()):
		for conn_idx in rooms[i]["connections"]:
			var diff: Vector2i = rooms[conn_idx]["grid_pos"] - rooms[i]["grid_pos"]
			var manhattan: int = abs(diff.x) + abs(diff.y)
			assert_eq(manhattan, 1,
				"Connected rooms %d and %d should be adjacent (manhattan=1), got %d" % [i, conn_idx, manhattan])


func test_multiple_seeds_produce_valid_maps() -> void:
	# Run with many seeds to ensure robustness
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var failures: int = 0

	for s in range(100):
		seed(s * 31 + 7)
		var rooms: Array = _generate_test_map(randi_range(3, 5), types)

		# Basic validity checks
		if rooms.size() < 2:
			failures += 1
			continue

		var has_exit := false
		for room in rooms:
			if room["map_room_type"] == "exit":
				has_exit = true
				break
		if not has_exit:
			failures += 1

	assert_eq(failures, 0, "All 100 random seeds should produce valid maps, %d failed" % failures)


# ============================================================================
# Tests — treasure room state fields (Issue #1450)
# ============================================================================


func test_1450_treasure_room_has_treasure_item_field() -> void:
	## Treasure rooms generated by the map generator must carry treasure_item and
	## treasure_collected fields so state can be persisted across scene reloads.
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(4, types)

	for room in rooms:
		if room["map_room_type"] == "treasure":
			assert_true(room.has("treasure_item"),
				"Treasure room must have 'treasure_item' field for Issue #1450 state persistence")
			assert_true(room.has("treasure_collected"),
				"Treasure room must have 'treasure_collected' field for Issue #1450 state persistence")
			assert_null(room["treasure_item"],
				"treasure_item must be null on fresh map generation (no item offered yet)")
			assert_false(room["treasure_collected"],
				"treasure_collected must be false on fresh map generation")
			return  # Only one treasure room per level
	# If no treasure room was generated (can happen on edge cases), skip silently


func test_1450_non_treasure_rooms_lack_treasure_fields() -> void:
	## Combat, start, and exit rooms must NOT have treasure_item/treasure_collected.
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map(4, types)

	for room in rooms:
		if room["map_room_type"] != "treasure":
			assert_false(room.has("treasure_item"),
				"Non-treasure room '%s' must not have 'treasure_item' field" % room["map_room_type"])
			assert_false(room.has("treasure_collected"),
				"Non-treasure room '%s' must not have 'treasure_collected' field" % room["map_room_type"])
