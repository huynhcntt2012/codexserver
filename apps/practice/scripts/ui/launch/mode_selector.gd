extends Control
## 1P/2P is intended number of local participants; online lobby is separate.
signal mode_changed(mode: String)
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")
var _selected := "solo"

func _ready() -> void:
	$Solo.pressed.connect(func(): select_mode("solo"))
	$Duo.pressed.connect(func(): select_mode("duo"))
	select_mode("solo")

func select_mode(mode: String) -> void:
	if mode != "solo" and mode != "duo":
		return
	_selected = mode
	Ui.apply_button($Solo, Color("#8BE1F2") if mode == "solo" else Color("#DDF4FA"), Color("#2194C6") if mode == "solo" else Color("#ACCCD8"), 16, 24)
	Ui.apply_button($Duo, Color("#BAA5F2") if mode == "duo" else Color("#F2E9FF"), Color("#8374D3") if mode == "duo" else Color("#CEB8E6"), 16, 24)
	mode_changed.emit(_selected)

func get_selected_mode() -> String:
	return _selected
