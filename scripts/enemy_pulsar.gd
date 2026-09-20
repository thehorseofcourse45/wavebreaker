extends EnemyOrbiter
class_name EnemyPulsar

@export var pulse_interval := 2.8
@export var pulse_bullets := 8
@export var bullet_speed := 260.0
@export var bullet_damage := 7
var _pulse_timer := 1.4

func _update_behavior(delta: float) -> void:
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer = pulse_interval
		for i: int in pulse_bullets:
			BulletPool.fire(global_position, Vector2.RIGHT.rotated(TAU * i / pulse_bullets), bullet_damage, bullet_speed, true)
