extends Control
## In-match chat for the PC battle screens (docs/VOICE.md): a "Trò chuyện" pill
## with an unread badge that opens a panel with tabs Tất cả / Đội / Hệ thống,
## the messages (portrait, name, time) and an input with emoji and send.
## View only: the owner adds lines with add_message() and sends what on_send
## receives (room chat API online, local + bots offline). Enter opens the input,
## Enter sends, Esc closes the input so the keys go back to the match.

const TABS := [["all", "Tất cả"], ["team", "Đội"], ["system", "Hệ thống"]]
const EMOJI := ["👋", "💪", "😀", "😂", "😎", "👍", "🔥", "💣", "🎉", "😢", "😮", "❤️"]
const MAX_LINES := 80
const WIDTH := 430.0
const HEIGHT := 320.0

var kit: Control
var on_send: Callable
## Free-for-all has no teammates: the Đội tab explains instead of listing.
var has_team := false
var team_note := "Đấu tự do không chia đội."
var messages: Array[Dictionary] = []
var current_tab := "all"
var unread := 0
var pill: Button
var badge: Label
var panel: PanelContainer
var list: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var emoji_box: PanelContainer
var tab_buttons: Dictionary = {}

func _init(owner_kit: Control, send: Callable) -> void:
	kit = owner_kit
	on_send = send
	name = "MatchChat"
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	build_pill()
	build_panel()
	set_open(false)

func build_pill() -> void:
	pill = kit.candy("Trò chuyện", func(): set_open(true), "sky", 18)
	pill.name = "ChatPill"
	pill.focus_mode = Control.FOCUS_NONE
	pill.tooltip_text = "Mở trò chuyện (Enter)"
	pill.size = Vector2(170, 44)
	add_child(pill)
	badge = Label.new()
	badge.name = "Unread"
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color("b3122f"))
	badge.add_theme_constant_override("outline_size", 4)
	var style := StyleBoxTexture.new()
	style.texture = load(kit.KIT + "icon_dot_red.png")
	style.content_margin_left = 6
	style.content_margin_right = 6
	badge.add_theme_stylebox_override("normal", style)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(30, 30)
	badge.position = Vector2(150, -12)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(badge)

func build_panel() -> void:
	panel = kit.card(Color("1567ae", 0.94), Color("74d3f0"), 20, 4, 10)
	panel.name = "ChatPanel"
	panel.size = Vector2(WIDTH, HEIGHT)
	add_child(panel)
	var stack: VBoxContainer = kit.column(8, panel)
	var head: HBoxContainer = kit.row(6, stack)
	var group := ButtonGroup.new()
	for spec in TABS:
		var key: String = spec[0]
		var button: Button = kit.tab(str(spec[1]), func(): set_tab(key), group)
		button.name = "Tab_" + key
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(108, 40)
		button.button_pressed = key == current_tab
		head.add_child(button)
		tab_buttons[key] = button
	kit.spacer(head)
	var hide_button: Button = kit.round_icon("down", func(): set_open(false), "ghost", 38)
	hide_button.name = "Minimize"
	hide_button.tooltip_text = "Thu gọn"
	hide_button.focus_mode = Control.FOCUS_NONE
	head.add_child(hide_button)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	list = kit.column(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var line: HBoxContainer = kit.row(6, stack)
	input = LineEdit.new()
	input.name = "ChatInput"
	input.placeholder_text = "Nhập tin nhắn… (Enter để gửi)"
	input.max_length = 200
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 15)
	input.add_theme_color_override("font_color", kit.INK)
	input.add_theme_color_override("font_placeholder_color", kit.MUTED)
	input.add_theme_stylebox_override("normal", kit.box(Color("f3f9ff"), Color("cfe6fb"), 14, 2, 8))
	input.add_theme_stylebox_override("focus", kit.box(Color.WHITE, kit.SKY, 14, 2, 8))
	input.text_submitted.connect(func(_value): submit())
	line.add_child(input)
	var emoji: Button = kit.candy("😀", toggle_emoji, "ghost", 18)
	emoji.name = "Emoji"
	emoji.focus_mode = Control.FOCUS_NONE
	emoji.custom_minimum_size = Vector2(48, 44)
	line.add_child(emoji)
	var send: Button = kit.round_icon("send", submit, "sky", 44)
	send.name = "Send"
	send.focus_mode = Control.FOCUS_NONE
	line.add_child(send)
	emoji_box = kit.card(Color.WHITE, Color("cfe6fb"), 14, 2, 6)
	emoji_box.name = "EmojiPicker"
	emoji_box.hide()
	add_child(emoji_box)
	var grid := GridContainer.new()
	grid.columns = 6
	emoji_box.add_child(grid)
	for e in EMOJI:
		var pick := Button.new()
		pick.text = e
		pick.flat = true
		pick.focus_mode = Control.FOCUS_NONE
		pick.add_theme_font_size_override("font_size", 22)
		pick.pressed.connect(func(): input.insert_text_at_caret(e); emoji_box.hide(); input.grab_focus())
		grid.add_child(pick)

