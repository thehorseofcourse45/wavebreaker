extends EnemyBase
class_name EnemySentinel
## Planted turret: stands still and shoots in bursts, then relocates to a new
## ring position. The walk is its vulnerable window -- while planted it never
## moves, while moving it never fires.

@export_group("Sentinel")
@export var planted_time: float = 2.8
@export var relocate_time: float = 1.1
@export var shot_interval: float = 0.9
@export var bullet_speed: float = 320.0
@export var bullet_damage: int = 7
@export var keep_distance: float = 240.0

var _planting: bool = true
var _state_timer: float = planted_time
var _shot_timer: float = shot_interval


func _update_behavior(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_planting = not _planting
		_state_timer = planted_time if _planting else relocate_time
		_shot_timer = shot_interval
	if _planting:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_timer = shot_interval
			_fire_at_player()


func _desired_velocity() -> Vector2:
	if _planting:
		return Vector2.ZERO
	# Relocating: hold a rough ring around the player (shooter's rule) at full
	# speed, so the walk reads as repositioning rather than fleeing.
	var dist: float = _player_position().distance_to(global_position)
	var fwd: Vector2 = _dir_toward_player()
	if dist < keep_distance * 0.8:
		return -fwd * move_speed
	if dist > keep_distance:
		return fwd * move_speed
	return Vector2.ZERO


func _fire_at_player() -> void:
	var dir: Vector2 = (_player_position() - global_position).normalized()
	if dir == Vector2.ZERO:
		return
	BulletPool.fire(global_position, dir, bullet_damage, bullet_speed, true)
