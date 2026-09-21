extends Node
class_name WaveManager
## Endless escalating waves. Data-driven: edit `wave_table` in the inspector
## to author waves; anything past the table is generated procedurally with
## growing counts and stat multipliers.
##
## Each entry: {"chaser": int, "rusher": int, "tank": int,
##               "hp_mult": float, "speed_mult": float}
## Flow per wave: intermission pause -> wave_started -> trickle-spawn the queue
## -> when the queue is empty AND every spawned enemy has died: wave_cleared ->
## next intermission. Main listens to the signals for HUD/banner/score.

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal progress_changed(remaining: int)
signal game_over

@export_group("Waves (data-driven)")
@export var wave_table: Array[Dictionary] = [
	{"chaser": 4, "rusher": 0, "tank": 0, "weaver": 0, "orbiter": 0, "shooter": 0, "splitter": 0, "elite": 0, "leaper": 0, "bulwark": 0, "sniper": 0, "pulsar": 0, "medic": 0, "skirmisher": 0, "rammer": 0, "hp_mult": 1.0, "speed_mult": 1.0},
	{"chaser": 5, "rusher": 3, "tank": 0, "weaver": 2, "orbiter": 0, "shooter": 0, "splitter": 0, "elite": 0, "leaper": 2, "bulwark": 0, "sniper": 1, "pulsar": 0, "medic": 0, "skirmisher": 0, "rammer": 0, "hp_mult": 1.05, "speed_mult": 1.0},
	{"chaser": 6, "rusher": 4, "tank": 1, "weaver": 2, "orbiter": 1, "shooter": 1, "splitter": 0, "elite": 0, "leaper": 2, "bulwark": 1, "sniper": 1, "pulsar": 1, "medic": 0, "skirmisher": 0, "rammer": 0, "hp_mult": 1.1, "speed_mult": 1.02},
	{"chaser": 6, "rusher": 6, "tank": 2, "weaver": 3, "orbiter": 2, "shooter": 1, "splitter": 1, "elite": 0, "leaper": 3, "bulwark": 1, "sniper": 1, "pulsar": 1, "medic": 1, "skirmisher": 0, "rammer": 0, "hp_mult": 1.2, "speed_mult": 1.05},
	{"chaser": 8, "rusher": 8, "tank": 3, "weaver": 4, "orbiter": 3, "shooter": 2, "splitter": 2, "elite": 0, "leaper": 3, "bulwark": 2, "sniper": 2, "pulsar": 1, "medic": 1, "skirmisher": 2, "rammer": 0, "hp_mult": 1.3, "speed_mult": 1.08},
	{"chaser": 10, "rusher": 10, "tank": 4, "weaver": 5, "orbiter": 4, "shooter": 3, "splitter": 2, "elite": 1, "leaper": 4, "bulwark": 2, "sniper": 2, "pulsar": 2, "medic": 1, "skirmisher": 2, "rammer": 2, "hp_mult": 1.45, "speed_mult": 1.1},
]

@export_group("Pacing")
@export var spawn_interval: float = 0.7
@export var intermission_time: float = 3.0
@export var max_alive: int = 20

@export_group("Adaptive director")
## The director reads how the LAST wave actually went -- how hard the player was
## hit and how long the pack took to clear -- and biases the next one: cruising
## gets a heavier, faster roster, bleeding gets a lighter, slower one. It is a
## bias on the authored table, never a replacement: pressure 0 (the first wave,
## or an even fight) reproduces the table exactly, and boss waves are exempt
## (their escort is deliberately trimmed -- the boss IS the wave).
@export var director_enabled: bool = true
## Roster weight at full pressure: every count in the composition moves +-25%.
@export var director_swing: float = 0.25
## Extra elites at full pressure. Bleeding adds none, so the swing is symmetric
## in feel even though elites can only ever be added, not removed.
@export var director_elite_bonus: int = 2
## Spawn-interval swing at full pressure: a cruising player is pressed faster.
@export var director_pace_swing: float = 0.15
## Seconds per queued enemy that counts as an even fight, for the pace term. A
## roster cleared faster than this is slack the director spends.
@export var director_pace_ref: float = 0.55

