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
	# Nav-aware radial so the orbit follows the path around cover instead of
	# swinging through walls. Distance for the ring is still plain Euclidean.
	var radial: Vector2 = _dir_toward_player()
	if radial == Vector2.ZERO:
		return Vector2.ZERO
	var dist: float = _player_position().distance_to(global_position)
	var tangential := Vector2(-radial.y, radial.x) * spin_dir
	# Inside the ring: push back out gently; outside: pull in. Steepness via
	# radial_pull so export tweaking changes the "snap" of the orbit.
	var radial_mag: float = clampf((dist - orbit_radius) / orbit_radius, -0.6, 1.4) * radial_pull
	return (tangential + radial * radial_mag).normalized() * move_speed
