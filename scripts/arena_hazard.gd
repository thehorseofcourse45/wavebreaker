extends Node2D
class_name ArenaHazard
## Per-arena environmental hazard. The later arenas stop being pure reskins once
## the room itself can hurt you.
##
## One node, three mechanics, assigned by arena INDEX (see BY_ARENA) -- so adding an
## arena is still one scene plus one entry here, and an arena scene stays a pure
## layout with no per-scene hazard authoring. Main installs it right after building
## the arena (_install_hazard) and it is freed with the arena on a swap.
##
## Damage routes through the player's own take_damage, so i-frames and armour apply
## exactly as they do to a bullet: the hazard is not a second damage system.
##
##   none  - arena 1 (the tutorial room) stays hazard-free.
##   vents - fixed floor vents that telegraph, then erupt: stand clear when they light.
##   pulse - a shock ring expands from the centre: CROSS it and you are hit; the
##           centre itself is safe, so it rewards holding the middle.
##   void  - persistent damage pools you must route around.

const KIND_NONE := "none"
const KIND_VENTS := "vents"
const KIND_PULSE := "pulse"
const KIND_VOID := "void"

## Arena index -> hazard. Index order MUST match Main.ARENA_SCENES (arena 0 is the
## opening room and is deliberately quiet). Colours are the cue that a hazard
## belongs to THIS room.
const BY_ARENA: Array[Dictionary] = [
	{"kind": KIND_NONE},
	{"kind": KIND_VOID, "color": Color(0.55, 0.4, 1.0)},    # deep
	{"kind": KIND_VENTS, "color": Color(1.0, 0.6, 0.2)},    # vault
	{"kind": KIND_PULSE, "color": Color(0.4, 0.9, 1.0)},    # nexus
	{"kind": KIND_VENTS, "color": Color(1.0, 0.3, 0.35)},   # citadel
	{"kind": KIND_PULSE, "color": Color(0.6, 1.0, 0.5)},    # rift
	{"kind": KIND_VENTS, "color": Color(1.0, 0.78, 0.25)},  # foundry
]

const VENT_DAMAGE := 10
const VENT_RADIUS := 74.0
const VENT_IDLE := 1.7
const VENT_WARN := 0.8
const VENT_ON := 0.5
const PULSE_DAMAGE := 8
const PULSE_MAX_RADIUS := 780.0
const PULSE_SPEED := 520.0
const PULSE_REST := 1.3
const VOID_DAMAGE := 7
const VOID_TICK := 0.55
const VOID_RADIUS := 92.0

var kind: String = KIND_NONE
var color: Color = Color(0.9, 0.5, 0.2)
## Armed only while a RUN is live (Main sets it on install). The headless self-test
## builds arenas to inspect them, not to play them -- an armed hazard there would
## chip the test player mid-probe and make unrelated snapshot probes flaky.
var live: bool = false

var _player: Node2D = null
var _vents: Array = []          # {pos: Vector2, timer: float, phase: String}
var _pools: Array = []          # void centres, Vector2
var _tick: float = 0.0          # shared damage cadence (void pools)
var _pulse_r: float = 0.0
var _pulse_prev: float = 0.0
var _pulse_rest: float = 0.0


## Build and attach a hazard for `index`, or return null when the arena has none.
## Static so Main installs through one door; the node configures itself.
static func install(arena_root: Node2D, index: int) -> ArenaHazard:
	if arena_root == null:
		return null
	var cfg: Dictionary = BY_ARENA[index] if index >= 0 and index < BY_ARENA.size() else BY_ARENA[0]
	var kind_id: String = String(cfg.get("kind", KIND_NONE))
	if kind_id == KIND_NONE:
		return null
	var hazard := ArenaHazard.new()
	hazard.name = "ArenaHazard"
	hazard.kind = kind_id
	hazard.color = cfg.get("color", Color(0.9, 0.5, 0.2))
	arena_root.add_child(hazard)
	return hazard


func _ready() -> void:
	z_index = -1   # floor markings: above the floor, below actors
	match kind:
		KIND_VENTS:
			for pos: Vector2 in [Vector2(-380, -300), Vector2(380, -300),
					Vector2(-380, 300), Vector2(380, 300)]:
				# Stagger the first cycle so four vents never erupt in unison.
				_vents.append({"pos": pos, "timer": randf() * VENT_IDLE, "phase": "idle"})
		KIND_VOID:
			_pools = [Vector2(0, -320), Vector2(-430, 250), Vector2(430, 250)]
		KIND_PULSE:
			_pulse_rest = 0.9   # a beat before the first ring


