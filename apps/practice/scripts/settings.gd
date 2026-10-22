extends Node
## Player settings (docs/SETTINGS.md), saved in user://settings.cfg on this PC and
## applied at start: window mode and size, anti-aliasing (quality), FPS cap,
## V-Sync, brightness, audio buses (Master > Music, SFX, UI) and devices, mute
## when the window loses focus, and gameplay switches read by the match screens.
## The settings window edits a draft and calls save() on LƯU.
signal changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"display": {
		"mode": "fullscreen", "resolution": "1600x900", "quality": "high", "fps": 60,
		"vsync": true, "brightness": 50, "show_names": true,
	},
	"audio": {
		"master": 80, "music": 70, "sfx": 90, "ui": 85,
		"output_device": "Default", "input_device": "Default", "mute_unfocused": true,
	},
	"game": {
		"auto_ready": false, "screen_shake": true, "vibration": true,
		"confirm_leave": true, "chat_filter": true,
	},
	"language": {"ui": "vi"},
	"controls": {"device": "keyboard", "show_hints": true, "auto_detect": true, "deadzone": 50},
}
## Gamepad (Xbox layout) in a match; menus use Godot's defaults (A accept, B back).
const PAD_ACTIONS := {
	JOY_BUTTON_A: "bomb", JOY_BUTTON_X: "use", JOY_BUTTON_B: "mount",
	JOY_BUTTON_LEFT_SHOULDER: "prev", JOY_BUTTON_RIGHT_SHOULDER: "next", JOY_BUTTON_START: "pause",
}
const HINTS := {  # action -> [keyboard, gamepad]
	"bomb": ["Space", "A"], "use": ["Ctrl", "X"], "mount": ["Q", "B"],
	"slots": ["1–6", "LB / RB"], "pause": ["Esc", "Start"],
}
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440"]
const QUALITY := {  # name -> [label, 2D MSAA]
	"low": ["Thấp", Viewport.MSAA_DISABLED],
	"medium": ["Trung bình", Viewport.MSAA_2X],
	"high": ["Cao", Viewport.MSAA_4X],
	"ultra": ["Rất cao", Viewport.MSAA_8X],
}
const FPS := [30, 60, 120, 0]  # 0 = no cap
const BUSES := ["Music", "SFX", "UI"]
const UI_SOUNDS := ["ui_select"]
## Shown as ✱✱✱ in chat when the filter is on (whole words, any case).
const BLOCKED := ["địt", "đụ", "lồn", "cặc", "buồi", "đéo", "đm", "đcm", "dcm", "vcl", "vkl", "fuck", "shit", "bitch"]

var values: Dictionary = {}
var _overlay: ColorRect
var _focus_muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	load_values()
	apply(values, true)
	Input.joy_connection_changed.connect(_on_joy_changed)

## Stored values over DEFAULTS (unknown keys and wrong types dropped).
func load_values() -> void:
	values = defaults()
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not file.has_section_key(section, key):
				continue  # added in a later version: keep the default
			var stored = file.get_value(section, key)
			if stored != null and typeof(stored) == typeof(DEFAULTS[section][key]):
				values[section][key] = stored
			elif stored != null and DEFAULTS[section][key] is int and stored is float:
				values[section][key] = int(stored)

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)

func get_value(section: String, key: String):
	return values.get(section, {}).get(key, DEFAULTS[section][key])

func draft() -> Dictionary:
	return values.duplicate(true)

## Applies and stores a draft from the settings window.
func save(draft_values: Dictionary) -> void:
	apply(draft_values)
	values = draft_values.duplicate(true)
	var file := ConfigFile.new()
	for section in values:
		for key in values[section]:
			file.set_value(section, key, values[section][key])
	file.save(PATH)
	changed.emit()

## Makes the values take effect now (the window previews volumes with it too).
func apply(v: Dictionary, startup := false) -> void:
	var display: Dictionary = v.display
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var full: bool = display.mode == "fullscreen"
		var current := DisplayServer.window_get_mode()
		var is_full := current in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if full != is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)
		if not full:
			var size := resolution_size(str(display.resolution))
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			if DisplayServer.window_get_size() != size:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if display.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(display.fps)
	if get_viewport():
		get_viewport().msaa_2d = QUALITY.get(str(display.quality), QUALITY.high)[1]
	var light := (float(display.brightness) - 50.0) / 50.0  # -1 .. 1
	_overlay.color = Color(0, 0, 0, -light * 0.45) if light < 0.0 else Color(1, 1, 1, light * 0.12)
	_overlay.visible = absf(light) > 0.01
	var audio: Dictionary = v.audio
	set_volume("Master", float(audio.master))
	set_volume("Music", float(audio.music))
	set_volume("SFX", float(audio.sfx))
	set_volume("UI", float(audio.ui))
	if str(audio.output_device) in AudioServer.get_output_device_list():
		AudioServer.output_device = str(audio.output_device)
	if not startup and str(audio.input_device) in AudioServer.get_input_device_list():
		AudioServer.input_device = str(audio.input_device)

