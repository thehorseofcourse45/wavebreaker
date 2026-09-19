extends Node
## Game root: owns the MENU -> PLAYING -> GAME_OVER state machine, the score,
## and ALL cross-system signal wiring (player <-> HUD/camera, waves <-> UI).
## Systems never reference each other directly -- everything is connected here.

enum State { MENU, PLAYING, GAME_OVER }

const Storage := preload("res://scripts/storage.gd")

## Brief slow-motion on every kill. Short enough to read as impact rather than
## as lost control.
const HIT_STOP_SCALE := 0.35
const HIT_STOP_TIME := 0.055
## Kill count between streak banners.
const STREAK_STEP := 10
## Unlockable "war_chest": credits the run starts with, once it is earned.
const WAR_CHEST_CREDITS := 100

## Arena scenes, in run order. Wave BOSS_EVERY opens the next one; a third is an
## entry here plus one baked scene.
const ARENA_SCENES: Array[String] = [
	"res://scenes/arena.tscn",
	"res://scenes/arena_deep.tscn",
	"res://scenes/arena_vault.tscn",
]
## Unlockable that has to be earned before Main may switch to that arena ("" =
## always available). The vault is the reward for reaching wave 20, so a player who
## gets there without it simply stays in the deep arena.
const ARENA_UNLOCKS: Array[String] = ["", "", "vault_arena"]
## Unlockable "second_wind": the one auto-revive per run, at this share of max HP.
const SECOND_WIND_FRACTION := 0.30

var _state: int = State.MENU
var _score: int = 0
var _credits: int = 0
var _kills: int = 0
var _upgrades: Node = null
var _hit_stop_timer: Timer = null
var _arena_index: int = 0

## Lifetime progress for the unlockables. These live in memory for the run and
## reach save.json at wave boundaries / run end via Unlockables -- never per kill.
var _bosses_killed: int = 0
var _elites_killed: int = 0
var _crits: int = 0
var _charged_shots: int = 0
var _purchases: int = 0
var _bought_armor: bool = false
## Run clock for the STATS tab's per-minute columns. Only ticks while PLAYING, so
## a pause does not inflate it.
var _run_time: float = 0.0
## Unlockable "second_wind" is one revive PER RUN, so this is reset in start_game.
var _second_wind_used: bool = false
## Run mutators (unlockable-gated menu toggles), seeded from the save in _enter_menu.
var _glass_cannon: bool = false
var _boss_rush: bool = false
## Earned by now, announced once the shop closes so the callout does not fight
## the "WAVE CLEARED" banner.
var _fresh_unlocks: Array[String] = []

## World-owned nodes are plain vars, NOT @onready: `_switch_arena` replaces the
## whole World node mid-run and re-binds them (the Player is carried over, so
## every signal wired in `_wire_signals` stays connected).
var _player: Player = null
var _camera: PlayerCamera = null
var _enemy_container: Node2D = null
var _effects_layer: Node2D = null

@onready var _waves: WaveManager = $WaveManager
@onready var _hud: Hud = $UI/HUD
@onready var _banner: WaveBanner = $UI/WaveBanner
@onready var _menu: MainMenu = $UI/MainMenu
@onready var _game_over: GameOverScreen = $UI/GameOver
@onready var _shop: CanvasLayer = $UI/ShopPanel
@onready var _pause_menu: PauseMenu = $UI/PauseMenu


func _bind_world() -> void:
	_player = $World/Player
	_camera = $World/Player/PlayerCamera
	_enemy_container = $World/EnemyContainer
	_effects_layer = $World/EffectsLayer
	# Re-arm the kill watcher HERE, not in _wire_signals: _switch_arena replaces
	# the container with the new arena's, and a stale connection means kills in
	# that arena stop scoring AND the dead enemy is never freed -- it stays on
	# screen as a corpse. Guarded because _bind_world runs on every bind.
	if not _enemy_container.child_entered_tree.is_connected(_watch_enemy):
		_enemy_container.child_entered_tree.connect(_watch_enemy)


