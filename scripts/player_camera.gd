extends Camera2D
class_name PlayerCamera
## Follow camera with mouse-lookahead and trauma-based screen shake.
##
## Lookahead: the camera drifts toward the mouse so the player sees more of
## where they're aiming (twin-stick feel). Shake: call [method add_trauma];
## trauma decays over time and the offset scales with trauma^2, which makes big
## hits feel punchy and small hits subtle. Noise comes from FastNoiseLite so
## the shake is smooth rather than jittery.

@export_group("Lookahead")
@export var lookahead_factor: float = 0.22
@export var max_lookahead: float = 110.0
@export var lookahead_smoothing: float = 6.0

@export_group("Shake")
@export var trauma_decay: float = 1.8
@export var max_shake_offset: float = 26.0
@export var shake_frequency: float = 42.0

## Kill punch: a short zoom-in that settles. Shake alone reads as "something
## happened near me"; the punch is what makes a kill feel like it landed.
@export var punch_zoom: float = 0.03
@export var punch_decay: float = 6.0

var _trauma: float = 0.0
var _punch: float = 0.0
var _smoothed_look: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()
var _player: Node2D = null


func _ready() -> void:
	# This camera follows its parent (the Player) automatically because it is a
	# child of it; position_smoothing keeps the follow soft.
	position_smoothing_enabled = true
	position_smoothing_speed = 9.0
	make_current()
	_player = get_parent() as Node2D


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Short zoom-in that settles, on top of the shake. Same decay-to-zero shape as
## trauma so a burst of kills cannot leave the camera zoomed in.
func add_punch(amount: float = 1.0) -> void:
	_punch = clampf(_punch + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_punch = maxf(_punch - punch_decay * delta, 0.0)
	zoom = Vector2.ONE * (1.0 + punch_zoom * _punch)
	var look_target: Vector2 = Vector2.ZERO
	if is_instance_valid(_player):
		look_target = (_player.get_global_mouse_position() - _player.global_position) * lookahead_factor
		look_target = look_target.limit_length(max_lookahead)
	_smoothed_look = _smoothed_look.lerp(look_target, 1.0 - exp(-lookahead_smoothing * delta))
	var shake_strength: float = _trauma * _trauma * max_shake_offset
	var shake_offset := Vector2(
		_noise.get_noise_1d(_time * shake_frequency),
		_noise.get_noise_1d(_time * shake_frequency + 1000.0)
	) * shake_strength
	# Camera2D.offset shifts the view without moving the camera body, which
	# keeps position_smoothing (follow) and shake fully independent.
	offset = _smoothed_look + shake_offset
