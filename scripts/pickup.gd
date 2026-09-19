extends Area2D
class_name Pickup
## Pooled collectible dropped by enemies: credits or health. The pool owns
## reuse; this script owns the look (an additive glow body + a halo light --
## never a Lit receiver, glow composes ON TOP of the lighting), the magnet,
## and the one-shot collection.

signal deactivated(pickup: Pickup)
signal collected(kind: String)

@export_group("Pickup")
@export var kind: String = "credits"   # "credits" | "health"
@export var magnet_radius: float = 150.0
@export var magnet_speed: float = 520.0
@export var bob_speed: float = 24.0
@export var lifetime: float = 10.0

const CREDITS_COLOR := Color(1.0, 0.85, 0.3)
const HEALTH_COLOR := Color(0.4, 1.0, 0.5)
const HALO_RANGE := 90.0
const HALO_ENERGY := 0.7

var is_active: bool = false
var _age: float = 0.0
var _player: Node2D = null
var _halo: LitPointLight2D = null

@onready var _body: Polygon2D = $Body


func _ready() -> void:
	# Additive glow, deliberately NOT converted to a Lit receiver: a pickup
	# must shine in the dark instead of being shaded by it.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_body.material = mat
	_halo = LitLighting.add_point_light(self, CREDITS_COLOR, HALO_RANGE, HALO_ENERGY)
	body_entered.connect(_on_body_entered)
	_deactivate_immediate()


## Activate. Called ONLY by PickupPool.fire(), which hands out parked pickups.
func fire(start_position: Vector2, new_kind: String) -> void:
	kind = new_kind
	var color: Color = HEALTH_COLOR if kind == "health" else CREDITS_COLOR
	_body.color = color
	if _halo != null:
		_halo.color = color
	global_position = start_position
	_age = 0.0
	is_active = true
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_age += delta
	if _age >= lifetime:
		deactivate()
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist > 0.01 and dist <= magnet_radius:
		# Magnet: pulls in from a distance, so walking past is enough to scoop.
		global_position += to_player / dist * magnet_speed * delta
		rotation += 6.0 * delta
	else:
		# Idle bob: stays where it dropped, visible but not demanding.
		global_position += Vector2(cos(_age * 3.0), sin(_age * 2.3)) * bob_speed * delta


func _on_body_entered(body: Node2D) -> void:
	if not is_active or not body.is_in_group("player"):
		return
	_collect()


## Grant exactly once: deactivate BEFORE emitting, so no second body_entered
## can ever double-grant a single drop.
func _collect() -> void:
	deactivate()
	collected.emit(kind)


func deactivate() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	deactivated.emit(self)


## Used at pool construction and on reset, before any activation.
func _deactivate_immediate() -> void:
	is_active = false
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	position = Vector2.ZERO
	rotation = 0.0
	_age = 0.0
