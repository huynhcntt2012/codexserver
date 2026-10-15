extends Control
## PC-only home for the practice game. Cards are real local bot matches (one per
## level file), not online rooms; social, chat and ranked show honest empty states.
const DESIGN := Vector2(1920, 1080)
const PAGE_SIZE := 6
const INK := Color("345581")
const SKY := Color("1569b3")
const LINE := Color("8fe3f3")
const TIER_COLORS := {"Dễ": Color("4fa8ef"), "Trung bình": Color("ffaa45"), "Khó": Color("f4738d")}
const FOLD := {
	"a": "àáạảãâầấậẩẫăằắặẳẵ", "e": "èéẹẻẽêềếệểễ", "i": "ìíịỉĩ", "o": "òóọỏõôồốộổỗơờớợởỡ",
	"u": "ùúụủũưừứựửữ", "y": "ỳýỵỷỹ", "d": "đ",
}
const ScreenFill := preload("res://scripts/ui/screen_fill.gd")

## Small vector icons so the lobby needs no unverified icon assets.
class Glyph extends Control:
	var kind := ""
	var tint := Color.WHITE
	var _o := Vector2.ZERO
	var _s := 1.0

	func _init(icon: String, color := Color.WHITE, side := 32.0) -> void:
		kind = icon
		tint = color
		custom_minimum_size = Vector2(side, side)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_kind(icon: String) -> void:
		kind = icon
		queue_redraw()

	func pt(x: float, y: float) -> Vector2:
		return _o + Vector2(x, y) * _s

	func poly(points: Array, color := tint) -> void:
		var out := PackedVector2Array()
		for p in points:
			out.append(pt(p[0], p[1]))
		draw_colored_polygon(out, color)

	func line(a: Array, b: Array, width := 0.12) -> void:
		draw_line(pt(a[0], a[1]), pt(b[0], b[1]), tint, width * _s, true)

	func _draw() -> void:
		_s = minf(size.x, size.y)
		_o = (size - Vector2(_s, _s)) / 2
		match kind:
			"home":
				poly([[0.5, 0.06], [0.96, 0.48], [0.04, 0.48]])
				draw_rect(Rect2(pt(0.17, 0.44), Vector2(0.66, 0.48) * _s), tint)
				draw_rect(Rect2(pt(0.41, 0.6), Vector2(0.18, 0.32) * _s), tint.darkened(0.4))
			"shop":
				draw_rect(Rect2(pt(0.14, 0.44), Vector2(0.72, 0.48) * _s), tint)
				poly([[0.06, 0.12], [0.94, 0.12], [1.0, 0.46], [0.0, 0.46]], tint.lightened(0.25))
				draw_rect(Rect2(pt(0.4, 0.6), Vector2(0.2, 0.32) * _s), tint.darkened(0.4))
			"lock":
				draw_arc(pt(0.5, 0.42), 0.22 * _s, PI, TAU, 18, tint, 0.11 * _s, true)
				line([0.28, 0.42], [0.28, 0.5], 0.11)
				line([0.72, 0.42], [0.72, 0.5], 0.11)
				draw_rect(Rect2(pt(0.16, 0.46), Vector2(0.68, 0.48) * _s), tint)
			"star":
				var points := []
				for i in 10:
					var r := 0.48 if i % 2 == 0 else 0.2
					var a := -PI / 2 + i * PI / 5
					points.append([0.5 + cos(a) * r, 0.53 + sin(a) * r])
				poly(points)
			"trophy":
				poly([[0.2, 0.08], [0.8, 0.08], [0.68, 0.52], [0.32, 0.52]])
				draw_arc(pt(0.2, 0.26), 0.12 * _s, PI / 2, PI * 1.5, 10, tint, 0.07 * _s)
				draw_arc(pt(0.8, 0.26), 0.12 * _s, -PI / 2, PI / 2, 10, tint, 0.07 * _s)
				draw_rect(Rect2(pt(0.44, 0.5), Vector2(0.12, 0.24) * _s), tint)
				draw_rect(Rect2(pt(0.26, 0.74), Vector2(0.48, 0.16) * _s), tint)
			"people":
				for c in [[0.68, 0.3, 0.75], [0.34, 0.34, 1.0]]:
					var color: Color = tint.darkened(0.15) if c[2] < 1.0 else tint
					draw_circle(pt(c[0], c[1]), 0.15 * _s, color)
					var body := []
					for i in 13:
						var a := PI + i * PI / 12
						body.append([c[0] + cos(a) * 0.27, 0.9 + sin(a) * 0.32])
					poly(body, color)
			"mail":
				draw_rect(Rect2(pt(0.08, 0.2), Vector2(0.84, 0.6) * _s), tint, false, 0.09 * _s)
				line([0.1, 0.24], [0.5, 0.55], 0.09)
				line([0.9, 0.24], [0.5, 0.55], 0.09)
			"gear":
				for i in 8:
					var a := i * PI / 4
					line([0.5 + cos(a) * 0.26, 0.5 + sin(a) * 0.26], [0.5 + cos(a) * 0.46, 0.5 + sin(a) * 0.46], 0.16)
				draw_arc(pt(0.5, 0.5), 0.25 * _s, 0, TAU, 32, tint, 0.15 * _s, true)
			"search":
				draw_arc(pt(0.42, 0.42), 0.28 * _s, 0, TAU, 32, tint, 0.11 * _s, true)
				line([0.63, 0.63], [0.92, 0.92], 0.14)
			"speaker", "mute":
				poly([[0.08, 0.36], [0.3, 0.36], [0.56, 0.12], [0.56, 0.88], [0.3, 0.64], [0.08, 0.64]])
				if kind == "speaker":
					draw_arc(pt(0.56, 0.5), 0.2 * _s, -0.9, 0.9, 12, tint, 0.08 * _s, true)
					draw_arc(pt(0.56, 0.5), 0.34 * _s, -0.9, 0.9, 12, tint, 0.08 * _s, true)
				else:
					line([0.68, 0.36], [0.94, 0.64], 0.09)
					line([0.94, 0.36], [0.68, 0.64], 0.09)
			"send":
				poly([[0.06, 0.12], [0.96, 0.5], [0.06, 0.88], [0.2, 0.5]])
			"left":
				draw_polyline(PackedVector2Array([pt(0.64, 0.16), pt(0.3, 0.5), pt(0.64, 0.84)]), tint, 0.14 * _s, true)
			"right":
				draw_polyline(PackedVector2Array([pt(0.36, 0.16), pt(0.7, 0.5), pt(0.36, 0.84)]), tint, 0.14 * _s, true)
			"down":
				draw_polyline(PackedVector2Array([pt(0.16, 0.34), pt(0.5, 0.68), pt(0.84, 0.34)]), tint, 0.12 * _s, true)
			"plus":
				line([0.5, 0.18], [0.5, 0.82], 0.16)
				line([0.18, 0.5], [0.82, 0.5], 0.16)
			"close":
				line([0.24, 0.24], [0.76, 0.76], 0.16)
				line([0.76, 0.24], [0.24, 0.76], 0.16)
			"check":
				draw_polyline(PackedVector2Array([pt(0.18, 0.52), pt(0.42, 0.76), pt(0.84, 0.26)]), tint, 0.15 * _s, true)
			"coin":
				draw_circle(pt(0.5, 0.5), 0.48 * _s, Color("f5a623"))
				draw_circle(pt(0.5, 0.5), 0.38 * _s, Color("ffd257"))
				var star := []
				for i in 10:
					var r := 0.24 if i % 2 == 0 else 0.1
					var a := -PI / 2 + i * PI / 5
					star.append([0.5 + cos(a) * r, 0.52 + sin(a) * r])
				poly(star, Color("f59e1b"))
			"gem":
				poly([[0.18, 0.36], [0.34, 0.12], [0.66, 0.12], [0.82, 0.36], [0.5, 0.92]], Color("63d8f6"))
				poly([[0.34, 0.12], [0.66, 0.12], [0.58, 0.36], [0.42, 0.36]], Color("b5f1ff"))
			"dot":
				draw_circle(pt(0.5, 0.5), 0.36 * _s, tint)