@export_group("Spawn telegraph")
## Enemies announce their arrival with an expanding ring at the spawn point,
## then materialise. Set to 0 to spawn instantly.
@export var spawn_telegraph_time: float = 0.35

@export_group("Procedural scaling (past the table)")
@export var extra_chasers_per_wave: int = 2
@export var extra_rushers_per_wave: int = 2
@export var extra_tanks_per_wave: int = 1
@export var hp_growth_per_wave: float = 0.12
@export var speed_growth_per_wave: float = 0.02
@export var max_speed_mult: float = 1.6

@export_group("Run length")
## ENDLESS (the menu's toggle) keeps generating waves past the authored table
## forever. OFF ends the run when the last authored wave is cleared: a finite
## campaign, identical rules otherwise (boss rule, shop, pacing unchanged).
@export var endless: bool = true

@export_group("Difficulty")
## Multipliers applied ON TOP of the wave table for the menu's chosen difficulty,
## so the table itself is never mutated. `spawn` scales the spawn INTERVAL (lower
## = more pressure per second) and `elite` scales the wave's elite COUNT (0 = this
## difficulty never fields an elite at all). One place, every wave routes here.
const DIFFICULTIES: Dictionary = {
	# Bumped ~1.5x over the original tuning to counter the shop's power curve:
	# hp x1.5, spawn interval /1.5 (lower = more pressure per second), and a lighter
	# x1.1 on speed -- a full x1.5 would put the fastest enemies past the player's
	# base 230 px/s move speed. NIGHTMARE is bumped with the rest so the ladder
	# stays ordered (it must always be harder than HARD).
	# `elite` reads as a difficulty identity rather than a nudge: EASY has none,
	# NORMAL the authored count, HARD and NIGHTMARE multiply it.
	"easy": {"hp": 1.13, "speed": 1.01, "spawn": 0.87, "elite": 0.0},
	"normal": {"hp": 1.5, "speed": 1.1, "spawn": 0.67, "elite": 1.0},
	"hard": {"hp": 2.1, "speed": 1.19, "spawn": 0.5, "elite": 2.0},
	# Unlockable "nightmare" (clear a Hard run): the fourth row appears in the menu
	# only once it is earned -- `unlock` is what the menu filters on.
	"nightmare": {"hp": 2.55, "speed": 1.27, "spawn": 0.43, "elite": 3.0, "unlock": "nightmare"},
}
## Menu order, so the UI never hardcodes the list.
const DIFFICULTY_ORDER: Array[String] = ["easy", "normal", "hard", "nightmare"]
## Unlockable "boss_rush": the menu's run mutator -- every wave is a full boss wave.
## Set by Main from the saved preference when a run starts.
var boss_rush: bool = false
## Set by Main from the menu's saved preference.
var difficulty: String = "normal"


## Is this difficulty playable yet? Rows without an `unlock` are always available;
## the rest wait for their unlockable (so a stale saved preference can never leave
## the player on a difficulty the menu refuses to show).
static func difficulty_unlocked(id: String) -> bool:
	var row: Variant = DIFFICULTIES.get(id, {})
	if not (row is Dictionary):
		return false
	var gate: String = String((row as Dictionary).get("unlock", ""))
	return gate == "" or Unlockables.is_unlocked(gate)

@export_group("Boss")
## Every Nth wave is a boss wave. The rule lives here so Main can ask instead of
## duplicating the modulo.
const BOSS_EVERY := 10
@export var boss_scenes: Array[PackedScene] = [
	preload("res://scenes/enemy_boss.tscn"),
	preload("res://scenes/enemy_boss_tempest.tscn"),
	preload("res://scenes/enemy_boss_hive.tscn"),
	preload("res://scenes/enemy_boss_juggernaut.tscn"),
]
## Bosses per boss wave, spawned together at wave start (see _start_wave).
@export var boss_count: int = 2
@export var boss_escort_chasers: int = 2


