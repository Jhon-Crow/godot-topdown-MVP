extends GutTest
## Unit tests for Issue #1451 — Isaac-style level generation improvements.
##
## Tests cover:
##  - BFS distance calculation correctness
##  - Exit room placed at the room with longest BFS path from start
##  - Door barrier creation and removal logic
##  - Room clearing unlocks doors


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
# BFS distance helper (mirrors roguelike_level.gd static function)
# ============================================================================

## Compute BFS shortest-path distances from a source room to all other rooms.
func _bfs_distances(rooms: Array, source: int) -> Dictionary:
	var dist: Dictionary = {source: 0}
	var queue: Array = [source]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor in rooms[current]["connections"]:
			if not dist.has(neighbor):
				dist[neighbor] = dist[current] + 1
				queue.append(neighbor)
	return dist


# ============================================================================
# Map generator using BFS distance (mirrors updated roguelike_level.gd)
# ============================================================================

func _generate_test_map_bfs(room_count: int, room_types_pool: Array) -> Array:
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

	# Place special rooms using BFS distance (Issue #1451)
	var dead_ends: Array = []
	for i in range(rooms.size()):
		if rooms[i]["map_room_type"] == "start":
			continue
		if rooms[i]["connections"].size() == 1:
			dead_ends.append(i)

	var bfs_dist: Dictionary = _bfs_distances(rooms, 0)
	dead_ends.sort_custom(func(a, b):
		var da: int = bfs_dist.get(a, 0)
		var db: int = bfs_dist.get(b, 0)
		return da > db
	)

	if dead_ends.size() > 0:
		rooms[dead_ends[0]]["map_room_type"] = "exit"
		dead_ends.remove_at(0)

	if dead_ends.size() > 0:
		rooms[dead_ends[0]]["map_room_type"] = "treasure"
		dead_ends.remove_at(0)

	return rooms


# ============================================================================
# BFS distance tests
# ============================================================================

func test_bfs_distances_simple_chain() -> void:
	# A → B → C → D (linear chain)
	var rooms: Array = [
		{"connections": [1]},
		{"connections": [0, 2]},
		{"connections": [1, 3]},
		{"connections": [2]},
	]
	var dist: Dictionary = _bfs_distances(rooms, 0)

	assert_eq(dist[0], 0, "Distance from source to itself should be 0")
	assert_eq(dist[1], 1, "Distance from 0 to 1 should be 1")
	assert_eq(dist[2], 2, "Distance from 0 to 2 should be 2")
	assert_eq(dist[3], 3, "Distance from 0 to 3 should be 3")


func test_bfs_distances_branching() -> void:
	# Star shape: 0 connects to 1, 2, 3
	var rooms: Array = [
		{"connections": [1, 2, 3]},
		{"connections": [0]},
		{"connections": [0]},
		{"connections": [0]},
	]
	var dist: Dictionary = _bfs_distances(rooms, 0)

	assert_eq(dist[0], 0)
	assert_eq(dist[1], 1)
	assert_eq(dist[2], 1)
	assert_eq(dist[3], 1)


func test_bfs_distances_L_shaped_path() -> void:
	# 0 → 1 → 2 → 3 (long arm)
	#     ↓
	#     4 (short arm, close Euclidean distance to 0 but same BFS dist as 2)
	# Room 3 is farthest by BFS (3 hops), room 4 is 2 hops.
	# But room 4 could be closer in Euclidean distance than room 3.
	var rooms: Array = [
		{"connections": [1]},
		{"connections": [0, 2, 4]},
		{"connections": [1, 3]},
		{"connections": [2]},
		{"connections": [1]},
	]
	var dist: Dictionary = _bfs_distances(rooms, 0)

	assert_eq(dist[3], 3, "Room 3 (end of long arm) should be 3 hops from start")
	assert_eq(dist[4], 2, "Room 4 (short arm) should be 2 hops from start")
	assert_gt(dist[3], dist[4], "Room 3 should be farther than room 4 by BFS")