## Soft ocean gradient with bubbles and stars, sized to the whole screen.
class Backdrop extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
			PackedColorArray([Color("1d8fd8"), Color("1a82cf"), Color("0f5aa6"), Color("126ab8")]))
		for b in [[0.08, 0.28, 0.16], [0.9, 0.72, 0.22], [0.55, 0.95, 0.12], [0.33, 0.6, 0.07], [0.72, 0.18, 0.09]]:
			draw_circle(Vector2(b[0], b[1]) * size, b[2] * size.y, Color(1, 1, 1, 0.045))
		for s in [[0.22, 0.27], [0.215, 0.87], [0.875, 0.87], [0.62, 0.9]]:
			draw_circle(Vector2(s[0], s[1]) * size, 5, Color("ffe17b", 0.85))

var game: Node
var canvas := Control.new()
var backdrop := Backdrop.new()
var modal := Control.new()
var modal_title: Label
var modal_icon: Glyph
var modal_message: Label
var modal_settings: VBoxContainer
var modal_ok: Button
var search := LineEdit.new()
var tier_select := OptionButton.new()
var map_select := OptionButton.new()
var profile: Label
var level: Label
var xp: ProgressBar
var hero_line: Label
var portrait: TextureRect
var presence: Label
var status: Label
var summary: Label
var empty: Label
var page_label: Label
var prev_page: Button
var next_page: Button
var speaker: Glyph
var gold: Label
var gem: Label
var hero_list: VBoxContainer
var friend_list: VBoxContainer
var hero_scroll: ScrollContainer
var friend_scroll: ScrollContainer
var fullscreen_toggle: Button
var audio_toggle: Button
var hero_buttons: Array[Button] = []
var hero_states: Array[Label] = []
var map_buttons: Array[Button] = []
var map_cards: Array[PanelContainer] = []
var maps: Array[Dictionary] = []
var tier_filter := ""
var map_filter := -1
var page := 0
var chat_channel := "Tất cả"
var signed_in_on_entry := false