## Bottom-left corner of the owner's free space (canvas units).
func place(at: Vector2) -> void:
	position = at
	pill.position = Vector2(0, -pill.size.y)
	panel.position = Vector2(0, -HEIGHT)
	emoji_box.position = Vector2(WIDTH - 300, -HEIGHT - 118)
	emoji_box.size = Vector2(300, 110)

func is_open() -> bool:
	return panel.visible

func set_open(value: bool) -> void:
	panel.visible = value
	pill.visible = not value
	emoji_box.hide()
	if value:
		unread = 0
		render()
	elif typing():
		input.release_focus()
	update_badge()

func set_tab(key: String) -> void:
	current_tab = key
	for k in tab_buttons:
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	render()

func typing() -> bool:
	return is_instance_valid(input) and input.has_focus()

func toggle_emoji() -> void:
	emoji_box.visible = not emoji_box.visible

func submit() -> void:
	var value := input.text.strip_edges()
	input.clear()
	input.release_focus()
	emoji_box.hide()
	if value.is_empty():
		return
	on_send.call(value)

## kind: "player" or "system". hero: portrait id for player lines.
func add_message(kind: String, who: String, body: String, hero := "", team := false, mine := false) -> void:
	messages.append({"kind": kind, "name": who, "text": body, "hero": hero, "team": team, "mine": mine, "time": Time.get_time_string_from_system().left(5)})
	while messages.size() > MAX_LINES:
		messages.pop_front()
	if not is_open() and not mine:
		unread += 1
		update_badge()
	elif is_open():
		render()

func clear_messages() -> void:
	messages.clear()
	unread = 0
	update_badge()
	render()

func update_badge() -> void:
	badge.text = str(unread) if unread < 100 else "99+"
	badge.visible = unread > 0 and pill.visible

func shown() -> Array[Dictionary]:
	match current_tab:
		"team":
			return messages.filter(func(m): return m.kind == "player" and bool(m.team))
		"system":
			return messages.filter(func(m): return m.kind == "system")
	return messages

func render() -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if current_tab == "team" and not has_team:
		note(team_note)
		return
	var rows := shown()
	if rows.is_empty():
		note("Chưa có tin nhắn.")
	for m in rows:
		list.add_child(message_row(m))
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func note(value: String) -> void:
	var label: Label = kit.text(value, 15, Color("d6e8ff"), list)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func message_row(m: Dictionary) -> Control:
	var line: HBoxContainer = kit.row(8)
	if m.kind == "system":
		line.add_child(kit.sticker("cat_system", 34))
	else:
		var face: PanelContainer = kit.card(Color("ffe9b0"), Color.WHITE, 18, 2, 0)
		face.custom_minimum_size = Vector2(38, 38)
		face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		face.add_child(kit.picture("", Vector2(36, 36)))
		(face.get_child(0) as TextureRect).texture = kit.HeroPortrait.texture(str(m.hero)) if str(m.hero) != "" else null
		line.add_child(face)
	var words: VBoxContainer = kit.column(0, line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = kit.row(8, words)
	var tint: Color = kit.SUN if m.kind == "system" else (Color("ffd23c") if bool(m.mine) else Color("9fe3ff"))
	kit.text("Hệ thống" if m.kind == "system" else str(m.name), 15, tint, top)
	kit.text(str(m.time), 12, Color("bcd6f0"), top)
	var body: Label = kit.text(str(m.text), 15, Color.WHITE, words)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 90, 0)
	return line

## Enter opens the chat and focuses the input; Esc gives the keys back.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if typing() and key == KEY_ESCAPE:
		input.release_focus()
		emoji_box.hide()
		get_viewport().set_input_as_handled()
	elif not typing() and key in [KEY_ENTER, KEY_KP_ENTER]:
		set_open(true)
		input.grab_focus()
		get_viewport().set_input_as_handled()
