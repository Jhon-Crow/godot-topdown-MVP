extends Node
## Autoload singleton for managing game audio.
##
## Provides centralized sound playback with support for:
## - Random sound selection from arrays (for variety)
## - Volume control
## - Positional audio (2D)
## - Dynamic audio pool expansion (Issue #73)
## - Priority-based voice management (critical sounds never cut off)

## Sound priority levels for voice stealing.
## Higher priority sounds won't be cut off by lower priority ones.
enum SoundPriority {
	CRITICAL = 0,  ## Never cut off (player shooting, reloading)
	HIGH = 1,      ## Cut off last (enemy shooting, explosions)
	MEDIUM = 2,    ## Normal (bullet impacts)
	LOW = 3        ## Cut off first (shell casings, ambient)
}

## Sound file paths organized by category.
## M16 single shots (1, 2, 3) - randomly selected for variety.
const M16_SHOTS: Array[String] = [
	"res://assets/audio/m16 1.wav",
	"res://assets/audio/m16 2.wav",
	"res://assets/audio/m16 3.wav"
]

## M16 double shot sounds for burst fire (first two bullets).
const M16_DOUBLE_SHOTS: Array[String] = [
	"res://assets/audio/m16 два выстрела подряд.wav",
	"res://assets/audio/m16  два выстрела подряд 2.wav"
]

## M16 bolt cycling sounds (for reload finish).
const M16_BOLT_SOUNDS: Array[String] = [
	"res://assets/audio/взвод затвора m16 1.wav",
	"res://assets/audio/взвод затвора m16 2.wav",
	"res://assets/audio/взвод затвора m16 3.wav",
	"res://assets/audio/взвод затвора m16 4.wav"
]

## Reload sounds.
const RELOAD_MAG_OUT: String = "res://assets/audio/игрок достал магазин (первая фаза перезарядки).wav"
const RELOAD_MAG_IN: String = "res://assets/audio/игрок вставил магазин (вторая фаза перезарядки).wav"
const RELOAD_FULL: String = "res://assets/audio/полная зарядка m16.wav"

## Pistol bolt sound (for pistol or generic bolt).
const PISTOL_BOLT: String = "res://assets/audio/взвод затвора пистолета.wav"

## Empty gun click sound (used for all weapons when out of ammo).
const EMPTY_GUN_CLICK: String = "res://assets/audio/кончились патроны в пистолете.wav"

## Hit sounds.
const HIT_LETHAL: String = "res://assets/audio/звук смертельного попадания.wav"
const HIT_NON_LETHAL: String = "res://assets/audio/звук попадания не смертельного попадания.wav"

## Bullet impact sounds.
const BULLET_WALL_HIT: String = "res://assets/audio/пуля попала в стену или укрытие (сделать по тише).wav"
const BULLET_NEAR_PLAYER: String = "res://assets/audio/пуля пролетела рядом с игроком.wav"
const BULLET_COVER_NEAR_PLAYER: String = "res://assets/audio/попадание пули в укрытие рядом с игроком.wav"

## Ricochet sounds array for variety.
## Uses fallback sounds until dedicated ricochet files (рикошет 1-4.mp3) are added.
## When ricochet sounds are added, update the paths to:
## "res://assets/audio/рикошет 1.mp3", "res://assets/audio/рикошет 2.mp3", etc.
const BULLET_RICOCHET_SOUNDS: Array[String] = [
	"res://assets/audio/пуля пролетела рядом с игроком.wav",
	"res://assets/audio/попадание пули в укрытие рядом с игроком.wav"
]

## Legacy single ricochet sound path (for backward compatibility).
const BULLET_RICOCHET: String = "res://assets/audio/пуля пролетела рядом с игроком.wav"

## Shell casing sounds.
const SHELL_RIFLE: String = "res://assets/audio/падает гильза автомата.wav"
const SHELL_PISTOL: String = "res://assets/audio/падает гильза пистолета.wav"
const SHELL_SHOTGUN: String = "res://assets/audio/падение гильзы дробовик.mp3"

