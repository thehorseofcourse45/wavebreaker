extends CharacterBody2D
class_name EnemyBase
## Shared enemy logic. Variants (Chaser / Rusher / Tank) extend this class and
## only override [method _desired_velocity] (+ optionally [method _update_behavior]).
##
## Movement: NavigationAgent2D paths toward the player; if no baked navmesh is
## available (or the target is unreachable) the enemy steers straight at the
## player so the game still works. Separation steering keeps enemies from
## stacking. Contact damage is dealt via slide collisions after move_and_slide.
##
## Godot 4 notes vs Godot 3:
## - NavigationAgent2D is configured with `target_position` (a global position),
##   and `get_next_path_position()` returns the next corner of the path.
## - `is_target_reachable()` tells us whether a real path exists.

signal damaged(amount: int)
signal died(enemy: EnemyBase)
## A death that bursts into minis (the splitter, the boss's summons, and the
## "splitting" affix) emits them here so the WaveManager re-parents and counts
## them toward the wave. Declared on the BASE so an affixed enemy can split with
## no dedicated subclass -- the splitter and boss simply inherit it now.
signal split_spawned(pair: Array)

@export_group("Stats")
@export var max_health: int = 40
@export var contact_damage: int = 10
@export var move_speed: float = 115.0
@export var steering_accel: float = 700.0
@export var score_value: int = 10

@export_group("Feel")
@export var separation_radius: float = 52.0
@export var separation_strength: float = 260.0
@export var knockback_resist: float = 0.0  # 0 = full knockback, 1 = immune
@export var player_knockback: float = 280.0
@export var contact_cooldown: float = 0.6
@export var flash_time: float = 0.09

@export_group("Mitigation")
## Multiplier applied to incoming damage (1 = none). The bulwark's aura sets
## this on nearby enemies; nothing else writes it. A hit always deals at
## least 1 so a mitigated enemy can still be killed.
@export var damage_taken_mult: float = 1.0

@export_group("Audio")
## Per-archetype death sound. Deliberately null in the scene: _ready derives the
## archetype from the scene file and asks AudioManager for a generated tone, so a
## new enemy type gets its own death sound with no asset authoring.
@export var death_sound: AudioStream = null
## Derived archetype tag ("chaser", "boss", ...); names the death tone.
var archetype: String = ""

@export_group("Affix")
## Elite-style modifier rolled by the WaveManager on spawn (see its affix
## exports). Applied in _ready BEFORE the halo is built, so a tinted affix
## also tints the halo light. Affixed enemies deliberately do NOT join the
## "elites" group: the elite is the only elite, and elite_kills stays honest.
var affix: String = ""

## The modifier table: one entry per affix, a tint plus its hooks.
## shielded: periodic invulnerability windows (the elite's mechanic, generic).
## frenzied: faster, and its touch bites twice as often.
## volatile: one-shot blast next to the player on death.
## regenerating: slowly heals back up, so chip damage alone never finishes it.
## teleporting: hops toward the player on a timer, ignoring cover.
## reflective: periodic windows that turn shots back into hostile rounds.
## splitting: bursts into minis on death (emitted so the wave still counts them).
## vampiric: heals itself when its touch actually draws blood.
## warded: brief immunity after each hit, so sustained fire is inefficient.
## Tints are applied in _apply_affix, BEFORE the halo is built, so the glow is
## tinted too (the documented trap: tinting after the halo leaves the old light).
const AFFIXES: Dictionary = {
	"shielded": {"tint": Color(0.4, 0.9, 1.0), "up": 2.0, "down": 1.3},
	"frenzied": {"tint": Color(1.0, 0.55, 0.15), "speed": 1.45, "contact": 0.5},
	"volatile": {"tint": Color(1.0, 0.8, 0.2)},
	"regenerating": {"tint": Color(0.4, 1.0, 0.55), "rate": 8.0},
	"teleporting": {"tint": Color(0.72, 0.5, 1.0), "interval": 3.5, "hop": 220.0},
	"reflective": {"tint": Color(0.95, 0.95, 1.0), "up": 2.2, "down": 1.6,
		"reflect_damage": 8, "reflect_speed": 380.0, "cooldown": 0.3},
	"splitting": {"tint": Color(0.55, 1.0, 0.8), "count": 2, "spread": 26.0},
	"vampiric": {"tint": Color(0.9, 0.15, 0.28), "heal": 8},
	"warded": {"tint": Color(1.0, 0.85, 0.4), "time": 0.35},
}

