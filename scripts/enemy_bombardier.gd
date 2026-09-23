extends EnemyBase
class_name EnemyBombardier
## Long-range lobber: holds a wide ring, plants to wind up, then fires one slow
## heavy shell -- big, readable, and dodgeable if you move early. The windup
## stop IS the telegraph.

@export_group("Bombardier")
@export var keep_distance: float = 360.0
@export var flee_range: float = 280.0
@export var creep_speed_scale: float = 0.6
@export var shot_interval: float = 2.6
@export var windup_time: float = 0.7
@export var shell_speed: float = 150.0
@export var shell_damage: int = 18
@export var shell_scale: float = 2.4

var _cooldown: float = shot_interval


func _update_behavior(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire_shell()
		_cooldown = shot_interval


func _desired_velocity() -> Vector2:
	var dist: float = _player_position().distance_to(global_position)
	# The windup stop: rooted while the shell is chambered, so the player gets
	# windup_time to sidestep before the round is loose.
	if _cooldown <= windup_time:
		return Vector2.ZERO
	var fwd: Vector2 = _dir_toward_player()
	if dist < flee_range:
		return -fwd * move_speed
	if dist > keep_distance:
		return fwd * move_speed * creep_speed_scale
	return Vector2.ZERO


func _fire_shell() -> void:
	var dir: Vector2 = (_player_position() - global_position).normalized()
	if dir == Vector2.ZERO:
		return
	# BulletPool.fire's trailing scale param makes the shell read as its own
	# class of round: fat, slow, and unmistakably not a pellet.
	BulletPool.fire(global_position, dir, shell_damage, shell_speed, true,
			0, 1.0, 0.0, shell_scale)