## A finite run includes its first boss and one following arena wave, so the
## campaign can exercise both boss combat and the arena transition it unlocks.
func finite_wave_count() -> int:
	return maxi(wave_table.size(), BOSS_EVERY + 1)

@export_group("Deep arena")
## Applied to every wave once the run has moved to the deeper arena.
const HARD_ARENA_HP := 1.30
const HARD_ARENA_SPEED := 1.10

@export_group("Affixes")
## Chance any one enemy rolls an affix at wave 1, how fast it grows per wave,
## and the cap. Affixes never roll on the elite (its shield IS its identity)
## or the boss (its phases are their own show).
@export var affix_chance: float = 0.08
@export var affix_growth: float = 0.01
@export var affix_chance_max: float = 0.35
## Set by a run mutator: every spawn rolls one, chance table ignored.
var force_affixes: bool = false

@export_group("Enemy scenes")
@export var chaser_scene: PackedScene = preload("res://scenes/enemy_chaser.tscn")
@export var rusher_scene: PackedScene = preload("res://scenes/enemy_rusher.tscn")
@export var tank_scene: PackedScene = preload("res://scenes/enemy_tank.tscn")
@export var weaver_scene: PackedScene = preload("res://scenes/enemy_weaver.tscn")
@export var orbiter_scene: PackedScene = preload("res://scenes/enemy_orbiter.tscn")
@export var shooter_scene: PackedScene = preload("res://scenes/enemy_shooter.tscn")
@export var splitter_scene: PackedScene = preload("res://scenes/enemy_splitter.tscn")
@export var elite_scene: PackedScene = preload("res://scenes/enemy_elite.tscn")
@export var bulwark_scene: PackedScene = preload("res://scenes/enemy_bulwark.tscn")
@export var leaper_scene: PackedScene = preload("res://scenes/enemy_leaper.tscn")
@export var sniper_scene: PackedScene = preload("res://scenes/enemy_sniper.tscn")
@export var pulsar_scene: PackedScene = preload("res://scenes/enemy_pulsar.tscn")
@export var medic_scene: PackedScene = preload("res://scenes/enemy_medic.tscn")
@export var skirmisher_scene: PackedScene = preload("res://scenes/enemy_skirmisher.tscn")
@export var rammer_scene: PackedScene = preload("res://scenes/enemy_rammer.tscn")

## The roster's scene paths live in the `Enemy scenes` export group as friendlier
## per-type @export PackedScenes; the registry (Beasts.DEFS) is now what the two
## lookups above read, so those exports are legacy and unused.
var current_wave: int = 0
var is_running: bool = false
var shop_pause_enabled: bool = false  # Main picks up wave_cleared and pauses here
var hard_arena: bool = false          # set by Main after the arena swap

## The run's random source. Every wave-level draw routes through it -- queue
## shuffle, spawn jitter, affix roll -- so one seed reproduces a whole run. Main
## pins it for a DAILY run (see seed_run); otherwise it is just random. The global
## RNG is left alone: only the wave loop needs to be reproducible.
var rng := RandomNumberGenerator.new()

## The director's read of the last completed wave: +1 cruising, -1 bleeding, 0
## while there is nothing to read (wave 1) or the wave was an even fight.
var pressure: float = 0.0
var _player: Player = null
var _hp_ratio: float = 1.0        # live, sampled every frame while a wave runs
var _hp_start: float = 1.0        # when this wave began (i.e. after the shop)
var _worst_hp_ratio: float = 1.0  # this wave's low point
var _wave_seconds: float = 0.0    # fight clock for the wave in progress
var _last_wave_seconds: float = 0.0
var _last_roster: int = 0         # enemies composed into the wave being measured
var _director_pace: float = 1.0   # spawn-interval multiplier from the director

