extends Label
## One floating damage number, pooled by the DamageNumbers autoload.
## It never frees itself: it parks on `finished` so the next hit reuses the node.
## The .tscn gives it a fixed 120x24 box with centred text, so placing it needs
## no measurement -- half the box is the offset that centres it on the hit point.

signal finished(label: Node)

@export var rise_speed: float = 54.0
@export var lifetime: float = 0.55
@export var gravity: float = 130.0

## Half of the box from the scene (120x24), so the number centres on the hit.
const BOX_CENTRE_OFFSET := Vector2(-60.0, -12.0)

var _age: float = 0.0
var _vel: Vector2 = Vector2.ZERO
var _running: bool = false


## Show one number at a world position. Safe to call on a label that is still
## animating (the pool reuses the oldest when everything is busy).
func popup(world_position: Vector2, value: int, color: Color, font_size: int) -> void:
	text = str(value)
	add_theme_color_override("font_color", color)
	add_theme_font_size_override("font_size", font_size)
	position = world_position + BOX_CENTRE_OFFSET
	_age = 0.0
	_vel = Vector2(randf_range(-16.0, 16.0), -rise_speed)
	modulate = Color.WHITE
	visible = true
	_running = true
	set_process(true)


## Stop the animation and go dormant until the pool hands this label out again.
func park() -> void:
	_running = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not _running:
		return
	_age += delta
	if _age >= lifetime:
		_running = false
		finished.emit(self)
		return
	_vel.y += gravity * delta
	position += _vel * delta
	modulate.a = 1.0 - _age / lifetime
