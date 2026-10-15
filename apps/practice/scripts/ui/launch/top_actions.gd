extends Control
signal settings_requested()
signal sound_changed(muted: bool)
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")
var _muted := false

func _ready() -> void:
	Ui.apply_button($Settings, Color("#FFF5D4"), Color("#FFFFFF"), 15, 20)
	Ui.apply_button($Sound, Color("#FFF5D4"), Color("#FFFFFF"), 15, 20)
	$Settings.pressed.connect(func(): settings_requested.emit())
	$Sound.pressed.connect(_toggle_sound)

func _toggle_sound() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(0, _muted)
	$Sound.text = "ÂM: TẮT" if _muted else "ÂM: BẬT"
	sound_changed.emit(_muted)