var _spawn_queue: Array[String] = []  # type names left to spawn
var _alive: int = 0
var _hp_mult: float = 1.0
var _speed_mult: float = 1.0
var _enemy_container: Node2D = null

var _spawn_timer: Timer = null
var _intermission_timer: Timer = null


func _ready() -> void:
	rng.randomize()   # a fresh RandomNumberGenerator is seeded to 0 -- make it random
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_intermission_timer = Timer.new()
	_intermission_timer.one_shot = true
	_intermission_timer.timeout.connect(_on_intermission_done)
	add_child(_intermission_timer)


## Main hands the director the live player: the run owns which instance that is,
## the same reason `rebind_container()` exists after an arena swap.
func bind_player(p: Player) -> void:
	_player = p


## The director's sampler -- the fight clock and the player's health. Read here
## rather than pushed from Main because the director is the only consumer, and a
## paused tree stops _process, so ESC-pause time never counts as fight time. (The
## shop does not pause the tree, but the clock is reset at every wave start and
## read at every wave clear, so shop time lands outside every measurement.)
func _process(delta: float) -> void:
	if not is_running:
		return
	_wave_seconds += delta
	if _player == null or not is_instance_valid(_player) or _player.max_health <= 0:
		return
	_hp_ratio = clampf(float(_player.health) / float(_player.max_health), 0.0, 1.0)
	_worst_hp_ratio = minf(_worst_hp_ratio, _hp_ratio)


## Pin the run's RNG. 0 = randomize (an ordinary run); any other value reproduces
## a whole run. Main passes today's date for a DAILY run, before start_game().
func seed_run(value: int) -> void:
	if value == 0:
		rng.randomize()
	else:
		rng.seed = value


func start_game() -> void:
	_enemy_container = get_tree().get_first_node_in_group("enemy_container") as Node2D
	if _enemy_container == null:
		push_error("WaveManager: no node in group 'enemy_container' -- enemies have nowhere to spawn.")
		return
	current_wave = 0
	_spawn_queue.clear()
	_alive = 0
	# A fresh run carries no verdict: the last run's pressure must never bias
	# wave 1 of this one, and the wave clock starts at the first wave start.
	pressure = 0.0
	_wave_seconds = 0.0
	_last_wave_seconds = 0.0
	_last_roster = 0
	_director_pace = 1.0
	_hp_ratio = 1.0
	_hp_start = 1.0
	_worst_hp_ratio = 1.0
	is_running = true
	_begin_intermission(intermission_time * 0.5)


func stop() -> void:
	is_running = false
	_spawn_timer.stop()
	_intermission_timer.stop()
	_spawn_queue.clear()


## Shop says "go": resume the wave loop after a cleared wave.
func resume_waves() -> void:
	if not is_running:
		return
	_begin_intermission(intermission_time)


## Called by Main when the player dies: freeze the field and announce it.
func notify_player_dead() -> void:
	stop()
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: EnemyBase = node as EnemyBase
		if enemy != null:
			enemy.is_dormant = true
	game_over.emit()


func enemies_remaining() -> int:
	return _spawn_queue.size() + _alive


func _begin_intermission(duration: float) -> void:
	if not is_running:
		return
	_intermission_timer.wait_time = duration
	_intermission_timer.start()


func _on_intermission_done() -> void:
	if not is_running:
		return
	_start_wave(current_wave + 1)


