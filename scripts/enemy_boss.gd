extends EnemyBase
class_name EnemyBoss
## Wave boss: a giant shape that ignores every barrier and sprays swirling
## bullet-hell patterns out of the shared BulletPool.
##
## "Through any barrier" is two settings, not a physics trick: the collision
## MASK has no Wall bit (3 = Player | Enemy, layer 8 deliberately absent) so
## walls and obstacles never block or slide it, and `_nav_fallback = true` skips
## the navmesh entirely so it steers straight at the player instead of pathing
## around cover. It still collides with the player (contact damage) and other
## enemies, and player rounds still hit it (its BODY stays on the Enemy layer).
##
## Three combat phases on health thresholds, entered EXACTLY once each: health
## never rises, so the monotonically forward `_combat_phase` doubles as the
## once-guard (a bare `ratio < X` check re-fires every frame). Phase state is
## per-instance -- wave 10 onward fields a PAIR, and each boss phases on its
## own health bar.
##
## Phase 1 -- summon: minis on an interval, emitted through `split_spawned` so
## the WaveManager's existing splitter plumbing counts them toward the wave.
## Phase 2 -- radial burst: the ring fattens and quickens.
## Phase 3 -- charge: locked-direction dashes with a rest between them, on top
## of the phase-2 ring.

signal boss_phase_changed(phase: int, color: Color, at: Vector2)

@export_group("Bullet hell")
@export var ring_interval: float = 1.5
@export var ring_bullets: int = 14
@export var spiral_interval: float = 0.26
@export var spiral_bullets: int = 3
@export var spiral_step_deg: float = 17.0
@export var bullet_speed: float = 340.0
@export var spiral_speed_scale: float = 1.25
@export var bullet_damage: int = 8

@export_group("Phases")
## Health fraction where phase 2 begins; phase 3 at roughly half that again.
const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33
## The transition's announcement + burst colour, and the boss's death burst:
## the kill reads as the phase it died in.
const PHASE_2_COLOR := Color(0.9, 0.35, 1.0)
const PHASE_3_COLOR := Color(1.0, 0.3, 0.2)
## Phase 1: the summon.
@export var minion_interval: float = 4.0
@export var minion_count: int = 2
@export var minion_scene: PackedScene = preload("res://scenes/enemy_mini.tscn")
## Phase 2: the radial burst.
@export var burst_ring_bullets: int = 22
@export var burst_ring_interval: float = 1.1
## Phase 3: the charge.
@export var charge_speed: float = 520.0
@export var charge_time: float = 0.8
@export var charge_rest: float = 0.9

@export_group("Boss look")
@export var body_color_full: Color = Color(0.55, 0.15, 0.45)
@export var body_color_hurt: Color = Color(1.0, 0.55, 0.1)

var _ring_timer: float = 1.0
var _spiral_timer: float = 0.0
var _phase: float = 0.0
var _combat_phase: int = 1
var _minion_timer: float = 0.0
var _charge_timer: float = 0.0
var _charging: bool = false
var _charge_dir: Vector2 = Vector2.RIGHT


func _ready() -> void:
	super._ready()
	add_to_group("bosses")    # Main counts boss kills for the unlockables
	collision_mask = 3        # Player (1) + Enemy (2); no Wall (8) -> walks through cover
	_nav_disabled = true      # straight-line pursuit, no navmesh (never falls back)
	_nav_fallback = true
	_minion_timer = minion_interval


func _update_behavior(delta: float) -> void:
	_check_phase()
	_ring_timer -= delta
	_spiral_timer -= delta
	_phase += deg_to_rad(spiral_step_deg) * delta / maxf(spiral_interval, 0.01)
	if _ring_timer <= 0.0:
		_ring_timer = ring_interval
		_fire_ring()
	if _spiral_timer <= 0.0:
		_spiral_timer = spiral_interval
		_fire_spiral()
	match _combat_phase:
		1:
			_minion_timer -= delta
			if _minion_timer <= 0.0:
				_minion_timer = minion_interval
				_summon_minions()
		3:
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charging = not _charging
				if _charging:
					_charge_dir = (_player_position() - global_position).normalized()
					_charge_timer = charge_time
				else:
					_charge_timer = charge_rest


## Thresholds. Health never rises, so `_combat_phase` moving only forward IS
## the once-guard: the same ratio cannot re-enter a threshold it already passed.
func _check_phase() -> void:
	var ratio: float = float(health) / float(maxi(max_health, 1))
	if _combat_phase == 1 and ratio < PHASE_2_AT:
		_enter_combat_phase(2)
	elif _combat_phase == 2 and ratio < PHASE_3_AT:
		_enter_combat_phase(3)


func _enter_combat_phase(phase: int) -> void:
	_combat_phase = phase
	match phase:
		2:
			ring_bullets = burst_ring_bullets
			ring_interval = burst_ring_interval
			death_burst_color = PHASE_2_COLOR
		3:
			death_burst_color = PHASE_3_COLOR
			_charge_timer = 0.0   # the first charge leaves on the next tick
	_charging = false
	boss_phase_changed.emit(phase, death_burst_color, global_position)


## Phase 1 attack: the summon. Same contract as the splitter's -- the pair is
## emitted, not parented, so the WaveManager can count them toward the wave
## (it is not cleared while they live) and Main's kill watcher arms on entry.
func _summon_minions() -> void:
	var pair: Array = []
	for i: int in minion_count:
		var mini: EnemyBase = minion_scene.instantiate() as EnemyBase
		if mini == null:
			push_warning("EnemyBoss: minion_scene failed to instantiate.")
			continue
		mini.global_position = global_position + Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(minion_count, 1))) * 90.0
		pair.append(mini)
	if not pair.is_empty():
		split_spawned.emit(pair)


## Straight at the player -- the base class still handles separation, knockback
## (scaled by `knockback_resist` in the scene) and contact damage. Phase 3
## overrides the walk with locked dashes.
func _desired_velocity() -> Vector2:
	if _charging:
		return _charge_dir * charge_speed
	return _steer_toward_player(move_speed)


## Health read-out without new UI: the body heats up from violet to orange as
## it takes damage, so a long fight still shows progress. EnemyBase applies this
## (and overrides it with white on the frame the boss is hit).
func _base_tint() -> Color:
	var hurt: float = 1.0 - clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
	return body_color_full.lerp(body_color_hurt, hurt)


func _fire_ring() -> void:
	var count: int = maxi(3, ring_bullets)
	for i: int in count:
		var angle: float = _phase + TAU * float(i) / float(count)
		BulletPool.fire(global_position, Vector2.RIGHT.rotated(angle), bullet_damage, bullet_speed, true)


func _fire_spiral() -> void:
	var count: int = maxi(1, spiral_bullets)
	for i: int in count:
		var angle: float = _phase + TAU * float(i) / float(count)
		BulletPool.fire(global_position, Vector2.RIGHT.rotated(angle), bullet_damage,
				bullet_speed * spiral_speed_scale, true)
