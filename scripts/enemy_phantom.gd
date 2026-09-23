extends EnemyBase
class_name EnemyPhantom
## Phase-cycler: drifts untouchable, then solidifies to close in and strike.
## Ghost = no collision layer (rounds pass through, body goes translucent) and
## no contact damage; solid = the enemy you can actually shoot.

@export_group("Phantom")
@export var solid_time: float = 2.2
@export var ghost_time: float = 1.5
@export var ghost_speed_scale: float = 1.5
@export var solid_speed_scale: float = 0.7

const GHOST_ALPHA := 0.35

var _solid: bool = true
var _phase_timer: float = solid_time
var _solid_layer: int = 0
var _base_contact: int = 0


func _ready() -> void:
	_base_contact = contact_damage   # the scene's authored value, before any toggle
	super._ready()
	_solid_layer = collision_layer


func _update_behavior(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	_solid = not _solid
	_phase_timer = solid_time if _solid else ghost_time
	collision_layer = _solid_layer if _solid else 0
	# Contact damage rides the same cycle: a ghost that hurt on touch would be
	# an unanswerable tax, so the touch only bites while solid.
	contact_damage = _base_contact if _solid else 0
	_phase_burst()


func _phase_burst() -> void:
	var layer: Node = get_tree().get_first_node_in_group("effects_layer")
	if layer != null:
		DeathBurst.spawn(layer, global_position, _base_tint().lightened(0.3), 40.0, 0.18)


func _desired_velocity() -> Vector2:
	return _steer_toward_player(move_speed * (solid_speed_scale if _solid else ghost_speed_scale))


func _base_tint() -> Color:
	var tint := super._base_tint()
	if not _solid:
		tint.a = GHOST_ALPHA
	return tint


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> int:
	if not _solid:
		return 0   # phased out: the round passes through even if a query sneaks in
	return super.take_damage(amount, knockback)
