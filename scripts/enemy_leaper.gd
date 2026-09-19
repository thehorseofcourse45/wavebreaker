extends EnemyBase
class_name EnemyLeaper
## Closes distance in telegraphed bursts: it approaches, plants and flashes
## (windup), then makes one fast leap in a locked direction, then recovers.
## The leap direction is locked at windup end so players can dodge -- the same
## fair-telegraph contract as the rusher, but in discrete hops with rests
## between them.

enum State { APPROACH, WINDUP, LEAP, RECOVER }

@export_group("Leaper")
@export var windup_range: float = 320.0
@export var windup_time: float = 0.35
@export var leap_time: float = 0.28
@export var leap_speed: float = 560.0
@export var recover_time: float = 0.55
@export var approach_speed_scale: float = 0.7

var _state: int = State.APPROACH
var _state_timer: float = 0.0
var _leap_direction: Vector2 = Vector2.RIGHT


func _update_behavior(delta: float) -> void:
	_state_timer -= delta
	match _state:
		State.APPROACH:
			if _distance_to_player() < windup_range:
				_enter_state(State.WINDUP, windup_time)
		State.WINDUP:
			if _state_timer <= 0.0:
				# Lock the leap direction now (dodgeable!) and go.
				_leap_direction = (_player_position() - global_position).normalized()
				if _leap_direction == Vector2.ZERO:
					_leap_direction = Vector2.RIGHT
				_enter_state(State.LEAP, leap_time)
		State.LEAP:
			if _state_timer <= 0.0:
				_enter_state(State.RECOVER, recover_time)
		State.RECOVER:
			if _state_timer <= 0.0:
				_enter_state(State.APPROACH, 0.0)


func _desired_velocity() -> Vector2:
	match _state:
		State.WINDUP:
			# Planted: the telegraph reads as a full stop, not a creep.
			return Vector2.ZERO
		State.LEAP:
			return _leap_direction * leap_speed
		State.RECOVER:
			return _steer_toward_player(move_speed * 0.25)
		_:
			return _steer_toward_player(move_speed * approach_speed_scale)


func _process(delta: float) -> void:
	super._process(delta)
	# Telegraph: pulse white-hot during windup so the leap reads clearly.
	if is_instance_valid(_body) and _state == State.WINDUP and _flash_timer <= 0.0:
		var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.06)
		_body.modulate = Color(1.0, pulse, pulse)


func _enter_state(state: int, duration: float) -> void:
	_state = state
	_state_timer = duration


func _distance_to_player() -> float:
	return global_position.distance_to(_player_position())