## Shotgun sounds.
## Shotgun shots (4 variants) - randomly selected for variety.
const SHOTGUN_SHOTS: Array[String] = [
	"res://assets/audio/выстрел из дробовика 1.wav",
	"res://assets/audio/выстрел из дробовика 2.wav",
	"res://assets/audio/выстрел из дробовика 3.wav",
	"res://assets/audio/выстрел из дробовика 4.wav"
]

## Shotgun action sounds (pump-action open/close).
const SHOTGUN_ACTION_OPEN: String = "res://assets/audio/открытие затвора дробовика.wav"
const SHOTGUN_ACTION_CLOSE: String = "res://assets/audio/закрытие затвора дробовика.wav"

## Shotgun empty click sound.
const SHOTGUN_EMPTY_CLICK: String = "res://assets/audio/выстрел без патронов дробовик.mp3"

## Shotgun reload (load single shell) sound.
const SHOTGUN_LOAD_SHELL: String = "res://assets/audio/зарядил один патрон в дробовик.mp3"

## Silenced pistol shot sounds (very quiet suppressed shots).
## Three variants for variety, randomly selected during playback.
const SILENCED_SHOTS: Array[String] = [
	"res://assets/audio/выстрел пистолета с глушителем 1.mp3",
	"res://assets/audio/выстрел пистолета с глушителем 2.mp3",
	"res://assets/audio/выстрел пистолета с глушителем 3.mp3"
]

## Volume for silenced shots (very quiet).
const VOLUME_SILENCED_SHOT: float = -18.0

## Grenade sounds.
## Activation sound (pin pull) - played when grenade timer starts.
const GRENADE_ACTIVATION: String = "res://assets/audio/выдернут чека (активирована) короткая версия.wav"
## Throw sound - played when grenade is thrown (LMB released).
const GRENADE_THROW: String = "res://assets/audio/звук броска гранаты (в момент отпускания LMB).wav"
## Wall collision sound - played when grenade hits a wall.
const GRENADE_WALL_HIT: String = "res://assets/audio/граната столкнулась со стеной.wav"
## Landing sound - played when grenade comes to rest on the ground.
const GRENADE_LANDING: String = "res://assets/audio/приземление гранаты.wav"
## Flashbang explosion sound when player is in the affected zone.
const FLASHBANG_EXPLOSION_IN_ZONE: String = "res://assets/audio/взрыв светошумовой гранаты игрок в зоне поражения.wav"
## Flashbang explosion sound when player is outside the affected zone.
const FLASHBANG_EXPLOSION_OUT_ZONE: String = "res://assets/audio/взрыв светошумовой гранаты игрок вне зоны поражения.wav"

## Volume settings (in dB).
const VOLUME_SHOT: float = -5.0
const VOLUME_RELOAD: float = -3.0
const VOLUME_IMPACT: float = -8.0
const VOLUME_HIT: float = -3.0
const VOLUME_SHELL: float = -10.0
const VOLUME_EMPTY_CLICK: float = -3.0
const VOLUME_RICOCHET: float = -6.0
const VOLUME_GRENADE: float = -3.0
const VOLUME_GRENADE_EXPLOSION: float = 0.0
const VOLUME_SHOTGUN_SHOT: float = -3.0
const VOLUME_SHOTGUN_ACTION: float = -5.0

## Preloaded audio streams cache.
var _audio_cache: Dictionary = {}

## Pool of AudioStreamPlayer nodes for non-positional sounds.
var _audio_pool: Array[AudioStreamPlayer] = []

## Pool of AudioStreamPlayer2D nodes for positional sounds.
var _audio_2d_pool: Array[AudioStreamPlayer2D] = []

## Minimum pool size (preallocated at startup).
const MIN_POOL_SIZE: int = 16

## Maximum pool size (hard limit to prevent memory issues).
## Set to -1 for truly unlimited (not recommended).
const MAX_POOL_SIZE: int = 128

