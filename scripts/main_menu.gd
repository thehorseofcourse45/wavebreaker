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
## Run mutators: glass cannon and boss rush are unlockable-gated; fog,
## elite_storm and no_shop are always available. One signal for all five, because
## Main only ever needs the set.
signal mutators_changed(glass_cannon: bool, boss_rush: bool, fog: bool,
		elite_storm: bool, no_shop: bool)
## The run's weapon archetype (weapons.gd): the menu owns the preference and
## announces it; Main applies it to the player and re-seeds it on boot.
signal weapon_changed(id: String)
## The DAILY run option (seeds the run to today's date). A separate signal from the
## mutator bundle because it is not a mutator -- Main stores it on its own.
signal daily_seed_toggled(enabled: bool)
## The RANDOM-waves mode: every wave rolls one of WaveManager's 17 archetypes.
## Not part of the mutator bundle (it is a MODE, not a handicap), so its own signal.
signal random_waves_toggled(enabled: bool)

const Storage := preload("res://scripts/storage.gd")
## A second click inside this window is the confirmation that wipes the records.
const RESET_CONFIRM_WINDOW := 4.0

@onready var _title: Label = $Center/Card/Margin/Column/Title
@onready var _best_label: Label = $Center/Card/Margin/Column/BestLabel
@onready var _kills_label: Label = $Center/Card/Margin/Column/KillsLabel
@onready var _start_button: Button = $Center/Card/Margin/Column/StartButton
@onready var _endless_check: CheckButton = $Center/Card/Margin/Column/EndlessCheck
@onready var _difficulty_row: HBoxContainer = $Center/Card/Margin/Column/DifficultyRow
@onready var _mutators_row: FlowContainer = $Center/Card/Margin/Column/Mutators
@onready var _glass_check: CheckButton = $Center/Card/Margin/Column/Mutators/GlassCheck
@onready var _boss_check: CheckButton = $Center/Card/Margin/Column/Mutators/BossCheck
@onready var _fog_check: CheckButton = $Center/Card/Margin/Column/Mutators/FogCheck
@onready var _elite_check: CheckButton = $Center/Card/Margin/Column/Mutators/EliteCheck
@onready var _no_shop_check: CheckButton = $Center/Card/Margin/Column/Mutators/NoShopCheck
@onready var _daily_check: CheckButton = $Center/Card/Margin/Column/Mutators/DailyCheck
@onready var _random_check: CheckButton = $Center/Card/Margin/Column/RandomCheck
@onready var _music_slider: HSlider = $Center/Card/Margin/Column/Audio/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Center/Card/Margin/Column/Audio/SfxRow/SfxSlider
@onready var _reset_button: Button = $Center/Card/Margin/Column/ResetButton
@onready var _reset_hint: Label = $Center/Card/Margin/Column/ResetHint

var _reset_armed: bool = false
var _reset_timer: Timer = null
var _difficulty_buttons: Dictionary = {}   # id -> Button
## The weapon dropdown. Built in code and parked in the Mutators row rather than
## authored into the scene: a new row costs ~40 px of a card that is already
## within ~7 px of its 715 px guard at 720p, and the row is the run-options row
## anyway. Builder, not .tscn, so nobody has to reload the scene from disk.
var _weapon_picker: OptionButton = null
## The RANDOM-waves mode toggle, authored in the scene on its own row (the
## run-options row was already full -- cramming it in widened the card off-screen).


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
	_build_weapon_picker()
	# set_pressed_no_signal: reflecting a saved preference must not re-write it
	# (and on boot that would rewrite the save file on every launch).
	_endless_check.set_pressed_no_signal(bool(Storage.get_value("endless", true)))
	_apply_difficulty(String(Storage.get_value("difficulty", "normal")))
	sync_audio_sliders()
	_endless_check.toggled.connect(_on_endless_toggled)
	_glass_check.toggled.connect(_on_mutator_toggled)
	_boss_check.toggled.connect(_on_mutator_toggled)
	_fog_check.toggled.connect(_on_mutator_toggled)
	_elite_check.toggled.connect(_on_mutator_toggled)
	_no_shop_check.toggled.connect(_on_mutator_toggled)
	_daily_check.set_pressed_no_signal(bool(Storage.get_value("daily_seed", false)))
	_daily_check.toggled.connect(_on_daily_toggled)
	_random_check.set_pressed_no_signal(bool(Storage.get_value("random_waves", false)))
	_random_check.toggled.connect(_on_random_toggled)
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


# ---------------------------------------------------------------- weapons ---

## One dropdown entry per registry row, in registry order, so adding a weapon is a
## row in weapons.gd and nothing here. `metadata` carries the id: the item index is
## a display detail and must never be the thing written to the save.
func _build_weapon_picker() -> void:
	if is_instance_valid(_weapon_picker):
		return
	_weapon_picker = OptionButton.new()
	_weapon_picker.name = "WeaponPicker"
	_weapon_picker.custom_minimum_size = Vector2(132, 0)
	_weapon_picker.focus_mode = Control.FOCUS_NONE
	for i: int in Weapons.ids().size():
		var id: String = Weapons.ids()[i]
		_weapon_picker.add_item(Weapons.display_name(id), i)
		_weapon_picker.set_item_metadata(i, id)
	_weapon_picker.item_selected.connect(_on_weapon_selected)
	_mutators_row.add_child(_weapon_picker)


