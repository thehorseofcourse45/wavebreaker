extends EnemyBoss
class_name EnemyBossHive

@export var hive_interval := 2.6
var _hive_timer := 1.0

func _update_behavior(delta: float) -> void:
	super._update_behavior(delta)
	_hive_timer -= delta
	if _hive_timer <= 0.0:
		_hive_timer = hive_interval
		_summon_minions()
		_summon_minions()
