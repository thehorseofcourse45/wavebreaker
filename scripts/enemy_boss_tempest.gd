extends EnemyBoss
class_name EnemyBossTempest

@export var cross_interval := 0.7
var _cross_timer := 0.0
var _cross_phase := 0.0

func _update_behavior(delta: float) -> void:
	super._update_behavior(delta)
	_cross_timer -= delta
	_cross_phase += delta * 0.8
	if _cross_timer <= 0.0:
		_cross_timer = cross_interval
		for i: int in 4:
			BulletPool.fire(global_position, Vector2.RIGHT.rotated(_cross_phase + i * PI * 0.5), bullet_damage, bullet_speed * 1.35, true)

func _desired_velocity() -> Vector2:
	if _charging:
		return _charge_dir * charge_speed
	var radial := (_player_position() - global_position).normalized()
	return Vector2(-radial.y, radial.x) * move_speed