## Legacy constant for backward compatibility.
const POOL_SIZE: int = MIN_POOL_SIZE

## Tracks currently playing sounds with their priorities for 2D audio.
## Key: AudioStreamPlayer2D instance, Value: Dictionary with priority and start_time.
var _playing_sounds_2d: Dictionary = {}

## Tracks currently playing sounds with their priorities for non-positional audio.
## Key: AudioStreamPlayer instance, Value: Dictionary with priority and start_time.
var _playing_sounds: Dictionary = {}

## Timer for cleanup of idle audio players.
var _cleanup_timer: float = 0.0

## Interval for cleanup of idle audio players (in seconds).
const CLEANUP_INTERVAL: float = 5.0

## Enable debug logging for audio pool management.
var _debug_logging: bool = false


func _ready() -> void:
	_create_audio_pools()
	_preload_all_sounds()


func _process(delta: float) -> void:
	# Periodically clean up idle audio players that exceed MIN_POOL_SIZE
	_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		_cleanup_idle_players()


## Creates pools of audio players for efficient sound playback.
func _create_audio_pools() -> void:
	for i in range(MIN_POOL_SIZE):
		_create_audio_player()
		_create_audio_player_2d()


## Creates a new non-positional audio player and adds it to the pool.
func _create_audio_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)
	_audio_pool.append(player)
	if _debug_logging:
		print("[AudioManager] Created non-positional player, pool size: ", _audio_pool.size())
	return player


## Creates a new positional audio player and adds it to the pool.
func _create_audio_player_2d() -> AudioStreamPlayer2D:
	var player_2d := AudioStreamPlayer2D.new()
	player_2d.bus = "Master"
	player_2d.max_distance = 2000.0
	add_child(player_2d)
	_audio_2d_pool.append(player_2d)
	if _debug_logging:
		print("[AudioManager] Created 2D player, pool size: ", _audio_2d_pool.size())
	return player_2d


## Cleans up idle audio players that exceed the minimum pool size.
func _cleanup_idle_players() -> void:
	# Clean up non-positional players
	while _audio_pool.size() > MIN_POOL_SIZE:
		var idle_player: AudioStreamPlayer = null
		for i in range(_audio_pool.size() - 1, MIN_POOL_SIZE - 1, -1):
			if not _audio_pool[i].playing:
				idle_player = _audio_pool[i]
				_audio_pool.remove_at(i)
				_playing_sounds.erase(idle_player)
				idle_player.queue_free()
				if _debug_logging:
					print("[AudioManager] Cleaned up idle non-positional player, pool size: ", _audio_pool.size())
				break
		if idle_player == null:
			break  # No idle players found above MIN_POOL_SIZE

	# Clean up 2D players
	while _audio_2d_pool.size() > MIN_POOL_SIZE:
		var idle_player: AudioStreamPlayer2D = null
		for i in range(_audio_2d_pool.size() - 1, MIN_POOL_SIZE - 1, -1):
			if not _audio_2d_pool[i].playing:
				idle_player = _audio_2d_pool[i]
				_audio_2d_pool.remove_at(i)
				_playing_sounds_2d.erase(idle_player)
				idle_player.queue_free()
				if _debug_logging:
					print("[AudioManager] Cleaned up idle 2D player, pool size: ", _audio_2d_pool.size())
				break
		if idle_player == null:
			break  # No idle players found above MIN_POOL_SIZE


