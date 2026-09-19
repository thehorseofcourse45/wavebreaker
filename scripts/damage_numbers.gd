extends Node
## Autoload ("DamageNumbers"): pooled floating hit numbers, the DamageBurst of
## the damage path. A bullet resolves a hit inside the physics tick, so this must
## never instantiate a node -- one Label scene is pre-built and recycled. When
## every label is busy the OLDEST is reused: numbers are cosmetic, so dropping a
## hit or growing the pool without bound are both worse than an early fade.
##
## The labels live in a follow-viewport CanvasLayer: positions stay in WORLD
## space (so a number sits on the enemy it came from) while drawing above the
## arena, which is what a plain world node cannot do from an autoload.

const POOL_SIZE := 24
const SCENE_PATH := "res://scenes/effects/damage_number.tscn"
const NORMAL_COLOR := Color(1.0, 0.96, 0.86)
const CRIT_COLOR := Color(1.0, 0.78, 0.25)
## Unlockable "gold_crits": the crit number goes full gold instead of amber.
const GOLD_CRIT_COLOR := Color(1.0, 0.94, 0.42)
const NORMAL_FONT := 15
const CRIT_FONT := 22

var _labels: Array[Node] = []
var _next: int = 0


func _ready() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("[DamageNumbers] missing %s -- hit numbers stay off." % SCENE_PATH)
		return
	var layer := CanvasLayer.new()
	layer.layer = 1                     # above the world, below the HUD
	layer.follow_viewport_enabled = true  # keep world-space placement
	add_child(layer)
	for i: int in POOL_SIZE:
		var label: Node = scene.instantiate()
		label.finished.connect(_on_finished)
		layer.add_child(label)
		label.park()
		_labels.append(label)


## Pop one number. `crit` swaps colour and size so a crit reads at a glance.
func spawn(world_position: Vector2, value: int, crit: bool = false) -> void:
	if _labels.is_empty():
		return
	var label: Node = _labels[_next]
	_next = (_next + 1) % _labels.size()
	label.popup(world_position, value, _crit_color() if crit else NORMAL_COLOR,
			CRIT_FONT if crit else NORMAL_FONT)


## Unlockable "gold_crits". A method rather than a const because the flag can flip
## between runs, and this is read once per crit -- not per frame.
func _crit_color() -> Color:
	return GOLD_CRIT_COLOR if Unlockables.is_unlocked("gold_crits") else CRIT_COLOR


## How many labels are currently animating (diagnostics / self-test).
func active_count() -> int:
	var live: int = 0
	for label: Node in _labels:
		if label.visible:
			live += 1
	return live


func _on_finished(label: Node) -> void:
	label.park()