static func resolution_size(value: String) -> Vector2i:
	var parts := value.split("x")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(1600, 900)

static func set_volume(bus: String, percent: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(percent / 100.0, 0.0001)))
		if bus != "Master":
			AudioServer.set_bus_mute(index, percent <= 0.0)

## Bus for a sound id of game._sound().
static func bus_for(sound_id: String) -> String:
	return "UI" if sound_id in UI_SOUNDS else "SFX"

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(get_value("audio", "mute_unfocused")):
		_focus_muted = not AudioServer.is_bus_mute(0)
		if _focus_muted:
			AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _focus_muted:
		_focus_muted = false
		AudioServer.set_bus_mute(0, false)

# ---------------------------------------------------------------- gameplay helpers

func on(section: String, key: String) -> bool:
	return bool(get_value(section, key))

## A short shake of a board node when a bomb explodes (if enabled).
func shake(node: Node2D) -> void:
	if node == null or not on("game", "screen_shake") or node.has_meta("shaking"):
		return
	node.set_meta("shaking", true)
	var home := node.position
	var tween := node.create_tween()
	for i in 6:
		var step := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (6.0 - i)
		tween.tween_property(node, "position", home + step, 0.03)
	tween.tween_property(node, "position", home, 0.03)
	tween.tween_callback(func(): node.remove_meta("shaking"))

## Gamepad rumble on explosions (if enabled and a pad is connected).
func rumble(strength := 0.5, seconds := 0.15) -> void:
	if not on("game", "vibration"):
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, strength * 0.6, strength, seconds)

## Chat text with blocked words hidden, when the filter is on.
func clean_chat(message: String) -> String:
	if not on("game", "chat_filter"):
		return message
	var out := message
	for word in BLOCKED:
		var pattern := RegEx.create_from_string("(?i)(?<![\\p{L}\\p{N}])" + word + "(?![\\p{L}\\p{N}])")
		out = pattern.sub(out, "✱".repeat(word.length()), true)
	return out

# ---------------------------------------------------------------- controls

func gamepad() -> bool:
	return str(get_value("controls", "device")) == "gamepad"

## Stick tilt below this is ignored (Độ nhạy / Deadzone 0..100 -> 0.05..0.65).
func deadzone() -> float:
	return 0.05 + 0.6 * float(get_value("controls", "deadzone")) / 100.0

## Held direction from the first pad (D-pad, else left stick), when the pad is the device.
func pad_direction() -> Vector2i:
	if not gamepad():
		return Vector2i.ZERO
	for pad in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT):
			return Vector2i.LEFT
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT):
			return Vector2i.RIGHT
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP):
			return Vector2i.UP
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN):
			return Vector2i.DOWN
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if stick.length() >= deadzone():
			if absf(stick.x) > absf(stick.y):
				return Vector2i.RIGHT if stick.x > 0.0 else Vector2i.LEFT
			return Vector2i.DOWN if stick.y > 0.0 else Vector2i.UP
	return Vector2i.ZERO

## Match action of a pad button press ("" when none or the pad is not the device).
func pad_action(event: InputEvent) -> String:
	if not gamepad() or not (event is InputEventJoypadButton) or not event.pressed:
		return ""
	return str(PAD_ACTIONS.get((event as InputEventJoypadButton).button_index, ""))

## Gameplay keys are ignored while the pad is the chosen device (Esc always works).
func keyboard() -> bool:
	return not gamepad()

## Key / button shown on HUD buttons ("" when hints are off).
func hint(action: String) -> String:
	if not on("controls", "show_hints"):
		return ""
	return str(HINTS.get(action, ["", ""])[1 if gamepad() else 0])

## Tự động nhận tay cầm: plugging a pad in selects it, unplugging the last one
## goes back to the keyboard.
func _on_joy_changed(_device: int, connected: bool) -> void:
	if not on("controls", "auto_detect"):
		return
	var wanted := "gamepad" if connected or not Input.get_connected_joypads().is_empty() else "keyboard"
	if str(get_value("controls", "device")) != wanted:
		var next := draft()
		next.controls.device = wanted
		save(next)