func _start_wave(wave_number: int) -> void:
	current_wave = wave_number
	# The director's read of the wave that just ENDED, taken before any of this
	# one exists. Wave 1 -- and a fresh run -- has nothing to read: pressure stays
	# 0 and the authored table is reproduced exactly.
	pressure = 0.0
	if _last_wave_seconds > 0.0:
		pressure = pressure_from(_hp_start, _worst_hp_ratio, _last_wave_seconds,
				director_pace_ref, _last_roster)
	# A COPY: an authored row is a live reference into `wave_table`, so writing the
	# director's bias into it would compound run after run -- wave 6 would come out
	# heavier every time it was played, and nothing would ever error.
	var comp: Dictionary = _composition_for_wave(wave_number).duplicate()
	_apply_director(comp, wave_number)
	# This wave's baseline for the next reading.
	_hp_start = _hp_ratio
	_worst_hp_ratio = _hp_ratio
	_wave_seconds = 0.0
	_hp_mult = float(comp.get("hp_mult", 1.0))
	_speed_mult = float(comp.get("speed_mult", 1.0))
	if hard_arena:
		_hp_mult *= HARD_ARENA_HP
		_speed_mult *= HARD_ARENA_SPEED
	var diff: Dictionary = DIFFICULTIES.get(difficulty, DIFFICULTIES["normal"])
	_hp_mult *= float(diff["hp"])
	_speed_mult *= float(diff["speed"])
	_spawn_timer.wait_time = spawn_interval * float(diff["spawn"]) * _director_pace
	_spawn_queue.clear()
	# The composition table's keys ARE Beasts' slugs, and the spellings come from
	# the registry -- a key that matches no row is a type the wave silently never
	# spawns (and a BESTIARY row that never appears), which is invisible in play.
	# Elite rows are skipped here: the `elite` count is expanded separately below.
	for entry: Dictionary in Beasts.roster():
		var slug: String = String(entry.slug)
		if slug == "boss" or bool(entry.get("elite", false)):
			continue   # the boss rule and the elite expansion spawn their own
		for i: int in int(comp.get(slug, 0)):
			_spawn_queue.append(slug)
	# The composition's `elite` count says HOW MANY elites the wave fields; WHICH
	# archetype each one is comes out of the registry, so an elite can be any
	# enemy in the game rather than one fixed scene. The difficulty scales the
	# COUNT on top (EASY fields none at all) -- the director's pressure bonus is
	# scaled with it, so a cruising run on EASY still spawns no elites.
	for i: int in int(round(float(comp.get("elite", 0)) * float(diff["elite"]))):
		var elite_slug: String = Beasts.random_elite_slug()
		if elite_slug != "":
			_spawn_queue.append(elite_slug)
	_shuffle_queue()
	# What the pace term will measure. A boss wave reports 0: the clock belongs to
	# the boss, not to its escort.
	_last_roster = 0 if is_boss_wave(wave_number) else _spawn_queue.size()
	if is_boss_wave(wave_number):
		# Bosses walk in TOGETHER: spawn them now rather than trickling them in
		# behind the escort, so both telegraphs start on the same frame.
		_spawn_queue = _spawn_queue.filter(func(entry: String) -> bool: return entry != "boss")
		for i: int in boss_count_for_wave(wave_number):
			_spawn_enemy("boss")
	print("[Wave] WAVE %d -- queued: %s (hp x%.2f, speed x%.2f, pressure %+.2f)" % [wave_number, str(_spawn_queue), _hp_mult, _speed_mult, pressure])
	wave_started.emit(wave_number)
	progress_changed.emit(enemies_remaining())
	_spawn_timer.start()


## Is `wave_number` a boss wave? One owner for the rule so Main never re-derives it.
func is_boss_wave(wave_number: int) -> bool:
	if wave_number <= 0:
		return false
	# Unlockable "boss_rush" (a menu toggle): every wave is a boss wave. Checked
	# first so the whole rule -- composition, spawn, arena tie-in -- follows.
	if boss_rush:
		return true
	if wave_number % BOSS_EVERY == 0:
		return true
	# Unlockable "mid_boss_waves": a single boss at the halfway mark too. Keyed to
	# BOSS_EVERY so moving the boss rule moves both.
	return Unlockables.is_unlocked("mid_boss_waves") \
			and wave_number % (BOSS_EVERY / 2) == 0


## How many bosses a boss wave fields. A full boss wave gets the pair; a mid-way
## one is deliberately a single boss (see is_boss_wave).
func boss_count_for_wave(wave_number: int) -> int:
	if not is_boss_wave(wave_number):
		return 0
	return boss_count if wave_number % BOSS_EVERY == 0 else 1


