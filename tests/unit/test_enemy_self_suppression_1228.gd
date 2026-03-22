extends GutTest
## Unit tests for Issue #1228: enemy self-suppression fix.
##
## Verifies that enemies are NOT suppressed by their own bullets
## or bullets fired by other enemies, and ARE suppressed only by
## player-fired bullets.


# ============================================================================
# Mock Classes
# ============================================================================


class MockBullet:
	## Simulates a GDScript bullet with snake_case shooter_id property (default -1).
	extends RefCounted

	var shooter_id: int = -1
	var global_position: Vector2 = Vector2.ZERO


class MockCSharpBullet:
	## Simulates a C# Bullet with PascalCase ShooterId property (default 0, as ulong).
	## C# Bullet.cs has [Export] public ulong ShooterId — accessible via .get("ShooterId").
	extends RefCounted

	var ShooterId: int = 0  # C# ulong default is 0 (no shooter)
	var global_position: Vector2 = Vector2.ZERO


class MockNode:
	## Simulates a Node that can be in groups.
	extends RefCounted

	var _groups: Array[String] = []

	func is_in_group(group: String) -> bool:
		return group in _groups

	func add_to_group(group: String) -> void:
		if not group in _groups:
			_groups.append(group)


class MockThreatAreaLogic:
	## Simulates the _on_threat_area_entered logic from enemy.gd (Issue #1228 fix).
	##
	## This class mirrors the fixed logic:
	##   - Skip if bullet position not visible (wall blocking)
	##   - Skip if shooter is not a player (own bullet or other enemy bullet)
	##   - Add to threat sphere if shooter IS a player

	var bullets_in_threat_sphere: Array = []
	var threat_memory_timer: float = 0.0

	## Simulates a simplified visibility check — always returns true in tests
	## (we test the shooter-id logic, not the raycast logic).
	var _mock_position_visible: bool = true

	## Registry mapping instance_id -> MockNode, used to simulate instance_from_id().
	var _instance_registry: Dictionary = {}

	func register_node(instance_id: int, node: MockNode) -> void:
		_instance_registry[instance_id] = node

	func _is_position_visible(_pos: Vector2) -> bool:
		return _mock_position_visible

	func _instance_from_id(id: int) -> Object:
		if _instance_registry.has(id):
			return _instance_registry[id]
		return null

	## Mirrors the fixed _on_threat_area_entered logic.
	## Accepts either MockBullet (GDScript, shooter_id) or MockCSharpBullet (C#, ShooterId).
	func on_threat_area_entered(area: RefCounted) -> void:
		if not _is_position_visible(area.global_position):
			return  # Wall blocking — no suppression

		# Issue #1228: only suppress from player bullets.
		# Use .get() for both GDScript "shooter_id" and C# "ShooterId" — same as enemy.gd fix.
		var raw_id = area.get("shooter_id")
		if raw_id == null: raw_id = area.get("ShooterId")
		if raw_id == null:
			return  # No shooter info — safe default, no suppression
		var bullet_shooter_id: int = int(raw_id)
		if bullet_shooter_id <= 0:
			return  # -1 (GDScript default) or 0 (C# default) — no suppression
		var bullet_shooter: Object = _instance_from_id(bullet_shooter_id)
		if bullet_shooter == null or not (bullet_shooter as MockNode).is_in_group("player"):
			return  # Bullet not from player — no suppression

		bullets_in_threat_sphere.append(area)
		threat_memory_timer = 1.0  # Simulated THREAT_MEMORY_DURATION


# ============================================================================
# Test Setup
# ============================================================================


var logic: MockThreatAreaLogic
var player_node: MockNode
var enemy_node: MockNode
var other_enemy_node: MockNode

const PLAYER_ID: int = 1001
const ENEMY_ID: int = 2001
const OTHER_ENEMY_ID: int = 3001


func before_each() -> void:
	logic = MockThreatAreaLogic.new()

	player_node = MockNode.new()
	player_node.add_to_group("player")

	enemy_node = MockNode.new()
	enemy_node.add_to_group("enemies")

	other_enemy_node = MockNode.new()
	other_enemy_node.add_to_group("enemies")

	logic.register_node(PLAYER_ID, player_node)
	logic.register_node(ENEMY_ID, enemy_node)
	logic.register_node(OTHER_ENEMY_ID, other_enemy_node)


func after_each() -> void:
	logic = null
	player_node = null
	enemy_node = null
	other_enemy_node = null


# ============================================================================
# Tests: Own Bullet (Issue #1228 — primary bug scenario)
# ============================================================================


func test_own_bullet_does_not_suppress() -> void:
	## Enemy's own bullet must NOT cause self-suppression.
	var bullet := MockBullet.new()
	bullet.shooter_id = ENEMY_ID  # Shot by the enemy itself

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"Enemy's own bullet must NOT be added to threat sphere")
	assert_eq(logic.threat_memory_timer, 0.0,
		"Threat memory timer must NOT be set by own bullet")


# ============================================================================
# Tests: Other Enemy Bullet (Issue #1228 — secondary bug scenario)
# ============================================================================