## Non-colour affix cue (accessibility). The affix TINT alone is invisible to a
## colourblind player, so every affixed enemy also carries a short ASCII tag above
## its body. Letters, not a glyph: the project ships no custom font, so a symbol
## like "\u25c8" could render as a missing-glyph box. Kept separate from AFFIXES so
## the modifier table stays "a tint plus its hooks".
const AFFIX_MARKS: Dictionary = {
	"shielded": "SH", "frenzied": "FR", "volatile": "VO", "regenerating": "RG",
	"teleporting": "TP", "reflective": "RF", "splitting": "SP", "vampiric": "VP",
	"warded": "WD",
}
const VOLATILE_RADIUS := 95.0
const VOLATILE_DAMAGE := 12
## Radius used to probe "would this teleport land inside a wall?".
const TELEPORT_PROBE_RADIUS := 18.0

var _affix_shielded: bool = false
var _affix_shield_timer: float = 0.0
var _affix_regen_acc: float = 0.0
var _affix_teleport_timer: float = 0.0
var _affix_reflect_up: bool = false
var _affix_reflect_timer: float = 0.0
var _affix_reflect_cd: float = 0.0
var _affix_ward_timer: float = 0.0
var _pre_affix_color: Color = Color.WHITE
var _damage_reduction_sources: Dictionary = {}

var health: int = max_health
var is_dead: bool = false
var is_dormant: bool = false  # set on game over: freezes the enemy in place

var _knockback_vel: Vector2 = Vector2.ZERO
var _contact_timer: float = 0.0
var _flash_timer: float = 0.0
var _retarget_timer: float = 0.0
var _nav_fallback: bool = false  # true = steer directly (no usable navmesh)
## Set by an archetype that must IGNORE the navmesh entirely (the boss plows
## through cover by design). Distinct from _nav_fallback, which is the runtime
## "no path" result -- _refresh_target must never overwrite this opt-out.
var _nav_disabled: bool = false
var _player: Node2D = null

## The colour of the burst Main pops when this enemy dies. The boss shifts it
## per combat phase, so a kill reads as the phase it died in.
var death_burst_color: Color = Color(1.0, 0.55, 0.2)

## The colour this enemy shows when it is NOT flashing, and the flash itself.
## EnemyBase owns Body.color so the hit flash has exactly one writer; variants
## that tint their body set _base_color (or override _base_tint()) instead.
var _base_color: Color = Color.WHITE
const FLASH_COLOR := Color(1.0, 1.0, 1.0)

## Lit: every enemy carries its own small halo light (see _ready), so a room reads as a
## constellation of neon glows and an enemy is visible before the player's torch reaches
## it. Colour comes from the body, lifted out of the dark so it glows rather than smears.
const GLOW_LIFT := 0.35
const GLOW_RANGE := 135.0
const GLOW_ENERGY := 0.9

@onready var _body: Polygon2D = $Body
@onready var _nav: NavigationAgent2D = $NavAgent

## Neon rim: an outline built from the body polygon, so every variant gets a
## crisp edge with no art files and no per-scene authoring. Built HERE so a new
## enemy type inherits it, and updated in the same place the hit flash writes
## Body.color (one writer for "how this enemy looks right now").
const RIM_SCALE := 1.07
const RIM_WIDTH := 2.5
const RIM_LIGHTEN := 0.4

