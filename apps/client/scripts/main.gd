extends Node2D
## All pixel geometry is authored here. Positions and results come from the server.

const Network = preload("res://scripts/network.gd")
const CELL := 40
const ORIGIN := Vector2(28, 118)
const COLORS := [
	Color("63e6be"), Color("ffbc72"), Color("a995ff"), Color("ff789d"),
	Color("77ccff"), Color("ffe27c"), Color("e0aaff"), Color("c3ed8b")
]

var net = Network.new()
var snapshot: Dictionary = {}
var status_label: Label
var phase_label: Label
var roster: Label
var api_input := LineEdit.new()
var arena_input := LineEdit.new()
var username_input := LineEdit.new()
var password_input := LineEdit.new()
var join_button := Button.new()
var ready_button := Button.new()
var move_timer := 0.0


func _ready() -> void:
	add_child(net)
	net.snapshot_received.connect(_on_snapshot)
	net.status_changed.connect(func(message: String): status_label.text = message)
	_setup_inputs()
	_build_ui()


func _setup_inputs() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"place_bomb": [KEY_SPACE], "ready_match": [KEY_R]
	}
	for action in bindings:
		InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _label(text: String, position_value: Vector2, size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.add_theme_font_size_override("font_size", size)
	add_child(label)
	return label


func _field(field: LineEdit, hint: String, value: String, y: float) -> void:
	field.position = Vector2(666, y)
	field.size = Vector2(300, 36)
	field.placeholder_text = hint
	field.text = value
	add_child(field)


func _build_ui() -> void:
	_label("SUNI / BOMB ARENA", Vector2(28, 24), 32)
	_label("NEON GARDEN   /   01", Vector2(30, 76), 16)
	_label("PLAY TOGETHER", Vector2(666, 36), 22)
	_field(api_input, "API URL", _env("SUNI_API_URL", "http://192.168.1.98:8000"), 88)
	_field(arena_input, "Arena URL", _env("SUNI_ARENA_URL", "http://192.168.1.98:2567"), 132)
	_field(username_input, "Username (empty = guest)", "", 176)
	_field(password_input, "Password", "", 220)
	password_input.secret = true
	join_button.text = "Join arena"
	join_button.position = Vector2(666, 266)
	join_button.size = Vector2(300, 42)
	join_button.pressed.connect(_join)
	add_child(join_button)
	ready_button.text = "Ready [R]"
	ready_button.position = Vector2(666, 318)
	ready_button.size = Vector2(300, 42)
	ready_button.pressed.connect(func(): net.send_action("ready"))
	add_child(ready_button)
	phase_label = _label("WAITING FOR CONNECTION", Vector2(666, 386), 18)
	roster = _label("Up to 8 pilots\nAt least 2 to start", Vector2(666, 430), 16)
	roster.add_theme_constant_override("line_spacing", 0)
	roster.size = Vector2(300, 170)
	roster.clip_text = true
	status_label = _label("Choose endpoints, then join an arena.", Vector2(28, 650), 16)
	status_label.size.x = 940
	status_label.clip_text = true
	_label("WASD / arrows: move     SPACE: bomb     R: ready", Vector2(28, 681), 16)
	var credits := AcceptDialog.new()
	credits.title = "Credits & licenses"
	credits.min_size = Vector2i(700, 480)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(660, 420)
	text.text = "Suni Bomb Arena / Original code and pixel geometry\n"
	text.text += "Copyright (c) 2026 Suni Bomb Arena contributors / MIT\n\n"
	text.text += Engine.get_license_text() + "\n\n"
	text.text += FileAccess.get_file_as_string("res://licenses/GODOT_COPYRIGHT.txt")
	credits.add_child(text)
	add_child(credits)
	var credits_button := Button.new()
	credits_button.text = "Credits & licenses"
	credits_button.position = Vector2(666, 608)
	credits_button.size = Vector2(300, 30)
	credits_button.pressed.connect(func(): credits.popup_centered())
	add_child(credits_button)


func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return fallback if value.is_empty() else value


func _join() -> void:
	get_viewport().gui_release_focus()
	snapshot = {}
	net.join_game(api_input.text, arena_input.text, username_input.text, password_input.text)
	password_input.clear()


func _on_snapshot(value: Dictionary) -> void:
	snapshot = value
	var seconds := maxi(0, int(ceil((value.deadline - value.now) / 1000.0)))
	phase_label.text = "%s  /  %ds" % [str(value.phase).to_upper(), seconds]
	if value.phase == "waiting":
		phase_label.text = "LOBBY / ALL PILOTS READY"
	elif value.phase == "finished":
		var winner_name := "DRAW" if value.winner == null else "WINNER LEFT"
		for player in value.players:
			if player.id == value.winner:
				winner_name = player.name + " WINS"
		phase_label.text = winner_name + "\nNew round in %ds" % seconds
	roster.text = ""
	for player in value.players:
		var marker := "YOU " if player.id == net.session_id else ""
		var state := "READY" if player.ready else "WAIT"
		if value.phase == "playing":
			state = "ALIVE" if player.alive else "OUT"
		roster.text += "%s%s / %s\n" % [marker, player.name, state]
	queue_redraw()


func _process(delta: float) -> void:
	join_button.disabled = net.busy or net.connected
	ready_button.disabled = not net.connected or snapshot.get("phase") != "waiting"
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or not net.connected:
		return
	if Input.is_action_just_pressed("ready_match"):
		net.send_action("ready")
	if snapshot.get("phase") != "playing":
		return
	if Input.is_action_just_pressed("place_bomb"):
		net.send_action("bomb")
	move_timer -= delta
	if move_timer <= 0:
		move_timer = 0.05
		for direction in ["up", "down", "left", "right"]:
			if Input.is_action_pressed("move_" + direction):
				net.send_action(direction)
				break


func _draw() -> void:
	draw_rect(Rect2(ORIGIN - Vector2(4, 4), Vector2(608, 528)), Color("25424b"))
	for y in range(13):
		for x in range(15):
			var tile := 1 if x == 0 or y == 0 or x == 14 or y == 12 else 0
			if snapshot.has("grid"):
				tile = int(snapshot.grid[y][x])
			_draw_tile(ORIGIN + Vector2(x, y) * CELL, tile, (x + y) % 2 == 0)
	for flame in snapshot.get("flames", []):
		var pos := ORIGIN + Vector2(flame.x, flame.y) * CELL
		draw_rect(Rect2(pos + Vector2(2, 8), Vector2(36, 24)), Color("ff8f55"))
		draw_rect(Rect2(pos + Vector2(8, 2), Vector2(24, 36)), Color("ffd879"))
		draw_rect(Rect2(pos + Vector2(13, 13), Vector2(14, 14)), Color("fff1bd"))
	for bomb in snapshot.get("bombs", []):
		var pos := ORIGIN + Vector2(bomb.x, bomb.y) * CELL
		draw_rect(Rect2(pos + Vector2(8, 10), Vector2(24, 24)), Color("0b1728"))
		draw_rect(Rect2(pos + Vector2(12, 14), Vector2(16, 16)), Color("f07894"))
		var remaining := float(bomb.explodeAt - snapshot.now) / 2000.0
		draw_rect(Rect2(pos + Vector2(8, 5), Vector2(24 * remaining, 3)), Color("ffe27c"))
	for player in snapshot.get("players", []):
		_draw_player(player)


func _draw_tile(pos: Vector2, tile: int, checker: bool) -> void:
	draw_rect(Rect2(pos, Vector2(CELL, CELL)), Color("172d37") if checker else Color("1b333c"))
	if tile == 1:
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(36, 36)), Color("385467"))
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(36, 5)), Color("587a8b"))
		draw_rect(Rect2(pos + Vector2(9, 14), Vector2(22, 4)), Color("2a4256"))
	elif tile == 2:
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(32, 32)), Color("aa674c"))
		draw_rect(Rect2(pos + Vector2(7, 7), Vector2(26, 5)), Color("e5a66b"))
		draw_rect(Rect2(pos + Vector2(17, 10), Vector2(6, 23)), Color("774c43"))


func _draw_player(player: Dictionary) -> void:
	var pos := ORIGIN + Vector2(player.x, player.y) * CELL
	var color: Color = COLORS[int(player.slot)]
	if not player.alive:
		draw_rect(Rect2(pos + Vector2(15, 25), Vector2(10, 6)), color.darkened(0.6))
		return
	if player.id == net.session_id:
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(36, 36)), color, false, 2)
	draw_rect(Rect2(pos + Vector2(8, 32), Vector2(26, 5)), Color("0b1728"))
	draw_rect(Rect2(pos + Vector2(10, 10), Vector2(22, 21)), color)
	draw_rect(Rect2(pos + Vector2(14, 5), Vector2(14, 6)), color.lightened(0.2))
	draw_rect(Rect2(pos + Vector2(13, 15), Vector2(17, 8)), Color("163349"))
	draw_rect(Rect2(pos + Vector2(23, 17), Vector2(4, 3)), Color("e7ffff"))
	draw_rect(Rect2(pos + Vector2(10, 31), Vector2(7, 5)), color.darkened(0.3))
	draw_rect(Rect2(pos + Vector2(25, 31), Vector2(7, 5)), color.darkened(0.3))
