extends EnemyBase
class_name EnemyMirage
## Erratic blinker: every few seconds it dissolves and reappears at a random
## nearby spot, so aim has to lead where it is GOING. The blink refuses to land
## inside wall geometry -- a trapped mirage would be a free kill.

@export_group("Mirage")
@export var blink_interval: float = 2.4
@export var blink_min: float = 110.0
@export var blink_max: float = 190.0

const BLINK_PROBE_RADIUS := 14.0

var _blink_timer: float = blink_interval


func _update_behavior(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = blink_interval
		_blink()


## A random hop: any direction, not toward the player (that is the teleporting
## affix's job). Bursts at both ends sell the dissolve, same vocabulary as the
## affix so the two read as one mechanic family.
func _blink() -> void:
	var angle: float = randf() * TAU
	var dist: float = randf_range(blink_min, blink_max)
	var dest: Vector2 = global_position + Vector2.RIGHT.rotated(angle) * dist
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var probe := CircleShape2D.new()
	probe.radius = BLINK_PROBE_RADIUS
	q.shape = probe
	q.collision_mask = 8   # Wall layer: outer walls + all obstacles
	q.transform = Transform2D(0.0, dest)
	if not space.intersect_shape(q, 1).is_empty():
		return   # blocked: eat the timer, try again next cycle
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		var tint: Color = _base_tint().lightened(0.3)
		DeathBurst.spawn(layer, global_position, tint, 44.0, 0.2)
		DeathBurst.spawn(layer, dest, tint, 44.0, 0.2)
	global_position = dest
