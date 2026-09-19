extends EnemyBase
class_name EnemyRusher
## Fast, fragile enemy that moves in bursts: it approaches, telegraphs with a
## windup flash, then dashes in a locked direction, then recovers.
##
## The state machine ticks in _update_behavior(); _desired_velocity() reads the
## current state. The dash direction is locked at windup end so players can
## dodge -- a classic fair-challenge pattern.

enum State { APPROACH, WINDUP, DASH, RECOVER }

@export_group("Rusher")
@export var windup_range: float = 230.0
@export var windup_time: float = 0.45
@export var dash_time: float = 0.5
@export var recover_time: float = 0.7
@export var dash_speed: float = 430.0
@export var approach_speed_scale: float = 1.35

var _state: int = State.APPROACH
var _state_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT


func _update_behavior(delta: float) -> void:
	_state_timer -= delta
	match _state:
		State.APPROACH:
			if _distance_to_player() < windup_range:
				_enter_state(State.WINDUP, windup_time)
		State.WINDUP:
			if _state_timer <= 0.0:
				# Lock the dash direction now (dodgeable!) and go.
				_dash_direction = (_player_position() - global_position).normalized()
				if _dash_direction == Vector2.ZERO:
					_dash_direction = Vector2.RIGHT
				_enter_state(State.DASH, dash_time)
		State.DASH:
			if _state_timer <= 0.0:
				_enter_state(State.RECOVER, recover_time)
		State.RECOVER:
			if _state_timer <= 0.0:
				_enter_state(State.APPROACH, 0.0)


func _desired_velocity() -> Vector2:
	match _state:
		State.WINDUP:
			# Creep forward slowly while telegraphing (flash handled below).
			return _steer_toward_player(move_speed * 0.25)
		State.DASH:
			return _dash_direction * dash_speed
		State.RECOVER:
			return _steer_toward_player(move_speed * 0.3)
		_:
			return _steer_toward_player(move_speed * approach_speed_scale)


func _process(delta: float) -> void:
	super._process(delta)
	# Telegraph: pulse white-hot during windup so the dash reads clearly.
	if is_instance_valid(_body) and _state == State.WINDUP and _flash_timer <= 0.0:
		var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.05)
		_body.modulate = Color(1.0, pulse, pulse)


func _enter_state(state: int, duration: float) -> void:
	_state = state
	_state_timer = duration


func _distance_to_player() -> float:
	return global_position.distance_to(_player_position())