func box(fill: Color, border := Color.TRANSPARENT, radius := 18, width := 0, pad := 0) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = border
	value.set_border_width_all(width)
	value.set_corner_radius_all(radius)
	value.set_content_margin_all(pad)
	value.anti_aliasing = true
	return value

func card(fill: Color, border := Color.TRANSPARENT, radius := 22, width := 0, pad := 14) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", box(fill, border, radius, width, pad))
	return node

func row(gap := 12, parent: Control = null) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	if parent:
		parent.add_child(node)
	return node

func column(gap := 12, parent: Control = null) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	if parent:
		parent.add_child(node)
	return node

func text(value: String, font_size := 20, color := Color.WHITE, parent: Control = null) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(node)
	return node

func pill(value: String, fill: Color, color := Color.WHITE, font_size := 18, parent: Control = null) -> Label:
	var holder := card(fill, Color.TRANSPARENT, 16, 0, 0)
	holder.get_theme_stylebox("panel").content_margin_left = 18
	holder.get_theme_stylebox("panel").content_margin_right = 18
	holder.get_theme_stylebox("panel").content_margin_top = 3
	holder.get_theme_stylebox("panel").content_margin_bottom = 3
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var node := text(value, font_size, color, holder)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if parent:
		parent.add_child(holder)
	return node

func button(value: String, action: Callable, fill := Color("ffd76a"), color := INK, font_size := 20, radius := 18, border := Color.WHITE) -> Button:
	var node := Button.new()
	node.text = value
	node.focus_mode = Control.FOCUS_ALL
	node.add_theme_stylebox_override("normal", box(fill, border, radius, 3, 8))
	node.add_theme_stylebox_override("hover", box(fill.lightened(0.15), border, radius, 3, 8))
	node.add_theme_stylebox_override("pressed", box(fill.darkened(0.12), border, radius, 3, 8))
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color("ffe17b"), radius, 4, 8))
	node.add_theme_stylebox_override("disabled", box(Color("a9cfe6"), Color("d9eef8"), radius, 3, 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(state, color)
	node.add_theme_color_override("font_disabled_color", Color("6c8eab"))
	node.add_theme_font_size_override("font_size", font_size)
	node.pressed.connect(action)
	return node

func icon_button(icon: String, action: Callable, side := 58.0, fill := Color("3aa6e6"), radius := 14) -> Button:
	var node := button("", action, fill, Color.WHITE, 18, radius)
	node.custom_minimum_size = Vector2(side, side)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := Glyph.new(icon, Color.WHITE, side * 0.55)
	glyph.position = Vector2(side, side) * 0.225
	glyph.size = Vector2(side, side) * 0.55
	node.add_child(glyph)
	return node

func picture(path: String, side: Vector2) -> TextureRect:
	var node := TextureRect.new()
	if ResourceLoader.exists(path):
		node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = side
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func stretch(node: Label) -> Label:
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text = true
	return node

func spacer(parent: Control) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _ready() -> void:
	name = "DesktopMainLobby"
	signed_in_on_entry = AuthSession.has_session()
	load_maps()
	add_child(backdrop)
	add_child(canvas)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Nunito", "Segoe UI", "Noto Sans", "Arial"])
	font.font_weight = 800
	canvas.theme = Theme.new()
	canvas.theme.default_font = font
	var page_root := column(0, canvas)
	page_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_top_bar(page_root)
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 20)
	page_root.add_child(body_margin)
	var body := row(22, body_margin)
	build_left(body)
	build_right(body)
	build_chat(page_root)
	build_modal()
	# Menus fill the monitor; the arena keeps its fixed 1280×920 frame while playing.
	visibility_changed.connect(func(): ScreenFill.set_fill(get_tree(), is_visible_in_tree()))
	ScreenFill.set_fill(get_tree(), is_visible_in_tree())
	refresh()

func build_top_bar(parent: Control) -> void:
	var bar := card(Color("1b7cc9"), Color("74d3f0"), 0, 0, 12)
	bar.get_theme_stylebox("panel").border_width_bottom = 5
	bar.get_theme_stylebox("panel").content_margin_left = 20
	bar.get_theme_stylebox("panel").content_margin_right = 20
	parent.add_child(bar)
	var line := row(14, bar)
	var logo := card(Color("2a8fd8"), Color("bff2ff"), 30, 5, 6)
	logo.custom_minimum_size = Vector2(350, 92)
	line.add_child(logo)
	var brand := column(-6, logo)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := text("BỤP BỤP!", 46, Color("ffe17b"), brand)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color("6b4fb8"))
	title.add_theme_constant_override("outline_size", 10)
	var tagline := text("ĐẤU TRƯỜNG BÓNG NƯỚC", 14, Color.WHITE, brand)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nav := [
		["home", "Sảnh chính", refresh],
		["shop", "Cửa hàng", func(): open_shop("shop")],
		["lock", "Trang bị", func(): open_shop("equipment")],
		["star", "Nhiệm vụ", func(): notice("Nhiệm vụ hằng ngày đang được phát triển.", "NHIỆM VỤ", "star")],
		["trophy", "Xếp hạng", func(): notice("Chế độ chơi bot chưa có bảng xếp hạng online.", "XẾP HẠNG", "trophy")],
	]
	for i in nav.size():
		var active := i == 0
		var tab := button("", nav[i][2], Color("e9fbff") if active else Color("1d6fb5"), INK, 20, 18, Color("ffffff") if active else Color("3f97d3"))
		tab.custom_minimum_size = Vector2(152, 92)
		line.add_child(tab)
		var stack := column(2, tab)
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph := Glyph.new(nav[i][0], Color("ff9f43") if active else Color("ffe17b"), 34)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stack.add_child(glyph)
		var caption := text(nav[i][1], 19, INK if active else Color.WHITE, stack)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spacer(line)
	gold = wallet(line, "coin", 250)
	gem = wallet(line, "gem", 210)
	line.add_child(icon_button("people", func(): show_social(1)))
	line.add_child(icon_button("mail", func(): notice("Hộp thư trống. Thư hệ thống sẽ có ở bản online.", "HỘP THƯ", "mail")))
	line.add_child(icon_button("gear", open_settings))

