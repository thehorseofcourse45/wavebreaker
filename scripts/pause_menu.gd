extends CanvasLayer
class_name PauseMenu
## In-game pause overlay. Main opens it (Escape while PLAYING, tree unpaused);
## this closes itself (Escape / Resume). process_mode = ALWAYS is the whole
## trick: it keeps receiving input while the tree is frozen.
##
## It also owns the audio toggles: the CheckButtons read/write AudioManager,
## which persists the flags itself, so nothing here touches the save file.

signal resume_pressed
signal quit_pressed
## A perk level was bought with salvage (the tab refreshed itself first).
signal perk_bought(id: String)

const Storage := preload("res://scripts/storage.gd")

@onready var _tabs: TabContainer = $Center/Card/Tabs
@onready var _music_slider: HSlider = $Center/Card/Tabs/MENU/Audio/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Center/Card/Tabs/MENU/Audio/SfxRow/SfxSlider
@onready var _resume_btn: Button = $Center/Card/Tabs/MENU/ResumeButton
@onready var _quit_btn: Button = $Center/Card/Tabs/MENU/QuitButton
## The UNLOCKABLES tab renders Unlockables.DEFS as a grid of 64x64 icons; locked
## rows are desaturated by shaders/icon_locked.gdshader.
@onready var _unlock_grid: GridContainer = %Grid
@onready var _unlock_count: Label = %CountLabel

const ICON_LOCKED_SHADER := preload("res://shaders/icon_locked.gdshader")
const ICON_SIZE := 64
## Tile width. A GridContainer sizes each column to its OWN widest child, so a
## name wider than this makes the columns ragged and the icon rows unevenly
## spaced -- this is set to the longest name at font 12 plus the icon padding.
const TILE_WIDTH := 92

## Unlockable "run_stats": the third tab. The page is BUILT here instead of being
## authored in the tscn, because the whole tab only exists once it is earned --
## and the rows are labels, not a scene.
const STATS_TAB := "STATS"
## The PERKS tab (meta-progression). Always present: salvage is the core meta
## loop, so the shop that spends it is never hidden behind a wave gate.
const PERKS_TAB := "PERKS"
## Row definitions: {"key", "text"} plus "header" for a section title. The values
## come from Main (this run) and the save (lifetime), never from this script.
## A row may instead carry "split" -- a header whose value goes in a LEFT cell and a
## RIGHT cell (the split's second text), for two-column tables like the BESTIARY.
const STATS_ROWS: Array[Dictionary] = [
	{"key": "this_run", "text": "THIS RUN", "header": true},
	{"key": "wave", "text": "WAVE"},
	{"key": "kills", "text": "KILLS"},
	{"key": "score", "text": "SCORE"},
	{"key": "credits", "text": "CREDITS"},
	{"key": "dps", "text": "DPS"},
	{"key": "credits_per_min", "text": "CREDITS / MIN"},
	{"key": "lifetime", "text": "LIFETIME", "header": true},
	{"key": "best_score", "text": "BEST SCORE"},
	{"key": "best_wave", "text": "BEST WAVE"},
	{"key": "total_kills", "text": "TOTAL KILLS"},
	{"key": "bosses", "text": "BOSSES KILLED"},
	{"key": "elites", "text": "ELITES KILLED"},
	{"key": "crits", "text": "CRITS LANDED"},
	{"key": "purchases", "text": "SHOP PURCHASES"},
	{"key": "by_difficulty", "text": "BEST WAVE BY DIFFICULTY", "header": true},
]

## The BESTIARY tab: every enemy in the game, grouped. The rows live in
## Beasts.DEFS (read by the WaveManager too -- one list, not three), and the
## headings are just the tagging group on the left. Two columns; the GROUP cell is
## the tag, so the roster can grow without the labels and the rows drifting apart.
const BESTIARY_TAB := "BESTIARY"
const BESTIARY_HEAD: Array[Dictionary] = [
	{"key": "seen_all", "text": "ENCOUNTERED", "header": true},
	{"key": "seen", "text": "BESTIARY PROGRESS"},
	{"key": "affixes", "text": "AFFIXES", "header": true},
	{"key": "affix_hint", "text": "RANDOM MODIFIERS"},
]

