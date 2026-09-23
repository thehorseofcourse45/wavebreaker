extends EnemyBase
class_name EnemyBomber
## Suicide rusher: sprints at the player and detonates on a short fuse once in
## range. Killing it from range sets the blast off too, just on your terms --
## distance is the only counterplay, never the body.

@export_group("Bomber")
@export var trigger_range: float = 80.0
@export var fuse_time: float = 0.55
@export var blast_radius: float = 110.0
@export var blast_damage: int = 22

var _fuse: float = -1.0  # < 0 = not lit


func _update_behavior(delta: float) -> void:
	if _fuse < 0.0 \
			and _player_position().distance_to(global_position) <= trigger_range:
		_fuse = fuse_time
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			_die()


func _desired_velocity() -> Vector2:
	if _fuse >= 0.0:
		return Vector2.ZERO   # planted feet while the fuse burns
	return _steer_toward_player(move_speed)


## The blast IS the enemy: it fires on any death -- shot down, volatile affix,
## or its own fuse. super._die() keeps the wave bookkeeping intact.
func _die() -> void:
	if is_dead:
		return
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		DeathBurst.spawn(layer, global_position, Color(1.0, 0.45, 0.2), blast_radius, 0.32)
	var target: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if target != null and target.has_method("take_damage") \
			and global_position.distance_to(target.global_position) <= blast_radius:
		target.take_damage(blast_damage)
	super._die()
