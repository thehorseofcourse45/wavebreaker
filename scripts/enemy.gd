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

var health: int = max_health
var is_dead: bool = false
var is_dormant: bool = false  # set on game over: freezes the enemy in place

var _knockback_vel: Vector2 = Vector2.ZERO
var _contact_timer: float = 0.0
var _flash_timer: float = 0.0
var _retarget_timer: float = 0.0
var _nav_fallback: bool = false  # true = steer directly (no usable navmesh)
var _player: Node2D = null

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
	health = max_health
	if is_instance_valid(_body):
		_base_color = _body.color
		# Lit: enemies are receivers, so the player's torch is what reveals them.
		LitLighting.make_receiver(_body)
		# ...and each one glows on its own, in its own colour (rime-tinted enemies glow
		# cold). No shadows on these: one shadow-casting light per enemy would be the
		# whole frame's budget for a halo nobody looks at.
		LitLighting.add_point_light(self, _base_tint().lightened(GLOW_LIFT), GLOW_RANGE, GLOW_ENERGY)
	_build_rim()


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
	var target: Vector2 = _player_position()
	var to_target: Vector2 = target - global_position
	if to_target.length_squared() < 4.0:
		return Vector2.ZERO
	if _nav_fallback:
		return to_target.normalized() * speed
	var next: Vector2 = _nav.get_next_path_position()
	var step: Vector2 = next - global_position
	if step.length_squared() < 4.0:
		return to_target.normalized() * speed
	return step.normalized() * speed


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
	var target: Vector2 = _player_position()
	_nav.target_position = target
	# When no NavigationPolygon is baked (or the target can't be pathed to),
	# the agent reports unreachable -- steer straight so gameplay never stalls.
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
				(collider as Node).take_damage(contact_damage, away * player_knockback)
				_contact_timer = contact_cooldown
				break


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead or amount <= 0:
		return
	var dealt: int = maxi(1, int(round(float(amount) * damage_taken_mult)))
	health -= dealt
	_flash_timer = flash_time
	_knockback_vel += knockback * (1.0 - clampf(knockback_resist, 0.0, 1.0))
	damaged.emit(dealt)
	if health <= 0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	# Stop colliding this frame so stray bullets can't double-count the kill.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	died.emit(self)


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