## Unlockable "rime_horde": enemy bodies take a cold tint.
const RIME_TINT := Color(0.55, 0.82, 1.0)
const RIME_MIX := 0.55
## Unlockable "rim_palette": every rim switches to one fixed accent instead of
## being derived from the body colour.
const RIM_ACCENT := Color(1.0, 0.45, 0.92)

var _rim: Line2D = null


func _ready() -> void:
	add_to_group("enemies")
	if archetype == "":
		archetype = get_scene_file_path().get_file().get_basename().trim_prefix("enemy_")
	if death_sound == null:
		death_sound = AudioManager.enemy_death_stream(archetype)
	health = max_health
	if is_instance_valid(_body):
		_base_color = _body.color
	_apply_affix()   # stats + tint, before the halo reads the tint
	if is_instance_valid(_body):
		# Lit: enemies are receivers, so the player's torch is what reveals them.
		LitLighting.make_receiver(_body)
		# ...and each one glows on its own, in its own colour (rime-tinted enemies glow
		# cold). No shadows on these: one shadow-casting light per enemy would be the
		# whole frame's budget for a halo nobody looks at.
		LitLighting.add_point_light(self, _base_tint().lightened(GLOW_LIFT), GLOW_RANGE, GLOW_ENERGY)
	_build_rim()


## One place turns a rolled affix id into stats + tint. Runs once, in _ready,
## before anything renders.
func _apply_affix() -> void:
	if affix == "" or not AFFIXES.has(affix):
		return
	_pre_affix_color = _base_color
	var def: Dictionary = AFFIXES[affix]
	match affix:
		"shielded":
			_affix_shielded = true
			_affix_shield_timer = float(def["up"])
			_base_color = def["tint"]
		"frenzied":
			move_speed *= float(def["speed"])
			contact_cooldown *= float(def["contact"])
			_base_color = def["tint"]
		"volatile":
			_base_color = def["tint"]
		"regenerating":
			_base_color = def["tint"]
		"teleporting":
			_affix_teleport_timer = float(def["interval"])
			_base_color = def["tint"]
		"reflective":
			_affix_reflect_up = true
			_affix_reflect_timer = float(def["up"])
			_base_color = def["tint"]
		"splitting":
			_base_color = def["tint"]
		"vampiric":
			_base_color = def["tint"]
		"warded":
			_base_color = def["tint"]
	_build_affix_mark()


## A short, colourblind-readable tag above the body naming the affix. It keeps
## its own affix-coloured text while the body flashes white on a hit, so "which
## modifier is this" never depends on catching a moving colour.
func _build_affix_mark() -> void:
	if not AFFIX_MARKS.has(affix):
		return
	var mark := Label.new()
	mark.name = "AffixMark"
	mark.text = String(AFFIX_MARKS[affix])
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", AFFIXES[affix]["tint"])
	mark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	mark.add_theme_constant_override("outline_size", 4)
	mark.position = Vector2(-20.0, -34.0)
	mark.size = Vector2(40.0, 14.0)
	add_child(mark)


## Per-frame affix upkeep. Called from _physics_process only while alive and
## awake. A plain enemy (affix == "") falls through every arm and does nothing.
func _tick_affix(delta: float) -> void:
	match affix:
		"shielded":
			_affix_shield_timer -= delta
			if _affix_shield_timer <= 0.0:
				_affix_shielded = not _affix_shielded
				var def: Dictionary = AFFIXES["shielded"]
				_affix_shield_timer = float(def["up"]) if _affix_shielded else float(def["down"])
				# Shield up = the affix's cold cyan; shield down = the body's natural
				# colour, so "vulnerable" reads as "the enemy you already know".
				_base_color = def["tint"] if _affix_shielded else _pre_affix_color
		"regenerating":
			if health < max_health:
				_affix_regen_acc += float(AFFIXES["regenerating"]["rate"]) * delta
				var whole: int = int(_affix_regen_acc)
				if whole > 0:
					_affix_regen_acc -= float(whole)
					health = mini(health + whole, max_health)
		"teleporting":
			_affix_teleport_timer -= delta
			if _affix_teleport_timer <= 0.0:
				_affix_teleport_timer = float(AFFIXES["teleporting"]["interval"])
				_teleport_hop()
		"reflective":
			_affix_reflect_cd = maxf(_affix_reflect_cd - delta, 0.0)
			_affix_reflect_timer -= delta
			if _affix_reflect_timer <= 0.0:
				_affix_reflect_up = not _affix_reflect_up
				var rdef: Dictionary = AFFIXES["reflective"]
				_affix_reflect_timer = float(rdef["up"]) if _affix_reflect_up else float(rdef["down"])
				_base_color = rdef["tint"] if _affix_reflect_up else _pre_affix_color
		"warded":
			_affix_ward_timer = maxf(_affix_ward_timer - delta, 0.0)


