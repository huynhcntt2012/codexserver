extends Control
## PC-only host for the kit-styled Shop and Equipment pages. Keeps the same
## `open_page` / `shop` / `equipment` API as the shared web showcase.
const ScreenFill := preload("res://scripts/ui/screen_fill.gd")
var shop: Control
var equipment: Control
var toast: Label
var toast_tween: Tween

func _ready() -> void:
	ScreenFill.set_fill(get_tree(), true)
	shop = preload("res://scripts/ui/pc/pc_shop.gd").new()
	equipment = preload("res://scripts/ui/pc/pc_equipment.gd").new()
	for page in [shop, equipment]:
		page.navigate.connect(open_page)
		add_child(page)
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_top = -110
	toast.offset_bottom = -60
	toast.offset_left = -320
	toast.offset_right = 320
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color.WHITE)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color("2d4a7a", 0.92)
	pill.set_corner_radius_all(22)
	toast.add_theme_stylebox_override("normal", pill)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.hide()
	add_child(toast)
	UIState.toast_requested.connect(show_toast)
	open_page(str(UIState.get_meta("desktop_page", "shop")))
	UIState.remove_meta("desktop_page")
	print("PRACTICE_PC_STORE_READY")

func open_page(page: String) -> void:
	match page:
		"shop", "equipment":
			shop.visible = page == "shop"
			equipment.visible = page == "equipment"
		"home":
			var lobby: bool = AuthSession.has_session() or UIState.get_meta("from_desktop_lobby", false)
			get_tree().change_scene_to_file("res://scenes/main.tscn" if lobby else "res://scenes/ui/launch/launch_screen.tscn")

func show_toast(message: String) -> void:
	if is_instance_valid(toast_tween):
		toast_tween.kill()
	toast.text = message
	toast.modulate.a = 1.0
	toast.show()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.0)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	toast_tween.tween_callback(toast.hide)

func _exit_tree() -> void:
	ScreenFill.set_fill(get_tree(), false)