func wallet(parent: Control, icon: String, width: float) -> Label:
	var holder := card(Color("0f5a9c"), Color("7fd9ef"), 36, 3, 6)
	holder.custom_minimum_size = Vector2(width, 66)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)
	var line := row(10, holder)
	line.add_child(Glyph.new(icon, Color.WHITE, 46))
	var amount := text("", 28, Color.WHITE, line)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(icon_button("plus", func(): open_shop("shop"), 40, Color("2fa8ec"), 20))
	return amount

func build_left(parent: Control) -> void:
	var side := column(20, parent)
	side.custom_minimum_size = Vector2(380, 0)
	var me := card(Color("e8fbff"), Color.WHITE, 26, 5, 16)
	side.add_child(me)
	var me_stack := column(14, me)
	var top := row(16, me_stack)
	var frame := card(Color("ffe9b0"), Color.WHITE, 80, 5, 6)
	frame.custom_minimum_size = Vector2(150, 150)
	top.add_child(frame)
	portrait = picture("", Vector2(130, 130))
	frame.add_child(portrait)
	var facts := column(6, top)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	profile = stretch(text("", 32, INK, facts))
	level = pill("", Color("ffe9a8"), Color("8a5a12"), 18, facts)
	level.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hero_line = stretch(text("", 18, Color("4b6a8a"), facts))
	xp = ProgressBar.new()
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(0, 14)
	xp.add_theme_stylebox_override("background", box(Color("c9dcef"), Color.TRANSPARENT, 7))
	xp.add_theme_stylebox_override("fill", box(Color("ffab4c"), Color.TRANSPARENT, 7))
	facts.add_child(xp)
	var place_card := card(SKY, LINE, 20, 3, 12)
	me_stack.add_child(place_card)
	var place_line := row(10, place_card)
	stretch(text("Đang ở Sảnh chính", 20, Color.WHITE, place_line))
	presence = pill("", Color("3fd39a"), Color("0d4b3a"), 15, place_line)
	var social := card(Color("1567ae"), LINE, 26, 4, 14)
	social.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(social)
	var social_stack := column(12, social)
	var tabs := row(8, social_stack)
	var group := ButtonGroup.new()
	for i in 2:
		var index: int = i
		var tab := button(["Nhân vật", "Bạn bè"][i], func(): show_social(index), Color("4fd0e6"), INK, 22, 16)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = i == 0
		tab.add_theme_stylebox_override("normal", box(Color("1d5f9e"), LINE, 16, 3, 8))
		tab.add_theme_color_override("font_color", Color.WHITE)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 56)
		tabs.add_child(tab)
	hero_scroll = scroll_list(social_stack)
	hero_list = hero_scroll.get_child(0).get_child(0)
	for i in game.HEROES.size():
		var index: int = i
		var entry := card(Color("1b77c0"), Color("5aa9de"), 18, 3, 8)
		hero_list.add_child(entry)
		var line := row(12, entry)
		var face := card(Color("bfeeff"), Color.WHITE, 30, 3, 2)
		face.custom_minimum_size = Vector2(60, 60)
		line.add_child(face)
		face.add_child(picture("res://assets/characters/portraits/%s.png" % game.HEROES[i], Vector2(54, 54)))
		var who := column(0, line)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.alignment = BoxContainer.ALIGNMENT_CENTER
		stretch(text(game.HERO_NAMES[i].capitalize(), 22, Color.WHITE, who))
		hero_states.append(text("", 16, Color("aef5c8"), who))
		var pick := icon_button("plus", func(): game._select_hero(index); refresh(), 48, Color("2fa8ec"), 24)
		pick.tooltip_text = "Chọn " + game.HERO_NAMES[i]
		line.add_child(pick)
		hero_buttons.append(pick)
	friend_scroll = scroll_list(social_stack)
	friend_list = friend_scroll.get_child(0).get_child(0)
	friend_list.alignment = BoxContainer.ALIGNMENT_CENTER
	var friends_icon := Glyph.new("people", Color("8fd7f5"), 70)
	friends_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	friend_list.add_child(friends_icon)
	var none := text("Bản chơi bot chưa có hệ thống bạn bè.\nBạn bè và bang hội sẽ có ở chế độ online.", 18, Color("d5f3ff"), friend_list)
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friend_scroll.hide()
	var all := button("DANH SÁCH BẠN BÈ", func(): show_social(1), Color("4fc3f0"), Color.WHITE, 20, 22)
	all.custom_minimum_size = Vector2(0, 54)
	social_stack.add_child(all)

