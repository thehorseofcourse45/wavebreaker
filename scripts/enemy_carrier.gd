extends EnemyBase
class_name EnemyCarrier
## Slow courier that grows a mini every few seconds while it advances -- the
## wave cannot shrink while it lives, so it is a priority target with Medic's
## urgency and none of its healing. Uses the splitter's split_spawned contract
## so the WaveManager parents and counts the offspring with no new plumbing.

@export_group("Carrier")
@export var spawn_interval: float = 4.5
@export var max_brood: int = 2

var _spawn_timer: float = spawn_interval
var _brood: Array[Node] = []


func _update_behavior(delta: float) -> void:
	for i: int in range(_brood.size() - 1, -1, -1):
		if not is_instance_valid(_brood[i]):
			_brood.remove_at(i)
	if _brood.size() >= max_brood:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval
	_spawn_mini()


func _spawn_mini() -> void:
	var scene: PackedScene = load("res://scenes/enemy_mini.tscn") as PackedScene
	if scene == null:
		push_warning("EnemyCarrier: could not load enemy_mini.tscn")
		return
	var mini: EnemyBase = scene.instantiate() as EnemyBase
	if mini == null:
		return
	mini.global_position = global_position \
			+ Vector2.RIGHT.rotated(randf() * TAU) * 26.0
	_brood.append(mini)
	split_spawned.emit([mini])
