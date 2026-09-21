extends Area2D
class_name Bullet
## Pooled player projectile.
##
## Bullets are NEVER created/destroyed during gameplay. The BulletPool autoload
## pre-instantiates them and reactivates them via [method fire]. When a bullet
## hits something or expires it deactivates itself and emits [signal deactivated]
## so the pool can reuse it. Active bullets fly straight in [member direction].

signal deactivated(bullet: Bullet)

## Unlockable "hollow_point": player rounds burn white-hot and the bloom with
## them. Read at fire time, so it lands on the next shot after it is earned.
const PLAYER_ROUND_COLOR := Color(1.0, 0.85, 0.3)
const HOLLOW_POINT_COLOR := Color(1.0, 0.97, 0.78)
const HOSTILE_ROUND_COLOR := Color(1.0, 0.4, 0.55)

## Enemy shots set this before firing; shared pool, so the flag flips the
## bullet's collision layer/mask onto the player and tint it hostile red.
## Bullets are parked with hostile=false in _deactivate_immediate.

var hostile: bool = false

@export_group("Projectile")
@export var damage: int = 12
@export var speed: float = 700.0
## Range, in seconds of flight. A weapon archetype overrides this per shot (a
## flamethrower is a 0.3 s round), so it is the DEFAULT, not a constant.
const BASE_LIFETIME := 2.0
@export var lifetime: float = BASE_LIFETIME
@export var knockback_force: float = 120.0

var direction: Vector2 = Vector2.RIGHT
var is_active: bool = false

## Pool-owned per-shot config (BulletPool.fire sets these BEFORE fire() runs):
## extra enemies this round passes through, and its crit odds. A piercing round
## remembers what it already hit so it can never double-dip one body.
var pierce_left: int = 0
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0

## Pool-owned per-shot behavior config (BulletPool.fire sets these BEFORE fire()):
## homing turn rate + look range, wall bounces left, and the kill-blast. Inert for
## a plain round and for every enemy round.
var homing_scale: float = 0.0
var homing_range: float = 420.0
var bounce_left: int = 0
var explosive_radius: float = 0.0
var explosive_damage: int = 0

var _hit_ids: Array[int] = []
var _age: float = 0.0


func _ready() -> void:
	# The pool parents pre-instantiated bullets to itself (a plain Node with no
	# transform), so local position == global position. Start dormant.
	body_entered.connect(_on_body_entered)
	_deactivate_immediate()


## Activate this bullet. Called ONLY by BulletPool.fire(), which owns [member hostile]
## and sets it BEFORE this call -- the reset lives in [method _deactivate_immediate]
## (park time), never here: resetting it in fire() made the hostile branch dead code.
func fire(start_position: Vector2, fire_direction: Vector2, new_damage: int, new_speed: float) -> void:
	collision_layer = 4   # keep PlayerBullet layer so walls still stop it
	if hostile:
		collision_mask = 9    # hit Player (1) + Wall (8), ignore other enemies
	else:
		collision_mask = 10   # Enemy (2) + Wall (8)
	global_position = start_position
	rotation = fire_direction.angle()
	direction = fire_direction.normalized()
	damage = new_damage
	speed = new_speed
	_age = 0.0
	is_active = true
	visible = true
	var body_poly: Polygon2D = get_node_or_null("Body") as Polygon2D
	if body_poly != null:
		if hostile:
			body_poly.color = HOSTILE_ROUND_COLOR
		elif Unlockables.is_unlocked("hollow_point"):
			body_poly.color = HOLLOW_POINT_COLOR
		else:
			body_poly.color = PLAYER_ROUND_COLOR
	# monitoring is toggled deferred because fire() runs inside physics callbacks
	# (player movement) and Area2D forbids flipping monitoring mid-physics-flush.
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_age += delta
	if _age >= lifetime:
		deactivate()
		return
	if homing_scale > 0.0 and not hostile:
		_steer_homing(delta)
	rotation = direction.angle()
	var old_pos: Vector2 = global_position
	global_position += direction * speed * delta
	# Swept hit: bullets move up to ~20 px/frame -- the plain Area2D shape
	# misses enemies it crosses without overlapping. Raycast the segment
	# old->new and resolve the first enemy/player/wall it intersects.
	# (Runs in physics tick so the space state is current.)
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(old_pos, global_position, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]  # Area2D vs bodies only, but be explicit
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		# Cases the ray misses: starting INSIDE a body (enemy charged into the
		# bullet's old position this frame), or grazing a tiny corner. Fall back
		# to a shape-overlap probe at both endpoints of the frame's segment.
		var shape_q := PhysicsShapeQueryParameters2D.new()
		shape_q.shape = (get_node("CollisionShape2D") as CollisionShape2D).shape
		shape_q.collision_mask = collision_mask
		shape_q.transform = Transform2D(0.0, old_pos)
		var results := space.intersect_shape(shape_q, 1)
		if results.is_empty():
			shape_q.transform = Transform2D(0.0, global_position)
			results = space.intersect_shape(shape_q, 1)
		if not results.is_empty():
			hit = results[0]
	if not hit.is_empty():
		var collider: Node2D = hit.get("collider") as Node2D
		if collider is StaticBody2D and bounce_left > 0:
			# Ricochet: reflect off the wall. `normal`/`position` exist on a ray hit
			# but NOT on the shape-overlap fallback, so guard both.
			var wall_normal: Vector2 = hit["normal"] if hit.has("normal") else -direction
			var wall_at: Vector2 = hit["position"] if hit.has("position") else global_position
			_bounce_off(wall_normal, wall_at)
		else:
			_handle_hit(collider)