## Called by Main on boot and on every menu re-entry. select() does not emit
## item_selected (only a user pick does), so reflecting the saved gun cannot
## re-write the save on launch -- the same rule as the ENDLESS toggle.
func set_weapon(id: String) -> void:
	if not is_instance_valid(_weapon_picker):
		return
	var want: String = String(Weapons.resolve(id).id)
	for i: int in _weapon_picker.item_count:
		if String(_weapon_picker.get_item_metadata(i)) == want:
			_weapon_picker.select(i)
			break
	_update_weapon_tooltip()


func _on_weapon_selected(index: int) -> void:
	var id: String = String(_weapon_picker.get_item_metadata(index))
	Storage.set_value(Weapons.SAVE_KEY, id)
	_update_weapon_tooltip()
	weapon_changed.emit(id)


## The row is a bare list of toggle labels, so the gun's own hint has to live in the
## tooltip: "LANCE" alone does not say it pierces.
func _update_weapon_tooltip() -> void:
	var at: int = _weapon_picker.selected
	var id: String = String(_weapon_picker.get_item_metadata(at)) if at >= 0 else Weapons.DEFAULT_ID
	_weapon_picker.tooltip_text = "%s - %s" % [Weapons.display_name(id), Weapons.hint(id)]


# ------------------------------------------------------------- random waves ---

## Called by Main on boot/menu re-entry (and after a RESET SAVE) to reflect the
## saved preference without re-writing it -- same rule as set_daily.
func set_random_waves(enabled: bool) -> void:
	_random_check.set_pressed_no_signal(enabled)


## The menu owns this preference (it is the only writer), so the toggle writes
## the save itself and tells Main, exactly like DAILY.
func _on_random_toggled(enabled: bool) -> void:
	Storage.set_value("random_waves", enabled)
	random_waves_toggled.emit(enabled)


# --------------------------------------------------------------- mutators ---

## Called by Main on boot and on every menu re-entry. Glass cannon and boss rush
## appear only once their unlockable is earned; fog / elite storm / no shop are
## always shown. The row is visible whenever any toggle is.
func refresh_run_options(glass_cannon: bool, boss_rush: bool, fog: bool = false,
		elite_storm: bool = false, no_shop: bool = false) -> void:
	var glass_open: bool = Unlockables.is_unlocked("glass_cannon")
	var rush_open: bool = Unlockables.is_unlocked("boss_rush")
	_glass_check.visible = glass_open
	_boss_check.visible = rush_open
	_mutators_row.visible = true
	# Reflecting a SAVED preference must not re-write it (same rule as ENDLESS),
	# and a toggle that is hidden must never report as enabled.
	_glass_check.set_pressed_no_signal(glass_open and glass_cannon)
	_boss_check.set_pressed_no_signal(rush_open and boss_rush)
	_fog_check.set_pressed_no_signal(fog)
	_elite_check.set_pressed_no_signal(elite_storm)
	_no_shop_check.set_pressed_no_signal(no_shop)


## The menu owns these preferences (it is the only writer), so a toggle writes the
## save itself and tells Main, exactly like ENDLESS and DIFFICULTY.
func _on_mutator_toggled(_pressed: bool) -> void:
	Storage.set_value("glass_cannon", _glass_check.button_pressed)
	Storage.set_value("boss_rush", _boss_check.button_pressed)
	Storage.set_value("fog", _fog_check.button_pressed)
	Storage.set_value("elite_storm", _elite_check.button_pressed)
	Storage.set_value("no_shop", _no_shop_check.button_pressed)
	mutators_changed.emit(_glass_check.button_pressed, _boss_check.button_pressed,
			_fog_check.button_pressed, _elite_check.button_pressed,
			_no_shop_check.button_pressed)


## Reflect the saved DAILY preference (Main calls this on menu entry).
## set_pressed_no_signal: showing a saved value must not re-write it, same rule as
## ENDLESS and the mutators.
func set_daily(enabled: bool) -> void:
	_daily_check.set_pressed_no_signal(enabled)


## The menu owns this preference (it is the only writer), so the toggle writes the
## save itself and tells Main, exactly like ENDLESS and DIFFICULTY.
func _on_daily_toggled(enabled: bool) -> void:
	Storage.set_value("daily_seed", enabled)
	daily_seed_toggled.emit(enabled)


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
	# The gun preference survives (it is in Storage.PREFERENCE_KEYS), so the picker
	# only needs to be re-read, not rebuilt.
	set_weapon(String(Storage.get_value(Weapons.SAVE_KEY, Weapons.DEFAULT_ID)))
	# The toggles are preferences and survive, but their unlockables are gone.
	refresh_run_options(_glass_check.button_pressed, _boss_check.button_pressed,
			_fog_check.button_pressed, _elite_check.button_pressed, _no_shop_check.button_pressed)
	set_random_waves(bool(Storage.get_value("random_waves", false)))
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
