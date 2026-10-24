extends Control
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")
func _ready() -> void:
	$Badge.add_theme_stylebox_override("panel", Ui.box(Color(1.0, 1.0, 1.0, 0.85), Color("#FFFFFF"), 16, 1, 2))
	Ui.apply_label($Text, 13, Ui.INK)
func set_announcement(value: String) -> void:
	$Text.text = value