## Preloads all sound files for faster playback.
func _preload_all_sounds() -> void:
	var all_sounds: Array[String] = []
	all_sounds.append_array(M16_SHOTS)
	all_sounds.append_array(M16_DOUBLE_SHOTS)
	all_sounds.append_array(M16_BOLT_SOUNDS)
	all_sounds.append(RELOAD_MAG_OUT)
	all_sounds.append(RELOAD_MAG_IN)
	all_sounds.append(RELOAD_FULL)
	all_sounds.append(PISTOL_BOLT)
	all_sounds.append(EMPTY_GUN_CLICK)
	all_sounds.append(HIT_LETHAL)
	all_sounds.append(HIT_NON_LETHAL)
	all_sounds.append(BULLET_WALL_HIT)
	all_sounds.append(BULLET_NEAR_PLAYER)
	all_sounds.append(BULLET_COVER_NEAR_PLAYER)
	all_sounds.append_array(BULLET_RICOCHET_SOUNDS)
	all_sounds.append(SHELL_RIFLE)
	all_sounds.append(SHELL_PISTOL)
	# Grenade sounds
	all_sounds.append(GRENADE_ACTIVATION)
	all_sounds.append(GRENADE_THROW)
	all_sounds.append(GRENADE_WALL_HIT)
	all_sounds.append(GRENADE_LANDING)
	all_sounds.append(FLASHBANG_EXPLOSION_IN_ZONE)
	all_sounds.append(FLASHBANG_EXPLOSION_OUT_ZONE)
	# Shotgun sounds
	all_sounds.append_array(SHOTGUN_SHOTS)
	all_sounds.append(SHOTGUN_ACTION_OPEN)
	all_sounds.append(SHOTGUN_ACTION_CLOSE)
	all_sounds.append(SHOTGUN_EMPTY_CLICK)
	all_sounds.append(SHOTGUN_LOAD_SHELL)
	all_sounds.append(SHELL_SHOTGUN)
	# Silenced weapon sounds
	all_sounds.append_array(SILENCED_SHOTS)

	for path in all_sounds:
		if not _audio_cache.has(path):
			var stream := load(path) as AudioStream
			if stream:
				_audio_cache[path] = stream


## Gets an available non-positional audio player from the pool.
## Uses LOW priority by default for backward compatibility.
func _get_available_player() -> AudioStreamPlayer:
	return _get_available_player_with_priority(SoundPriority.LOW)


## Gets an available non-positional audio player with priority support.
## If no free player is available and pool can expand, creates a new one.
## If pool is at max, steals from lowest priority sound.
func _get_available_player_with_priority(priority: SoundPriority) -> AudioStreamPlayer:
	# First, try to find an available player in existing pool
	for player in _audio_pool:
		if not player.playing:
			return player

	# No available player - expand pool if allowed
	if MAX_POOL_SIZE == -1 or _audio_pool.size() < MAX_POOL_SIZE:
		return _create_audio_player()

	# Pool is at maximum - use priority-based voice stealing
	return _steal_player_by_priority(priority)


## Gets an available positional audio player from the pool.
## Uses LOW priority by default for backward compatibility.
func _get_available_player_2d() -> AudioStreamPlayer2D:
	return _get_available_player_2d_with_priority(SoundPriority.LOW)


## Gets an available positional audio player with priority support.
## If no free player is available and pool can expand, creates a new one.
## If pool is at max, steals from lowest priority sound.
func _get_available_player_2d_with_priority(priority: SoundPriority) -> AudioStreamPlayer2D:
	# First, try to find an available player in existing pool
	for player in _audio_2d_pool:
		if not player.playing:
			return player

	# No available player - expand pool if allowed
	if MAX_POOL_SIZE == -1 or _audio_2d_pool.size() < MAX_POOL_SIZE:
		return _create_audio_player_2d()

	# Pool is at maximum - use priority-based voice stealing
	return _steal_player_2d_by_priority(priority)