var _stats_page: VBoxContainer = null
var _bestiary_page: VBoxContainer = null
var _stats_values: Dictionary = {}   # row key -> its value Label
var _perks_page: VBoxContainer = null
var _salvage_label: Label = null
var _perk_rows: Dictionary = {}      # perk id -> {"btn": Button, "label": Label}

## Room for the LEFT cell of a split row (an enemy name) and the RIGHT cell (its
## HP). Sized to the longest real name -- "ELITE SKIRMISHER", uppercased -- so
## nothing is clipped at any scale; the label also clips rather than widening, so
## a longer name can never ragged the grid.
const BEAST_NAME_WIDTH := 165
const BEAST_HINT_WIDTH := 300
const BEAST_HP_WIDTH := 56
## Portraits are generated at runtime (see beast_texture), so this is a render
## target size, not an asset size.
const BEAST_ICON := 40
## One grid cell's width: icon + name + hint + HP + the three gaps between them.
## EVERY row carries it, so a group's two columns come out equal whatever its text
## (a GridContainer otherwise sizes a column to its widest child's MINIMUM, and an
## autowrap hint's minimum is its longest word).
const BEAST_ROW_SEPARATION := 8
const BEAST_ROW_WIDTH := BEAST_ICON + BEAST_NAME_WIDTH + BEAST_HINT_WIDTH + BEAST_HP_WIDTH \
		+ BEAST_ROW_SEPARATION * 3
## An enemy the player has never met: portrait and name stay (you can look up what
## the thing that killed you looked like), the fight hint does not.
const UNMET_MODULATE := Color(0.42, 0.46, 0.55)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	_quit_btn.pressed.connect(func() -> void: quit_pressed.emit())
	# set_value_no_signal: reflecting the saved state must not re-write it.
	sync_audio_sliders()
	_music_slider.value_changed.connect(AudioManager.set_music_volume)
	_sfx_slider.value_changed.connect(AudioManager.set_sfx_volume)
	_build_unlockables()
	_build_stats()
	_build_perks()
	_build_bestiary()
	refresh_stats()
	refresh_perks()
	refresh_bestiary()


## Build the STATS page once. `refresh_stats()` decides whether the TabContainer
## actually shows it, so an unearned tab is never in the tab strip.
func _build_stats() -> void:
	_stats_page = VBoxContainer.new()
	_stats_page.name = STATS_TAB
	_stats_page.add_theme_constant_override("separation", 4)
	for row: Dictionary in STATS_ROWS:
		var is_head: bool = bool(row.get("header", false))
		var cell: Label = _add_stats_line(_stats_page, String(row.text), is_head,
				String(row.get("split", "")))
		if not is_head:
			_stats_values[String(row.key)] = cell
	# One line per difficulty, in the registry order the menu uses.
	for id: String in WaveManager.DIFFICULTY_ORDER:
		_stats_values["difficulty_" + id] = _add_stats_line(_stats_page, id.to_upper())
	_tabs.add_child(_stats_page)


## Name on the left, value on the right. Returns the right-hand Label, which is the
## only thing refresh_stats rewrites. A `header` row is a section title instead; a
## header carrying `split` puts a second title in the RIGHT cell, which is how the
## BESTIARY's two columns get their headings (one code path, one row shape).
func _add_stats_line(parent: Node, label_text: String, header: bool = false,
		split: String = "") -> Label:
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	if header:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if split != "" \
				else HORIZONTAL_ALIGNMENT_CENTER
		name_label.modulate = Color(1, 1, 1, 0.65)
	else:
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	# A header with no second title gets NO value cell text: a lone "-" next to a
	# section title reads as missing data.
	value_label.text = split if split != "" else ("-" if not header else "")
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(name_label)
	line.add_child(value_label)
	parent.add_child(line)
	return value_label


