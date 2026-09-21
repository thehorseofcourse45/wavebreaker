extends Node
## Autoload singleton ("BulletPool"): owns every Bullet in the game.
##
## At startup it pre-instantiates [member pool_size] bullets from bullet.tscn.
## [method fire] hands out an inactive bullet; bullets return themselves via
## the [signal Bullet.deactivated] signal. If the pool is exhausted it grows by
## one instead of dropping the shot (a warning is printed so you can raise
## pool_size). Enemies can call BulletPool.fire() too -- no changes needed.
##
## IMPORTANT: autoloads survive scene reloads, so Main calls [method reset]
## on every fresh run to park any bullets left over from a previous game.

@export_group("Pool")
## Sized for the worst realistic case: 4 bullets/shot (split shot maxed) at the
## 0.06 s fire-rate floor is ~67 rounds/s, and each lives 2 s -> ~135 in flight.
@export var pool_size: int = 160
@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")

@export_group("Knockback")
## Base knockback one round deals on hit (matches bullet.tscn's default). The pool owns
## it because bullets are shared: enemy rounds carry the same base, so there is one number
## to tune if the push ever needs to change.
@export var base_knockback: float = 120.0

@export_group("Crits")
## Player rounds only, and rolled per ENEMY hit (so one piercing round can crit
## on the first enemy and not the second). The number that pops is the damage
## actually dealt. Enemy rounds never crit. The shop's crit rows raise both from
## their authored values (see UpgradeSystem); Main restores them with
## reset_run_config() because the pool outlives a run.
@export var crit_chance: float = 0.10
@export var crit_multiplier: float = 2.0

@export_group("Behavior (shop-made)")
## Rows that reshape rounds rather than just scale them. All inert by default, so
## a run that buys none behaves exactly as before. Handed to each PLAYER round in
## fire(), like crit -- enemy rounds never carry them.
@export var homing_strength: float = 0.0   # radians/sec a round may turn toward the nearest enemy
@export var homing_range: float = 420.0     # how far a round looks for a homing target
@export var bounce_count: int = 0           # wall reflections a round gets
@export var explosive_radius: float = 0.0   # kill-blast radius (0 = off)
@export var explosive_damage: int = 0       # damage that blast deals

## Emitted by a round that just crit, for the lifetime "crits landed" counter.
## The pool owns the signal because the pool owns crit_chance -- Bullet reads it.
signal crit_landed

## Authored defaults, captured once at _ready so reset_run_config() has something
## to restore a shop-mutated pool to.
var _base_crit_chance: float = 0.0
var _base_crit_multiplier: float = 1.0
var _base_homing_strength: float = 0.0
var _base_bounce_count: int = 0
var _base_explosive_radius: float = 0.0
var _base_explosive_damage: int = 0

## Damage the player's rounds have dealt since Main zeroed it at run start (the
## STATS tab's DPS column). NOT cleared by reset(): an arena swap mid-run must not
## wipe the run's damage total.
var damage_dealt: int = 0

var _free: Array[Bullet] = []
var _all: Array[Bullet] = []


func _ready() -> void:
	_base_crit_chance = crit_chance
	_base_crit_multiplier = crit_multiplier
	_base_homing_strength = homing_strength
	_base_bounce_count = bounce_count
	_base_explosive_radius = explosive_radius
	_base_explosive_damage = explosive_damage
	for i: int in pool_size:
		_spawn_pooled_bullet()


## `pierce` = extra enemies the round passes through (player rounds only).
## `knockback_scale` multiplies this shot's push (the charge shot uses it).
## `lifetime` / `scale` are 0 -> keep the bullet's own parked defaults
## (Bullet.BASE_LIFETIME / 1.0), so a caller that cares about neither is unaffected.
## Weapons pass both; the charge shot passes scale only, to keep its own range.
func fire(start_position: Vector2, fire_direction: Vector2, new_damage: int, new_speed: float,
		is_hostile: bool = false, pierce: int = 0, knockback_scale: float = 1.0,
		lifetime: float = 0.0, scale: float = 0.0) -> Bullet:
	var bullet: Bullet = _take_free_bullet()
	bullet.hostile = is_hostile
	bullet.knockback_force = base_knockback * knockback_scale
	if is_hostile:
		bullet.pierce_left = 0
		bullet.crit_chance = 0.0
		# Enemy rounds never carry the shop-made behavior: clear it so a pooled
		# bullet reused by an enemy cannot inherit the player's last build.
		bullet.homing_scale = 0.0
		bullet.bounce_left = 0
		bullet.explosive_radius = 0.0
		bullet.explosive_damage = 0
	else:
		bullet.pierce_left = maxi(0, pierce)
		bullet.crit_chance = crit_chance
		bullet.homing_scale = homing_strength
		bullet.homing_range = homing_range
		bullet.bounce_left = bounce_count
		bullet.explosive_radius = explosive_radius
		bullet.explosive_damage = explosive_damage
	bullet.crit_multiplier = crit_multiplier
	if lifetime > 0.0:
		bullet.lifetime = lifetime
	if scale > 0.0:
		bullet.scale = Vector2.ONE * scale
	bullet.fire(start_position, fire_direction, new_damage, new_speed)
	return bullet


## Park every bullet (used after scene reload and on game over).
func reset() -> void:
	for bullet: Bullet in _all:
		if is_instance_valid(bullet):
			bullet._deactivate_immediate()
	_free = _all.duplicate()


## Restore every shop-tunable value to its authored default. The pool is an
## autoload, so a maxed crit / behavior build would otherwise leak into the NEXT
## run; Main calls this once at run start, right beside reset(). Bullet behavior
## is per-run state, not the pool's own config.
func reset_run_config() -> void:
	crit_chance = _base_crit_chance
	crit_multiplier = _base_crit_multiplier
	homing_strength = _base_homing_strength
	bounce_count = _base_bounce_count
	explosive_radius = _base_explosive_radius
	explosive_damage = _base_explosive_damage


## How many bullets are currently flying (handy for HUD/debug).
func active_count() -> int:
	return _all.size() - _free.size()


func _take_free_bullet() -> Bullet:
	if _free.is_empty():
		push_warning("BulletPool exhausted (pool_size=%d) -- growing by one. Consider raising pool_size." % _all.size())
		return _spawn_pooled_bullet()
	return _free.pop_back()


func _spawn_pooled_bullet() -> Bullet:
	var bullet: Bullet = bullet_scene.instantiate() as Bullet
	add_child(bullet)
	bullet._deactivate_immediate()
	if not bullet.deactivated.is_connected(_on_bullet_deactivated):
		bullet.deactivated.connect(_on_bullet_deactivated)
	_all.append(bullet)
	_free.append(bullet)
	return bullet


func _on_bullet_deactivated(bullet: Bullet) -> void:
	if not _free.has(bullet):
		_free.append(bullet)
