extends CanvasLayer
class_name MainMenu
## Title screen: START, the ENDLESS toggle, the audio sliders, a two-click RESET
## SAVE and the stored records.
##
## `start_pressed` is the only contract Main depends on; the rest are optional
## extras it may connect to. The menu owns every preference it can change (it
## writes them through Storage / AudioManager and announces the change), so
## there is exactly one writer per key.

signal start_pressed
signal endless_toggled(enabled: bool)
signal difficulty_changed(id: String)
## Run mutators (unlockable-gated toggles): glass cannon and boss rush. One signal
## for both, because Main only ever needs the pair.
signal mutators_changed(glass_cannon: bool, boss_rush: bool)

const Storage := preload("res://scripts/storage.gd")
## A second click inside this window is the confirmation that wipes the records.
const RESET_CONFIRM_WINDOW := 4.0

@onready var _title: Label = $Center/Card/Margin/Column/Title
@onready var _best_label: Label = $Center/Card/Margin/Column/BestLabel
@onready var _kills_label: Label = $Center/Card/Margin/Column/KillsLabel
@onready var _start_button: Button = $Center/Card/Margin/Column/StartButton
@onready var _endless_check: CheckButton = $Center/Card/Margin/Column/EndlessCheck
@onready var _difficulty_row: HBoxContainer = $Center/Card/Margin/Column/DifficultyRow
@onready var _mutators_row: HBoxContainer = $Center/Card/Margin/Column/Mutators
@onready var _glass_check: CheckButton = $Center/Card/Margin/Column/Mutators/GlassCheck
@onready var _boss_check: CheckButton = $Center/Card/Margin/Column/Mutators/BossCheck
@onready var _music_slider: HSlider = $Center/Card/Margin/Column/Audio/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Center/Card/Margin/Column/Audio/SfxRow/SfxSlider
@onready var _reset_button: Button = $Center/Card/Margin/Column/ResetButton
@onready var _reset_hint: Label = $Center/Card/Margin/Column/ResetHint

var _reset_armed: bool = false
var _reset_timer: Timer = null
var _difficulty_buttons: Dictionary = {}   # id -> Button


func _ready() -> void:
	var art := preload("res://scripts/retro_menu_art.gd").new()
	art.name = "RetroMenuArt"
	add_child(art)
	# One source of truth for the game's name: project.godot's config/name also
	# sets the window title, so renaming the game is a one-line edit there.
	_title.text = String(ProjectSettings.get_setting("application/config/name", "WAVEBREAKER"))
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	_start_button.grab_focus()
	_reset_timer = Timer.new()
	_reset_timer.one_shot = true
	_reset_timer.wait_time = RESET_CONFIRM_WINDOW
	_reset_timer.timeout.connect(_disarm_reset)
	add_child(_reset_timer)
	_reset_button.pressed.connect(_on_reset_pressed)
	_build_difficulty_buttons()
	# set_pressed_no_signal: reflecting a saved preference must not re-write it
	# (and on boot that would rewrite the save file on every launch).
	_endless_check.set_pressed_no_signal(bool(Storage.get_value("endless", true)))
	_apply_difficulty(String(Storage.get_value("difficulty", "normal")))
	sync_audio_sliders()
	_endless_check.toggled.connect(_on_endless_toggled)
	_glass_check.toggled.connect(_on_mutator_toggled)
	_boss_check.toggled.connect(_on_mutator_toggled)
	# Sliders write straight through to AudioManager, which owns the save key.
	_music_slider.value_changed.connect(AudioManager.set_music_volume)
	_sfx_slider.value_changed.connect(AudioManager.set_sfx_volume)
	_disarm_reset()
	refresh_stats()


## Called on _ready and again whenever the menu is re-entered, so a record set
## this session shows up without a restart.
func refresh_stats() -> void:
	var data: Dictionary = Storage.read_all()
	var best_score: int = int(data.get("best_score", 0))
	if best_score > 0:
		_best_label.text = "BEST: %d - WAVE %d" % [best_score, int(data.get("best_wave", 1))]
	else:
		_best_label.text = ""
	var kills: int = int(data.get("total_kills", 0))
	if kills > 0:
		_kills_label.text = "TOTAL KILLS: %d" % kills
	else:
		_kills_label.text = ""


## Reflect the CURRENT volumes (AudioManager owns them). set_value_no_signal: a
## slider moved by code must not re-write the save on every launch. Public so Main
## can re-sync on menu entry -- the pause menu moves the same volumes.
func sync_audio_sliders() -> void:
	_music_slider.set_value_no_signal(AudioManager.music_volume())
	_sfx_slider.set_value_no_signal(AudioManager.sfx_volume())


