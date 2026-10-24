extends Control
signal server_clicked()
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")

func _ready() -> void:
	$Background.add_theme_stylebox_override("panel", Ui.box(Color("#FFFDF1"), Color("#FFFFFF"), 24, 5, 3))
	Ui.apply_label($ServerName, 14, Ui.INK)
	Ui.apply_label($Connection, 13, Color("#B87A87"))
	$Select.pressed.connect(func(): server_clicked.emit())

func update_connection(connected: bool, server_name: String = "MÁY CHỦ BỤP BỤP") -> void:
	$ServerName.text = server_name
	$Connection.text = "Đã kết nối" if connected else "Chưa kết nối"
	$Connection.add_theme_color_override("font_color", Color("#268F7F") if connected else Color("#B87A87"))
	$Dot.color = Color("#63D7B2") if connected else Color("#F77891")
