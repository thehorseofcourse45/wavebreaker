extends EnemyBase
class_name EnemyOrbiter
## Circles the player at a fixed radius, spiralling in when too far out.
## Tangential (perpendicular-to-player) steering layered on the radial correction.

@export_group("Orbiter")
@export var orbit_radius: float = 170.0
@export var radial_pull: float = 0.9  # how hard it corrects toward the ring
@export var spin_dir: float = 1.0  # 1 = counter-clockwise, -1 = clockwise


func _ready() -> void:
	super._ready()
	spin_dir = 1.0 if randf() < 0.5 else -1.0


func _desired_velocity() -> Vector2:
	var to_player: Vector2 = _player_position() - global_position
	var dist: float = to_player.length()
	if dist < 1.0:
		return Vector2.ZERO
	var radial: Vector2 = to_player / dist
	var tangential := Vector2(-radial.y, radial.x) * spin_dir
	# Inside the ring: push back out gently; outside: pull in. Steepness via
	# radial_pull so export tweaking changes the "snap" of the orbit.
	var radial_mag: float = clampf((dist - orbit_radius) / orbit_radius, -0.6, 1.4) * radial_pull
	return (tangential + radial * radial_mag).normalized() * move_speed