## Vertical list that scrolls once characters/friends outgrow the panel.
func scroll_list(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(12, 0)
	bar.add_theme_stylebox_override("scroll", box(Color("0f4f8f"), Color.TRANSPARENT, 6))
	bar.add_theme_stylebox_override("grabber", box(Color("74d3f0"), Color.TRANSPARENT, 6))
	bar.add_theme_stylebox_override("grabber_highlight", box(Color("a6e8f8"), Color.TRANSPARENT, 6))
	bar.add_theme_stylebox_override("grabber_pressed", box(Color("ffe17b"), Color.TRANSPARENT, 6))
	parent.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 10)
	scroll.add_child(gutter)
	var list := column(10, gutter)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll

func build_right(parent: Control) -> void:
	var main := column(16, parent)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var modes := row(22, main)
	var mode_specs := [
		["TÌM TRẬN NHANH", "Vào trận ngay với bản đồ đã chọn", Color("ffd56b"), "res://assets/ui/launch/mascot_pip.png", start],
		["TẠO PHÒNG", "Tự chọn bản đồ, độ khó", Color("8fdcf5"), "res://assets/ui/launch/mascot_nop.png", func(): map_select.grab_focus(); map_select.show_popup()],
		["ĐẤU XẾP HẠNG", "Cần chế độ online", Color("d4bdf7"), "", func(): notice("Đấu xếp hạng cần chế độ online, chưa có trong bản chơi bot.", "ĐẤU XẾP HẠNG", "trophy")],
	]
	for spec in mode_specs:
		var big := button("", spec[4], spec[2], INK, 20, 26)
		big.custom_minimum_size = Vector2(0, 132)
		big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(big)
		var inner := row(18, big)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 26
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[3] != "":
			inner.add_child(picture(spec[3], Vector2(96, 96)))
		else:
			inner.add_child(Glyph.new("star", Color("ffd84d"), 90))
		var words := column(4, inner)
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text(spec[0], 30, Color("8a4b1f") if spec[0] == "TÌM TRẬN NHANH" else INK, words)
		text(spec[1], 18, Color("6a5a7a"), words)
	var filters := card(Color("1660a6"), LINE, 30, 4, 12)
	main.add_child(filters)
	var bar := row(16, filters)
	style_select(tier_select, "Tất cả độ khó", tiers())
	tier_select.item_selected.connect(func(index): set_tier(tier_select.get_item_text(index) if index > 0 else ""))
	bar.add_child(tier_select)
	var names: Array[String] = []
	for map in maps:
		names.append(str(map.name).capitalize())
	style_select(map_select, "Tất cả bản đồ", names)
	map_select.item_selected.connect(func(index): set_map(index - 1))
	bar.add_child(map_select)
	text("Bot · 1 người + 3 bot", 20, Color.WHITE, bar)
	spacer(bar)
	var field := card(Color("0f4f8f"), LINE, 26, 3, 4)
	field.custom_minimum_size = Vector2(470, 56)
	bar.add_child(field)
	var field_line := row(8, field)
	search.placeholder_text = "Tìm bản đồ (không cần dấu)…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 14))
	search.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 14))
	search.add_theme_font_size_override("font_size", 21)
	search.add_theme_color_override("font_color", Color.WHITE)
	search.add_theme_color_override("font_placeholder_color", Color("b9dcf3"))
	search.text_changed.connect(func(_value): page = 0; refresh())
	search.text_submitted.connect(func(_value): pick_first_match())
	field_line.add_child(search)
	field_line.add_child(Glyph.new("search", Color.WHITE, 34))
	var list := column(12, main)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 18)
	list.add_child(grid)
	for i in maps.size():
		grid.add_child(map_card(i))
	empty = text("Không tìm thấy bản đồ phù hợp. Thử từ khóa khác hoặc chọn \"Tất cả\".", 22, Color("ffe17b"), list)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.custom_minimum_size = Vector2(0, 120)
	var footer := row(16, main)
	summary = stretch(text("", 20, Color.WHITE, footer))
	summary.size_flags_stretch_ratio = 1.0
	var pager := card(Color("1660a6"), LINE, 34, 3, 6)
	pager.custom_minimum_size = Vector2(470, 0)
	footer.add_child(pager)
	var pager_line := row(10, pager)
	prev_page = icon_button("left", func(): page -= 1; refresh(), 56, Color("3aa6e6"), 28)
	pager_line.add_child(prev_page)
	page_label = text("", 24, Color.WHITE, pager_line)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_page = icon_button("right", func(): page += 1; refresh(), 56, Color("3aa6e6"), 28)
	pager_line.add_child(next_page)
	var balance := spacer(footer)
	balance.size_flags_stretch_ratio = 0.6

