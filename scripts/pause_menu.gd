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
## Row definitions: {"key", "text"} plus "header" for a section title. The values
## come from Main (this run) and the save (lifetime), never from this script.
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

var _stats_page: VBoxContainer = null
var _stats_values: Dictionary = {}   # row key -> its value Label


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
	refresh_stats()


## Build the STATS page once. `refresh_stats()` decides whether the TabContainer
## actually shows it, so an unearned tab is never in the tab strip.
func _build_stats() -> void:
	_stats_page = VBoxContainer.new()
	_stats_page.name = STATS_TAB
	_stats_page.add_theme_constant_override("separation", 4)
	for row: Dictionary in STATS_ROWS:
		if bool(row.get("header", false)):
			var head := Label.new()
			head.text = String(row.text)
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.modulate = Color(1, 1, 1, 0.65)
			_stats_page.add_child(head)
			continue
		_stats_values[String(row.key)] = _add_stats_line(_stats_page, String(row.text))
	# One line per difficulty, in the registry order the menu uses.
	for id: String in WaveManager.DIFFICULTY_ORDER:
		_stats_values["difficulty_" + id] = _add_stats_line(_stats_page, id.to_upper())


## Name on the left, value on the right. Returns the value Label, which is the
## only thing refresh_stats rewrites.
func _add_stats_line(parent: Node, label_text: String) -> Label:
	var line := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.text = "-"
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
	var present: bool = _stats_page.get_parent() == _tabs
	if wanted and not present:
		_tabs.add_child(_stats_page)
	elif not wanted and present:
		_tabs.remove_child(_stats_page)
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


func open(run: Dictionary = {}) -> void:
	show()
	# Always open on the menu tab: Escape should land on the same controls every
	# time, whatever tab was left selected.
	show_tab(0)
	sync_audio_sliders()   # volumes may have moved in the main menu since the last pause
	refresh_unlockables()
	refresh_stats(run)
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


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()