## Teleporting affix: a short hop toward the player that ignores cover. Refuses to
## land inside wall geometry (mask 8) -- a hop into a wall would trap the enemy --
## and never overshoots past the player. A burst at both ends sells the blink.
func _teleport_hop() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length_squared() < 4.0:
		return
	var hop: float = minf(float(AFFIXES["teleporting"]["hop"]), to_player.length())
	var dest: Vector2 = global_position + to_player.normalized() * hop
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var probe := CircleShape2D.new()
	probe.radius = TELEPORT_PROBE_RADIUS
	q.shape = probe
	q.collision_mask = 8   # Wall layer: outer walls + all obstacles
	q.transform = Transform2D(0.0, dest)
	if not space.intersect_shape(q, 1).is_empty():
		return   # blocked: eat the timer and try again next cycle
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		var tint: Color = AFFIXES["teleporting"]["tint"]
		DeathBurst.spawn(layer, global_position, tint, 48.0, 0.22)
		DeathBurst.spawn(layer, dest, tint, 48.0, 0.22)
	global_position = dest


## Reflective affix: turn a hit into a hostile round aimed at the player. The
## cooldown keeps a split-shot volley from reflecting one round per pellet.
func _reflect_at_player() -> void:
	if _affix_reflect_cd > 0.0:
		return
	var target: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if target == null:
		return
	var rdef: Dictionary = AFFIXES["reflective"]
	_affix_reflect_cd = float(rdef["cooldown"])
	BulletPool.fire(global_position, (target.global_position - global_position).normalized(),
			int(rdef["reflect_damage"]), float(rdef["reflect_speed"]), true)


## Vampiric affix: heal on a touch that actually drew blood (the contact path
## confirms the player's health dropped before calling this).
func _vampiric_heal() -> void:
	if affix != "vampiric":
		return
	health = mini(health + int(AFFIXES["vampiric"]["heal"]), max_health)


## Splitting affix: burst into minis on death, emitted so the WaveManager counts
## them toward the wave (same contract as the splitter's own split).
func _spawn_split_minis() -> void:
	var scene: PackedScene = load("res://scenes/enemy_mini.tscn") as PackedScene
	if scene == null:
		push_warning("EnemyBase: splitting affix could not load enemy_mini.tscn")
		return
	var sdef: Dictionary = AFFIXES["splitting"]
	var count: int = maxi(1, int(sdef["count"]))
	var spread: float = float(sdef["spread"])
	var pair: Array = []
	for i: int in count:
		var mini: EnemyBase = scene.instantiate() as EnemyBase
		if mini == null:
			continue
		mini.global_position = global_position + Vector2.RIGHT.rotated(TAU * float(i) / float(count)) * spread
		pair.append(mini)
	if not pair.is_empty():
		split_spawned.emit(pair)