func test_other_enemy_bullet_does_not_suppress() -> void:
	## Another enemy's bullet passing by must NOT suppress this enemy.
	var bullet := MockBullet.new()
	bullet.shooter_id = OTHER_ENEMY_ID  # Shot by a different enemy

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"Another enemy's bullet must NOT be added to threat sphere")
	assert_eq(logic.threat_memory_timer, 0.0,
		"Threat memory timer must NOT be set by friendly bullet")


# ============================================================================
# Tests: Player Bullet (correct suppression behavior)
# ============================================================================


func test_player_bullet_suppresses_enemy() -> void:
	## A bullet fired by the player MUST suppress enemies.
	var bullet := MockBullet.new()
	bullet.shooter_id = PLAYER_ID  # Shot by the player

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 1,
		"Player's bullet MUST be added to threat sphere")
	assert_gt(logic.threat_memory_timer, 0.0,
		"Threat memory timer MUST be set by player bullet")


func test_player_bullet_detected_in_sphere() -> void:
	## The added bullet should be the exact player bullet instance.
	var bullet := MockBullet.new()
	bullet.shooter_id = PLAYER_ID

	logic.on_threat_area_entered(bullet)

	assert_true(logic.bullets_in_threat_sphere.has(bullet),
		"The player bullet itself must be in the threat sphere array")


# ============================================================================
# Tests: Unknown Shooter / No Shooter ID
# ============================================================================


func test_bullet_without_shooter_id_does_not_suppress() -> void:
	## A bullet with no shooter_id property (e.g. grenade shrapnel) must not suppress.
	## Simulated by a plain RefCounted with no shooter_id property.
	## (MockBullet always has shooter_id, so we use a different approach:
	##  we set shooter_id = -1 to simulate "unset".)
	var bullet := MockBullet.new()
	bullet.shooter_id = -1  # Default / unset

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"Bullet with unset shooter_id must NOT suppress enemy")


func test_bullet_with_null_shooter_does_not_suppress() -> void:
	## A bullet whose shooter no longer exists (freed node) must not suppress.
	var bullet := MockBullet.new()
	bullet.shooter_id = 9999  # ID not registered — simulates freed node

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"Bullet from freed/unknown node must NOT suppress enemy")


# ============================================================================
# Tests: Wall Blocking
# ============================================================================


func test_wall_blocking_prevents_suppression() -> void:
	## Even a player bullet is ignored when it is behind a wall.
	logic._mock_position_visible = false
	var bullet := MockBullet.new()
	bullet.shooter_id = PLAYER_ID

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"Bullet behind a wall must NOT suppress enemy (regardless of shooter)")


# ============================================================================
# Tests: Multiple Bullets
# ============================================================================


func test_multiple_player_bullets_all_suppress() -> void:
	## Multiple player bullets all add to the threat sphere.
	for _i in range(3):
		var bullet := MockBullet.new()
		bullet.shooter_id = PLAYER_ID
		logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 3,
		"All three player bullets must be in the threat sphere")


func test_mix_of_bullets_only_player_suppresses() -> void:
	## Mix of own, enemy, and player bullets — only player bullets should suppress.
	var own_bullet := MockBullet.new()
	own_bullet.shooter_id = ENEMY_ID

	var other_enemy_bullet := MockBullet.new()
	other_enemy_bullet.shooter_id = OTHER_ENEMY_ID

	var player_bullet := MockBullet.new()
	player_bullet.shooter_id = PLAYER_ID

	logic.on_threat_area_entered(own_bullet)
	logic.on_threat_area_entered(other_enemy_bullet)
	logic.on_threat_area_entered(player_bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 1,
		"Only the player bullet must be in the threat sphere (1 out of 3)")
	assert_true(logic.bullets_in_threat_sphere.has(player_bullet),
		"The sole entry must be the player bullet")


# ============================================================================
# Tests: C# Bullets (Issue #1228 follow-up — PascalCase ShooterId interop)
# ============================================================================


func test_csharp_player_bullet_suppresses_enemy() -> void:
	## C# Bullet fired by the player (ShooterId = player instance ID) MUST suppress.
	## Mirrors C# Bullet.cs with [Export] public ulong ShooterId set by BaseWeapon.cs.
	var bullet := MockCSharpBullet.new()
	bullet.ShooterId = PLAYER_ID  # C# [Export] ulong — accessed via .get("ShooterId")

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 1,
		"C# player bullet (ShooterId) MUST suppress the enemy")
	assert_gt(logic.threat_memory_timer, 0.0,
		"Threat memory timer MUST be set by C# player bullet")


func test_csharp_enemy_bullet_does_not_suppress() -> void:
	## C# Bullet fired by an enemy (ShooterId = enemy instance ID) must NOT suppress.
	var bullet := MockCSharpBullet.new()
	bullet.ShooterId = ENEMY_ID

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"C# enemy bullet (ShooterId) must NOT suppress")


func test_csharp_bullet_default_shooter_id_zero_does_not_suppress() -> void:
	## C# Bullet with ShooterId = 0 (default, unset) must NOT suppress.
	var bullet := MockCSharpBullet.new()
	bullet.ShooterId = 0  # ulong default — no valid shooter

	logic.on_threat_area_entered(bullet)

	assert_eq(logic.bullets_in_threat_sphere.size(), 0,
		"C# bullet with ShooterId=0 (default/unset) must NOT suppress")
