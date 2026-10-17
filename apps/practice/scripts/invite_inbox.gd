extends CanvasLayer
## Room invites from friends (GET /v1/invites, docs/INVITES.md). Polls while signed
## in and not already in an online room, and shows one card at a time in the top
## right of any menu screen (never during a running practice match). "VÀO" accepts
## and joins the room through OnlineArena; "Từ chối" declines; cards expire.

signal invite_shown(invite: Dictionary)

const POLL_SECONDS := 4.0
const INK := Color("2b3a67")

var current: Dictionary = {}
var handled: Dictionary = {}  # invite id -> true (answered or expired here)
var queue: Array = []
var clock := 0.0
var busy := false
var clock_offset := 0.0  # server clock - local clock (seconds)
var card: PanelContainer
var title: Label
var detail: Label
var timer: Label
var accept_button: Button
var decline_button: Button

func _ready() -> void:
	layer = 60
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Nunito", "Segoe UI", "Noto Sans", "Arial"])
	font.font_weight = 800
	var theme := Theme.new()
	theme.default_font = font
	card = PanelContainer.new()
	card.name = "InviteCard"
	card.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff6e2")
	style.border_color = Color("ffc93c")
	style.set_border_width_all(4)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0.02, 0.12, 0.3, 0.4)
	style.shadow_size = 12
	card.add_theme_stylebox_override("panel", style)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -470
	card.offset_right = -24
	card.offset_top = 150
	card.hide()
	add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	card.add_child(stack)
	title = label(stack, 22, INK)
	detail = label(stack, 17, Color("6b7a9c"))
	timer = label(stack, 14, Color("d9890b"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	stack.add_child(line)
	accept_button = button(line, "VÀO", Color("44cf9e"), accept)
	accept_button.name = "AcceptInvite"
	decline_button = button(line, "Từ chối", Color("b3c1d6"), decline)
	decline_button.name = "DeclineInvite"

func label(parent: Control, size: int, color: Color) -> Label:
	var node := Label.new()
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(410, 0)
	parent.add_child(node)
	return node

func button(parent: Control, value: String, fill: Color, action: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size = Vector2(190, 50)
	node.add_theme_font_size_override("font_size", 19)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.lightened(0.1) if state == "hover" else (fill.darkened(0.1) if state == "pressed" else fill)
		style.set_corner_radius_all(14)
		node.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(state, Color.WHITE)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

static func parse_time(value: Variant) -> float:
	var text_value := str(value)
	if text_value.length() < 19:
		return 0.0
	var zone := text_value.right(6)
	var shift := 0.0
	if zone.length() == 6 and (zone[0] == "+" or zone[0] == "-") and zone[3] == ":":
		shift = (int(zone.substr(1, 2)) * 3600 + int(zone.substr(4, 2)) * 60) * (1 if zone[0] == "+" else -1)
	return Time.get_unix_time_from_datetime_string(text_value.left(19)) - shift

func game() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.has_method("show_pc_screen") else null

## No card while a practice round runs or the player already sits in an online room.
func can_show() -> bool:
	if not AuthSession.has_session() or OnlineArena.connected or OnlineArena.busy:
		return false
	var g := game()
	return g != null and str(g.game_state) != "playing" and str(g.game_state) != "paused"

func _process(delta: float) -> void:
	if not current.is_empty():
		var left := parse_time(current.get("expires_at", "")) - (Time.get_unix_time_from_system() + clock_offset)
		timer.text = "Hết hạn sau %d giây" % maxi(0, int(left))
		if left <= 0.0 or not can_show():
			hide_card(left <= 0.0)
	clock -= delta
	if clock > 0.0:
		return
	clock = POLL_SECONDS
	if can_show() and not busy:
		poll()

func poll() -> void:
	busy = true
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/invites")
	busy = false
	if reply.status != 200 or not reply.data is Dictionary:
		return
	clock_offset = parse_time(reply.data.get("server_now", "")) - Time.get_unix_time_from_system()
	queue = reply.data.get("invites", []).filter(func(i): return not handled.has(str(i.id)))
	if current.is_empty() and not queue.is_empty() and can_show():
		show_invite(queue.pop_front())

func show_invite(invite: Dictionary) -> void:
	current = invite
	var map := MapCatalog.find(str(invite.get("map_id", "")))
	var map_name := str(map.get("name", invite.get("map_name", ""))).capitalize()
	title.text = "%s mời bạn vào phòng" % str(invite["from"].name)
	detail.text = "Phòng %03d · %s · %d/%d người" % [int(invite.get("number", 0)), map_name, int(invite.get("players", 0)), int(invite.get("max_players", 8))]
	accept_button.disabled = false
	decline_button.disabled = false
	card.show()
	invite_shown.emit(invite)

func hide_card(mark := true) -> void:
	if mark and not current.is_empty():
		handled[str(current.id)] = true
	current = {}
	card.hide()
	if not queue.is_empty() and can_show():
		show_invite(queue.pop_front())

func decline() -> void:
	if current.is_empty():
		return
	AuthSession.api(HTTPClient.METHOD_POST, "/v1/invites/%s/decline" % str(current.id))
	hide_card()

func accept() -> void:
	if current.is_empty():
		return
	accept_button.disabled = true
	decline_button.disabled = true
	var invite := current
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/invites/%s/accept" % str(invite.id))
	if reply.status != 200:
		detail.text = "Phòng đã đầy, đã bắt đầu hoặc lời mời hết hạn."
		handled[str(invite.id)] = true
		await get_tree().create_timer(2.0).timeout
		if current == invite:
			hide_card()
		return
	var g := game()
	var hero: String = g.HEROES[g.selected_hero] if g else "bombo"
	hide_card()
	if await OnlineArena.join_room(str(invite.room_id), hero):
		if game():
			game().show_pc_screen("online")
	elif game() and game().pc_screens.has("lobby"):
		game().pc_screens["lobby"].notice(OnlineArena.last_error, "LỜI MỜI", "people")
