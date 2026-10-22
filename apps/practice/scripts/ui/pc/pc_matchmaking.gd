extends "res://scripts/ui/pc/pc_kit.gd"
## Quick match: seats the player, then three local bots one by one, then opens
## the room. Nothing is sent to a server; the copy says bots, not players.
const JOIN_STEP := 0.7
const HOLD := 0.6

var game: Node
var clock := 0.0
var timer_label: Label
var found_label: Label
var subtitle: Label
var seats: Array[TextureRect] = []
var seat_frames: Array[PanelContainer] = []
var heroes: Array = []

func _init() -> void:
	super("sunset")

func _ready() -> void:
	name = "PcMatchmaking"
	setup()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	var sheet := card(CREAM, Color.WHITE, 30, 5, 22)
	sheet.custom_minimum_size = Vector2(580, 0)
	center.add_child(sheet)
	var stack := column(16, sheet)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", lipped(SKY, Color("2b88cf"), 6))
	stack.add_child(head)
	var head_stack := column(0, head)
	var title := title_text("TÌM TRẬN NHANH", 30, Color.WHITE, head_stack)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle = text("", 14, Color.WHITE, head_stack)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var status_line := row(14, stack)
	status_line.alignment = BoxContainer.ALIGNMENT_CENTER
	status_line.add_child(Spinner.new(56))
	var words := column(0, status_line)
	text("Đang xếp bot vào trận…", 20, INK, words)
	timer_label = text("00:00", 26, Color("2b88cf"), words)
	var seat_row := row(16, stack)
	seat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 4:
		var frame := card(GLASS, Color("cfe6fb"), 46, 3, 4)
		frame.custom_minimum_size = Vector2(92, 92)
		seat_row.add_child(frame)
		var face := picture("", Vector2(82, 82))
		frame.add_child(face)
		seats.append(face)
		seat_frames.append(frame)
	found_label = text("", 16, INK, stack)
	found_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tip := text("Mẹo: đặt bom cạnh thùng rồi lùi vào ô an toàn trước khi bom nổ.", 13, MUTED, stack)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cancel := sized(candy("HỦY TÌM", cancel_search, "coral", 20), Vector2(220, 56))
	cancel.name = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(cancel)
	build_modal()
	visibility_changed.connect(_on_visibility)

func _on_visibility() -> void:
	ScreenFill.set_fill(get_tree(), is_visible_in_tree())
	if is_visible_in_tree():
		clock = 0.0
		heroes = [game.HEROES[game.selected_hero]] + game.bot_heroes()
		var map_name := str(MapCatalog.level_at(game.selected_level).get("name", ""))
		subtitle.text = "1 người + 3 bot · %s" % map_name.capitalize()
		refresh()

func seated() -> int:
	return mini(4, 1 + int(clock / JOIN_STEP))

func refresh() -> void:
	var count := seated()
	for i in seats.size():
		var filled := i < count
		seats[i].texture = HeroPortrait.texture(heroes[i]) if filled else null
		var frame := seat_frames[i].get_theme_stylebox("panel") as StyleBoxFlat
		frame.border_color = game.HERO_COLORS[game.HEROES.find(heroes[i])] if filled else Color("cfe6fb")
		frame.bg_color = Color.WHITE if filled else GLASS
	found_label.text = "Đã có %d/4 người chơi (bạn + %d bot)" % [count, count - 1]
	timer_label.text = "00:%02d" % int(clock)

func cancel_search() -> void:
	game.show_pc_screen("lobby")

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_search()

func _process(delta: float) -> void:
	super._process(delta)
	if not is_visible_in_tree():
		return
	var before := seated()
	clock += delta
	if seated() != before:
		game._sound("ui_select")
	refresh()
	if clock >= JOIN_STEP * 3 + HOLD:
		game.show_pc_screen("room")
