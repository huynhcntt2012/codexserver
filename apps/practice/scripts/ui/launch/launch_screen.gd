extends Control
## Single screen orchestration; component logic stays in each child script.
## Signals are the integration boundary for Auth API / lobby navigation.
signal login_requested(username: String, password: String, mode: String)
signal guest_requested(mode: String)
signal registration_requested()
signal password_recovery_requested()
signal events_requested()

const BASE_SIZE := Vector2(1280.0, 720.0)
@onready var canvas_root: Control = $CanvasRoot
@onready var auth_panel: Control = $CanvasRoot/AuthPanel
@onready var mode_selector: Control = $CanvasRoot/ModeSelector
@onready var info_dialog: Control = $CanvasRoot/InfoDialog
@onready var settings_dialog: Control = $CanvasRoot/SettingsDialog

func _ready() -> void:
	var shop := Button.new()
	shop.name = "ShopEquipment"
	shop.text = "CỬA HÀNG / TRANG BỊ"
	shop.position = Vector2(490, 211)
	shop.size = Vector2(300, 48)
	preload("res://scripts/ui/launch/ui_theme.gd").apply_button(shop, Color("fff9e9"), Color("50cfcb"))
	canvas_root.add_child(shop)
	canvas_root.move_child(shop, canvas_root.get_child_count() - 3)
	shop.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/ui_showcase.tscn"))
	var logout_button := Button.new()
	logout_button.name = "Logout"
	logout_button.text = "ĐĂNG XUẤT"
	logout_button.position = Vector2(1010, 110)
	logout_button.size = Vector2(240, 44)
	preload("res://scripts/ui/launch/ui_theme.gd").apply_button(logout_button, Color("fff9e9"), Color("50cfcb"))
	canvas_root.add_child(logout_button)
	canvas_root.move_child(logout_button, canvas_root.get_child_count() - 3)
	logout_button.pressed.connect(func(): AuthSession.logout())
	resized.connect(_update_layout)
	_update_layout()
	auth_panel.login_requested.connect(_on_login)
	auth_panel.guest_requested.connect(_on_guest)
	auth_panel.forgot_password_requested.connect(_on_forgot)
	auth_panel.validation_failed.connect(_show_validation)
	$CanvasRoot/TopActions.settings_requested.connect(func(): settings_dialog.open())
	$CanvasRoot/ServerStatus.server_clicked.connect(_on_server_clicked)
	$CanvasRoot/FooterNav.guide_requested.connect(_on_guide)
	$CanvasRoot/FooterNav.news_requested.connect(_on_events)
	$CanvasRoot/FooterNav.register_requested.connect(_on_register)
	$CanvasRoot/FooterNav.exit_requested.connect(func(): get_tree().quit())

func _update_layout() -> void:
	if not is_instance_valid(canvas_root):
		return
	var size_factor: float = minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	canvas_root.scale = Vector2.ONE * size_factor
	canvas_root.position = (size - BASE_SIZE * size_factor) / 2.0

func _on_login(username: String, password: String) -> void:
	if AuthSession.busy:
		return
	if mode_selector.get_selected_mode() != "solo":
		info_dialog.show_info("CHƠI CÙNG BẠN", "Chọn 1P để chơi với bot. 2P chưa hỗ trợ trong bản này.")
		return
	auth_panel.set_busy(true)
	$CanvasRoot/ShopEquipment.disabled = true
	$CanvasRoot/FooterNav/Register.disabled = true
	$CanvasRoot/TopActions/Settings.disabled = true
	var success: bool = await AuthSession.authenticate(username, password, auth_panel.registering)
	auth_panel.reset_password_field()
	auth_panel.set_busy(false)
	$CanvasRoot/ShopEquipment.disabled = false
	$CanvasRoot/FooterNav/Register.disabled = false
	$CanvasRoot/TopActions/Settings.disabled = false
	if success:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		info_dialog.show_info("KHÔNG THỂ ĐĂNG NHẬP", AuthSession.last_error)
		$CanvasRoot/ServerStatus.update_connection(false)

func _on_guest() -> void:
	if AuthSession.busy:
		return
	guest_requested.emit(mode_selector.get_selected_mode())
	if mode_selector.get_selected_mode() != "solo":
		info_dialog.show_info("CHƠI CÙNG BẠN", "Bản này hỗ trợ một người chơi với bot. Hãy chọn 1P rồi CHƠI THỬ.")
		return
	AuthSession.logout()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_forgot() -> void:
	password_recovery_requested.emit()
	info_dialog.show_info("LẤY LẠI MẬT KHẨU", "Máy chủ chưa hỗ trợ khôi phục mật khẩu.")

func _on_register() -> void:
	registration_requested.emit()
	if AuthSession.busy:
		return
	auth_panel.set_registration(not auth_panel.registering)
	$CanvasRoot/FooterNav/Register.text = "ĐĂNG NHẬP" if auth_panel.registering else "ĐĂNG KÝ"

func _on_events() -> void:
	events_requested.emit()
	info_dialog.show_info("SỰ KIỆN", "Chưa có sự kiện đang diễn ra. Thử sức với ba đối thủ bot ngay hôm nay!")

func _on_guide() -> void:
	info_dialog.show_info("HƯỚNG DẪN", "Di chuyển: WASD hoặc phím mũi tên. Đặt bóng nước: Space. Đừng để bóng nổ chạm vào mình!")

func _on_server_clicked() -> void:
	settings_dialog.open()

func _show_validation(message: String) -> void:
	info_dialog.show_info("KIỂM TRA THÔNG TIN", message)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if settings_dialog.visible:
			settings_dialog.hide()
		elif info_dialog.visible:
			info_dialog.hide_dialog()

func _process(_delta: float) -> void:
	var signed_in: bool = AuthSession.has_session()
	$CanvasRoot/Logout.visible = signed_in
	$CanvasRoot/Logout.disabled = AuthSession.busy
	if signed_in:
		$CanvasRoot/ServerStatus/Connection.text = "Tài khoản: " + AuthSession.account_name
	else:
		$CanvasRoot/ServerStatus/Connection.text = "Đang đăng nhập…" if AuthSession.busy else "Chưa đăng nhập"