## Called by Main right after the arena swap: later waves spawn tougher.
func enter_hard_arena() -> void:
	hard_arena = true


## Re-resolve the enemy container after an arena swap freed the old one.
func rebind_container() -> void:
	var container: Node2D = get_tree().get_first_node_in_group("enemy_container") as Node2D
	if container == null:
		push_error("WaveManager: no node in group 'enemy_container' after rebind.")
		return
	_enemy_container = container


## One affix id for this spawn, or "" for none.
func _roll_affix(wave_number: int) -> String:
	var chance: float = minf(affix_chance + float(maxi(wave_number - 1, 0)) * affix_growth, affix_chance_max)
	if not force_affixes and rng.randf() >= chance:
		return ""
	var keys: Array = EnemyBase.AFFIXES.keys()
	return String(keys[rng.randi_range(0, keys.size() - 1)])


## Pressure from one completed wave's numbers, in [-1, 1]: +1 untouched and fast,
## -1 bled dry and slow, 0 an even fight. Health is the heavier term -- a fast
## clock can just mean a good route, but coming through untouched cannot be
## faked. Static and pure so the suite can pin it without a live run.
static func pressure_from(start_hp: float, worst_hp: float, seconds: float,
		pace_ref: float, roster: int) -> float:
	var health: float = clampf((start_hp + worst_hp) * 0.5, 0.0, 1.0)
	var health_term: float = clampf(health * 2.0 - 1.0, -1.0, 1.0)
	# A boss wave reports roster 0: its clock belongs to the boss, so pace is not
	# read at all rather than read wrong.
	var pace_term: float = 0.0
	if roster >= 2:
		var expect: float = maxf(pace_ref * float(roster), 0.001)
		pace_term = clampf((expect - seconds) / expect, -1.0, 1.0)
	return clampf(health_term * 0.65 + pace_term * 0.35, -1.0, 1.0)


## What the wave banner should say about the director, or "" when the last wave
## read as even. The threshold lives here so Main only has to render it.
func pressure_label() -> String:
	if absf(pressure) < 0.35:
		return ""
	return "PRESSURE RISING" if pressure > 0.0 else "EASING OFF"


## Bias one composed roster by the pressure the last wave showed. Composition and
## pace only: the hp/speed multipliers belong to the difficulty row (and nudging
## them would drift the boss-TTK measurement the suite pins), and the boss count
## is the boss rule's business.
func _apply_director(comp: Dictionary, wave_number: int) -> void:
	_director_pace = 1.0
	if not director_enabled or is_boss_wave(wave_number) or absf(pressure) < 0.01:
		return
	var scale: float = 1.0 + director_swing * pressure
	for key: String in comp.keys():
		if key == "hp_mult" or key == "speed_mult" or key == "boss":
			continue
		comp[key] = maxi(0, int(round(float(comp[key]) * scale)))
	comp["elite"] = maxi(0, int(comp.get("elite", 0))
			+ int(round(float(director_elite_bonus) * maxf(pressure, 0.0))))
	_director_pace = clampf(1.0 - director_pace_swing * pressure, 0.5, 1.5)


func _composition_for_wave(wave_number: int) -> Dictionary:
	if is_boss_wave(wave_number):
		# The boss IS the wave: normal scaling for its stat multipliers, but the
		# escort is trimmed to a handful of chasers so it never reads as a swarm.
		var boss_comp: Dictionary = _base_composition(wave_number)
		for key: String in ["rusher", "tank", "weaver", "orbiter", "shooter", "splitter",
				"elite", "bulwark", "leaper", "sniper", "pulsar", "medic", "skirmisher", "rammer"]:
			boss_comp[key] = 0
		boss_comp["chaser"] = boss_escort_chasers
		boss_comp["boss"] = boss_count_for_wave(wave_number)
		return boss_comp
	return _base_composition(wave_number)