## Steals a non-positional player from a lower priority sound.
## Returns the first player if no lower priority sound is found.
func _steal_player_by_priority(new_priority: SoundPriority) -> AudioStreamPlayer:
	var best_victim: AudioStreamPlayer = null
	var best_victim_priority: SoundPriority = SoundPriority.CRITICAL
	var best_victim_start_time: float = INF

	for player in _audio_pool:
		if not _playing_sounds.has(player):
			continue

		var sound_info: Dictionary = _playing_sounds[player]
		var sound_priority: SoundPriority = sound_info.get("priority", SoundPriority.LOW)
		var start_time: float = sound_info.get("start_time", 0.0)

		# Look for lower priority sounds (higher enum value = lower priority)
		if sound_priority > best_victim_priority:
			best_victim = player
			best_victim_priority = sound_priority
			best_victim_start_time = start_time
		elif sound_priority == best_victim_priority and start_time < best_victim_start_time:
			# Same priority - steal older sound
			best_victim = player
			best_victim_start_time = start_time

	# Only steal if victim has lower priority than new sound
	if best_victim != null and best_victim_priority >= new_priority:
		if _debug_logging:
			print("[AudioManager] Stealing from priority ", best_victim_priority, " for priority ", new_priority)
		return best_victim

	# Cannot steal higher priority sounds - return first player as fallback
	if _debug_logging:
		print("[AudioManager] Cannot steal - all sounds are higher priority, using first player")
	return _audio_pool[0]


## Steals a 2D player from a lower priority sound.
## Returns the first player if no lower priority sound is found.
func _steal_player_2d_by_priority(new_priority: SoundPriority) -> AudioStreamPlayer2D:
	var best_victim: AudioStreamPlayer2D = null
	var best_victim_priority: SoundPriority = SoundPriority.CRITICAL
	var best_victim_start_time: float = INF

	for player in _audio_2d_pool:
		if not _playing_sounds_2d.has(player):
			continue

		var sound_info: Dictionary = _playing_sounds_2d[player]
		var sound_priority: SoundPriority = sound_info.get("priority", SoundPriority.LOW)
		var start_time: float = sound_info.get("start_time", 0.0)

		# Look for lower priority sounds (higher enum value = lower priority)
		if sound_priority > best_victim_priority:
			best_victim = player
			best_victim_priority = sound_priority
			best_victim_start_time = start_time
		elif sound_priority == best_victim_priority and start_time < best_victim_start_time:
			# Same priority - steal older sound
			best_victim = player
			best_victim_start_time = start_time

	# Only steal if victim has lower priority than new sound
	if best_victim != null and best_victim_priority >= new_priority:
		if _debug_logging:
			print("[AudioManager] Stealing 2D from priority ", best_victim_priority, " for priority ", new_priority)
		return best_victim

	# Cannot steal higher priority sounds - return first player as fallback
	if _debug_logging:
		print("[AudioManager] Cannot steal 2D - all sounds are higher priority, using first player")
	return _audio_2d_pool[0]


## Registers a playing sound with its priority for tracking.
func _register_playing_sound(player: AudioStreamPlayer, priority: SoundPriority) -> void:
	_playing_sounds[player] = {
		"priority": priority,
		"start_time": Time.get_ticks_msec() / 1000.0
	}


## Registers a playing 2D sound with its priority for tracking.
func _register_playing_sound_2d(player: AudioStreamPlayer2D, priority: SoundPriority) -> void:
	_playing_sounds_2d[player] = {
		"priority": priority,
		"start_time": Time.get_ticks_msec() / 1000.0
	}


## Gets or loads an audio stream from cache.
func _get_stream(path: String) -> AudioStream:
	if _audio_cache.has(path):
		return _audio_cache[path]

	var stream := load(path) as AudioStream
	if stream:
		_audio_cache[path] = stream
	return stream


## Plays a non-positional sound with default LOW priority.
func play_sound(path: String, volume_db: float = 0.0) -> void:
	play_sound_with_priority(path, volume_db, SoundPriority.LOW)


## Plays a non-positional sound with specified priority.
func play_sound_with_priority(path: String, volume_db: float, priority: SoundPriority) -> void:
	var stream := _get_stream(path)
	if stream == null:
		push_warning("AudioManager: Could not load sound: " + path)
		return

	var player := _get_available_player_with_priority(priority)
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	_register_playing_sound(player, priority)


## Plays a positional 2D sound at the given position with default LOW priority.
func play_sound_2d(path: String, position: Vector2, volume_db: float = 0.0) -> void:
	play_sound_2d_with_priority(path, position, volume_db, SoundPriority.LOW)


