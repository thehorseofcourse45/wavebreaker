extends EnemyBase
class_name EnemyMedic

@export var heal_interval := 3.0
@export var heal_radius := 210.0
@export var heal_amount := 18
var _heal_timer := 1.5

func _update_behavior(delta: float) -> void:
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer = heal_interval
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as EnemyBase
		if ally != null and ally != self and not ally.is_dead and global_position.distance_to(ally.global_position) <= heal_radius:
			ally.health = mini(ally.health + heal_amount, ally.max_health)

func _desired_velocity() -> Vector2:
	var dist: float = _player_position().distance_to(global_position)
	var fwd: Vector2 = _dir_toward_player()
	return -fwd * move_speed if dist < 240.0 else fwd * move_speed * 0.65
