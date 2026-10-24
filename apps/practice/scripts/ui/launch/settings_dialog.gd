extends Control
signal applied(volume_percent: float, fullscreen: bool)
var api_field := LineEdit.new()
var connection_status := Label.new()
var check_button := Button.new()
var public_button := Button.new()
var checking := false
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")

func _ready() -> void:
	$Card.position = Vector2(330, 100)
	$Card.size = Vector2(620, 530)
	$Title.position = Vector2(350, 115)
	$Title.size = Vector2(580, 45)
	$VolumeLabel.position = Vector2(370, 175)
	$Volume.position = Vector2(370, 215)
	$Volume.size.x = 540
	$Fullscreen.position = Vector2(370, 245)
	var caption := Label.new()
	caption.text = "MÁY CHỦ TÀI KHOẢN"
	caption.position = Vector2(370, 290)
	caption.size = Vector2(540, 28)
	Ui.apply_label(caption, 18, Ui.INK)
	add_child(caption)
	api_field.name = "ApiUrl"
	api_field.position = Vector2(370, 325)
	api_field.size = Vector2(540, 44)
	api_field.placeholder_text = AuthSession.PUBLIC_API
	Ui.apply_input(api_field, Ui.AQUA, Ui.AQUA_DARK, 18, 3)
	add_child(api_field)
	public_button.text = "MÁY CHỦ BỤP BỤP"
	public_button.position = Vector2(370, 382)
	public_button.size = Vector2(300, 44)
	Ui.apply_button(public_button, Ui.CREAM, Ui.AQUA, 17)
	add_child(public_button)
	public_button.pressed.connect(func():
		api_field.text = AuthSession.PUBLIC_API
		connection_status.text = "Đã chọn máy chủ online. Kiểm tra rồi nhấn ÁP DỤNG."
	)
	check_button.text = "KIỂM TRA"
	check_button.position = Vector2(685, 382)
	check_button.size = Vector2(225, 44)
	Ui.apply_button(check_button, Ui.AQUA, Ui.AQUA_DARK, 17)
	add_child(check_button)
	check_button.pressed.connect(_check)
	connection_status.position = Vector2(370, 438)
	connection_status.size = Vector2(540, 96)
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Ui.apply_label(connection_status, 16, Ui.INK)
	add_child(connection_status)
	$Cancel.position = Vector2(370, 553)
	$Done.position = Vector2(680, 553)
	$Done.size = Vector2(230, 50)
	$Cancel.size = Vector2(230, 50)
	$Card.add_theme_stylebox_override("panel", Ui.box(Ui.CREAM, Ui.WHITE, 30, 14, 5))
	Ui.apply_label($Title, 28, Ui.INK)
	Ui.apply_label($VolumeLabel, 18, Ui.INK)
	$Fullscreen.add_theme_color_override("font_color", Ui.INK)
	Ui.apply_button($Cancel, Color("EAE4F5"), Color("D0C3E6"), 19, 19)
	Ui.apply_button($Done, Ui.PEACH, Ui.CORAL, 19, 19)
	$Cancel.pressed.connect(hide)
	$Done.pressed.connect(_apply)

func open() -> void:
	if not checking:
		api_field.text = AuthSession.api_url
		connection_status.text = "127.0.0.1 là máy PC của bạn. Chọn MÁY CHỦ BỤP BỤP để chơi online." if "127.0.0.1" in api_field.text else "Kiểm tra kết nối rồi nhấn ÁP DỤNG để lưu."
	$Fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	$Volume.value = roundf(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	show()
	api_field.grab_focus()

func _check() -> void:
	if checking:
		return
	checking = true
	check_button.disabled = true
	public_button.disabled = true
	api_field.editable = false
	$Done.disabled = true
	connection_status.text = "Đang kiểm tra kết nối…"
	connection_status.text = await AuthSession.check_connection(api_field.text)
	checking = false
	check_button.disabled = false
	public_button.disabled = false
	api_field.editable = true
	$Done.disabled = false

func _apply() -> void:
	if not AuthSession.configure(api_field.text):
		connection_status.text = AuthSession.last_error
		return
	# Same values as the in-game settings window (Settings autoload), so they last.
	var values: Dictionary = Settings.draft()
	values.audio.master = int($Volume.value)
	values.display.mode = "fullscreen" if $Fullscreen.button_pressed else "window"
	Settings.save(values)
	applied.emit(float($Volume.value), $Fullscreen.button_pressed)
	hide()
