extends EnemyBase
class_name EnemyRammer

@export var acceleration_scale := 2.4
@export var max_rush_speed := 430.0

func _desired_velocity() -> Vector2:
	var distance := global_position.distance_to(_player_position())
	var rush := clampf(move_speed + distance * acceleration_scale, move_speed, max_rush_speed)
	return _steer_toward_player(rush)
