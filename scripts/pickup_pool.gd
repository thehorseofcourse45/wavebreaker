extends Node
## Autoload singleton ("PickupPool"): owns every Pickup in the game, mirroring
## BulletPool exactly. Pre-instantiated at startup, reused via fire(), parked
## by reset() -- Main calls that on every fresh run and arena switch so no live
## pickup leaks into the new field.

signal collected(kind: String)

@export_group("Pool")
## A wave fields ~30 enemies at an 18% drop rate over a ~10 s lifetime: a few
## dozen live at once is the worst realistic case.
@export var pool_size: int = 48
@export var pickup_scene: PackedScene = preload("res://scenes/pickup.tscn")

var _free: Array[Pickup] = []
var _all: Array[Pickup] = []


func _ready() -> void:
	for i: int in pool_size:
		_spawn_pooled_pickup()


func fire(start_position: Vector2, kind: String) -> Pickup:
	var pickup: Pickup = _take_free_pickup()
	pickup.fire(start_position, kind)
	return pickup


## Park every pickup (fresh run / arena switch).
func reset() -> void:
	for pickup: Pickup in _all:
		if is_instance_valid(pickup):
			pickup._deactivate_immediate()
	_free = _all.duplicate()


func active_count() -> int:
	return _all.size() - _free.size()


func _take_free_pickup() -> Pickup:
	if _free.is_empty():
		push_warning("PickupPool exhausted (pool_size=%d) -- growing by one." % _all.size())
		return _spawn_pooled_pickup()
	return _free.pop_back()


func _spawn_pooled_pickup() -> Pickup:
	var pickup: Pickup = pickup_scene.instantiate() as Pickup
	add_child(pickup)
	pickup._deactivate_immediate()
	if not pickup.deactivated.is_connected(_on_pickup_deactivated):
		pickup.deactivated.connect(_on_pickup_deactivated)
	if not pickup.collected.is_connected(_on_pickup_collected):
		pickup.collected.connect(_on_pickup_collected)
	_all.append(pickup)
	_free.append(pickup)
	return pickup


func _on_pickup_deactivated(pickup: Pickup) -> void:
	if not _free.has(pickup):
		_free.append(pickup)


## One relay per collection: Main connects to the POOL's signal once instead of
## per-spawned pickup.
func _on_pickup_collected(kind: String) -> void:
	collected.emit(kind)
