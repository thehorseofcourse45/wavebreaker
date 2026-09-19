extends Node
## Central audio autoload. Loads compressed streams from assets/sounds/.
## Files are CC0 (Kenney packs + OpenGameArt "Space Shooter").

const SOUND_DIR := "res://assets/sounds/"
const Storage := preload("res://scripts/storage.gd")

@export var shoot: AudioStream = null
@export var enemy_death: AudioStream = null
@export var player_hit: AudioStream = null
@export var player_death: AudioStream = null
@export var wave_start: AudioStream = null
@export var wave_cleared: AudioStream = null
@export var game_over: AudioStream = null
@export var music: AudioStream = null
## Boss-wave bed. Falls back to `music` if the file is missing, so a boss wave
## never goes silent.
@export var boss_music: AudioStream = null
## Unlockable "boss_track_2": a second boss bed, picked at random per boss wave
## once it is earned. Missing file = the unlock simply changes nothing.
@export var boss_music_2: AudioStream = null

const POOL_SIZE := 10
## Volume sliders are 0..1 and persist in the save. Music runs on its own player
## and SFX through the pool with a per-shot db offset, so each volume is applied
## where the sound is actually played: music sets the player's volume_db, SFX fold
## into _play(). 0.4 is the level the old hardcoded -8 dB bed sat at.
const DEFAULT_MUSIC_VOLUME := 0.4
const DEFAULT_SFX_VOLUME := 1.0
## A slider at zero is silence, not -infinity dB (which Godot refuses).
const SILENT_DB := -80.0

var _pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_volume: float = DEFAULT_MUSIC_VOLUME
var _sfx_volume: float = DEFAULT_SFX_VOLUME


func _ready() -> void:
	_try_load_sounds()
	_init_pool()
	var saved: Dictionary = Storage.read_all()
	_music_volume = clampf(float(saved.get("music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	_sfx_volume = clampf(float(saved.get("sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)


func music_volume() -> float:
	return _music_volume


func sfx_volume() -> float:
	return _sfx_volume


## Volumes are the player's preference, not run state, so they persist across
## launches in the same JSON file the records use. Music applies live -- dragging
## the slider is audible immediately, even mid-pause, because the music player runs
## with PROCESS_MODE_ALWAYS and a volume change needs no processing at all.
func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_music_player.volume_db = _music_db()
	Storage.set_value("music_volume", _music_volume)


func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	Storage.set_value("sfx_volume", _sfx_volume)


func _music_db() -> float:
	return SILENT_DB if _music_volume <= 0.001 else linear_to_db(_music_volume)


func _try_load_sounds() -> void:
	if shoot == null:
		shoot = _load_sound("shoot.wav")
		if shoot == null:
			shoot = _load_sound("shoot.ogg")
	if enemy_death == null:
		enemy_death = _load_sound("enemy_death.wav")
		if enemy_death == null:
			enemy_death = _load_sound("enemy_death.ogg")
	if player_hit == null:
		player_hit = _load_sound("player_hit.wav")
		if player_hit == null:
			player_hit = _load_sound("player_hit.ogg")
	if player_death == null:
		player_death = _load_sound("player_death.wav")
		if player_death == null:
			player_death = _load_sound("player_death.ogg")
	if wave_start == null:
		wave_start = _load_sound("wave_start.wav")
		if wave_start == null:
			wave_start = _load_sound("wave_start.ogg")
	if wave_cleared == null:
		wave_cleared = _load_sound("wave_cleared.wav")
		if wave_cleared == null:
			wave_cleared = _load_sound("wave_cleared.ogg")
	if game_over == null:
		game_over = _load_sound("game_over.wav")
		if game_over == null:
			game_over = _load_sound("game_over.ogg")
	if music == null:
		music = _load_sound("music.wav")
		if music == null:
			music = _load_sound("music.ogg")
	if boss_music == null:
		boss_music = _load_sound("boss_music.ogg")
		if boss_music == null:
			boss_music = _load_sound("boss_music.wav")
	if boss_music_2 == null:
		boss_music_2 = _load_sound("boss_music_2.ogg")
		if boss_music_2 == null:
			boss_music_2 = _load_sound("boss_music_2.wav")
	_ensure_loop(music)
	_ensure_loop(boss_music)
	_ensure_loop(boss_music_2)


## Music must loop: the imported flag (`loop=false` in music.ogg.import) is an
## asset property that a re-import or an asset swap resets, so the runtime is
## the place that decides. SFX are one-shots and are deliberately untouched.
func _ensure_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _load_sound(path: String) -> AudioStream:
	var full := SOUND_DIR + path
	if not ResourceLoader.exists(full):
		return null
	var stream = load(full)
	if stream is AudioStream:
		return stream
	return null


func _init_pool() -> void:
	for i: int in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS  # music survives pause
	add_child(_music_player)


func _pick_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _pool:
		if not p.playing:
			return p
	_pool[0].playing = false
	return _pool[0]


func _play(stream: AudioStream, pitch_scale: float = 1.0, vol_db: float = 0.0) -> void:
	if _sfx_volume <= 0.001:
		return   # slider at zero: nothing to mix, and no player to steal
	if stream == null:
		push_warning("[AudioManager] Sound not loaded - check assets/sounds/")
		return
	var p := _pick_player()
	p.stream = stream
	p.pitch_scale = pitch_scale + randf_range(-0.05, 0.05)
	p.volume_db = vol_db + linear_to_db(_sfx_volume)
	p.play()


func play_shoot(_dummy := 0) -> void:
	_play(shoot, 1.1, -4.0)


func play_enemy_death(_dummy := 0) -> void:
	_play(enemy_death, 0.85, -3.0)


func play_player_hit(_dummy := 0) -> void:
	_play(player_hit, 0.9, -5.0)


func play_player_death(_dummy := 0) -> void:
	var stream := player_death if player_death != null else enemy_death
	_play(stream, 0.6, -2.0)


func play_wave_start(_dummy := 0) -> void:
	_play(wave_start if wave_start != null else shoot, 0.7, -4.0)


func play_wave_cleared(_dummy := 0) -> void:
	_play(wave_cleared, 1.0, -3.0)


func play_game_over(_dummy := 0) -> void:
	_play(game_over, 0.9, -1.0)


## Normal bed. Called on run start, on every non-boss wave, and when a boss wave
## is cleared (so the arena drops back to the ambient track).
func start_music() -> void:
	_play_music(music)


## Boss bed, swapped in by Main on a boss wave. Same player, same volume --
## only the stream changes, so nothing else in the audio path needs to know.
## Unlockable "boss_track_2" makes it a 50/50 pick between the two boss beds.
func start_boss_music() -> void:
	var track: AudioStream = boss_music
	if boss_music_2 != null and Unlockables.is_unlocked("boss_track_2") and randf() < 0.5:
		track = boss_music_2
	if track == null:
		track = music
	_play_music(track)


func _play_music(stream: AudioStream) -> void:
	if stream == null:
		push_warning("[AudioManager] Music not loaded - check assets/sounds/")
		return
	# Already playing this track: leave it running (a re-issue on every wave must
	# not restart the loop from the top).
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.volume_db = _music_db()
	_music_player.play()


func stop_music() -> void:
	_music_player.playing = false