## Plays a positional 2D sound at the given position with specified priority.
func play_sound_2d_with_priority(path: String, position: Vector2, volume_db: float, priority: SoundPriority) -> void:
	var stream := _get_stream(path)
	if stream == null:
		push_warning("AudioManager: Could not load sound: " + path)
		return

	var player := _get_available_player_2d_with_priority(priority)
	player.stream = stream
	player.volume_db = volume_db
	player.global_position = position
	player.play()
	_register_playing_sound_2d(player, priority)


## Plays a random sound from an array of paths with default LOW priority.
func play_random_sound(paths: Array, volume_db: float = 0.0) -> void:
	play_random_sound_with_priority(paths, volume_db, SoundPriority.LOW)


## Plays a random sound from an array of paths with specified priority.
func play_random_sound_with_priority(paths: Array, volume_db: float, priority: SoundPriority) -> void:
	if paths.is_empty():
		return
	var path: String = paths[randi() % paths.size()]
	play_sound_with_priority(path, volume_db, priority)


## Plays a random positional 2D sound from an array of paths with default LOW priority.
func play_random_sound_2d(paths: Array, position: Vector2, volume_db: float = 0.0) -> void:
	play_random_sound_2d_with_priority(paths, position, volume_db, SoundPriority.LOW)


## Plays a random positional 2D sound from an array of paths with specified priority.
func play_random_sound_2d_with_priority(paths: Array, position: Vector2, volume_db: float, priority: SoundPriority) -> void:
	if paths.is_empty():
		return
	var path: String = paths[randi() % paths.size()]
	play_sound_2d_with_priority(path, position, volume_db, priority)


# ============================================================================
# Convenience methods for specific game sounds
# ============================================================================
# Priority assignments:
# - CRITICAL: Player shooting, reloading (must never be cut off)
# - HIGH: Enemy shooting, explosions, hit sounds
# - MEDIUM: Bullet impacts, ricochets
# - LOW: Shell casings (can be cut off if needed)
# ============================================================================

## Plays a random M16 shot sound at the given position.
## Uses CRITICAL priority for player shooting sounds.
func play_m16_shot(position: Vector2) -> void:
	play_random_sound_2d_with_priority(M16_SHOTS, position, VOLUME_SHOT, SoundPriority.CRITICAL)


## Plays M16 double shot sound (for burst fire) at the given position.
## Uses CRITICAL priority for player shooting sounds.
func play_m16_double_shot(position: Vector2) -> void:
	play_random_sound_2d_with_priority(M16_DOUBLE_SHOTS, position, VOLUME_SHOT, SoundPriority.CRITICAL)


## Plays a random M16 bolt cycling sound at the given position.
## Uses CRITICAL priority for reload sounds.
func play_m16_bolt(position: Vector2) -> void:
	play_random_sound_2d_with_priority(M16_BOLT_SOUNDS, position, VOLUME_RELOAD, SoundPriority.CRITICAL)


## Plays magazine removal sound (first phase of reload).
## Uses CRITICAL priority for reload sounds.
func play_reload_mag_out(position: Vector2) -> void:
	play_sound_2d_with_priority(RELOAD_MAG_OUT, position, VOLUME_RELOAD, SoundPriority.CRITICAL)


## Plays magazine insertion sound (second phase of reload).
## Uses CRITICAL priority for reload sounds.
func play_reload_mag_in(position: Vector2) -> void:
	play_sound_2d_with_priority(RELOAD_MAG_IN, position, VOLUME_RELOAD, SoundPriority.CRITICAL)


## Plays full reload sound.
## Uses CRITICAL priority for reload sounds.
func play_reload_full(position: Vector2) -> void:
	play_sound_2d_with_priority(RELOAD_FULL, position, VOLUME_RELOAD, SoundPriority.CRITICAL)


## Plays empty gun click sound.
## Uses CRITICAL priority for player feedback sounds.
func play_empty_click(position: Vector2) -> void:
	play_sound_2d_with_priority(EMPTY_GUN_CLICK, position, VOLUME_EMPTY_CLICK, SoundPriority.CRITICAL)


