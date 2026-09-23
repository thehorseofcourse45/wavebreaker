extends EnemyBase
class_name EnemyPhalanx
## Grid-locked pursuit: moves only along the cardinal axes, committing to the
## dominant one for a beat before re-evaluating. Kiting it diagonally is free --
## crossing its lane is the counterplay.

@export_group("Phalanx")
@export var commit_time: float = 0.35  # seconds an axis is locked before a re-read

var _axis: Vector2 = Vector2.RIGHT
var _commit_timer: float = 0.0


func _update_behavior(delta: float) -> void:
	_commit_timer -= delta
	if _commit_timer > 0.0:
		return
	_commit_timer = commit_time
	var fwd: Vector2 = _dir_toward_player()
	if fwd == Vector2.ZERO:
		return
	# Dominant component wins the whole axis: the nav path bends, the phalanx
	# does not -- that stair-step is the identity.
	if absf(fwd.x) >= absf(fwd.y):
		_axis = Vector2(signf(fwd.x), 0.0)
	else:
		_axis = Vector2(0.0, signf(fwd.y))


func _desired_velocity() -> Vector2:
	return _axis * move_speed