## Show/hide the tab for the unlockable, then fill it from this run plus the save.
## `run` comes from Main (wave/kills/score/credits/seconds/damage); the lifetime
## numbers are the same save keys the unlockables read.
func refresh_stats(run: Dictionary = {}) -> void:
	if _stats_page == null:
		return
	var wanted: bool = Unlockables.is_unlocked("run_stats")
	_tabs.set_tab_hidden(_stats_page.get_index(), not wanted)
	if not wanted:
		return
	var data: Dictionary = Storage.read_all()
	var seconds: float = maxf(float(run.get("seconds", 0.0)), 1.0)
	var damage: float = float(run.get("damage", 0))
	var credits: float = float(run.get("credits", 0))
	_set_stat("wave", str(int(run.get("wave", 0))))
	_set_stat("kills", str(int(run.get("kills", 0))))
	_set_stat("score", str(int(run.get("score", 0))))
	_set_stat("credits", str(int(credits)))
	_set_stat("dps", "%.1f" % (damage / seconds))
	_set_stat("credits_per_min", "%.0f" % (credits / (seconds / 60.0)))
	_set_stat("best_score", str(int(data.get("best_score", 0))))
	_set_stat("best_wave", str(int(data.get("best_wave", 0))))
	_set_stat("total_kills", str(int(data.get("total_kills", 0))))
	_set_stat("bosses", str(int(data.get("bosses", 0))))
	_set_stat("elites", str(int(data.get("elites", 0))))
	_set_stat("crits", str(int(data.get("crits", 0))))
	_set_stat("purchases", str(int(data.get("purchases", 0))))
	for id: String in WaveManager.DIFFICULTY_ORDER:
		# A difficulty the player has not unlocked gets no row: the tab must not
		# spoil a mode the menu still hides.
		var open: bool = WaveManager.difficulty_unlocked(id)
		var label: Label = _stats_values["difficulty_" + id] as Label
		label.get_parent().visible = open
		if open:
			_set_stat("difficulty_" + id, str(int(data.get("best_wave_" + id, 0))))


func _set_stat(key: String, value: String) -> void:
	if _stats_values.has(key):
		(_stats_values[key] as Label).text = value


## Build the PERKS page once: a salvage balance header and one buy row per
## Perks.DEFS entry. The page is plain Labels + Buttons, like the STATS page --
## no scene to keep in sync with the registry.
func _build_perks() -> void:
	_perks_page = VBoxContainer.new()
	_perks_page.name = PERKS_TAB
	_perks_page.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var head_label := Label.new()
	head_label.text = "SALVAGE"
	head_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_salvage_label = Label.new()
	_salvage_label.text = "0"
	_salvage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(head_label)
	head.add_child(_salvage_label)
	_perks_page.add_child(head)
	for d: Dictionary in Perks.DEFS:
		var id: String = String(d.id)
		var line := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s  %s" % [String(d.name), String(d.hint)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.pressed.connect(func() -> void: _on_perk_pressed(id))
		line.add_child(lbl)
		line.add_child(btn)
		_perks_page.add_child(line)
		_perk_rows[id] = {"btn": btn, "label": lbl}
	_tabs.add_child(_perks_page)


func _on_perk_pressed(id: String) -> void:
	if Perks.buy(id):
		refresh_perks()
		perk_bought.emit(id)


## Reflect the salvage balance and each row's next price. Called on build and on
## every open(), so a run banked since the last pause is visible immediately.
func refresh_perks() -> void:
	if _perks_page == null:
		return
	var balance: int = Storage.salvage()
	_salvage_label.text = str(balance)
	for d: Dictionary in Perks.DEFS:
		var id: String = String(d.id)
		if not _perk_rows.has(id):
			continue
		var btn: Button = _perk_rows[id]["btn"]
		var lvl: int = Perks.level(id)
		if lvl >= int(d.get("max_level", 1)):
			btn.text = "MAX"
			btn.disabled = true
		else:
			var price: int = Perks.cost(id)
			btn.text = "%d  (%d/%d)" % [price, lvl, int(d.get("max_level", 1))]
			btn.disabled = balance < price