## Plays lethal hit sound at the given position.
## Uses HIGH priority for hit feedback.
func play_hit_lethal(position: Vector2) -> void:
	play_sound_2d_with_priority(HIT_LETHAL, position, VOLUME_HIT, SoundPriority.HIGH)


## Plays non-lethal hit sound at the given position.
## Uses HIGH priority for hit feedback.
func play_hit_non_lethal(position: Vector2) -> void:
	play_sound_2d_with_priority(HIT_NON_LETHAL, position, VOLUME_HIT, SoundPriority.HIGH)


## Plays bullet wall impact sound at the given position.
## Uses MEDIUM priority for impact sounds.
func play_bullet_wall_hit(position: Vector2) -> void:
	play_sound_2d_with_priority(BULLET_WALL_HIT, position, VOLUME_IMPACT, SoundPriority.MEDIUM)


## Plays bullet near player sound (bullet flew close to player).
## Uses HIGH priority for player awareness.
func play_bullet_near_player(position: Vector2) -> void:
	play_sound_2d_with_priority(BULLET_NEAR_PLAYER, position, VOLUME_IMPACT, SoundPriority.HIGH)


## Plays bullet hitting cover near player sound.
## Uses HIGH priority for player awareness.
func play_bullet_cover_near_player(position: Vector2) -> void:
	play_sound_2d_with_priority(BULLET_COVER_NEAR_PLAYER, position, VOLUME_IMPACT, SoundPriority.HIGH)


## Plays rifle shell casing sound at the given position.
## Uses LOW priority - can be cut off if needed.
func play_shell_rifle(position: Vector2) -> void:
	play_sound_2d_with_priority(SHELL_RIFLE, position, VOLUME_SHELL, SoundPriority.LOW)


## Plays pistol shell casing sound at the given position.
## Uses LOW priority - can be cut off if needed.
func play_shell_pistol(position: Vector2) -> void:
	play_sound_2d_with_priority(SHELL_PISTOL, position, VOLUME_SHELL, SoundPriority.LOW)


## Plays a random bullet ricochet sound at the given position.
## The ricochet sound is a distinct whizzing/buzzing sound when a bullet
## bounces off a hard surface like concrete or metal.
## Uses random selection from BULLET_RICOCHET_SOUNDS for variety.
## Uses MEDIUM priority for impact sounds.
func play_bullet_ricochet(position: Vector2) -> void:
	play_random_sound_2d_with_priority(BULLET_RICOCHET_SOUNDS, position, VOLUME_RICOCHET, SoundPriority.MEDIUM)


# ============================================================================
# Grenade sounds
# ============================================================================

## Plays grenade activation sound (pin pull) at the given position.
## Uses CRITICAL priority for player action feedback.
func play_grenade_activation(position: Vector2) -> void:
	play_sound_2d_with_priority(GRENADE_ACTIVATION, position, VOLUME_GRENADE, SoundPriority.CRITICAL)


## Plays grenade throw sound (when LMB is released) at the given position.
## Uses CRITICAL priority for player action feedback.
func play_grenade_throw(position: Vector2) -> void:
	play_sound_2d_with_priority(GRENADE_THROW, position, VOLUME_GRENADE, SoundPriority.CRITICAL)


## Plays grenade wall collision sound at the given position.
## Uses MEDIUM priority for impact sounds.
func play_grenade_wall_hit(position: Vector2) -> void:
	play_sound_2d_with_priority(GRENADE_WALL_HIT, position, VOLUME_GRENADE, SoundPriority.MEDIUM)


## Plays grenade landing sound at the given position.
## Uses MEDIUM priority for impact sounds.
func play_grenade_landing(position: Vector2) -> void:
	play_sound_2d_with_priority(GRENADE_LANDING, position, VOLUME_GRENADE, SoundPriority.MEDIUM)