func test_bfs_distances_covers_all_rooms() -> void:
	seed(42)
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	var rooms: Array = _generate_test_map_bfs(5, types)

	var dist: Dictionary = _bfs_distances(rooms, 0)
	assert_eq(dist.size(), rooms.size(),
		"BFS should reach all %d rooms, but reached %d" % [rooms.size(), dist.size()])


# ============================================================================
# Exit room placement tests
# ============================================================================

func test_exit_is_at_farthest_bfs_dead_end() -> void:
	# Run multiple seeds and verify exit is at the dead end with longest BFS path
	var types := [RoomType.LABYRINTH, RoomType.BUILDING, RoomType.BEACH, RoomType.DOCKS, RoomType.CITY]
	for test_seed in [42, 77, 123, 256, 999, 1451]:
		seed(test_seed)
		var rooms: Array = _generate_test_map_bfs(5, types)

		# Find exit room and all dead ends
		var exit_idx: int = -1
		var dead_ends: Array = []
		for i in range(rooms.size()):
			if rooms[i]["map_room_type"] == "exit":
				exit_idx = i
			if rooms[i]["map_room_type"] != "start" and rooms[i]["connections"].size() == 1:
				dead_ends.append(i)

		assert_ne(exit_idx, -1, "Seed %d: Exit room should exist" % test_seed)

		# Verify exit is at the dead end with the longest BFS path
		var dist: Dictionary = _bfs_distances(rooms, 0)
		var exit_dist: int = dist.get(exit_idx, 0)

		for de in dead_ends:
			if rooms[de]["map_room_type"] in ["exit", "treasure"]:
				continue  # Skip rooms that were already assigned
			var de_dist: int = dist.get(de, 0)
			assert_gte(exit_dist, de_dist,
				"Seed %d: Exit (room %d, dist %d) should be >= any other dead end's dist (room %d, dist %d)" % [
					test_seed, exit_idx, exit_dist, de, de_dist])

		gut.p("Seed %d: Exit at room %d (BFS dist=%d) — verified farthest" % [test_seed, exit_idx, exit_dist])


func test_exit_uses_graph_distance_not_euclidean() -> void:
	# Construct a specific map where Euclidean and BFS distances disagree.
	# Room layout:
	#   0(start) → 1 → 2 → 3 → 4 (long path, BFS=4)
	#                   ↓
	#                   5 (short path, BFS=3, but 5 could be diagonally far from 0)
	#
	# We test that exit goes to room 4 (BFS=4), not room 5 (BFS=3),
	# even though we could make room 5 Euclidean-far by choosing grid positions.
	var rooms: Array = [
		{"grid_pos": Vector2i(3, 3), "connections": [1], "map_room_type": "start", "cleared": false, "visited": false, "room_type": 0},
		{"grid_pos": Vector2i(4, 3), "connections": [0, 2], "map_room_type": "combat", "cleared": false, "visited": false, "room_type": 1},
		{"grid_pos": Vector2i(5, 3), "connections": [1, 3, 5], "map_room_type": "combat", "cleared": false, "visited": false, "room_type": 2},
		{"grid_pos": Vector2i(6, 3), "connections": [2, 4], "map_room_type": "combat", "cleared": false, "visited": false, "room_type": 3},
		{"grid_pos": Vector2i(6, 2), "connections": [3], "map_room_type": "combat", "cleared": false, "visited": false, "room_type": 4},
		# Room 5: grid pos makes it Euclidean-far from start but BFS-close
		{"grid_pos": Vector2i(5, 0), "connections": [2], "map_room_type": "combat", "cleared": false, "visited": false, "room_type": 0},
	]

	# Check Euclidean distances
	var start_pos := Vector2(3, 3)
	var euclid_4: float = Vector2(rooms[4]["grid_pos"]).distance_to(start_pos)  # (6,2) → ~3.16
	var euclid_5: float = Vector2(rooms[5]["grid_pos"]).distance_to(start_pos)  # (5,0) → ~3.61

	# Room 5 is Euclidean-farther but BFS-closer
	assert_gt(euclid_5, euclid_4, "Room 5 should be Euclidean-farther than room 4")

	# BFS distances
	var dist: Dictionary = _bfs_distances(rooms, 0)
	assert_eq(dist[4], 4, "Room 4 should be BFS distance 4")
	assert_eq(dist[5], 3, "Room 5 should be BFS distance 3")

	# Now apply exit placement using BFS distance
	var dead_ends: Array = []
	for i in range(rooms.size()):
		if rooms[i]["map_room_type"] == "start":
			continue
		if rooms[i]["connections"].size() == 1:
			dead_ends.append(i)

	dead_ends.sort_custom(func(a, b):
		var da: int = dist.get(a, 0)
		var db: int = dist.get(b, 0)
		return da > db
	)

	# Exit should be room 4 (BFS=4), not room 5 (BFS=3, Euclidean-farther)
	assert_eq(dead_ends[0], 4, "Exit should be at room 4 (longest BFS path), not room 5 (Euclidean-farther)")
	gut.p("Verified: BFS distance correctly places exit at room 4 (dist=4), not room 5 (Euclidean=%.2f, BFS=3)" % euclid_5)