func _base_composition(wave_number: int) -> Dictionary:
	if wave_number >= 1 and wave_number <= wave_table.size():
		return wave_table[wave_number - 1]
	# Procedural: keep the last authored wave as a base, then grow.
	var base: Dictionary = wave_table[wave_table.size() - 1]
	var extra: int = wave_number - wave_table.size()
	return {
		"chaser": int(base.get("chaser", 6)) + extra * extra_chasers_per_wave,
		"rusher": int(base.get("rusher", 6)) + extra * extra_rushers_per_wave,
		"tank": int(base.get("tank", 2)) + extra * extra_tanks_per_wave,
		"weaver": int(base.get("weaver", 4)) + extra,
		"orbiter": int(base.get("orbiter", 3)) + extra,
		"shooter": int(base.get("shooter", 2)) + extra,
		"splitter": int(base.get("splitter", 1)) + extra,
		"elite": int(base.get("elite", 1)) + extra,
		"leaper": int(base.get("leaper", 3)) + extra,
		# One more bulwark only every 3 waves: an aura carrier needs presence,
		# not count -- its mitigation does not stack with its own kind.
		"bulwark": int(base.get("bulwark", 1)) + (extra / 3),
		"sniper": 1 + (extra / 3),
		"pulsar": 1 + (extra / 4),
		"medic": 1 + (extra / 5),
		"skirmisher": 1 + (extra / 3),
		"rammer": 1 + (extra / 4),
		"hp_mult": float(base.get("hp_mult", 1.4)) + extra * hp_growth_per_wave,
		"speed_mult": minf(float(base.get("speed_mult", 1.1)) + extra * speed_growth_per_wave, max_speed_mult),
	}


func _on_spawn_tick() -> void:
	if not is_running:
		_spawn_timer.stop()
		return
	if _alive >= max_alive or _spawn_queue.is_empty():
		# Queue empty + spawn pressure relieved: just wait for kills. The tick
		# keeps running cheaply until wave-cleared stops it.
		if _spawn_queue.is_empty():
			_spawn_timer.stop()
		else:
			_spawn_timer.start()
		return
	_spawn_enemy(_spawn_queue.pop_back())
	progress_changed.emit(enemies_remaining())
	if not _spawn_queue.is_empty():
		_spawn_timer.start()
	else:
		_spawn_timer.stop()


func _spawn_enemy(type_name: String) -> void:
	# ONE lookup per type, out of the same registry the roster and the BESTIARY
	# read. The row owns the scene, whether this is an elite VARIANT, and the
	# elite multipliers -- a type whose row is gone can no longer silently spawn a
	# chaser, and a new enemy needs no `match` arm here.
	var row: Dictionary = Beasts.roster_row(type_name)
	var scene: PackedScene = chaser_scene
	var row_scene: String = String(row.get("scene", ""))
	if row_scene != "" and ResourceLoader.exists(row_scene):
		scene = load(row_scene) as PackedScene
	if type_name == "boss":
		var boss_wave_index: int = maxi(floori(float(current_wave) / float(BOSS_EVERY)) - 1, 0)
		scene = boss_scenes[boss_wave_index % boss_scenes.size()]
	var is_elite: bool = bool(row.get("elite", false))
	var enemy: EnemyBase = scene.instantiate() as EnemyBase
	if enemy == null:
		push_error("WaveManager: failed to instantiate enemy type '%s'." % type_name)
		return
	# Base stats come from the scene's export overrides; wave scaling and the row's
	# elite multipliers apply multiplicatively on top.
	enemy.max_health = maxi(1, int(round(float(enemy.max_health) * _hp_mult * float(row.get("hp_mult", 1.0)))))
	enemy.score_value = maxi(1, int(round(float(enemy.score_value) * float(row.get("score_mult", 1.0)))))
	enemy.move_speed *= _speed_mult
	# Elite: set BEFORE it enters the tree (_ready reads it) and it is what puts
	# the enemy in the "elites" group + the elite row of the BESTIARY.
	enemy.is_elite = is_elite
	# Affix: an elite's comes from its row (that IS the elite's shield phase), a
	# normal enemy rolls one, and the boss never takes either (its phases are its
	# own show).
	if is_elite:
		enemy.affix = String(row.get("affix", ""))
	elif type_name != "boss":
		enemy.affix = _roll_affix(current_wave)
	enemy.position = _pick_spawn_position()
	# Count it BEFORE it is in the tree: a wave must not read as cleared while
	# enemies are still materialising behind their telegraph.
	_alive += 1
	if spawn_telegraph_time > 0.0:
		_telegraph(enemy.position)
		await get_tree().create_timer(spawn_telegraph_time).timeout
		if not is_running or not is_instance_valid(enemy):
			if is_instance_valid(enemy):
				enemy.queue_free()
			_alive = maxi(_alive - 1, 0)
			return
	_enemy_container.add_child(enemy)
	# initialize() runs after _ready (add_child triggers _ready first), so it
	# safely overwrites the values _ready just set.
	enemy.initialize(enemy.max_health, 1.0)
	enemy.died.connect(_on_enemy_died)
	if enemy.has_signal("split_spawned"):
		enemy.connect("split_spawned", _on_split_spawned)