func _process(delta: float) -> void:
	if not live or kind == KIND_NONE:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	match kind:
		KIND_VENTS:
			_tick_vents(delta)
		KIND_PULSE:
			_tick_pulse(delta)
		KIND_VOID:
			_tick_void(delta)
	queue_redraw()


## Vents cycle idle -> warn -> on. The warning is the contract: the ring is the
## tell, the eruption is the hit.
func _tick_vents(delta: float) -> void:
	for vent: Dictionary in _vents:
		vent["timer"] = float(vent["timer"]) - delta
		if float(vent["timer"]) > 0.0:
			continue
		var phase: String = String(vent["phase"])
		if phase == "idle":
			vent["phase"] = "warn"
			vent["timer"] = VENT_WARN
		elif phase == "warn":
			vent["phase"] = "on"
			vent["timer"] = VENT_ON
			var center: Vector2 = vent["pos"]
			_hit_in_radius(center, VENT_RADIUS, VENT_DAMAGE)
		else:
			vent["phase"] = "idle"
			vent["timer"] = VENT_IDLE


## One ring expands from the centre each cycle. The annulus test below means only
## CROSSING the ring hurts.
func _tick_pulse(delta: float) -> void:
	if _pulse_rest > 0.0:
		_pulse_rest -= delta
		if _pulse_rest <= 0.0:
			_pulse_prev = 0.0
			_pulse_r = 0.0
		return
	_pulse_prev = _pulse_r
	_pulse_r += PULSE_SPEED * delta
	_hit_ring(_pulse_prev, _pulse_r, PULSE_DAMAGE)
	if _pulse_r >= PULSE_MAX_RADIUS:
		_pulse_rest = PULSE_REST


func _tick_void(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = VOID_TICK
	for pool: Vector2 in _pools:
		_hit_in_radius(pool, VOID_RADIUS, VOID_DAMAGE)


## Hurt the player if they stand inside a hazard circle.
func _hit_in_radius(at: Vector2, radius: float, damage: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if at.distance_to(_player.global_position) <= radius:
		_damage_player(damage, at)


## Hurt the player if the expanding ring swept across them this frame. The ring is
## centred on the arena origin, so the player's distance from origin is the test.
func _hit_ring(from_r: float, to_r: float, damage: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var d: float = _player.global_position.length()
	if d >= from_r and d <= to_r:
		_damage_player(damage, Vector2.ZERO)


## One damage door. i-frames live in the player, so a player standing in a pool is
## hit once per invulnerability window -- never a per-frame shred -- and a dead
## player is a no-op. knockback is optional (the pulse shoves nothing).
func _damage_player(damage: int, from: Vector2) -> void:
	if _player == null or not _player.has_method("take_damage"):
		return
	var knock: Vector2 = Vector2.ZERO
	if from != Vector2.ZERO:
		var away: Vector2 = _player.global_position - from
		if away.length_squared() > 1.0:
			knock = away.normalized() * 130.0
	_player.take_damage(damage, knock)


func _draw() -> void:
	match kind:
		KIND_VENTS:
			for vent: Dictionary in _vents:
				var center: Vector2 = vent["pos"]
				var phase: String = String(vent["phase"])
				if phase == "warn":
					var t: float = 1.0 - clampf(float(vent["timer"]) / VENT_WARN, 0.0, 1.0)
					draw_circle(center, VENT_RADIUS * (0.35 + 0.65 * t), Color(color, 0.22))
					draw_arc(center, VENT_RADIUS, 0.0, TAU, 48, Color(color, 0.7), 2.0, true)
				elif phase == "on":
					draw_circle(center, VENT_RADIUS, Color(color, 0.5))
					draw_arc(center, VENT_RADIUS, 0.0, TAU, 48, color, 3.0, true)
				else:
					draw_arc(center, VENT_RADIUS, 0.0, TAU, 48, Color(color, 0.25), 1.0, true)
		KIND_PULSE:
			if _pulse_r > 0.0:
				draw_arc(Vector2.ZERO, _pulse_r, 0.0, TAU, 96, Color(color, 0.6), 6.0, true)
				draw_arc(Vector2.ZERO, maxf(_pulse_r - 8.0, 0.0), 0.0, TAU, 96, Color(color, 0.25), 10.0, true)
		KIND_VOID:
			for pool: Vector2 in _pools:
				draw_circle(pool, VOID_RADIUS, Color(color, 0.3))
				draw_arc(pool, VOID_RADIUS, 0.0, TAU, 48, Color(color, 0.7), 2.0, true)
