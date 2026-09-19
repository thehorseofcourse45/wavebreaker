extends CanvasLayer
class_name ShopPanel
## Between-wave shop. UI only: builds a row per UpgradeSystem.DEFS entry,
## emits `buy_attempted(id)`; Main validates + applies. Refreshed via `refresh`
## so buttons reflect current credits.

signal buy_attempted(id: String)
signal resume_pressed

## Unlockable "fast_shop": number keys buy a row without the mouse. Covers rows 1-9
## (the shop has 13 entries, so the last few stay mouse-only).
const HOTKEY_COUNT := 9

var _rows: Dictionary = {}   # id -> Button
## Row ids in build order, so a hotkey maps to a row without walking the tree.
var _row_ids: Array[String] = []

@onready var _list: VBoxContainer = %ItemList
@onready var _credits_label: Label = %CreditsLabel
@onready var _resume_btn: Button = %ResumeButton


func _ready() -> void:
	hide()
	_resume_btn.pressed.connect(func() -> void: resume_pressed.emit())


func build(up: Node) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_rows.clear()
	_row_ids.clear()
	for d: Dictionary in up.DEFS:
		var h := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(d.label)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.pressed.connect(func() -> void: buy_attempted.emit(String(d.id)))
		h.add_child(lbl)
		h.add_child(btn)
		_list.add_child(h)
		_rows[String(d.id)] = {"btn": btn, "label": lbl}
		_row_ids.append(String(d.id))


## Unlockable "fast_shop". The shop owns the mapping (it owns the row order); the
## buy itself still goes through buy_attempted -> Main, so a hotkey can never
## purchase something a button could not.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not Unlockables.is_unlocked("fast_shop"):
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.ctrl_pressed or key.alt_pressed:
		return
	var index: int = key.keycode - KEY_1
	if index < 0 or index >= mini(HOTKEY_COUNT, _row_ids.size()):
		return
	var id: String = _row_ids[index]
	if (_rows[id]["btn"] as Button).disabled:
		return
	buy_attempted.emit(id)
	get_viewport().set_input_as_handled()


func refresh(up: Node, credits: int) -> void:
	if up == null:
		return
	_credits_label.text = "CREDITS: %d" % credits
	for d: Dictionary in up.DEFS:
		var id := String(d.id)
		if not _rows.has(id):
			continue
		var btn: Button = _rows[id]["btn"]
		var lvl: int = up.level(id)
		if up.is_blocked(id):
			# Say WHY the row is dead, or a disabled button with no price reads as
			# a bug. Cost/level are hidden because neither is reachable this run.
			btn.text = "LOCKED"
			btn.disabled = true
		elif lvl >= int(d.max_level):
			btn.text = "MAX"
			btn.disabled = true
		else:
			var c: int = up.cost(id)
			btn.text = "%d  (%d/%d)" % [c, lvl, int(d.max_level)]
			btn.disabled = not up.can_buy(id, credits)


func show_shop(up: Node, credits: int) -> void:
	refresh(up, credits)
	show()


func hide_shop() -> void:
	hide()