## One tile per Unlockables.DEFS row: the 64x64 icon, its name, and the condition
## as the tooltip. The tile is NAMED after the unlockable id, which is what
## refresh_unlockables() and the self-test look tiles up by.
func _build_unlockables() -> void:
	for d: Dictionary in Unlockables.DEFS:
		var id: String = String(d.id)
		var tile := VBoxContainer.new()
		tile.name = id
		tile.custom_minimum_size = Vector2(TILE_WIDTH, 0)
		tile.tooltip_text = "%s -- %s" % [String(d.name), String(d.hint)]
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.texture = load(Unlockables.icon_path(id))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = ICON_LOCKED_SHADER
		icon.material = mat
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = String(d.name)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# No autowrap: an autowrap Label reports a wild minimum height before its
		# first layout (it wraps to one character per line at width 0), which
		# inflates the tab's min size and makes the card jump. The tile instead
		# widens to the longest name -- the grid keeps every column equal.
		name_label.add_theme_font_size_override("font_size", 12)
		tile.add_child(icon)
		tile.add_child(name_label)
		_unlock_grid.add_child(tile)
	refresh_unlockables()


## Locked = desaturated and dark; earned = the art as drawn. Runs on _ready and on
## every open(), so something earned mid-run shows up the next time you pause.
func refresh_unlockables() -> void:
	for tile: Node in _unlock_grid.get_children():
		var earned: bool = Unlockables.is_unlocked(String(tile.name))
		var icon: TextureRect = tile.get_node("Icon") as TextureRect
		if icon.material is ShaderMaterial:
			(icon.material as ShaderMaterial).set_shader_parameter("locked", 0.0 if earned else 1.0)
		var name_label: Label = tile.get_node("Name") as Label
		name_label.modulate = Color.WHITE if earned else Color(0.6, 0.64, 0.7)
	_unlock_count.text = "%d / %d UNLOCKED" % [Unlockables.count_unlocked(), Unlockables.DEFS.size()]


