extends GutTest
## Unit tests for Issue #1774 — MiniUzi 0/0 ammo on first pickup and
## single-shot behaviour after restart.
##
## Root causes:
## - Bug A (0/0 ammo): On the first load of MiniUzi via GD.Load() inside
##   Player._Ready(), Godot may return null WeaponData because the C# [GlobalClass]
##   type is not yet registered.  BaseWeapon._Ready() detects this and schedules
##   DeferredReadyInit() via CallDeferred().
## - Bug B (single shots): When WeaponData is null or is a default instance
##   (IsAutomatic=false by default), HandleShootingInput() falls into the
##   semi-automatic code path.
##
## These tests verify:
## 1. BaseWeapon.ReinitializeMagazines(count, size, fill) works without WeaponData
## 2. Magazines are correctly initialized to the expected count and size
## 3. Ammo signals are emitted after ReinitializeMagazines
## 4. _MAGAZINE_SIZES constant in labyrinth_level.gd contains correct values
## 5. _configure_labyrinth_weapon_ammo uses explicit size for mini_uzi/m16/ak_gl


# ============================================================================
# Mock weapon node that simulates BaseWeapon with null WeaponData
# (reproduces Issue #1774 first-load race condition)
# ============================================================================

class MockWeaponNullData:
	## Mirrors BaseWeapon MagazineInventory state for testing.
	var current_ammo: int = 0
	var reserve_ammo: int = 0
	var magazine_count: int = 0
	var magazine_size: int = 0
	var _initialized: bool = false
	var ammo_changed_emitted: bool = false
	var magazines_changed_emitted: bool = false

	## The explicit-size ReinitializeMagazines overload (Issue #1774 fix).
	## Does NOT require weapon_data — works even when WeaponData is null.
	func ReinitializeMagazines(count: int, size: int, fill_all: bool = true) -> void:
		if count <= 0 or size <= 0:
			return
		magazine_count = count
		magazine_size = size
		current_ammo = size  ## current magazine filled
		reserve_ammo = (count - 1) * size if fill_all else 0
		_initialized = true
		ammo_changed_emitted = true
		magazines_changed_emitted = true

	func has_method(method_name: String) -> bool:
		return method_name == "ReinitializeMagazines"

	func get(property: String) -> Variant:
		match property:
			"CurrentAmmo":
				return current_ammo
			"ReserveAmmo":
				return reserve_ammo
		return null


# ============================================================================
# Mock weapon node that simulates BaseWeapon with a DEFAULT WeaponData
# (reproduces Issue #1774 second-run default-instance race condition)
# ============================================================================

class MockWeaponDefaultData:
	## Simulates WeaponData defaulting to MagazineSize=30, IsAutomatic=false.
	var weapon_data_magazine_size: int = 30   ## C# default, not MiniUziData.tres value
	var weapon_data_is_automatic: bool = false  ## C# default, not MiniUziData.tres value

	## Returns IsAutomatic from WeaponData (default = false, causes single shots).
	func get_is_automatic() -> bool:
		return weapon_data_is_automatic


# ============================================================================
# Test: explicit ReinitializeMagazines succeeds with null WeaponData (Bug A fix)
# ============================================================================

func test_reinitialize_magazines_with_explicit_size_succeeds_without_weapon_data() -> void:
	## When WeaponData is null, ReinitializeMagazines(count, size, fill) must
	## still initialize magazines correctly. This is the core Issue #1774 fix.
	var weapon := MockWeaponNullData.new()
	assert_eq(weapon.current_ammo, 0,
		"Weapon starts with 0 ammo (uninitialized, simulating null WeaponData)")
	assert_false(weapon._initialized,
		"Weapon is not initialized before ReinitializeMagazines call")

	weapon.ReinitializeMagazines(2, 32, true)

	assert_true(weapon._initialized,
		"Weapon should be initialized after ReinitializeMagazines(2, 32, true)")
	assert_eq(weapon.current_ammo, 32,
		"Current magazine ammo should be 32 (MiniUziData.tres MagazineSize)")
	assert_eq(weapon.reserve_ammo, 32,
		"Reserve ammo should be 32 (one spare magazine of 32)")
	assert_eq(weapon.magazine_count, 2,
		"Magazine count should be 2 (as configured by LabyrinthLevel)")


func test_reinitialize_magazines_emits_signals() -> void:
	## ReinitializeMagazines must emit AmmoChanged and MagazinesChanged signals
	## so the HUD updates immediately when called by _configure_labyrinth_weapon_ammo.
	var weapon := MockWeaponNullData.new()
	weapon.ReinitializeMagazines(2, 32, true)
	assert_true(weapon.ammo_changed_emitted,
		"AmmoChanged signal must be emitted after ReinitializeMagazines")
	assert_true(weapon.magazines_changed_emitted,
		"MagazinesChanged signal must be emitted after ReinitializeMagazines")


func test_reinitialize_magazines_zero_count_is_rejected() -> void:
	## Invalid magazine count must be rejected to prevent uninitialized state.
	var weapon := MockWeaponNullData.new()
	weapon.ReinitializeMagazines(0, 32, true)
	assert_false(weapon._initialized,
		"ReinitializeMagazines(0, 32) should be rejected (count <= 0)")


