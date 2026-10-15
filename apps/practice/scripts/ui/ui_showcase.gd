extends Control
@onready var shop: Control = $ShopScreen
@onready var equipment: Control = $EquipmentScreen
@onready var toast: Label = $Toast
var toast_tween: Tween

func _ready() -> void:
	shop.navigate.connect(open_page)
	equipment.navigate.connect(open_page)
	UIState.toast_requested.connect(_show_toast)
	open_page("shop")
	print("PRACTICE_UI_READY")

func open_page(page: String) -> void:
	match page:
		"shop":
			shop.show(); equipment.hide()
		"equipment":
			shop.hide(); equipment.show()
		"battle":
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"home":
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		_:
			_show_toast("Tính năng đang được phát triển")

func _show_toast(message: String) -> void:
	if is_instance_valid(toast_tween): toast_tween.kill()
	toast.text = message
	toast.modulate.a = 1.0
	toast.show()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.2)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	toast_tween.tween_callback(toast.hide)