## The BESTIARY page: two columns, built in code (like STATS and PERKS -- no scene
## to keep in sync). The values are read-only reference data; refresh_bestiary()
## only rewrites the progress line, so a new enemy added to Beasts.DEFS shows up
## here with no scene edit at all.
func _build_bestiary() -> void:
	_bestiary_page = VBoxContainer.new()
	_bestiary_page.name = BESTIARY_TAB
	_bestiary_page.add_theme_constant_override("separation", 4)
	for head: Dictionary in BESTIARY_HEAD:
		if not bool(head.get("header", false)):
			_stats_values[String(head.key)] = _add_stats_line(_bestiary_page,
					String(head.text), false, "")
			continue
		_add_stats_line(_bestiary_page, String(head.text), true, String(head.get("split", "")))
		# The section head is NAMED too, so a probe can find it without counting
		# children (the group headings and their grids interleave below).
		_bestiary_page.get_child(_bestiary_page.get_child_count() - 1).name = \
				"BestiaryHead_" + String(head.key)
	# One grid per group, so the two columns line up inside each group and the
	# group headings above them are free to be different heights. The grid is
	# NAMED after the group and its row cells after the enemy id -- that is how
	# the suite finds a row without depending on the scroll position.
	for group_key: String in Beasts.groups():
		# _add_stats_line returns the RIGHT cell (a Label); the row is its parent.
		_add_stats_line(_bestiary_page, String(Beasts.GROUP_LABELS[group_key]), true, "HP")
		var head_line: Node = _bestiary_page.get_child(_bestiary_page.get_child_count() - 1)
		head_line.name = "Head_" + (group_key if group_key != "" else "normal")
		var tiles := GridContainer.new()
		tiles.name = "Tiles_" + (group_key if group_key != "" else "normal")
		tiles.columns = 2
		tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_theme_constant_override("h_separation", 10)
		tiles.add_theme_constant_override("v_separation", 6)
		for d: Dictionary in Beasts.group(group_key):
			var id: String = String(d.id)
			var line := HBoxContainer.new()
			line.name = id
			line.add_theme_constant_override("separation", BEAST_ROW_SEPARATION)
			# A FIXED row width, or a GridContainer sizes each column to its widest
			# child's minimum and an autowrap hint's minimum is its longest WORD --
			# which made the elite group's columns ~270 px while the normal group's
			# filled 570, leaving half the grid empty for one group and not the
			# other. One number for every row keeps the two columns aligned.
			line.custom_minimum_size = Vector2(BEAST_ROW_WIDTH, 0)
			line.add_child(_beast_icon(String(d.scene)))
			var name_label := Label.new()
			name_label.name = "Name"
			name_label.text = String(d.name).to_upper()
			name_label.custom_minimum_size = Vector2(BEAST_NAME_WIDTH, 0)
			# Clip rather than widen: a name longer than the cell must not push the
			# grid's column out (that is what ragged the two columns apart).
			name_label.clip_text = true
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(name_label)
			var hint_label := Label.new()
			hint_label.name = "Hint"
			# Fixed size instead of autowrap: an autowrap Label reports a wild
			# minimum height before its first layout, which inflates the card.
			hint_label.custom_minimum_size = Vector2(BEAST_HINT_WIDTH, 0)
			hint_label.add_theme_font_size_override("font_size", 12)
			hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_label.modulate = Color(1, 1, 1, 0.72)
			hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hint_label.text = String(d.hint)
			line.add_child(hint_label)
			var hp_label := Label.new()
			hp_label.name = "Hp"
			hp_label.text = str(int(d.hp))
			hp_label.custom_minimum_size = Vector2(BEAST_HP_WIDTH, 0)
			hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(hp_label)
			tiles.add_child(line)
		_bestiary_page.add_child(tiles)
	# The spawn affixes: the same table the WaveManager rolls from, so a new affix
	# appears here without a second list.
	var affix_label := Label.new()
	affix_label.name = "Affixes"
	affix_label.custom_minimum_size = Vector2(BEAST_HINT_WIDTH + BEAST_NAME_WIDTH, 0)
	affix_label.add_theme_font_size_override("font_size", 12)
	affix_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	affix_label.text = _affix_text()
	_bestiary_page.add_child(affix_label)
	var scroll := ScrollContainer.new()
	# Named: the TabContainer uses a child's NAME as its tab title, and the page's
	# own name is nested inside this wrapper.
	scroll.name = BESTIARY_TAB
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 0)
	scroll.add_child(_bestiary_page)
	_tabs.add_child(scroll)


## "shielded - periodic invulnerability windows / frenzied - faster, ..." straight
## off the one affix table: a hand-written list here would be the third copy.
func _affix_text() -> String:
	var parts: Array[String] = []
	for key: String in EnemyBase.AFFIXES:
		parts.append("%s - %s" % [key, String((EnemyBase.AFFIXES[key] as Dictionary).get("blurb", ""))])
	return "  /  ".join(parts)


## The portrait: the enemy's own generated art (enemy_base.tscn draws its body as
## a Polygon2D), rendered into a small texture at runtime. One autoload-free helper
## -- no art files, and a new enemy is instantly correct instead of a missing icon.
func _beast_icon(scene_path: String) -> Control:
	var out := TextureRect.new()
	out.name = "Icon"
	out.custom_minimum_size = Vector2(BEAST_ICON, BEAST_ICON)
	out.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	out.texture = beast_texture(scene_path)
	return out


