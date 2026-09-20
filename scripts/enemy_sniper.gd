extends EnemyBase
class_name EnemySniper

@export var preferred_range := 430.0
@export var shot_interval := 2.4
@export var bullet_speed := 650.0
@export var bullet_damage := 14
var _shot_timer := 1.2

func _update_behavior(delta: float) -> void:
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_shot_timer = shot_interval
		var direction := (_player_position() - global_position).normalized()
		if direction != Vector2.ZERO:
			BulletPool.fire(global_position, direction, bullet_damage, bullet_speed, true)

func _desired_velocity() -> Vector2:
	var dist: float = _player_position().distance_to(global_position)
	# Retreat / close along the nav path, not the raw bearing.
	var fwd: Vector2 = _dir_toward_player()
	if dist < preferred_range * 0.75:
		return -fwd * move_speed
	if dist > preferred_range:
		return fwd * move_speed
	return Vector2.ZERO
