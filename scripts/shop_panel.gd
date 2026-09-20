extends CanvasLayer
class_name ShopPanel
## Between-wave shop. UI only: builds a row per UpgradeSystem.DEFS entry,
## emits `buy_attempted(id)`; Main validates + applies. Refreshed via `refresh`
## so buttons reflect current credits.

signal buy_attempted(id: String)
signal resume_pressed
## The player asked to re-roll the offers. Main owns the credits, so it validates
## and deducts; the shop only announces the request (same split as buy_attempted).
signal reroll_attempted

## Unlockable "fast_shop": number keys buy a row without the mouse. Covers rows 1-9
## (a hand is OFFER_COUNT rows, so 9 is plenty).
const HOTKEY_COUNT := 9
## Reroll price (paid by Main) and how many rows one shop hand offers. The hand is
## a RANDOM subset, re-dealt on every wave clear and on a reroll -- the shop never
## dumps the whole upgrade list at once, so REROLL actually re-deals a new hand.
const REROLL_COST := 30
const OFFER_COUNT := 6

var _rows: Dictionary = {}   # id -> {btn, label, row}
## Row ids in OFFERED order, so a hotkey maps to a visible row without walking
## the tree. A deal (wave clear or reroll) rewrites this.
var _row_ids: Array[String] = []
## Ids currently on offer -- the hand.
var _offered: Array[String] = []

@onready var _list: VBoxContainer = %ItemList
@onready var _credits_label: Label = %CreditsLabel
@onready var _resume_btn: Button = %ResumeButton
@onready var _reroll_btn: Button = %RerollButton


func _ready() -> void:
	hide()
	_resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	_reroll_btn.pressed.connect(func() -> void: reroll_attempted.emit())


func build(up: Node) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_rows.clear()
	_row_ids.clear()
	_offered.clear()
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
		_rows[String(d.id)] = {"btn": btn, "label": lbl, "row": h}
	# One row per DEFS entry exists in `_rows` (Main addresses rows by id), but
	# only a random hand is OFFERED -- see deal().
	deal(up)


## Deal a fresh hand: OFFER_COUNT random rows drawn from what this run may still
## sell (skips blocked rows and rows already at max, so an offer is never a dead
## button). Main calls this on every wave clear; reroll() calls it too.
func deal(up: Node) -> void:
	if up == null:
		return
	var pool: Array[String] = []
	for d: Dictionary in up.DEFS:
		var id := String(d.id)
		if up.is_blocked(id):
			continue
		if up.level(id) >= int(d.max_level):
			continue
		pool.append(id)
	pool.shuffle()
	_offered = pool.slice(0, mini(OFFER_COUNT, pool.size()))
	_row_ids = _offered.duplicate()


## Re-roll the hand. Main has already paid.
func reroll(up: Node, credits: int, player: Node = null) -> void:
	if up == null:
		return
	deal(up)
	refresh(up, credits, player)


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


func refresh(up: Node, credits: int, player: Node = null) -> void:
	if up == null:
		return
	_credits_label.text = "CREDITS: %d" % credits
	_reroll_btn.text = "REROLL (%d)" % REROLL_COST
	_reroll_btn.disabled = credits < REROLL_COST
	for d: Dictionary in up.DEFS:
		var id := String(d.id)
		if not _rows.has(id):
			continue
		# Only the current hand is visible; `_rows` keeps every button so Main can
		# still address one by id (glass cannon's / no-shop's LOCKED probe reads
		# the text of a row that need not be on offer). Text is set for every row,
		# visibility is what the hand controls.
		(_rows[id]["row"] as HBoxContainer).visible = _offered.has(id)
		var btn: Button = _rows[id]["btn"]
		var lbl: Label = _rows[id]["label"]
		lbl.text = "%s  [%s]" % [String(d.label), up.rarity(id).to_upper()]
		var lvl: int = up.level(id)
		if up.is_blocked(id):
			# Say WHY the row is dead, or a disabled button with no price reads as
			# a bug. Cost/level are hidden because neither is reachable this run.
			btn.text = "LOCKED"
			btn.disabled = true
		elif lvl >= int(d.max_level):
			btn.text = "MAX"
			btn.disabled = true
		elif id == "repair" and player != null and player.health >= player.max_health:
			btn.text = "FULL"
			btn.disabled = true
		else:
			var c: int = up.cost(id)
			btn.text = "%d  (%d/%d)" % [c, lvl, int(d.max_level)]
			btn.disabled = not up.can_buy(id, credits)


func show_shop(up: Node, credits: int, player: Node = null) -> void:
	refresh(up, credits, player)
	show()


func hide_shop() -> void:
	hide()
