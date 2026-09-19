extends EnemyBase
class_name EnemyWeaver
## Zig-zag approach: sine sway perpendicular to the chase direction.
## Reads as "dodging" without any state machine.

@export_group("Weaver")
@export var sway_frequency: float = 3.2  # Hz of the side-to-side oscillation
@export var sway_strength: float = 0.75  # fraction of forward speed spent swaying

var _phase: float = 0.0


func _update_behavior(delta: float) -> void:
	_phase += delta * sway_frequency * TAU


func _desired_velocity() -> Vector2:
	var to_player: Vector2 = _player_position() - global_position
	if to_player.length_squared() < 1.0:
		return Vector2.ZERO
	var fwd: Vector2 = to_player.normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var dir: Vector2 = (fwd + side * sin(_phase) * sway_strength).normalized()
	return dir * move_speed