## Labels the ENDLESS row with what turning it OFF actually buys, using the
## wave manager's own table size instead of a number copied into the scene.
func set_scripted_waves(count: int) -> void:
	_endless_check.text = "ENDLESS" if count <= 0 else "ENDLESS  (off = %d-wave run)" % count


## One toggle button per WaveManager.DIFFICULTY_ORDER entry the player can
## actually pick, so the menu never hardcodes the list: add a difficulty in the
## wave manager and it shows up here (gated by its `unlock`, if it has one).
func _build_difficulty_buttons() -> void:
	for btn: Node in _difficulty_row.get_children():
		# free(), not queue_free(): a queued button keeps its name for the rest of
		# the frame, and Godot would then rename the rebuilt one "Easy2".
		_difficulty_row.remove_child(btn)
		btn.free()
	_difficulty_buttons.clear()
	var group := ButtonGroup.new()
	for id: String in WaveManager.DIFFICULTY_ORDER:
		if not WaveManager.difficulty_unlocked(id):
			continue
		var btn := Button.new()
		btn.name = id.capitalize()
		btn.text = id.to_upper()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(96, 36)
		btn.pressed.connect(_on_difficulty_pressed.bind(id))
		_difficulty_row.add_child(btn)
		_difficulty_buttons[id] = btn


func _on_difficulty_pressed(id: String) -> void:
	if not _difficulty_buttons.has(id):
		return
	_apply_difficulty(id)
	Storage.set_value("difficulty", id)
	difficulty_changed.emit(id)


## Called by Main on boot/menu re-entry to show the run's actual difficulty.
## Rebuilds the row first: a difficulty earned since the last visit (or the last
## launch) has to appear without a restart.
func set_difficulty(id: String) -> void:
	_build_difficulty_buttons()
	_apply_difficulty(id)


func _apply_difficulty(id: String) -> void:
	var chosen: String = id if _difficulty_buttons.has(id) else "normal"
	for key: String in _difficulty_buttons:
		(_difficulty_buttons[key] as Button).set_pressed_no_signal(key == chosen)


func _on_endless_toggled(enabled: bool) -> void:
	Storage.set_value("endless", enabled)
	endless_toggled.emit(enabled)


# --------------------------------------------------------------- mutators ---

## Called by Main on boot and on every menu re-entry: a toggle appears only once
## its unlockable is earned, and the row hides itself while neither is.
func refresh_run_options(glass_cannon: bool, boss_rush: bool) -> void:
	var glass_open: bool = Unlockables.is_unlocked("glass_cannon")
	var rush_open: bool = Unlockables.is_unlocked("boss_rush")
	_glass_check.visible = glass_open
	_boss_check.visible = rush_open
	_mutators_row.visible = glass_open or rush_open
	# Reflecting a SAVED preference must not re-write it (same rule as ENDLESS),
	# and a toggle that is hidden must never report as enabled.
	_glass_check.set_pressed_no_signal(glass_open and glass_cannon)
	_boss_check.set_pressed_no_signal(rush_open and boss_rush)


## The menu owns these preferences (it is the only writer), so a toggle writes the
## save itself and tells Main, exactly like ENDLESS and DIFFICULTY.
func _on_mutator_toggled(_pressed: bool) -> void:
	Storage.set_value("glass_cannon", _glass_check.button_pressed)
	Storage.set_value("boss_rush", _boss_check.button_pressed)
	mutators_changed.emit(_glass_check.button_pressed, _boss_check.button_pressed)


# ------------------------------------------------------------------ reset ---

## Erasing everything is a footgun, so the first click only arms the button and
## starts a countdown; the hint says what the second click will do.
func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "CONFIRM RESET?"
		_reset_hint.text = "Click again -- records are erased, sound settings stay."
		_reset_timer.start()
		return
	Storage.reset_progress()
	# Wiping the save has to wipe the cached unlock flags too, and the difficulty
	# row may shrink back (nightmare was earned).
	Unlockables.refresh()
	set_difficulty(String(Storage.get_value("difficulty", "normal")))
	# The toggles are preferences and survive, but their unlockables are gone.
	refresh_run_options(_glass_check.button_pressed, _boss_check.button_pressed)
	_disarm_reset()
	refresh_stats()


func _disarm_reset() -> void:
	_reset_timer.stop()
	_reset_armed = false
	_reset_button.text = "RESET SAVE"
	_reset_hint.text = ""


# ------------------------------------------------------------------ input ---

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		start_pressed.emit()
		get_viewport().set_input_as_handled()