func _ready() -> void:
	_ensure_input_actions()  # safety net if project.godot input map is missing
	Engine.time_scale = 1.0  # a hit-stop in flight must never leak into a reload
	_hit_stop_timer = Timer.new()
	_hit_stop_timer.one_shot = true
	_hit_stop_timer.ignore_time_scale = true
	_hit_stop_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_hit_stop_timer.timeout.connect(func() -> void: Engine.time_scale = 1.0)
	add_child(_hit_stop_timer)
	BulletPool.reset()  # autoloads survive reloads -- park stale bullets
	_bind_world()
	_wire_signals()
	_enter_menu()
	# Self-test hook (no-op unless NEON_TEST is passed on the cmdline).
	load("res://scripts/_selftest.gd").new().attach_to(self)
	_capture_screenshot()


## Test-only screenshot mode: `NEON_SHOT`
## (optionally `=run|shop|over|pause|unlock`) in the ENGINE args (before --)
## captures one settled frame and quits. Nothing
## renders headlessly, so this is how the LOOK gets verified: run the non-headless
## console binary and inspect the PNG. The mode goes in the FILENAME, or every
## capture silently overwrites the one before it.
func _capture_screenshot() -> void:
	var mode: String = _shot_mode()
	if mode == "":
		return
	var settle: float = 1.5
	match mode:
		"run":
			start_game()
			# Outlast the intermission, the spawn telegraph AND the enemies'
			# walk-in from the corner spawns, or the shot is an empty arena.
			settle = 12.0
		"shop":
			start_game()
			_shop.show_shop(_upgrades, 640)
		"over":
			start_game()
			_shop.hide_shop()
			# A hand-built record: never write the player's real save from a shot.
			_game_over.show_game_over(1234, 7, {"best_score": 1234, "best_wave": 7,
				"new_score": true, "new_wave": true})
		"pause", "unlock":
			start_game()
			toggle_pause()
			if mode == "unlock":
				_pause_menu.show_tab(1)
		"deep":
			# Arena 2, for comparing the retro pass across arenas.
			start_game()
			_switch_arena(1)
			settle = 12.0
		"vault":
			# Arena 3 (the vault). Reachable here even while the unlockable is unearned,
			# so its LOCKED palette is what this shot shows.
			start_game()
			_switch_arena(2)
			settle = 12.0
		"showcase":
			# New-archetype exhibit: dormant bulwarks and leapers at fixed offsets
			# around the player, so their bodies and halos are on screen at
			# deterministic positions (a run shot only ever shows wave 1, and a
			# live wave shuffles spawn order).
			start_game()
			_waves.stop()
			_waves._intermission_timer.stop()
			var showcase_box: Node = get_tree().get_first_node_in_group("enemy_container")
			for showcase: Array in [["bulwark", Vector2(-240, -150)], ["leaper", Vector2(240, -150)],
					["bulwark", Vector2(-240, 150)], ["leaper", Vector2(240, 150)]]:
				var exhibit: EnemyBase = (load("res://scenes/enemy_%s.tscn" % showcase[0]) as PackedScene).instantiate() as EnemyBase
				exhibit.position = showcase[1]
				showcase_box.add_child(exhibit)
				exhibit.is_dormant = true
			settle = 3.0
		_:
			pass
	await get_tree().create_timer(settle).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "res://shot_%s.png" % mode
	img.save_png(path)
	print("[Shot] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	_dump_rects(get_node("UI"), 0)
	get_tree().quit(0)


## "" when the flag is absent, else the mode ("menu" for a bare NEON_SHOT).
func _shot_mode() -> String:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("NEON_SHOT"):
			var mode: String = arg.substr("NEON_SHOT".length()).lstrip("=")
			return mode if mode != "" else "menu"
	return ""


func _dump_rects(n: Node, depth: int) -> void:
	var label_text: String = ""
	if n is Label:
		label_text = (n as Label).text
	elif n is Button:
		label_text = (n as Button).text
	var rect_text: String = ""
	if n is Control:
		rect_text = str((n as Control).get_global_rect())
	print("%s%s %s %s" % ["  ".repeat(depth), n.name, rect_text, label_text])
	for child: Node in n.get_children():
		_dump_rects(child, depth + 1)


## Run clock for the STATS tab. A paused tree stops _process, so pausing does not
## inflate the per-minute numbers.
func _process(delta: float) -> void:
	if _state == State.PLAYING:
		_run_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_game") and _state == State.GAME_OVER:
		_restart()
		return
	if event.is_action_pressed("ui_cancel") and _state == State.PLAYING:
		toggle_pause()


# ---------------------------------------------------------------- states ---

## This run's contribution to the lifetime counters, keyed exactly like save.json
## so Unlockables can merge it into the stored totals. `best_streak` is the run's
## kill count: a death ends the run, so kills-without-dying IS the streak.
func _run_stats() -> Dictionary:
	return {
		"total_kills": _kills,
		"best_score": _score,
		"best_wave": _waves.current_wave,
		"best_streak": _kills,
		"bosses": _bosses_killed,
		"elites": _elites_killed,
		"crits": _crits,
		"charged": _charged_shots,
		"purchases": _purchases,
		"no_armor_best_wave": _waves.current_wave if not _bought_armor else 0,
	}


func start_game() -> void:
	if _state != State.MENU:
		return
	_state = State.PLAYING
	_score = 0
	_kills = 0
	_bosses_killed = 0
	_elites_killed = 0
	_crits = 0
	_charged_shots = 0
	_purchases = 0
	_bought_armor = false
	_fresh_unlocks.clear()
	_run_time = 0.0
	_second_wind_used = false
	BulletPool.damage_dealt = 0   # the STATS tab's DPS column is per run
	# Unlockable "war_chest": a head start at the first shop.
	_credits = WAR_CHEST_CREDITS if Unlockables.is_unlocked("war_chest") else 0
	Engine.time_scale = 1.0
	_upgrades = load("res://scripts/upgrade_system.gd").new()
	add_child(_upgrades)
	# Run mutators, from the menu's saved toggles. "glass_cannon" also refuses to
	# sell armor this run, which is why the block list is set here and not in the
	# shop: one place owns "what this run allows".
	_waves.boss_rush = _boss_rush
	if _glass_cannon:
		_player.apply_glass_cannon()
		_upgrades.block("armor")
	_waves.shop_pause_enabled = true
	_shop.build(_upgrades)
	_shop.hide_shop()
	_player.respawn(Vector2.ZERO)
	_player.controls_enabled = true
	_hud.reset(_player.max_health, _credits)
	_hud.visible = true
	_menu.visible = false
	_game_over.visible = false
	print("[Main] Game started.")
	AudioManager.start_music()
	_waves.start_game()


func _enter_menu() -> void:
	_state = State.MENU
	# The menu is the owner of the ENDLESS and DIFFICULTY preferences (it writes
	# them on change), but they also have to survive a reload -- so the run config
	# is seeded from disk here, before any run can start.
	_waves.endless = bool(Storage.get_value("endless", true))
	_waves.difficulty = String(Storage.get_value("difficulty", "normal"))
	_glass_cannon = bool(Storage.get_value("glass_cannon", false))
	_boss_rush = bool(Storage.get_value("boss_rush", false))
	_waves.boss_rush = _boss_rush
	_player.controls_enabled = false
	_hud.visible = false
	_banner.visible = false
	_game_over.visible = false
	_menu.visible = true
	_menu.set_scripted_waves(_waves.wave_table.size())
	_menu.set_difficulty(_waves.difficulty)
	_menu.refresh_run_options(_glass_cannon, _boss_rush)
	_menu.sync_audio_sliders()   # the pause menu moves the same volumes
	_menu.refresh_stats()   # a record set this session shows up without a restart
	_shop.hide_shop()
	AudioManager.stop_music()
	if OS.get_cmdline_user_args().has("--autostart"):
		call_deferred("start_game")


func _on_endless_toggled(enabled: bool) -> void:
	_waves.endless = enabled


func _on_difficulty_changed(id: String) -> void:
	_waves.difficulty = id


## The menu owns the mutator toggles (it writes them, like ENDLESS); Main only
## forwards them to the run. boss_rush applies at once -- it is read per wave.
func _on_mutators_changed(glass_cannon: bool, boss_rush: bool) -> void:
	_glass_cannon = glass_cannon
	_boss_rush = boss_rush
	_waves.boss_rush = boss_rush


func _on_player_died() -> void:
	if _state != State.PLAYING:
		return
	# Unlockable "second_wind": one save per run, and it comes before anything else
	# in the death path so the WaveManager never learns the player died.
	if Unlockables.is_unlocked("second_wind") and not _second_wind_used:
		_second_wind_used = true
		_player.revive(SECOND_WIND_FRACTION)
		_banner.show_banner("SECOND WIND")
		_camera.add_trauma(0.6)
		DeathBurst.spawn(_effects_layer, _player.global_position, Color(0.4, 1.0, 0.6))
		return
	DeathBurst.spawn(_effects_layer, _player.global_position, Color(0.3, 0.9, 1.0))
	_camera.add_trauma(1.0)
	_waves.notify_player_dead()  # emits game_over once the field is frozen


func _on_wave_game_over() -> void:
	_state = State.GAME_OVER
	# Short beat before the panel so the death burst reads.
	await get_tree().create_timer(1.0).timeout
	# Only ONE place writes the record, and it hands back the numbers the panel
	# prints -- so the "NEW BEST" callout can never disagree with the file.
	var record: Dictionary = Storage.record_run(_score, _waves.current_wave, _kills)
	# The STATS tab's "best wave by difficulty" rows: one key per difficulty.
	Storage.record_difficulty_wave(_waves.difficulty, _waves.current_wave)
	var stats: Dictionary = _run_stats()
	# "Clear a Hard run" = finish a scripted campaign on Hard without dying.
	if _player.is_alive and not _waves.endless and _waves.difficulty == "hard" \
			and _waves.current_wave >= _waves.wave_table.size():
		stats["hard_clears"] = 1
	# The run's counters go in once, here. record_run already owns kills/score/
	# wave, so flush_run skips those three and the run is never counted twice.
	Unlockables.flush_run(stats)
	# Totals are in the file now, so judge WITHOUT the run dict -- merging it in
	# again would double-count this run.
	Unlockables.evaluate()
	_game_over.show_game_over(_score, _waves.current_wave, record)


func _restart() -> void:
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ pause --

## Native tree pause: freezes player, enemies, bullets and all WaveManager
## timers with one flag. The pause menu runs with process_mode = ALWAYS.
func toggle_pause() -> void:
	if _state != State.PLAYING:
		return
	get_tree().paused = not get_tree().paused
	if get_tree().paused:
		_pause_menu.open(_pause_stats())
	else:
		_pause_menu.hide()


## Everything the pause menu's STATS tab prints. Main owns the numbers; the menu
## only renders them, so the tab never has to reach back into the game.
func _pause_stats() -> Dictionary:
	return {
		"wave": _waves.current_wave,
		"kills": _kills,
		"score": _score,
		"credits": _credits,
		"seconds": _run_time,
		"damage": BulletPool.damage_dealt,
		"boss_rush": _boss_rush,
		"glass_cannon": _glass_cannon,
	}


func _on_pause_resume() -> void:
	get_tree().paused = false
	_pause_menu.hide()


func _on_pause_quit() -> void:
	get_tree().paused = false
	_restart.call_deferred()


# --------------------------------------------------------------- wiring ---

func _wire_signals() -> void:
	# Audio -- all sounds routed through AudioManager autoload.
	_player.shoot.connect(AudioManager.play_shoot)
	_player.damaged.connect(AudioManager.play_player_hit)
	_player.died.connect(AudioManager.play_player_death)
	_waves.wave_started.connect(AudioManager.play_wave_start)
	_waves.wave_cleared.connect(AudioManager.play_wave_cleared)
	_waves.game_over.connect(AudioManager.play_game_over)
	# Player -> HUD / camera / flow.
	_player.health_changed.connect(_hud.set_health)
	_player.damaged.connect(_on_player_damaged)
	_player.died.connect(_on_player_died)
	# Waves -> HUD / banner / flow. Enemy deaths reach the WaveManager because
	# it connects each spawned enemy's `died` signal at spawn time.
	_waves.wave_started.connect(_on_wave_started)
	_waves.wave_cleared.connect(_on_wave_cleared)
	_waves.progress_changed.connect(_hud.set_remaining)
	_waves.game_over.connect(_on_wave_game_over)
	# Menu buttons.
	_menu.start_pressed.connect(start_game)
	# ENDLESS and DIFFICULTY are saved PREFERENCES the menu owns; Main only
	# forwards them to the wave manager (and re-seeds them on boot, below).
	_menu.endless_toggled.connect(_on_endless_toggled)
	_menu.difficulty_changed.connect(_on_difficulty_changed)
	_menu.mutators_changed.connect(_on_mutators_changed)
	_game_over.restart_pressed.connect(_restart)
	# Pause menu.
	_pause_menu.resume_pressed.connect(_on_pause_resume)
	_pause_menu.quit_pressed.connect(_on_pause_quit)
	# Score + kill juice: Main observes the same `died` signal the WaveManager
	# uses for bookkeeping (an enemy can have many listeners -- that's the point
	# of signals). Enemies are connected as they spawn, so _bind_world() watches
	# the container -- it is the one place that knows which container is live.
	# Shop UI.
	_shop.buy_attempted.connect(_on_shop_buy)
	_shop.resume_pressed.connect(_on_shop_resume)
	# Lifetime counters fed by the systems that own the events: the pool knows
	# when a round crit, the player knows when a charged shot went out.
	BulletPool.crit_landed.connect(_on_crit_landed)
	_player.charged_shot.connect(_on_charged_shot)


func _on_crit_landed() -> void:
	_crits += 1


func _on_charged_shot() -> void:
	_charged_shots += 1


func _watch_enemy(node: Node) -> void:
	var enemy: EnemyBase = node as EnemyBase
	if enemy != null and not enemy.died.is_connected(_on_enemy_killed):
		enemy.died.connect(_on_enemy_killed)


func _on_enemy_killed(enemy: EnemyBase) -> void:
	_score += enemy.score_value
	_credits += enemy.score_value
	_kills += 1
	# Variants tag themselves with a group in _ready, so this is the whole
	# "boss / elite killed" counter -- no per-variant type checks here.
	if enemy.is_in_group("bosses"):
		_bosses_killed += 1
	elif enemy.is_in_group("elites"):
		_elites_killed += 1
	_hud.set_score(_score)
	_hud.set_credits(_credits)
	AudioManager.play_enemy_death()
	DeathBurst.spawn(_effects_layer, enemy.global_position, Color(1.0, 0.55, 0.2))
	_camera.add_trauma(0.22)
	_camera.add_punch(0.6)
	_hit_stop()
	if _player.kill_heal > 0:
		_player.heal(_player.kill_heal)
	if _kills % STREAK_STEP == 0:
		_banner.show_banner("STREAK %d" % _kills)
	enemy.queue_free()
	print("[Main] Enemy killed (+%d score, +%d credits) - score %d, remaining %d." % [enemy.score_value, enemy.score_value, _score, _waves.enemies_remaining()])


## One-shot slow-motion on a kill. The timer ignores time_scale and runs
## always, so it restores even if the game is paused mid-hit-stop.
func _hit_stop() -> void:
	Engine.time_scale = HIT_STOP_SCALE
	_hit_stop_timer.start(HIT_STOP_TIME)


func _on_player_damaged(_amount: int) -> void:
	_camera.add_trauma(0.55)
	DeathBurst.spawn(_effects_layer, _player.global_position, Color(1.0, 0.3, 0.3))


func _on_wave_started(wave_number: int) -> void:
	_hud.set_wave(wave_number)
	_banner.show_banner("WAVE %d" % wave_number)
	# Boss waves get their own bed; every other wave (re)asserts the normal one,
	# so leaving a boss wave never leaves the boss track playing.
	if _waves.is_boss_wave(wave_number):
		AudioManager.start_boss_music()
	else:
		AudioManager.start_music()


func _on_wave_cleared(wave_number: int) -> void:
	_banner.show_banner("WAVE %d CLEARED" % wave_number)
	AudioManager.start_music()
	if _upgrades == null or _waves == null:
		return
	# WaveManager already paused because shop_pause_enabled; open the shop.
	_shop.show_shop(_upgrades, _credits)
	# Lifetime progress is judged at wave boundaries, never per kill. The merged
	# view (stored + this run) means an unlock can land mid-run; the callout waits
	# for the shop to close.
	for id: String in Unlockables.evaluate(_run_stats()):
		if not _fresh_unlocks.has(id):
			_fresh_unlocks.append(id)


func _on_shop_buy(id: String) -> void:
	var r: Dictionary = _upgrades.buy(id, _credits, _player)
	if r.ok:
		_credits -= int(r.spent)
		_purchases += 1
		if id == "armor":
			_bought_armor = true
		_hud.set_credits(_credits)
		_shop.refresh(_upgrades, _credits)
		print("[Shop] Bought %s for %d (credits left: %d)" % [id, int(r.spent), _credits])


func _on_shop_resume() -> void:
	_shop.hide_shop()
	# Beating a FULL boss wave (every BOSS_EVERY waves) opens the next arena.
	# Keyed to BOSS_EVERY rather than is_boss_wave(): the "mid_boss_waves"
	# unlockable adds boss waves at the halfway mark, which are one boss and
	# must NOT open an arena early.
	if _waves.current_wave % WaveManager.BOSS_EVERY == 0:
		_switch_arena(_arena_index + 1)
	if not _fresh_unlocks.is_empty():
		_banner.show_banner("UNLOCKED: %s" % Unlockables.display_name(_fresh_unlocks[0]).to_upper())
		_fresh_unlocks.clear()
	_waves.resume_waves()


# ------------------------------------------------------------- arena swap ---

## Replace the whole World node under a running game. The Player node is CARRIED
## OVER (health, upgrades, i-frames and its PlayerCamera all live on it), so the
## signals wired in _wire_signals stay connected; everything else in the old
## arena -- enemies, obstacles, its nav region -- is freed with it.
func _switch_arena(index: int) -> void:
	if index <= 0 or index >= ARENA_SCENES.size() or index == _arena_index:
		return
	# A gated arena stays shut: the index is legal but the unlockable is not earned
	# (the vault is what "clear wave 20" buys).
	var gate: String = ARENA_UNLOCKS[index] if index < ARENA_UNLOCKS.size() else ""
	if gate != "" and not Unlockables.is_unlocked(gate):
		print("[Main] arena %d is still locked (%s)." % [index + 1, gate])
		return
	var old_world: Node = $World
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	old_world.remove_child(_player)
	# free(), not queue_free(): the replacement has to take the name "World" now,
	# or Godot renames it to World2 and every $World/... path breaks.
	old_world.free()
	var fresh: Node = load(ARENA_SCENES[index]).instantiate()
	fresh.name = "World"
	add_child(fresh)
	move_child(fresh, 0)
	var placeholder: Node = fresh.get_node_or_null("Player")
	if placeholder != null:
		fresh.remove_child(placeholder)
		placeholder.free()
	fresh.add_child(_player)
	_arena_index = index
	_bind_world()
	BulletPool.reset()          # no leftover rounds flying in the new layout
	_waves.rebind_container()
	_waves.enter_hard_arena()
	_player.global_position = Vector2.ZERO   # deliberate: no free full heal here
	_player.velocity = Vector2.ZERO
	_banner.show_banner("ARENA %d" % (index + 1))
	print("[Main] Arena switched to %s" % ARENA_SCENES[index])


# ----------------------------------------------------------- input map ----

## Belt-and-braces: project.godot already defines these, but headless/CI runs
## or a hand-edited project.godot could lose them -- ensure them at runtime.
func _ensure_input_actions() -> void:
	_ensure_key_action("move_up", [KEY_W, KEY_UP])
	_ensure_key_action("move_down", [KEY_S, KEY_DOWN])
	_ensure_key_action("move_left", [KEY_A, KEY_LEFT])
	_ensure_key_action("move_right", [KEY_D, KEY_RIGHT])
	_ensure_key_action("restart_game", [KEY_R])


func _ensure_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: int in keys:
		var exists: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == key:
				exists = true
				break
		if not exists:
			var press := InputEventKey.new()
			press.physical_keycode = key
			InputMap.action_add_event(action, press)