## Outline slightly larger than the body, drawn BEHIND it so only the outer half
## of the stroke shows: a crisp edge instead of a fat outline.
func _build_rim() -> void:
	if not is_instance_valid(_body) or _body.polygon.size() < 3:
		return
	var rim := Line2D.new()
	rim.name = "Rim"
	var points := PackedVector2Array()
	for point: Vector2 in _body.polygon:
		points.append(point * RIM_SCALE)
	rim.points = points
	rim.closed = true
	rim.width = RIM_WIDTH
	rim.antialiased = true
	rim.default_color = _rim_color(_base_color)
	add_child(rim)
	move_child(rim, 0)
	_rim = rim


## Unlockable "rim_palette": one accent for every rim instead of a lightened copy
## of the body colour. The single owner of "what colour is the rim".
func _rim_color(body_color: Color) -> Color:
	if Unlockables.is_unlocked("rim_palette"):
		return RIM_ACCENT
	return body_color.lightened(RIM_LIGHTEN)


## WaveManager calls this right after instancing to apply wave scaling.
func initialize(spawn_health: int, speed_multiplier: float) -> void:
	max_health = spawn_health
	health = max_health
	move_speed *= speed_multiplier


func _physics_process(delta: float) -> void:
	if is_dead or is_dormant:
		return
	_contact_timer = maxf(_contact_timer - delta, 0.0)
	_tick_affix(delta)
	_update_behavior(delta)
	_refresh_target()
	var desired: Vector2 = _desired_velocity()
	desired += _compute_separation() + _knockback_vel
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, 900.0 * delta)
	velocity = velocity.move_toward(desired, steering_accel * delta)
	move_and_slide()
	_check_player_contact()


## Overridden by variants (e.g. Rusher's dash state machine ticks here).
func _update_behavior(_delta: float) -> void:
	pass


## Base steering: follow the nav path at move_speed. Variants override this.
func _desired_velocity() -> Vector2:
	return _steer_toward_player(move_speed)


func _steer_toward_player(speed: float) -> Vector2:
	return _dir_toward_player() * speed


## Unit direction of the next step along the navmesh path to the player, or the
## straight-line direction when no navmesh is usable. The ONE owner of "which way
## is the player, respecting cover": retreat / strafe / orbit / weave variants
## derive from this instead of the raw to-player vector, so they path around walls
## instead of grinding into them.
func _dir_toward_player() -> Vector2:
	var to_target: Vector2 = _player_position() - global_position
	if to_target.length_squared() < 4.0:
		return Vector2.ZERO
	if _nav_fallback:
		return to_target.normalized()
	var next: Vector2 = _nav.get_next_path_position()
	var step: Vector2 = next - global_position
	if step.length_squared() < 4.0:
		return to_target.normalized()
	return step.normalized()


func _player_position() -> Vector2:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(_player):
		return _player.global_position
	return global_position


## Retarget the agent a few times per second (cheaper than every frame) and
## detect whether the navmesh is usable; fall back to direct steering if not.
func _refresh_target() -> void:
	_retarget_timer -= get_physics_process_delta_time()
	if _retarget_timer > 0.0:
		return
	_retarget_timer = 0.15
	if _nav_disabled:
		_nav_fallback = true
		return
	# Snap the target to the CLOSEST point on the navmesh. The player routinely
	# stands a few px off the mesh (the bake insets walkable ground by the agent
	# radius, so hugging a wall puts the player outside it). A target off the mesh
	# makes is_target_reachable() report false, which used to flip EVERY enemy to
	# straight-line steering -- the whole horde ignoring pathfinding. Targeting the
	# nearest mesh point keeps the target reachable and the path real.
	var target: Vector2 = NavigationServer2D.map_get_closest_point(
			get_world_2d().navigation_map, _player_position())
	_nav.target_position = target
	_nav_fallback = not _nav.is_target_reachable()


## Push away from nearby enemies so the horde spreads out instead of stacking.
## O(n^2) over the enemy group -- fine for dozens of enemies; spatial hashing is
## a "next steps" optimization if you ever field hundreds.
func _compute_separation() -> Vector2:
	var push := Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var other: Node2D = node as Node2D
		if other == null or other == self or not is_instance_valid(other):
			continue
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()
		if distance > 0.01 and distance < separation_radius:
			push += offset.normalized() * (1.0 - distance / separation_radius)
	return push * separation_strength