## Plays flashbang explosion sound based on whether player is in the affected zone.
## @param position: Position of the explosion.
## @param player_in_zone: True if player is within the flashbang effect radius.
## Uses HIGH priority for explosion sounds.
func play_flashbang_explosion(position: Vector2, player_in_zone: bool) -> void:
	var sound_path: String = FLASHBANG_EXPLOSION_IN_ZONE if player_in_zone else FLASHBANG_EXPLOSION_OUT_ZONE
	play_sound_2d_with_priority(sound_path, position, VOLUME_GRENADE_EXPLOSION, SoundPriority.HIGH)


# ============================================================================
# Shotgun sounds
# ============================================================================

## Plays a random shotgun shot sound at the given position.
## Randomly selects from 4 shotgun shot variants for variety.
## Uses CRITICAL priority for player shooting sounds.
func play_shotgun_shot(position: Vector2) -> void:
	play_random_sound_2d_with_priority(SHOTGUN_SHOTS, position, VOLUME_SHOTGUN_SHOT, SoundPriority.CRITICAL)


## Plays shotgun action open sound (pump-action pulling back) at the given position.
## Uses CRITICAL priority for player action feedback.
func play_shotgun_action_open(position: Vector2) -> void:
	play_sound_2d_with_priority(SHOTGUN_ACTION_OPEN, position, VOLUME_SHOTGUN_ACTION, SoundPriority.CRITICAL)


## Plays shotgun action close sound (pump-action pushing forward) at the given position.
## Uses CRITICAL priority for player action feedback.
func play_shotgun_action_close(position: Vector2) -> void:
	play_sound_2d_with_priority(SHOTGUN_ACTION_CLOSE, position, VOLUME_SHOTGUN_ACTION, SoundPriority.CRITICAL)


## Plays shotgun shell casing drop sound at the given position.
## Uses LOW priority - can be cut off if needed.
func play_shell_shotgun(position: Vector2) -> void:
	play_sound_2d_with_priority(SHELL_SHOTGUN, position, VOLUME_SHELL, SoundPriority.LOW)


## Plays shotgun empty click sound at the given position.
## Uses CRITICAL priority for player feedback.
func play_shotgun_empty_click(position: Vector2) -> void:
	play_sound_2d_with_priority(SHOTGUN_EMPTY_CLICK, position, VOLUME_EMPTY_CLICK, SoundPriority.CRITICAL)


## Plays shotgun shell loading sound at the given position.
## Uses CRITICAL priority for reload sounds.
func play_shotgun_load_shell(position: Vector2) -> void:
	play_sound_2d_with_priority(SHOTGUN_LOAD_SHELL, position, VOLUME_SHOTGUN_ACTION, SoundPriority.CRITICAL)


# ============================================================================
# Silenced weapon sounds
# ============================================================================

## Plays a random silenced pistol shot sound at the given position.
## This is a very quiet sound that simulates a suppressed shot.
## The sound is only audible at close range and does not alert distant enemies.
## Randomly selects from 3 silenced pistol shot variants for variety.
## Uses CRITICAL priority for player shooting sounds.
func play_silenced_shot(position: Vector2) -> void:
	play_random_sound_2d_with_priority(SILENCED_SHOTS, position, VOLUME_SILENCED_SHOT, SoundPriority.CRITICAL)


# ============================================================================
# Debug and utility methods
# ============================================================================

## Enables or disables debug logging for audio pool management.
func set_debug_logging(enabled: bool) -> void:
	_debug_logging = enabled


## Returns the current size of the non-positional audio pool.
func get_pool_size() -> int:
	return _audio_pool.size()


## Returns the current size of the 2D audio pool.
func get_pool_2d_size() -> int:
	return _audio_2d_pool.size()


## Returns the number of currently playing non-positional sounds.
func get_playing_count() -> int:
	var count := 0
	for player in _audio_pool:
		if player.playing:
			count += 1
	return count


## Returns the number of currently playing 2D sounds.
func get_playing_2d_count() -> int:
	var count := 0
	for player in _audio_2d_pool:
		if player.playing:
			count += 1
	return count