## Arrival ring at the spawn point, drawn through the existing burst effect.
func _telegraph(at: Vector2) -> void:
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer == null:
		return
	DeathBurst.spawn(layer, at, Color(1.0, 0.35, 0.4), 62.0, spawn_telegraph_time)


## Splitter emits its pair right before dying; add them to the roster so the
## wave isn't declared cleared until the minis are gone too.
func _on_split_spawned(pair: Array) -> void:
	for mini: EnemyBase in pair:
		if mini == null:
			continue
		_enemy_container.add_child(mini)
		mini.died.connect(_on_enemy_died)
		_alive += 1
		progress_changed.emit(enemies_remaining())


func _pick_spawn_position() -> Vector2:
	var points: Array[Node] = get_tree().get_nodes_in_group("spawn_points")
	if points.is_empty():
		push_warning("WaveManager: no spawn points found; spawning at origin.")
		return Vector2.ZERO
	var chosen: Node2D = points[rng.randi_range(0, points.size() - 1)] as Node2D
	var pos: Vector2 = chosen.global_position
	# Jitter so simultaneous spawns don't stack exactly.
	pos += Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-24.0, 24.0))
	return pos


## Fisher-Yates on the spawn queue using THIS run's rng. Array.shuffle() draws from
## the global RNG, which a seeded run must not depend on -- two runs with the same
## seed have to deal the same queue.
func _shuffle_queue() -> void:
	for i: int in range(_spawn_queue.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = _spawn_queue[i]
		_spawn_queue[i] = _spawn_queue[j]
		_spawn_queue[j] = tmp


func _on_enemy_died(_enemy: EnemyBase) -> void:
	_alive = maxi(_alive - 1, 0)
	progress_changed.emit(enemies_remaining())
	if is_running and _spawn_queue.is_empty() and _alive <= 0:
		# The fight clock stops HERE: the director measures the wave, not the shop
		# and intermission that follow it.
		_last_wave_seconds = _wave_seconds
		if not endless and current_wave >= finite_wave_count():
			# Finite campaign: the last authored wave ends the run. Announced as
			# game_over (NOT wave_cleared) so the shop never opens behind it.
			print("[Wave] WAVE %d -- the scripted run is complete (ENDLESS off)." % current_wave)
			stop()
			game_over.emit()
			return
		print("[Wave] WAVE %d cleared." % current_wave)
		wave_cleared.emit(current_wave)
		# Shop takes over the intermission: when a shop is present Main pauses
		# the wave loop via pause_waves() and calls resume_waves() on close.
		if shop_pause_enabled:
			return
		_begin_intermission(intermission_time)