## Homing (shop row): turn the round's heading toward the nearest enemy, capped at
## homing_scale radians per second so it curves rather than snaps. Re-aimed every
## frame; the sweep above still resolves whatever it crosses.
func _steer_homing(delta: float) -> void:
	var target: Node2D = _nearest_enemy()
	if target == null:
		return
	var to: Vector2 = target.global_position - global_position
	if to.length_squared() < 1.0:
		return
	var max_turn: float = homing_scale * delta
	direction = direction.rotated(clampf(direction.angle_to(to.normalized()), -max_turn, max_turn))


## Closest enemy within homing_range, or null. A plain linear scan: the enemy group
## is dozens at most, and only homing rounds pay for it.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d: float = homing_range * homing_range
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Ricochet (shop row): reflect off a wall instead of dying on it. The round is
## nudged just clear of the surface so the next frame's ray starts outside it.
func _bounce_off(normal: Vector2, at: Vector2) -> void:
	bounce_left -= 1
	direction = direction.bounce(normal)
	rotation = direction.angle()
	global_position = at + normal * 3.0


## Explosive (shop row): a round that KILLS detonates. Enemies only -- the blast
## never hurts the player -- and it does not chain (a blast kill never re-detonates).
## Damage routes through EnemyBase.take_damage, so armour auras and affixes apply
## exactly as they do to the bullet itself.
func _detonate(at: Vector2) -> void:
	if explosive_radius <= 0.0 or explosive_damage <= 0:
		return
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		DeathBurst.spawn(layer, at, Color(1.0, 0.62, 0.2), explosive_radius, 0.3)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy: EnemyBase = node as EnemyBase
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var offset: Vector2 = enemy.global_position - at
		if offset.length() <= explosive_radius:
			var push: Vector2 = offset.normalized() * BulletPool.base_knockback * 0.5 if offset.length_squared() > 1.0 else Vector2.ZERO
			BulletPool.damage_dealt += int(enemy.take_damage(explosive_damage, push))


func _on_body_entered(body: Node2D) -> void:
	# Area2D fallback (bullets that start inside an enemy or arrive at low
	# speed still register here even if the raycast missed the edge frame).
	if not is_active:
		return
	_handle_hit(body)


func _handle_hit(body: Node2D) -> void:
	if body == null:
		return
	if hostile and body.is_in_group("player") and body.has_method("take_damage"):
		(body as Node).take_damage(damage, direction * knockback_force)
		deactivate()
		return
	if not hostile and body.is_in_group("enemies") and body.has_method("take_damage"):
		var id: int = body.get_instance_id()
		if _hit_ids.has(id):
			return   # already pierced this one -- pass through, never double-dip
		_hit_ids.append(id)
		# Crit is rolled per enemy hit, so one piercing round can crit on the
		# first body and not the second. The number that pops is what landed.
		var crit: bool = crit_chance > 0.0 and randf() < crit_chance
		var dealt: int = int(round(float(damage) * (crit_multiplier if crit else 1.0)))
		if crit:
			BulletPool.crit_landed.emit()   # lifetime counter, not per-run bookkeeping
		# The number carries the enemy's own colour, so a kill reads as WHICH
		# enemy was hit, not just how hard.
		var tint: Color = (body as EnemyBase).death_burst_color if body is EnemyBase else Color(0.0, 0.0, 0.0, 0.0)
		DamageNumbers.spawn(body.global_position, dealt, crit, tint)
		var applied: int = int(body.take_damage(dealt, direction * knockback_force))
		BulletPool.damage_dealt += applied   # actual HP removed, not blocked/overkill damage
		# Explosive rounds detonate on the KILLING blow only: a wounded enemy does not
		# blast, or every round would be an area weapon. `is_dead` is set by _die()
		# synchronously inside take_damage.
		if body is EnemyBase and (body as EnemyBase).is_dead:
			_detonate(body.global_position)
		if pierce_left > 0:
			pierce_left -= 1
			return   # keep flying: shop "pierce" rounds pass through N enemies
		deactivate()
		return
	if body is StaticBody2D:
		deactivate()


## Public deactivate: hides the bullet and hands it back to the pool.
func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	_hit_ids.clear()   # the next flight starts with a clean pierce history
	# Behavior config is PER SHOT too (see BulletPool.fire): clear it so a plain
	# round dealt this pooled bullet cannot inherit homing / bounces / a blast.
	homing_scale = 0.0
	bounce_left = 0
	explosive_radius = 0.0
	explosive_damage = 0
	# Range and size are PER SHOT (see BulletPool.fire), so they must not survive a
	# flight: the pool is shared with the enemies, whose rounds pass neither.
	lifetime = BASE_LIFETIME
	scale = Vector2.ONE
	set_deferred("monitoring", false)
	set_physics_process(false)
	deactivated.emit(self)


## Used once at pool construction (and on scene reset) before any activation.
func _deactivate_immediate() -> void:
	is_active = false
	hostile = false
	visible = false
	_hit_ids.clear()
	homing_scale = 0.0
	bounce_left = 0
	explosive_radius = 0.0
	explosive_damage = 0
	lifetime = BASE_LIFETIME
	scale = Vector2.ONE
	set_deferred("monitoring", false)
	set_physics_process(false)
	position = Vector2.ZERO
	rotation = 0.0
	direction = Vector2.RIGHT
	_age = 0.0