## Public so the self-test can measure a portrait without the pause menu.
## ponytail: a tiny SubViewport per row, built once at _ready. A real art drop
## (scenes/bestiary/<id>.png) can replace this by returning it here first.
func beast_texture(scene_path: String) -> Texture2D:
	if not ResourceLoader.exists(scene_path):
		return null
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return null
	var body_poly: Polygon2D = null
	var inst: Node = scene.instantiate()
	for child: Node in inst.find_children("*", "Polygon2D", true, false):
		body_poly = child as Polygon2D
		break
	if body_poly == null:
		inst.free()
		return null
	var points: PackedVector2Array = body_poly.polygon
	# The body's own box. A body polygon is authored around its own origin, but an
	# asymmetric one is not centred ON it -- so both the size and the offset come
	# from the box, not from the origin.
	var box := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		box = box.expand(p)
	var half: Vector2 = box.size * 0.5
	var vp := SubViewport.new()
	vp.size = Vector2i(BEAST_ICON, BEAST_ICON)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var canvas := Node2D.new()
	# CENTRE the drawing, or the shape's centre lands on the viewport's top-left
	# corner and three quarters of it fall outside the tile -- the "portraits look
	# cut off" report. The 1.25 leaves a margin, so the art fills ~80% of the tile.
	var scale_factor: float = float(BEAST_ICON) * 0.5 / (maxf(maxf(half.x, half.y), 0.001) * 1.25)
	canvas.position = Vector2(BEAST_ICON, BEAST_ICON) * 0.5 - Vector2(box.get_center()) * scale_factor
	var scaled := Polygon2D.new()
	scaled.polygon = body_poly.polygon
	scaled.color = body_poly.color
	scaled.scale = Vector2.ONE * scale_factor
	canvas.add_child(scaled)
	vp.add_child(canvas)
	# The body's own children (a core, an eye) come along: they are what makes each
	# silhouette recognisable rather than a same-shaped blob.
	for child: Node in inst.find_children("*", "Polygon2D", true, false):
		if child == body_poly:
			continue
		var extra := Polygon2D.new()
		extra.polygon = (child as Polygon2D).polygon
		extra.color = (child as Polygon2D).color
		extra.scale = Vector2.ONE * scale_factor
		extra.position = (child as Node2D).position * scale_factor
		canvas.add_child(extra)
	add_child(vp)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	inst.free()
	return vp.get_texture()


## Just the count line and the seen/unseen styling: the tab's text is static
## reference data, so the rows never change -- only whether you have MET each one.
## Runs on build and on every open().
func refresh_bestiary() -> void:
	if _bestiary_page == null:
		return
	var seen: Dictionary = Beasts.seen_ids()
	_set_stat("seen", "%d / %d" % [seen.size(), Beasts.DEFS.size()])
	for group_key: String in Beasts.groups():
		var tiles: Node = _bestiary_page.get_node_or_null("Tiles_" + (group_key if group_key != "" else "normal"))
		if tiles == null:
			continue
		for line: Node in tiles.get_children():
			var met: bool = seen.has(String(line.name))
			for cell_name: String in ["Icon", "Name", "Hint"]:
				var cell: CanvasItem = line.get_node_or_null(cell_name) as CanvasItem
				if cell != null:
					cell.modulate = Color.WHITE if met else UNMET_MODULATE
			# An unmet enemy keeps its portrait and its name and hides only what
			# you would have to fight it to learn.
			var hint: Label = line.get_node_or_null("Hint") as Label
			if hint != null:
				hint.visible = met


func open(run: Dictionary = {}) -> void:
	show()
	# Always open on the menu tab: Escape should land on the same controls every
	# time, whatever tab was left selected.
	show_tab(0)
	sync_audio_sliders()   # volumes may have moved in the main menu since the last pause
	refresh_unlockables()
	refresh_stats(run)
	refresh_perks()
	refresh_bestiary()
	_resume_btn.grab_focus()


## Reflect the CURRENT volumes; AudioManager owns them and the save key.
## set_value_no_signal so opening the menu never rewrites the file.
func sync_audio_sliders() -> void:
	_music_slider.set_value_no_signal(AudioManager.music_volume())
	_sfx_slider.set_value_no_signal(AudioManager.sfx_volume())


## Select a tab by index (clamped). Public so anything that opens the pause menu
## -- including the screenshot mode -- can land on a specific tab.
func show_tab(index: int) -> void:
	_tabs.current_tab = clampi(index, 0, maxi(_tabs.get_tab_count() - 1, 0))


## Select a tab by TITLE. Indices are not stable: the STATS tab is only added
## while `run_stats` is earned, so every later index shifts by one at that moment
## -- anything that names a tab must name it, never its position.
func show_tab_named(title: String) -> void:
	for i: int in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == title:
			show_tab(i)
			return


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()