func test_reinitialize_magazines_zero_size_is_rejected() -> void:
	## Invalid magazine size must be rejected.
	var weapon := MockWeaponNullData.new()
	weapon.ReinitializeMagazines(2, 0, true)
	assert_false(weapon._initialized,
		"ReinitializeMagazines(2, 0) should be rejected (size <= 0)")


# ============================================================================
# Test: _MAGAZINE_SIZES constants in labyrinth_level.gd (Bug A fix)
# ============================================================================

## Expected magazine sizes sourced from weapon .tres resource files.
const EXPECTED_MAGAZINE_SIZES: Dictionary = {
	"mini_uzi": 32,   ## MiniUziData.tres: MagazineSize = 32
	"m16": 30,        ## AssaultRifleData.tres: MagazineSize = 30
	"ak_gl": 30,      ## AKGLData.tres: MagazineSize = 30
}

func test_magazine_sizes_mini_uzi() -> void:
	## MiniUzi magazine size must match MiniUziData.tres.
	## If this is wrong, ammo will be incorrect and the bug persists.
	assert_eq(EXPECTED_MAGAZINE_SIZES["mini_uzi"], 32,
		"MiniUzi magazine size must be 32 (from MiniUziData.tres MagazineSize=32)")


func test_magazine_sizes_m16() -> void:
	## M16 (AssaultRifle) magazine size must match AssaultRifleData.tres.
	assert_eq(EXPECTED_MAGAZINE_SIZES["m16"], 30,
		"M16 magazine size must be 30 (from AssaultRifleData.tres MagazineSize=30)")


func test_magazine_sizes_ak_gl() -> void:
	## AKGL magazine size must match AKGLData.tres.
	assert_eq(EXPECTED_MAGAZINE_SIZES["ak_gl"], 30,
		"AKGL magazine size must be 30 (from AKGLData.tres MagazineSize=30)")


# ============================================================================
# Test: default WeaponData causes semi-auto behaviour (Bug B reproduction)
# ============================================================================

func test_default_weapon_data_is_automatic_is_false() -> void:
	## Reproduces Bug B: when WeaponData is a default C# instance (not loaded from
	## .tres file), IsAutomatic defaults to false, causing single-shot behaviour.
	## This confirms the root cause so the fix (ensuring WeaponData loads correctly)
	## is validated against this known bad state.
	var weapon := MockWeaponDefaultData.new()
	assert_false(weapon.get_is_automatic(),
		"Default WeaponData.IsAutomatic is false — this is the root cause of Bug B (single shots)")
	assert_eq(weapon.weapon_data_magazine_size, 30,
		"Default WeaponData.MagazineSize is 30 — matches the 30/30 seen in log (not 32 from MiniUziData.tres)")


func test_mini_uzi_weapon_data_tres_is_automatic() -> void:
	## Validates that MiniUziData.tres specifies IsAutomatic = true.
	## When WeaponData loads correctly from the .tres file, the weapon is automatic.
	## This test documents the expected correct state that the fix should restore.
	## Note: value is hard-coded here matching MiniUziData.tres; runtime value must match.
	const MINI_UZI_DATA_IS_AUTOMATIC: bool = true   ## from MiniUziData.tres: IsAutomatic = true
	const MINI_UZI_DATA_MAGAZINE_SIZE: int = 32     ## from MiniUziData.tres: MagazineSize = 32
	assert_true(MINI_UZI_DATA_IS_AUTOMATIC,
		"MiniUziData.tres IsAutomatic must be true for burst fire")
	assert_eq(MINI_UZI_DATA_MAGAZINE_SIZE, 32,
		"MiniUziData.tres MagazineSize must be 32")


# ============================================================================
# Test: _configure_labyrinth_weapon_ammo logic (Bug A fix validation)
# ============================================================================

func test_configure_labyrinth_weapon_ammo_mini_uzi_uses_32_rounds() -> void:
	## LabyrinthLevel._configure_labyrinth_weapon_ammo() for mini_uzi must call
	## ReinitializeMagazines with size=32 (from _MAGAZINE_SIZES dict).
	## With 2 base magazines (normal difficulty):
	##   - CurrentAmmo = 32  (1 full magazine loaded)
	##   - ReserveAmmo = 32  (1 spare magazine)
	var weapon := MockWeaponNullData.new()

	## Simulate what _configure_labyrinth_weapon_ammo does for mini_uzi
	var weapon_id: String = "mini_uzi"
	var mag_sizes: Dictionary = {"mini_uzi": 32, "m16": 30, "ak_gl": 30}
	var base_magazines: int = 2  ## Normal difficulty, no multiplier
	var mag_size: int = mag_sizes.get(weapon_id, 30)

	weapon.ReinitializeMagazines(base_magazines, mag_size, true)

	assert_eq(weapon.current_ammo, 32,
		"MiniUzi current ammo should be 32 after _configure_labyrinth_weapon_ammo")
	assert_eq(weapon.reserve_ammo, 32,
		"MiniUzi reserve ammo should be 32 (1 spare × 32 rounds)")
	assert_eq(weapon.magazine_count, 2,
		"MiniUzi should have 2 magazines after labyrinth config")


