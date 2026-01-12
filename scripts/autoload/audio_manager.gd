extends Node
## Autoload singleton for managing game audio.
##
## Provides centralized sound playback with support for:
## - Random sound selection from arrays (for variety)
## - Volume control
## - Positional audio (2D)

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

## Shell casing sounds.
const SHELL_RIFLE: String = "res://assets/audio/падает гильза автомата.wav"
const SHELL_PISTOL: String = "res://assets/audio/падает гильза пистолета.wav"

## Volume settings (in dB).
const VOLUME_SHOT: float = -5.0
const VOLUME_RELOAD: float = -3.0
const VOLUME_IMPACT: float = -8.0
const VOLUME_HIT: float = -3.0
const VOLUME_SHELL: float = -10.0
const VOLUME_EMPTY_CLICK: float = -3.0

## Preloaded audio streams cache.
var _audio_cache: Dictionary = {}

## Pool of AudioStreamPlayer nodes for non-positional sounds.
var _audio_pool: Array[AudioStreamPlayer] = []

## Pool of AudioStreamPlayer2D nodes for positional sounds.
var _audio_2d_pool: Array[AudioStreamPlayer2D] = []

## Number of audio players in each pool.
const POOL_SIZE: int = 16


func _ready() -> void:
	_create_audio_pools()
	_preload_all_sounds()


## Creates pools of audio players for efficient sound playback.
func _create_audio_pools() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_audio_pool.append(player)

		var player_2d := AudioStreamPlayer2D.new()
		player_2d.bus = "Master"
		player_2d.max_distance = 2000.0
		add_child(player_2d)
		_audio_2d_pool.append(player_2d)


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
	all_sounds.append(SHELL_RIFLE)
	all_sounds.append(SHELL_PISTOL)

	for path in all_sounds:
		if not _audio_cache.has(path):
			var stream := load(path) as AudioStream
			if stream:
				_audio_cache[path] = stream


## Gets an available non-positional audio player from the pool.
func _get_available_player() -> AudioStreamPlayer:
	for player in _audio_pool:
		if not player.playing:
			return player
	# All players busy, return the first one (will interrupt it)
	return _audio_pool[0]


## Gets an available positional audio player from the pool.
func _get_available_player_2d() -> AudioStreamPlayer2D:
	for player in _audio_2d_pool:
		if not player.playing:
			return player
	# All players busy, return the first one (will interrupt it)
	return _audio_2d_pool[0]


## Gets or loads an audio stream from cache.
func _get_stream(path: String) -> AudioStream:
	if _audio_cache.has(path):
		return _audio_cache[path]

	var stream := load(path) as AudioStream
	if stream:
		_audio_cache[path] = stream
	return stream


## Plays a non-positional sound.
func play_sound(path: String, volume_db: float = 0.0) -> void:
	var stream := _get_stream(path)
	if stream == null:
		push_warning("AudioManager: Could not load sound: " + path)
		return

	var player := _get_available_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Plays a positional 2D sound at the given position.
func play_sound_2d(path: String, position: Vector2, volume_db: float = 0.0) -> void:
	var stream := _get_stream(path)
	if stream == null:
		push_warning("AudioManager: Could not load sound: " + path)
		return

	var player := _get_available_player_2d()
	player.stream = stream
	player.volume_db = volume_db
	player.global_position = position
	player.play()


## Plays a random sound from an array of paths.
func play_random_sound(paths: Array, volume_db: float = 0.0) -> void:
	if paths.is_empty():
		return
	var path: String = paths[randi() % paths.size()]
	play_sound(path, volume_db)


## Plays a random positional 2D sound from an array of paths.
func play_random_sound_2d(paths: Array, position: Vector2, volume_db: float = 0.0) -> void:
	if paths.is_empty():
		return
	var path: String = paths[randi() % paths.size()]
	play_sound_2d(path, position, volume_db)


# ============================================================================
# Convenience methods for specific game sounds
# ============================================================================

## Plays a random M16 shot sound at the given position.
func play_m16_shot(position: Vector2) -> void:
	play_random_sound_2d(M16_SHOTS, position, VOLUME_SHOT)


## Plays M16 double shot sound (for burst fire) at the given position.
func play_m16_double_shot(position: Vector2) -> void:
	play_random_sound_2d(M16_DOUBLE_SHOTS, position, VOLUME_SHOT)


## Plays a random M16 bolt cycling sound at the given position.
func play_m16_bolt(position: Vector2) -> void:
	play_random_sound_2d(M16_BOLT_SOUNDS, position, VOLUME_RELOAD)


## Plays magazine removal sound (first phase of reload).
func play_reload_mag_out(position: Vector2) -> void:
	play_sound_2d(RELOAD_MAG_OUT, position, VOLUME_RELOAD)


## Plays magazine insertion sound (second phase of reload).
func play_reload_mag_in(position: Vector2) -> void:
	play_sound_2d(RELOAD_MAG_IN, position, VOLUME_RELOAD)


## Plays full reload sound.
func play_reload_full(position: Vector2) -> void:
	play_sound_2d(RELOAD_FULL, position, VOLUME_RELOAD)


## Plays empty gun click sound.
func play_empty_click(position: Vector2) -> void:
	play_sound_2d(EMPTY_GUN_CLICK, position, VOLUME_EMPTY_CLICK)


## Plays lethal hit sound at the given position.
func play_hit_lethal(position: Vector2) -> void:
	play_sound_2d(HIT_LETHAL, position, VOLUME_HIT)


## Plays non-lethal hit sound at the given position.
func play_hit_non_lethal(position: Vector2) -> void:
	play_sound_2d(HIT_NON_LETHAL, position, VOLUME_HIT)


## Plays bullet wall impact sound at the given position.
func play_bullet_wall_hit(position: Vector2) -> void:
	play_sound_2d(BULLET_WALL_HIT, position, VOLUME_IMPACT)


## Plays bullet near player sound (bullet flew close to player).
func play_bullet_near_player(position: Vector2) -> void:
	play_sound_2d(BULLET_NEAR_PLAYER, position, VOLUME_IMPACT)


## Plays bullet hitting cover near player sound.
func play_bullet_cover_near_player(position: Vector2) -> void:
	play_sound_2d(BULLET_COVER_NEAR_PLAYER, position, VOLUME_IMPACT)


## Plays rifle shell casing sound at the given position.
func play_shell_rifle(position: Vector2) -> void:
	play_sound_2d(SHELL_RIFLE, position, VOLUME_SHELL)


## Plays pistol shell casing sound at the given position.
func play_shell_pistol(position: Vector2) -> void:
	play_sound_2d(SHELL_PISTOL, position, VOLUME_SHELL)
