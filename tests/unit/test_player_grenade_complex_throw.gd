extends GutTest
## Regression tests for the complex grenade throw state machine.
##
## Covers issue #1819:
## 1. Holding G after RMB press in step 4 must not enter aiming.
## 2. Releasing G before the hand transfer is complete must drop the grenade.


class MockComplexGrenadePlayer:
	enum GrenadeState {
		Idle,
		TimerStarted,
		WaitingForGRelease,
		Aiming,
		SimpleAiming
	}

	enum GrenadeAnimPhase {
		None,
		GrabGrenade,
		PullPin,
		HandsApproach,
		Transfer,
		WindUp,
		Throw,
		ReturnIdle
	}

	var grenade_state: int = GrenadeState.Idle
	var grenade_anim_phase: int = GrenadeAnimPhase.None
	var grenade_anim_timer: float = 0.0
	var dropped_at_feet: bool = false
	var aiming_started: bool = false
	var throw_triggered: bool = false

	func handle_waiting_for_g_release(rmb_pressed: bool, g_pressed: bool) -> void:
		if not rmb_pressed:
			grenade_state = GrenadeState.TimerStarted
			return

		if not g_pressed:
			if grenade_anim_phase == GrenadeAnimPhase.HandsApproach and grenade_anim_timer > 0.0:
				drop_grenade_at_feet()
				return

			grenade_state = GrenadeState.Aiming
			grenade_anim_phase = GrenadeAnimPhase.Transfer
			aiming_started = true

	func handle_aiming_state(g_pressed: bool, rmb_just_released: bool) -> void:
		if g_pressed:
			grenade_state = GrenadeState.WaitingForGRelease
			return

		if rmb_just_released:
			throw_triggered = true

	func drop_grenade_at_feet() -> void:
		dropped_at_feet = true
		grenade_state = GrenadeState.Idle
		grenade_anim_phase = GrenadeAnimPhase.ReturnIdle


var player: MockComplexGrenadePlayer


func before_each() -> void:
	player = MockComplexGrenadePlayer.new()


func after_each() -> void:
	player = null


func test_waiting_for_g_release_does_not_aim_while_g_is_still_held() -> void:
	player.grenade_state = MockComplexGrenadePlayer.GrenadeState.WaitingForGRelease
	player.grenade_anim_phase = MockComplexGrenadePlayer.GrenadeAnimPhase.HandsApproach
	player.grenade_anim_timer = 0.2

	player.handle_waiting_for_g_release(true, true)

	assert_eq(player.grenade_state, MockComplexGrenadePlayer.GrenadeState.WaitingForGRelease)
	assert_false(player.aiming_started)
	assert_false(player.dropped_at_feet)


func test_releasing_g_before_transfer_completes_drops_grenade() -> void:
	player.grenade_state = MockComplexGrenadePlayer.GrenadeState.WaitingForGRelease
	player.grenade_anim_phase = MockComplexGrenadePlayer.GrenadeAnimPhase.HandsApproach
	player.grenade_anim_timer = 0.2

	player.handle_waiting_for_g_release(true, false)

	assert_true(player.dropped_at_feet)
	assert_eq(player.grenade_state, MockComplexGrenadePlayer.GrenadeState.Idle)
	assert_eq(player.grenade_anim_phase, MockComplexGrenadePlayer.GrenadeAnimPhase.ReturnIdle)
	assert_false(player.aiming_started)


func test_releasing_g_after_hands_meet_enters_aiming() -> void:
	player.grenade_state = MockComplexGrenadePlayer.GrenadeState.WaitingForGRelease
	player.grenade_anim_phase = MockComplexGrenadePlayer.GrenadeAnimPhase.HandsApproach
	player.grenade_anim_timer = 0.0

	player.handle_waiting_for_g_release(true, false)

	assert_true(player.aiming_started)
	assert_eq(player.grenade_state, MockComplexGrenadePlayer.GrenadeState.Aiming)
	assert_eq(player.grenade_anim_phase, MockComplexGrenadePlayer.GrenadeAnimPhase.Transfer)
	assert_false(player.dropped_at_feet)


func test_aiming_state_rejects_throw_until_g_is_released() -> void:
	player.grenade_state = MockComplexGrenadePlayer.GrenadeState.Aiming
	player.grenade_anim_phase = MockComplexGrenadePlayer.GrenadeAnimPhase.WindUp

	player.handle_aiming_state(true, true)

	assert_eq(player.grenade_state, MockComplexGrenadePlayer.GrenadeState.WaitingForGRelease)
	assert_false(player.throw_triggered)
