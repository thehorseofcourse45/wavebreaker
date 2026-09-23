extends EnemyBase
class_name EnemySkirmisher

@export var keep_distance := 280.0
@export var flee_range := 180.0
@export var creep_speed_scale := 0.7
@export var shot_interval := 1.25
@export var bullet_speed := 390.0
@export var bullet_damage := 6
var _shot_timer := 0.5
var _side := 1.0

func _ready() -> void:
	super._ready()
	_side = -1.0 if randf() < 0.5 else 1.0

func _update_behavior(delta: float) -> void:
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_shot_timer = shot_interval
		var aim := (_player_position() - global_position).normalized()
		for spread: float in [-0.12, 0.12]:
			BulletPool.fire(global_position, aim.rotated(spread), bullet_damage, bullet_speed, true)

func _desired_velocity() -> Vector2:
	var dist := _player_position().distance_to(global_position)
	if dist < 1.0:
		return Vector2.ZERO
	var radial := _dir_toward_player()
	if radial == Vector2.ZERO:
		return Vector2.ZERO
	# Keep the engagement band: flee when too close, creep when too far, only
	# strafe while inside it -- otherwise it orbits forever out of bullet range.
	if dist < flee_range:
		return -radial * move_speed
	if dist > keep_distance:
		return radial * move_speed * creep_speed_scale
	return Vector2(-radial.y, radial.x) * move_speed * _side