func style_select(select: OptionButton, all: String, entries: Array[String]) -> void:
	select.add_item(all)
	for entry in entries:
		select.add_item(entry)
	select.custom_minimum_size = Vector2(290, 56)
	select.add_theme_font_size_override("font_size", 21)
	select.add_theme_stylebox_override("normal", box(Color("2a86d0"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("hover", box(Color("3596df"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("pressed", box(Color("1f75bb"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color("ffe17b"), 16, 3, 14))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		select.add_theme_color_override(state, Color.WHITE)
	select.get_popup().add_theme_font_size_override("font_size", 20)

func map_card(index: int) -> PanelContainer:
	var map: Dictionary = maps[index]
	var holder := card(Color("e9fbff"), Color("b8e9f7"), 24, 4, 14)
	holder.custom_minimum_size = Vector2(0, 162)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_on_card_input.bind(index))
	var line := row(18, holder)
	var thumb := card(Color("bfeeff"), Color("2f8fd0"), 14, 3, 3)
	thumb.custom_minimum_size = Vector2(150, 120)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(thumb)
	thumb.add_child(picture("res://assets/level_previews/%s.png" % map.id, Vector2(140, 110)))
	var facts := column(8, line)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := row(12, facts)
	pill("%03d" % (index + 1), Color("1d78bd"), Color.WHITE, 17, head)
	stretch(text(str(map.name).capitalize(), 28, INK, head))
	var meta := row(12, facts)
	pill(map.tier if map.tier != "" else "Đấu bot", TIER_COLORS.get(map.tier, Color("4fa8ef")), Color.WHITE, 17, meta)
	meta.add_child(Glyph.new("people", Color("2f7fc0"), 30))
	text("1 + 3 bot", 22, INK, meta)
	var detail := stretch(text("Sẵn sàng · %s" % str(map.subtitle).get_slice("•", 1).strip_edges(), 16, Color("6a8aa6"), facts))
	detail.name = "Detail"
	var choice := button("CHỌN", func(): choose(index), Color("ffcb52"), Color("8a4b1f"), 21, 18)
	choice.custom_minimum_size = Vector2(160, 62)
	choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choice.set_meta("map_name", map.name)
	line.add_child(choice)
	map_cards.append(holder)
	map_buttons.append(choice)
	return holder

func build_chat(parent: Control) -> void:
	var bar := card(Color("1572bd"), Color("74d3f0"), 0, 0, 10)
	bar.get_theme_stylebox("panel").border_width_top = 4
	bar.get_theme_stylebox("panel").content_margin_left = 20
	bar.get_theme_stylebox("panel").content_margin_right = 20
	parent.add_child(bar)
	var line := row(12, bar)
	var group := ButtonGroup.new()
	for channel in ["Tất cả", "Thế giới", "Bang hội", "Riêng"]:
		var name_of: String = channel
		var tab := button(channel, func(): chat_channel = name_of; refresh(), Color("56d2c9"), INK, 20, 14, Color("9be9f0"))
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = channel == "Tất cả"
		tab.add_theme_stylebox_override("normal", box(Color("1d5f9e"), Color("4f9fd8"), 14, 3, 8))
		tab.add_theme_color_override("font_color", Color.WHITE)
		tab.custom_minimum_size = Vector2(118, 58)
		line.add_child(tab)
	var sound := icon_button("speaker", func(): game._toggle_audio(); refresh(), 58, Color("2a86d0"), 14)
	speaker = sound.get_child(0) as Glyph
	line.add_child(sound)
	var message := card(Color("0f5a9c"), Color("4f9fd8"), 14, 3, 10)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(message)
	status = stretch(text("", 20, Color.WHITE, message))
	line.add_child(icon_button("send", func(): notice("Chat chưa hỗ trợ trong bản chơi bot.", "TRÒ CHUYỆN", "send"), 62, Color("4fc3f0"), 16))

## In-canvas popup in the lobby's own style, shared by notices and settings.
func build_modal() -> void:
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.hide()
	canvas.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.16, 0.36, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var sheet := card(Color("fff9e9"), Color.WHITE, 34, 6, 26)
	var frame := sheet.get_theme_stylebox("panel") as StyleBoxFlat
	frame.shadow_color = Color(0.02, 0.12, 0.3, 0.45)
	frame.shadow_size = 18
	frame.shadow_offset = Vector2(0, 10)
	sheet.custom_minimum_size = Vector2(680, 0)
	center.add_child(sheet)
	var stack := column(20, sheet)
	var head := row(12, stack)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(54, 0)
	head.add_child(balance)
	modal_title = pill("", Color("2a86d0"), Color.WHITE, 26, head)
	modal_title.get_parent().size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	(modal_title.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(10)
	(modal_title.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 40
	(modal_title.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 40
	head.add_child(icon_button("close", close_modal, 54, Color("f4738d"), 27))
	var badge := card(Color("dff6ff"), Color("8fdcf5"), 60, 5, 0)
	badge.custom_minimum_size = Vector2(120, 120)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(badge)
	modal_icon = Glyph.new("star", Color("ffb43c"), 64)
	modal_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.add_child(modal_icon)
	modal_message = text("", 24, INK, stack)
	modal_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_message.custom_minimum_size = Vector2(600, 0)
	modal_settings = column(12, stack)
	fullscreen_toggle = setting_row("Toàn màn hình", func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	audio_toggle = setting_row("Âm thanh", _on_audio_toggled)
	var out := button("ĐĂNG XUẤT" if signed_in_on_entry else "VỀ MÀN HÌNH ĐĂNG NHẬP", leave, Color("f4738d"), Color.WHITE, 22, 20)
	out.custom_minimum_size = Vector2(0, 62)
	modal_settings.add_child(out)
	modal_ok = button("ĐÃ HIỂU", close_modal, Color("ffcb52"), Color("8a4b1f"), 24, 22)
	modal_ok.custom_minimum_size = Vector2(260, 66)
	modal_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(modal_ok)

func setting_row(label_text: String, action: Callable) -> Button:
	var holder := card(Color("e4f7ff"), Color("b8e9f7"), 20, 3, 14)
	modal_settings.add_child(holder)
	var line := row(12, holder)
	stretch(text(label_text, 24, INK, line))
	var toggle := button("", func(): pass, Color("3fd39a"), Color.WHITE, 20, 24)
	toggle.toggle_mode = true
	toggle.custom_minimum_size = Vector2(130, 52)
	toggle.add_theme_stylebox_override("normal", box(Color("b9cbdc"), Color.WHITE, 24, 3, 8))
	toggle.add_theme_stylebox_override("hover", box(Color("c8d8e7"), Color.WHITE, 24, 3, 8))
	toggle.add_theme_stylebox_override("pressed", box(Color("3fd39a"), Color.WHITE, 24, 3, 8))
	toggle.add_theme_stylebox_override("hover_pressed", box(Color("52dea8"), Color.WHITE, 24, 3, 8))
	toggle.toggled.connect(func(on): toggle.text = "BẬT" if on else "TẮT")
	toggle.toggled.connect(action)
	line.add_child(toggle)
	return toggle

func open_modal(title: String, icon: String, message: String, with_settings := false) -> void:
	modal_title.text = title
	modal_icon.set_kind(icon)
	modal_message.text = message
	modal_message.visible = message != ""
	modal_settings.visible = with_settings
	modal_ok.text = "ĐÓNG" if with_settings else "ĐÃ HIỂU"
	modal.show()
	modal_ok.grab_focus()

func close_modal() -> void:
	modal.hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if modal.visible and event.is_action_pressed("ui_cancel"):
		close_modal()
		get_viewport().set_input_as_handled()

func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		choose(index)

func _on_audio_toggled(on: bool) -> void:
	if on != game.music_enabled:
		game._toggle_audio()
	refresh()

func open_settings() -> void:
	for pair in [[fullscreen_toggle, DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]], [audio_toggle, game.music_enabled]]:
		pair[0].set_pressed_no_signal(pair[1])
		pair[0].text = "BẬT" if pair[1] else "TẮT"
	open_modal("CÀI ĐẶT", "gear", "", true)

func show_social(tab: int) -> void:
	hero_scroll.visible = tab == 0
	friend_scroll.visible = tab == 1

## Lowercases and strips Vietnamese diacritics so "lau dai" matches "LÂU ĐÀI".
static func fold(value: String) -> String:
	var out := ""
	for ch in value.to_lower():
		var plain: String = ch
		for base in FOLD:
			if FOLD[base].contains(ch):
				plain = base
				break
		out += plain
	return out

## Reads map cards from the same level files gameplay loads, so new maps need no lobby edits.
func load_maps() -> void:
	for path in game.LEVEL_FILES:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			data = {}
		var subtitle := str(data.get("subtitle", ""))
		var map := {
			"id": str(data.get("id", path.get_file().get_basename())),
			"name": str(data.get("name", path.get_file().get_basename())),
			"subtitle": subtitle,
			"tier": subtitle.get_slice("•", 0).strip_edges(),
		}
		map.keywords = fold(" ".join([map.id, map.name, subtitle, str(data.get("theme", ""))]))
		maps.append(map)

func tiers() -> Array[String]:
	var found: Array[String] = []
	for map in maps:
		if map.tier != "" and not found.has(map.tier):
			found.append(map.tier)
	return found

func set_tier(tier: String) -> void:
	tier_filter = tier
	tier_select.select(maxi(0, tiers().find(tier) + 1))
	page = 0
	refresh()

func set_map(index: int) -> void:
	map_filter = index
	map_select.select(index + 1)
	page = 0
	refresh()

func matches(index: int) -> bool:
	var map: Dictionary = maps[index]
	if tier_filter != "" and map.tier != tier_filter:
		return false
	if map_filter >= 0 and map_filter != index:
		return false
	for word in fold(search.text).split(" ", false):
		if not map.keywords.contains(word):
			return false
	return true

func visible_maps() -> Array[int]:
	var found: Array[int] = []
	for i in maps.size():
		if matches(i):
			found.append(i)
	return found

func choose(index: int) -> void:
	game._select_level(index)
	refresh()

func pick_first_match() -> void:
	var found := visible_maps()
	if not found.is_empty():
		choose(found[0])
		map_buttons[found[0]].grab_focus()

func page_count() -> int:
	return maxi(1, ceili(visible_maps().size() / float(PAGE_SIZE)))

func refresh() -> void:
	var hero: int = game.selected_hero
	profile.text = AuthSession.account_name if AuthSession.has_session() else "Khách"
	profile.tooltip_text = profile.text
	level.text = "Lv. %d" % int(UIState.profile.get("level", 1))
	xp.max_value = maxf(1.0, float(UIState.profile.get("xp_max", 1)))
	xp.value = float(UIState.profile.get("xp", 0))
	hero_line.text = "Nhân vật: " + game.HERO_NAMES[hero].capitalize()
	portrait.texture = load("res://assets/characters/portraits/%s.png" % game.HEROES[hero])
	presence.text = "ONLINE" if AuthSession.has_session() else "KHÁCH"
	gold.text = grouped(int(UIState.profile.get("gold", 0)))
	gem.text = grouped(int(UIState.profile.get("gem", 0)))
	for i in hero_buttons.size():
		var picked: bool = i == hero
		hero_states[i].text = "Đang chọn" if picked else "Sẵn sàng"
		hero_states[i].add_theme_color_override("font_color", Color("ffe17b") if picked else Color("aef5c8"))
		(hero_buttons[i].get_child(0) as Glyph).set_kind("check" if picked else "plus")
	var found := visible_maps()
	page = clampi(page, 0, page_count() - 1)
	var shown := found.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)
	for i in map_buttons.size():
		var picked: bool = game.selected_level == i
		map_buttons[i].text = "ĐÃ CHỌN" if picked else "CHỌN"
		map_cards[i].visible = shown.has(i)
		var frame := map_cards[i].get_theme_stylebox("panel") as StyleBoxFlat
		frame.border_color = Color("ffc93c") if picked else Color("b8e9f7")
		frame.set_border_width_all(6 if picked else 4)
	empty.visible = found.is_empty()
	summary.text = "%d/%d bản đồ · Enter để chọn bản đồ đầu tiên" % [found.size(), maps.size()]
	page_label.text = "TRANG %d / %d" % [page + 1, page_count()]
	prev_page.disabled = page == 0
	next_page.disabled = page >= page_count() - 1
	speaker.set_kind("speaker" if game.music_enabled else "mute")
	var selected: String = str(maps[game.selected_level].name).capitalize() if game.selected_level < maps.size() else "?"
	if chat_channel == "Tất cả":
		status.text = "[Hệ thống] Chào mừng bạn đến với BỤP BỤP! • Bản đồ: %s • Nhân vật: %s • Âm thanh: %s" % [selected, game.HERO_NAMES[hero].capitalize(), "Bật" if game.music_enabled else "Tắt"]
	else:
		status.text = "[%s] Chat chưa hỗ trợ trong bản chơi bot." % chat_channel

static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return ("-" if value < 0 else "") + out

func start() -> void:
	game._new_round()

func notice(message: String, title := "THÔNG BÁO", icon := "star") -> void:
	open_modal(title, icon, message)

func leave() -> void:
	UIState.remove_meta("from_desktop_lobby")
	AuthSession.logout()
	get_tree().change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")

func open_shop(target: String) -> void:
	UIState.set_meta("desktop_page", target)
	UIState.set_meta("from_desktop_lobby", true)
	get_tree().change_scene_to_file("res://scenes/ui/ui_showcase.tscn")

func _exit_tree() -> void:
	ScreenFill.set_fill(get_tree(), false)

func _process(_delta: float) -> void:
	var viewport := get_viewport_rect().size
	backdrop.position = Vector2.ZERO
	backdrop.size = viewport
	var ratio := minf(viewport.x / DESIGN.x, viewport.y / DESIGN.y)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = Vector2.ZERO
	canvas.size = viewport / ratio
	if is_visible_in_tree() and signed_in_on_entry and not AuthSession.has_session():
		leave()
