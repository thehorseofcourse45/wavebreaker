extends Node2D
class_name DeathBurst
## One-shot juice effect: an expanding ring + fading core dot, drawn with
## _draw() so it needs zero textures. Spawn via DeathBurst.spawn(parent, pos,
## color); it frees itself when finished.

@export var ring_color: Color = Color(1.0, 0.6, 0.2)
@export var max_radius: float = 44.0
@export var duration: float = 0.35
@export var ring_width: float = 6.0

var _age: float = 0.0


static func spawn(parent: Node, world_position: Vector2, color: Color = Color(1.0, 0.6, 0.2),
		radius: float = -1.0, life: float = -1.0) -> void:
	var scene: PackedScene = load("res://scenes/effects/death_burst.tscn") as PackedScene
	if scene == null:
		return
	var burst: DeathBurst = scene.instantiate() as DeathBurst
	parent.add_child(burst)
	burst.global_position = world_position
	burst.ring_color = color
	if radius > 0.0:
		burst.max_radius = radius
	if life > 0.0:
		burst.duration = life


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k: float = clampf(_age / duration, 0.0, 1.0)
	var fade := ring_color
	fade.a = 1.0 - k
	# Ease-out expansion: fast at first, settling at the end.
	var radius: float = max_radius * (1.0 - (1.0 - k) * (1.0 - k))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, fade, ring_width, true)
	draw_circle(Vector2.ZERO, 7.0 * (1.0 - k), fade)