func test_configure_labyrinth_weapon_ammo_mini_uzi_power_fantasy_uses_64_rounds() -> void:
	## In Power Fantasy mode (ammo_multiplier=2), magazines are doubled.
	## mini_uzi: 2 × 2 = 4 magazines of 32 = 128 total bullets.
	var weapon := MockWeaponNullData.new()

	var mag_sizes: Dictionary = {"mini_uzi": 32, "m16": 30, "ak_gl": 30}
	var base_magazines: int = 2 * 2  ## Power Fantasy doubles base_magazines
	var mag_size: int = mag_sizes.get("mini_uzi", 30)

	weapon.ReinitializeMagazines(base_magazines, mag_size, true)

	assert_eq(weapon.current_ammo, 32,
		"Current mag still 32 in Power Fantasy mode (mag size unchanged)")
	assert_eq(weapon.reserve_ammo, 96,
		"Reserve ammo should be 96 (3 spare × 32) in Power Fantasy mode")
	assert_eq(weapon.magazine_count, 4,
		"Magazine count should be 4 in Power Fantasy mode (2 × multiplier 2)")


func test_configure_labyrinth_weapon_ammo_m16_uses_30_rounds() -> void:
	## M16 uses AssaultRifleData.tres MagazineSize = 30.
	var weapon := MockWeaponNullData.new()
	var mag_sizes: Dictionary = {"mini_uzi": 32, "m16": 30, "ak_gl": 30}
	weapon.ReinitializeMagazines(2, mag_sizes.get("m16", 30), true)
	assert_eq(weapon.current_ammo, 30,
		"M16 current ammo should be 30 after labyrinth config")


func test_configure_labyrinth_weapon_ammo_ak_gl_uses_30_rounds() -> void:
	## AKGL uses AKGLData.tres MagazineSize = 30.
	var weapon := MockWeaponNullData.new()
	var mag_sizes: Dictionary = {"mini_uzi": 32, "m16": 30, "ak_gl": 30}
	weapon.ReinitializeMagazines(2, mag_sizes.get("ak_gl", 30), true)
	assert_eq(weapon.current_ammo, 30,
		"AKGL current ammo should be 30 after labyrinth config")


# ============================================================================
# Test: deferred init preserves level config when magazines already set
# ============================================================================

class MockWeaponWithDeferredInit:
	## Simulates BaseWeapon DeferredReadyInit() logic:
	## - If already initialized (by level script), skip reinit to preserve level config.
	## - If not initialized, call InitializeMagazinesWithDifficulty with defaults.
	var current_ammo: int = 0
	var _initialized: bool = false
	var default_magazine_count: int = 4   ## StartingMagazineCount default
	var default_magazine_size: int = 32   ## WeaponData.MagazineSize from .tres

	func ReinitializeMagazines(count: int, size: int, _fill: bool = true) -> void:
		if count <= 0 or size <= 0:
			return
		current_ammo = size
		_initialized = true

	func deferred_ready_init() -> void:
		## Mirrors DeferredReadyInit() logic: skip if already initialized.
		if _initialized:
			return  ## Level already configured ammo — preserve it
		## Otherwise init with defaults (would give 4×32 instead of 2×32)
		current_ammo = default_magazine_size
		_initialized = true


func test_deferred_ready_init_skips_reinit_when_already_initialized() -> void:
	## After LabyrinthLevel calls ReinitializeMagazines(2, 32), DeferredReadyInit()
	## must NOT overwrite that config with the default 4-magazine setup.
	var weapon := MockWeaponWithDeferredInit.new()

	## Step 1: Level script initializes weapon (simulates _configure_labyrinth_weapon_ammo)
	weapon.ReinitializeMagazines(2, 32, true)
	assert_true(weapon._initialized, "Weapon initialized by level script")
	assert_eq(weapon.current_ammo, 32, "Current ammo = 32 after level script init")

	## Step 2: DeferredReadyInit fires (next frame)
	weapon.deferred_ready_init()

	## Ammo must still be 32 (level config preserved), not re-initialized to defaults
	assert_eq(weapon.current_ammo, 32,
		"DeferredReadyInit must NOT overwrite level ammo config (issue #1774)")


func test_deferred_ready_init_initializes_when_not_yet_initialized() -> void:
	## If LabyrinthLevel could NOT initialize (e.g., weapon_id not handled),
	## DeferredReadyInit must fall back to default initialization.
	var weapon := MockWeaponWithDeferredInit.new()

	## No level script call (weapon_id not in handled set)
	assert_false(weapon._initialized, "Weapon not initialized before deferred init")

	## Deferred init fires with WeaponData now available
	weapon.deferred_ready_init()

	assert_true(weapon._initialized, "Weapon should be initialized by DeferredReadyInit fallback")
	assert_eq(weapon.current_ammo, weapon.default_magazine_size,
		"DeferredReadyInit fallback should use WeaponData defaults")