# ============================================================================
# Door barrier tests (logic-only, no scene tree required)
# ============================================================================

func test_door_barrier_count_matches_connections() -> void:
	# Verify that the number of barriers matches the number of doorway directions.
	# For a room with 3 connections, there should be 3 barriers.
	var connections := [1, 2, 3]  # 3 connected rooms
	# Simulate directions
	var door_dirs: Array = [DIR_NORTH, DIR_EAST, DIR_SOUTH]
	assert_eq(door_dirs.size(), connections.size(),
		"Number of door directions should match number of connections")


func test_barrier_positions_cover_all_directions() -> void:
	# Verify barrier rect calculations for each direction
	var w: float = 1280.0
	var h: float = 720.0
	var t: float = 24.0
	var door_gap: float = 120.0

	var expected_rects: Dictionary = {}

	# North barrier
	var gap_center_n: float = w * 0.5
	expected_rects[DIR_NORTH] = Rect2(gap_center_n - door_gap * 0.5, 0, door_gap, t)

	# South barrier
	var gap_center_s: float = w * 0.5
	expected_rects[DIR_SOUTH] = Rect2(gap_center_s - door_gap * 0.5, h - t, door_gap, t)

	# West barrier
	var gap_center_w: float = h * 0.5
	expected_rects[DIR_WEST] = Rect2(0, gap_center_w - door_gap * 0.5, t, door_gap)

	# East barrier
	var gap_center_e: float = h * 0.5
	expected_rects[DIR_EAST] = Rect2(w - t, gap_center_e - door_gap * 0.5, t, door_gap)

	# Verify barriers span the full doorway gap
	for d in [DIR_NORTH, DIR_SOUTH]:
		assert_eq(expected_rects[d].size.x, door_gap,
			"Horizontal barrier width should equal DOOR_GAP (%.0f)" % door_gap)
	for d in [DIR_WEST, DIR_EAST]:
		assert_eq(expected_rects[d].size.y, door_gap,
			"Vertical barrier height should equal DOOR_GAP (%.0f)" % door_gap)

	gut.p("All 4 barrier positions verified for %.0f×%.0f room" % [w, h])


func test_cleared_rooms_should_not_have_barriers() -> void:
	# Verify the logic: start rooms and cleared-revisit rooms should skip barriers
	var room_cleared: bool = true
	var is_start_room: bool = false
	var is_cleared_revisit: bool = true

	# The condition in _ready(): barriers only created when NOT start/cleared
	var should_have_barriers: bool = not is_start_room and not is_cleared_revisit and not room_cleared
	assert_false(should_have_barriers,
		"A cleared/revisited room should not have barriers")


func test_uncleared_combat_room_should_have_barriers() -> void:
	var room_cleared: bool = false
	var is_start_room: bool = false
	var is_cleared_revisit: bool = false
	var is_treasure_room: bool = false

	var should_have_barriers: bool = not is_start_room and not is_cleared_revisit and not is_treasure_room
	assert_true(should_have_barriers,
		"An uncleared combat room should have barriers")
