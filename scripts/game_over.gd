extends CanvasLayer
class_name GameOverScreen
## Game-over panel: final score + wave survived + the stored record + a run
## summary, and a restart via button or the R key (Main handles the R key; this
## handles the button).
##
## The summary is the SAME dictionary the pause menu's STATS tab renders (Main's
## `_pause_stats()`), so the two screens can never disagree -- one source of
## numbers, two renderers.

signal restart_pressed

## Palette, shared with the menu art.
const COLOR_TITLE := Color("#f4eaff")
const COLOR_MUTED := Color("#a59ab8")
const COLOR_ACCENT := Color("#ff71bb")

## Summary rows, in display order. Keys are Main._pause_stats()' keys.
const SUMMARY_ROWS: Array[Dictionary] = [
	{"key": "kills", "text": "KILLS"},
	{"key": "credits", "text": "CREDITS"},
	{"key": "dps", "text": "DPS"},
	{"key": "time", "text": "TIME"},
]

@onready var _score_label: Label = $Center/Card/Margin/Column/ScoreLabel
@onready var _wave_label: Label = $Center/Card/Margin/Column/WaveLabel
@onready var _best_label: Label = $Center/Card/Margin/Column/BestLabel
@onready var _restart_button: Button = $Center/Card/Margin/Column/RestartButton

## row key -> its value Label.
var _summary_values: Dictionary = {}


func _ready() -> void:
	visible = false
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	_build_summary()


## Build the summary rows once. The values are rewritten by show_game_over().
func _build_summary() -> void:
	var column: VBoxContainer = $Center/Card/Margin/Column
	var box := VBoxContainer.new()
	box.name = "Summary"
	box.add_theme_constant_override("separation", 2)
	for row: Dictionary in SUMMARY_ROWS:
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(row.text)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", COLOR_MUTED)
		var value_label := Label.new()
		value_label.text = "-"
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 18)
		value_label.add_theme_color_override("font_color", COLOR_TITLE)
		line.add_child(name_label)
		line.add_child(value_label)
		box.add_child(line)
		_summary_values[String(row.key)] = value_label
	column.add_child(box)
	# The summary reads above the button, not below it.
	column.move_child(box, _restart_button.get_index())


## `record` is Storage.record_run()'s reply: best_score/best_wave/new_score/new_wave.
## `run_stats` is Main._pause_stats() -- the same numbers the STATS tab shows.
func show_game_over(score: int, wave_reached: int, record: Dictionary,
		run_stats: Dictionary = {}) -> void:
	_score_label.text = "SCORE: %d" % score
	_wave_label.text = "SURVIVED TO WAVE %d" % maxi(wave_reached, 1)
	var beat_score: bool = bool(record.get("new_score", false)) and score > 0
	var beat_wave: bool = bool(record.get("new_wave", false)) and wave_reached > 0
	var best_score: int = int(record.get("best_score", score))
	var best_wave: int = int(record.get("best_wave", maxi(wave_reached, 1)))
	if beat_score or beat_wave:
		_best_label.text = "NEW BEST!  %d - WAVE %d" % [best_score, best_wave]
		_best_label.modulate = Color(1.0, 0.82, 0.3)
	else:
		_best_label.text = "BEST: %d - WAVE %d" % [best_score, best_wave]
		_best_label.modulate = Color(1, 1, 1, 0.65)
	_fill_summary(run_stats)
	visible = true
	_restart_button.grab_focus()


func _fill_summary(run_stats: Dictionary) -> void:
	var seconds: float = maxf(float(run_stats.get("seconds", 0.0)), 1.0)
	var damage: float = float(run_stats.get("damage", 0))
	_set_summary("kills", str(int(run_stats.get("kills", 0))))
	_set_summary("credits", str(int(run_stats.get("credits", 0))))
	_set_summary("dps", "%.1f" % (damage / seconds))
	_set_summary("time", _format_time(seconds))


func _set_summary(key: String, value: String) -> void:
	if _summary_values.has(key):
		(_summary_values[key] as Label).text = value


## mm:ss, shared with the probe so the card and the assertion agree.
func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