func _check_player_contact() -> void:
	if _contact_timer > 0.0:
		return
	for i: int in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider is Node and (collider as Node).is_in_group("player"):
			if (collider as Node).has_method("take_damage"):
				var away: Vector2 = ((collider as Node2D).global_position - global_position).normalized()
				var player_hp_before: int = (collider as Node).health
				(collider as Node).take_damage(contact_damage, away * player_knockback)
				_contact_timer = contact_cooldown
				# Vampiric: only a touch that actually drew blood feeds it (the
				# player's i-frames make the next contact a no-op).
				if (collider as Node).health < player_hp_before:
					_vampiric_heal()
				break


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> int:
	if is_dead or amount <= 0:
		return 0
	if _affix_shielded:
		return 0   # shielded affix: the round still dies on contact, no damage lands
	if _affix_ward_timer > 0.0:
		return 0   # warded affix: brief immunity after the hit that started the ward
	if _affix_reflect_up:
		_reflect_at_player()
		return 0   # reflective window: the hit is turned back, no damage lands
	var dealt: int = maxi(1, int(round(float(amount) * damage_taken_mult)))
	var applied: int = mini(dealt, health)
	health -= dealt
	_flash_timer = flash_time
	_knockback_vel += knockback * (1.0 - clampf(knockback_resist, 0.0, 1.0))
	if affix == "warded":
		_affix_ward_timer = float(AFFIXES["warded"]["time"])
	damaged.emit(applied)
	if health <= 0:
		_die()
	return applied


## Damage-reduction auras are keyed by their source, so one aura leaving cannot
## erase another overlapping aura. The strongest active reduction wins.
func set_damage_reduction_source(source_id: int, multiplier: float) -> void:
	_damage_reduction_sources[source_id] = multiplier
	_refresh_damage_reduction()


func clear_damage_reduction_source(source_id: int) -> void:
	_damage_reduction_sources.erase(source_id)
	_refresh_damage_reduction()


func _refresh_damage_reduction() -> void:
	damage_taken_mult = 1.0
	for multiplier: float in _damage_reduction_sources.values():
		damage_taken_mult = minf(damage_taken_mult, multiplier)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	if affix == "volatile":
		_explode_volatile()
	elif affix == "splitting":
		_spawn_split_minis()
	# Stop colliding this frame so stray bullets can't double-count the kill.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	died.emit(self)


## Volatile affix: one-shot blast on death. Radius damage to the player only --
## no area system, just one distance check and one take_damage call -- plus the
## burst that telegraphs what just happened.
func _explode_volatile() -> void:
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		DeathBurst.spawn(layer, global_position, Color(1.0, 0.75, 0.2), VOLATILE_RADIUS, 0.3)
	var target: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if target != null and target.has_method("take_damage") \
			and global_position.distance_to(target.global_position) <= VOLATILE_RADIUS:
		target.take_damage(VOLATILE_DAMAGE)


func _process(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	# One writer for Body.color: white for the hit flash, the owner's tint
	# otherwise. Only assign on change so a tint that never moves does not
	# re-dirty the canvas item every frame.
	var want: Color = FLASH_COLOR if _flash_timer > 0.0 else _base_tint()
	if _body.color != want:
		_body.color = want
		if _rim != null:
			_rim.default_color = _rim_color(want)


## The colour this enemy shows while NOT flashing. Variants that own their body
## colour (the boss's health read-out) override this instead of writing
## Body.color in their own _process, which would race the flash.
func _base_tint() -> Color:
	# Unlockable "rime_horde": a cold cast over every enemy body. Read per frame
	# -- it is a dictionary lookup, not a disk read.
	if Unlockables.is_unlocked("rime_horde"):
		return _base_color.lerp(RIME_TINT, RIME_MIX)
	return _base_color
