extends EnemyBoss
class_name EnemyBossJuggernaut

@export var shock_interval := 1.8
var _shock_timer := 0.8

func _update_behavior(delta: float) -> void:
	super._update_behavior(delta)
	_shock_timer -= delta
	if _shock_timer <= 0.0:
		_shock_timer = shock_interval
		for i: int in 10:
			BulletPool.fire(global_position, Vector2.RIGHT.rotated(TAU * i / 10.0), bullet_damage + 4, bullet_speed * 0.72, true)
