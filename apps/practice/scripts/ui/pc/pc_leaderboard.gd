extends "res://scripts/ui/pc/pc_kit.gd"
## PC leaderboard (docs/LEADERBOARD.md): three boards — Kinh nghiệm, Điểm skin,
## Tiền — from GET /v1/leaderboards. Each tab shows only its own board: the top
## 10 and the player's own rank on it. The server computes every value.
signal navigate(destination: String)

const BOARDS := ["exp", "skin", "gold"]
const LOOK := {
	"exp": {"title": "Kinh nghiệm", "short": "EXP", "kind": "sky", "fill": Color("4fb7f5"), "unit": "EXP"},
	"skin": {"title": "Điểm skin", "short": "SKIN", "kind": "coral", "fill": Color("ff7aa8"), "unit": "Điểm skin"},
	"gold": {"title": "Tiền", "short": "VÀNG", "kind": "sun", "fill": Color("ffb432"), "unit": "Vàng"},
}
const MEDALS := [Color("ffc93c"), Color("b9c7dc"), Color("e59a5c")]
const ROW_TINT := [Color("fff1c4"), Color("dcefff"), Color("ffe3cc")]
const TOP := 10
const REFRESH_SECONDS := 60.0

var current := "exp"
var data: Dictionary = {}
var state := "idle"  # idle | loading | ok | error | signed_out
var error_text := ""
var busy := false
var refresh_clock := 0.0
var tab_buttons: Dictionary = {}
var table: VBoxContainer
var value_head: Label
var tab_labels: Dictionary = {}
var me_line: HBoxContainer
var status_label: Label

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcLeaderboard"
	setup()
	var root := page(canvas, 12)
	var tabs := row(14, root)
	var group := ButtonGroup.new()
	for board in BOARDS:
		var key: String = board
		var button := tab("", func(): set_board(key), group)
		button.name = "Tab_" + key
		button.custom_minimum_size = Vector2(300, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 22)
		var fill: Color = LOOK[key].fill
		# Every tab wears its board's colour; the open one is solid.
		var pale := fill.lerp(Color.WHITE, 0.72)
		button.add_theme_stylebox_override("normal", lipped(pale, fill, 6))
		button.add_theme_stylebox_override("hover", lipped(pale.lightened(0.3), fill, 6))
		for font_state in ["font_color", "font_hover_color", "font_focus_color"]:
			button.add_theme_color_override(font_state, fill.darkened(0.35))
		button.add_theme_stylebox_override("pressed", lipped(fill, fill.darkened(0.25), 3))
		button.add_theme_stylebox_override("hover_pressed", lipped(fill.lightened(0.08), fill.darkened(0.25), 3))
		button.button_pressed = key == current
		tabs.add_child(button)
		tab_buttons[key] = button
		# Icon + name centred on the tab (the board's unit, as in its rows).
		var face_line := HBoxContainer.new()
		face_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face_line.alignment = BoxContainer.ALIGNMENT_CENTER
		face_line.add_theme_constant_override("separation", 10)
		face_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face_line)
		unit_icon(key, face_line, 30)
		var label := title_text(LOOK[key].title, 24, Color.WHITE, face_line)
		tab_labels[key] = label
	var body := row(16, root)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Main table.
	var main := card(GHOST, Color("cfe3f7"), 22, 2, 12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var main_col := column(6, main)
	var head := card(Color("d6ecff"), Color.TRANSPARENT, 14, 0, 8)
	main_col.add_child(head)
	var head_line := row(10, head)
	var rank_head := text("Hạng", 17, MUTED, head_line)
	rank_head.custom_minimum_size = Vector2(90, 0)
	rank_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stretch(text("Tên người chơi", 17, MUTED, head_line)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_head = text("", 17, MUTED, head_line)
	value_head.custom_minimum_size = Vector2(260, 0)
	value_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_col.add_child(scroll)
	table = column(4)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(table)
	# Footer: your rank on this board | ĐÃ HIỂU (centred) | the data note.
	var foot := row(16, root)
	me_line = row(10, foot)
	me_line.name = "MyRank"
	me_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var done := candy("ĐÃ HIỂU", func(): navigate.emit("home"), "sun", 26)
	done.name = "Done"
	done.custom_minimum_size = Vector2(300, 60)
	foot.add_child(done)
	status_label = stretch(text("", 14, MUTED, foot))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_modal()
	when_shown(load_boards)
	tint_tabs()
	render()

func set_board(key: String) -> void:
	current = key
	for k in tab_buttons:
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	tint_tabs()
	render()

## The open tab's name is white on its colour; the others take their colour.
func tint_tabs() -> void:
	for k in tab_labels:
		var label: Label = tab_labels[k]
		var fill: Color = LOOK[k].fill
		var open: bool = k == current
		label.add_theme_color_override("font_color", Color.WHITE if open else fill.darkened(0.3))
		label.add_theme_color_override("font_outline_color", fill.darkened(0.35) if open else Color.WHITE)

func load_boards() -> void:
	if busy:
		return
	if not AuthSession.has_session():
		state = "signed_out"
		data = {}
		render()
		return
	busy = true
	if state != "ok":
		state = "loading"
		render()
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/leaderboards?limit=%d" % TOP)
	busy = false
	refresh_clock = 0.0
	if reply.status == 200 and reply.data is Dictionary:
		apply(reply.data)
	else:
		state = "error"
		error_text = str(reply.error)
		render()

func apply(payload: Dictionary) -> void:
	data = payload
	state = "ok"
	render()

func _process(delta: float) -> void:
	super(delta)
	if state == "ok" and is_visible_in_tree():
		refresh_clock += delta
		if refresh_clock >= REFRESH_SECONDS:
			load_boards()

func clear(node: Control) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func render() -> void:
	if table == null:
		return
	clear(table)
	clear(me_line)
	value_head.text = LOOK[current].title
	match state:
		"signed_out":
			message("Đăng nhập tài khoản để xem bảng xếp hạng. Chế độ khách chỉ chơi với bot.")
		"loading", "idle":
			var spin := Spinner.new(56)
			spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			table.add_child(spin)
			message("Đang tải bảng xếp hạng…")
		"error":
			message("Không tải được bảng xếp hạng: %s" % error_text)
	status_label.text = ""
	if state != "ok":
		return
	var rows: Array = data.get("boards", {}).get(current, [])
	if rows.is_empty():
		message("Chưa có ai trên bảng này. Chơi trận online để ghi tên đầu tiên!")
	for entry in rows:
		table.add_child(main_row(entry, current))
	my_rank()
	status_label.text = "Cập nhật mỗi phút · chỉ tính trận máy chủ đã xác nhận"

func message(value: String) -> void:
	var note := text(value, 18, MUTED, table)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func value_text(board: String, value: int) -> String:
	return grouped(value)

## Rank badge: a medal for the top 3, a grey pill after.
func rank_badge(rank: int, side: float) -> Control:
	var holder := PanelContainer.new()
	var fill: Color = MEDALS[rank - 1] if rank <= 3 else Color("e8edf5")
	var style := box(fill, fill.darkened(0.25) if rank <= 3 else Color.TRANSPARENT, int(side / 2), 3 if rank <= 3 else 0, 0)
	holder.add_theme_stylebox_override("panel", style)
	holder.custom_minimum_size = Vector2(side, side)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := text(str(rank), int(side * 0.48), Color.WHITE if rank <= 3 else MUTED, holder)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if rank <= 3:
		label.add_theme_color_override("font_outline_color", fill.darkened(0.45))
		label.add_theme_constant_override("outline_size", 6)
	return holder

func face(hero: String, side: float) -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", box(Color("eaf5ff"), Color("9fd7ff"), int(side * 0.3), 2, 0))
	holder.custom_minimum_size = Vector2(side, side)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	var art := picture("res://assets/characters/portraits/%s.png" % hero, Vector2(side, side))
	holder.add_child(art)
	return holder

func main_row(entry: Dictionary, board: String) -> Control:
	var rank := int(entry.get("rank", 0))
	var fill: Color = ROW_TINT[rank - 1] if rank >= 1 and rank <= 3 else Color("f6f8fc")
	var line_card := card(fill, Color.TRANSPARENT, 12, 0, 2)
	line_card.name = "Row_%d" % rank
	var line := row(10, line_card)
	var badge_slot := Control.new()
	badge_slot.custom_minimum_size = Vector2(90, 38)
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(badge_slot)
	var badge := rank_badge(rank, 38.0 if rank <= 3 else 30.0)
	badge_slot.add_child(badge)
	badge.position = (Vector2(90, 38) - badge.custom_minimum_size) * 0.5
	line.add_child(face(str(entry.get("hero", "bombo")), 36))
	stretch(text(str(entry.get("name", "")), 20, INK if rank > 3 else NAVY, line))
	var amount := row(6, line)
	amount.custom_minimum_size = Vector2(260, 0)
	amount.alignment = BoxContainer.ALIGNMENT_END
	unit_icon(board, amount, 24)
	var value := title_text(value_text(board, int(entry.get("value", 0))), 21, NAVY, amount)
	value.remove_theme_constant_override("outline_size")
	return line_card

## The board's unit: EXP pill, star for skin points, coin for gold.
func unit_icon(board: String, parent: Control, side: float) -> void:
	if board == "exp":
		pill("EXP", Color("ff9a3c"), Color.WHITE, int(side * 0.5), parent)
	else:
		parent.add_child(Glyph.new("star" if board == "skin" else "coin", Color("ff6fa0") if board == "skin" else Color("ffb432"), side))

func my_rank() -> void:
	var me: Dictionary = data.get("me", {})
	var mine: Dictionary = me.get(current, {})
	var holder := card(Color("2d4a7a"), Color("9fd7ff"), 14, 2, 4)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me_line.add_child(holder)
	var line := row(10, holder)
	var rank = mine.get("rank")
	var label := "Bạn: chưa có hạng" if rank == null else "Bạn: hạng %d" % int(rank)
	if bool(me.get("hidden", false)):
		label = "Bạn đang tạm ẩn khỏi bảng xếp hạng"
	line.add_child(face(str(me.get("hero", "bombo")), 34))
	stretch(text("%s · %s" % [str(me.get("name", "")), label], 16, Color.WHITE, line))
	unit_icon(current, line, 20)
	text(value_text(current, int(mine.get("value", 0))), 18, SUN, line)
