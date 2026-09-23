extends EnemyBase
class_name EnemySkitterer
## Chases while healthy, bolts the moment it is hurt -- below the flee threshold
## it backs along the nav path (so it retreats around cover, not through it)
## with a nervous side-wobble. Corner it or run it down.

@export_group("Skitterer")
@export var flee_ratio: float = 0.5   # health fraction below which it runs
@export var wobble_frequency: float = 5.0
@export var wobble_strength: float = 0.4

var _phase: float = 0.0


func _update_behavior(delta: float) -> void:
	_phase += delta * wobble_frequency * TAU


func _desired_velocity() -> Vector2:
	var fwd: Vector2 = _dir_toward_player()
	if fwd == Vector2.ZERO:
		return Vector2.ZERO
	var side := Vector2(-fwd.y, fwd.x)
	var wobble: Vector2 = side * sin(_phase) * wobble_strength
	var fleeing: bool = float(health) <= float(max_health) * flee_ratio
	# Flee along the nav corridor's reverse -- a raw to-player vector would grid
	# itself into the same wall the path just walked around.
	var core: Vector2 = -fwd if fleeing else fwd
	return (core + wobble).normalized() * move_speed
