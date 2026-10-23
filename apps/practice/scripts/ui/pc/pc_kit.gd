extends Control
## Shared base for PC-only screens after the lobby (matchmaking, room, result,
## shop, equipment). Style follows the supplied "Bubble Isles" UI kit: sky or
## sunset backdrop, cream panels. Buttons, close, coin / gem and mail icons are
## the glossy pills and stickers of the mailbox kit (assets/ui/kit, cut by
## tools/slice_ui_kit.gd); characters and items reuse the game's own art.
const HeroPortrait := preload("res://scripts/hero_portrait.gd")
const Glyph := preload("res://scripts/ui/desktop_lobby.gd").Glyph
const ScreenFill := preload("res://scripts/ui/screen_fill.gd")
const PopupHeader := preload("res://scripts/ui/popup_header.gd")
const DESIGN := Vector2(1280, 720)
const KIT := "res://assets/ui/kit/"
## Pill caps of the kit button textures (56 px high): left/right, top/bottom.
const PILL_CAP := 28
const PILL_EDGE := 20
const INK := Color("2b3a67")
const MUTED := Color("6b7a9c")
const CREAM := Color("fff6e2")
const GLASS := Color("eaf5ff")
const NAVY := Color("2d4a7a")
const SKY := Color("4fb7f5")
const SUN := Color("ffc93c")
const CORAL := Color("ff7083")
const LAVENDER := Color("a98bf0")
const MINT := Color("44cf9e")
const GHOST := Color("fbfbfd")
const CANDY := {
	"sun": [Color("ffc93c"), Color("e39b14"), Color.WHITE],
	"sky": [Color("4fb7f5"), Color("2b88cf"), Color.WHITE],
	"coral": [Color("ff7083"), Color("d74d63"), Color.WHITE],
	"lavender": [Color("a98bf0"), Color("7c62c9"), Color.WHITE],
	"mint": [Color("44cf9e"), Color("23a079"), Color.WHITE],
	"ghost": [Color("fbfbfd"), Color("e2d6bd"), Color("2b3a67")],
}

## Vertical gradient sky with sun, clouds, bubbles and sea, in three moods.
class Backdrop extends Control:
	var mood := "sky"

	func _init(kind := "sky") -> void:
		mood = kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var top := Color("74c6f7")
		var bottom := Color("bfe6ff")
		var sea := Color("8fd0f4")
		if mood == "sunset":
			top = Color("ffb08a")
			bottom = Color("ffe0b8")
			sea = Color("9fd2ec")
		elif mood == "candy":
			top = Color("ffb9d0")
			bottom = Color("ffe6ef")
			sea = Color("ffd0e1")
		var r := Rect2(Vector2.ZERO, size)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))
		var sun := Vector2(0.84, 0.2) * size
		draw_circle(sun, size.y * 0.17, Color(1, 1, 1, 0.16))
		draw_circle(sun, size.y * 0.11, Color(1, 1, 1, 0.24))
		for c in [[0.06, 0.12, 1.0], [0.5, 0.08, 0.8], [0.72, 0.55, 0.7], [0.2, 0.62, 0.6]]:
			var at := Vector2(c[0], c[1]) * size
			var s: float = c[2] * size.y * 0.045
			for puff in [[-1.2, 0.2, 0.9], [0.0, 0.0, 1.2], [1.2, 0.25, 0.85], [0.5, -0.5, 0.9]]:
				draw_circle(at + Vector2(puff[0], puff[1]) * s, puff[2] * s, Color(1, 1, 1, 0.85))
		for b in [[0.12, 0.42, 0.03], [0.3, 0.2, 0.018], [0.62, 0.3, 0.024], [0.9, 0.48, 0.035], [0.45, 0.8, 0.02], [0.78, 0.82, 0.028]]:
			var at := Vector2(b[0], b[1]) * size
			draw_arc(at, b[2] * size.y, 0, TAU, 28, Color(1, 1, 1, 0.55), 2.0, true)
			draw_circle(at - Vector2(0.35, 0.35) * b[2] * size.y, b[2] * size.y * 0.22, Color(1, 1, 1, 0.6))
		var wave := PackedVector2Array([Vector2(0, size.y)])
		for i in 33:
			var x := size.x * i / 32.0
			wave.append(Vector2(x, size.y * 0.9 + sin(i * 0.8) * size.y * 0.01))
		wave.append(size)
		draw_colored_polygon(wave, sea)

## Small spinning ring of bubbles used while bots are being seated.
class Spinner extends Control:
	var turn := 0.0

	func _init(side := 48.0) -> void:
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		turn += delta * 4.0
		queue_redraw()

	func _draw() -> void:
		var center := size / 2
		var radius := minf(size.x, size.y) * 0.38
		for i in 8:
			var a := turn + i * TAU / 8
			draw_circle(center + Vector2(cos(a), sin(a)) * radius, radius * (0.08 + 0.025 * i), Color(SKY, 0.35 + i * 0.08))

var sky := Backdrop.new()
var canvas := Control.new()
var modal := Control.new()
var modal_title: Label
var modal_message: Label
var modal_actions: HBoxContainer
var settings_overlay: Control
var settings_page: Control
var fill_screen := true
## Set before adding to the tree: the page lives inside a lobby popup, so it
## draws no backdrop or top bar and scales to its own rect, not the window.
var embedded := false

func _init(mood := "sky") -> void:
	sky.mood = mood

func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if embedded:
		fill_screen = false
		sky.hide()
	add_child(sky)
	add_child(canvas)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Nunito", "Segoe UI", "Noto Sans", "Arial"])
	font.font_weight = 800
	canvas.theme = Theme.new()
	canvas.theme.default_font = font
	if fill_screen:
		visibility_changed.connect(func(): if is_visible_in_tree(): ScreenFill.set_fill(get_tree(), true))

## Builds the in-canvas modal last so it sits above the page.
func build_modal() -> void:
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.hide()
	canvas.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.18, 0.36, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var sheet := card(CREAM, Color.WHITE, 26, 5, 22)
	sheet.custom_minimum_size = Vector2(560, 0)
	center.add_child(sheet)
	var stack := column(16, sheet)
	var header := PopupHeader.new(true)
	stack.add_child(header)
	modal_title = header.title_label
	modal_message = text("", 18, MUTED, stack)
	modal_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_message.custom_minimum_size = Vector2(430, 0)
	modal_actions = row(14, stack)
	modal_actions.alignment = BoxContainer.ALIGNMENT_CENTER

## One-button notice, or a confirm when `on_yes` is given.
func notice(title: String, message: String, on_yes := Callable(), yes_label := "ĐỒNG Ý") -> void:
	modal_title.text = title
	modal_message.text = message
	modal_message.visible = message != ""
	for child in modal_actions.get_children():
		child.queue_free()
	if on_yes.is_valid():
		modal_actions.add_child(sized(candy("Hủy", close_modal, "ghost", 18), Vector2(150, 50)))
		modal_actions.add_child(sized(candy(yes_label, func(): close_modal(); on_yes.call(), "sun", 20), Vector2(190, 50)))
	else:
		modal_actions.add_child(sized(candy("ĐÃ HIỂU", close_modal, "sun", 20), Vector2(190, 50)))
	modal.show()

func close_modal() -> void:
	modal.hide()

## The settings window (pc_settings.gd) over this page, built on first use.
## Loaded at run time: the window is itself a kit page.
func open_settings(_audio_on := false, _on_audio := Callable()) -> void:
	if settings_overlay == null:
		settings_overlay = Control.new()
		settings_overlay.name = "SettingsOverlay"
		settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.add_child(settings_overlay)
		var dim := ColorRect.new()
		dim.color = Color(0.1, 0.18, 0.36, 0.6)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		settings_overlay.add_child(dim)
		var sheet := card(CREAM, Color.WHITE, 26, 4, 12)
		sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			sheet.set("offset_" + side, 28 if side in ["left", "top"] else -28)
		settings_overlay.add_child(sheet)
		var stack := column(6, sheet)
		var head := row(10, stack)
		var header := PopupHeader.new()
		head.add_child(header)
		header.set_title("CÀI ĐẶT")
		header.set_icon(Glyph.new("gear", SUN, 56))
		head.add_child(round_icon("close", close_settings, "coral", 44))
		var area := Control.new()
		area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(area)
		settings_page = load("res://scripts/ui/pc/pc_settings.gd").new()
		settings_page.embedded = true
		settings_page.navigate.connect(func(destination: String):
			close_settings()
			if destination == "logout":
				if OnlineArena.connected:
					OnlineArena.leave()
				AuthSession.logout()
				get_tree().change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn"))
		area.add_child(settings_page)
		settings_page.hide()
	if "game" in self and self.get("game") != null:
		settings_page.hero_id = str(self.get("game").HEROES[self.get("game").selected_hero])
	settings_overlay.show()
	settings_page.show()
	canvas.move_child(settings_overlay, canvas.get_child_count() - 1)

func close_settings() -> void:
	if settings_overlay:
		settings_page.hide()
		settings_overlay.hide()

## Top bar from the kit: back, profile chip, title, wallet, mail, settings.
func top_bar(title: String, on_back: Callable, on_settings: Callable) -> Dictionary:
	var bar := row(12)
	bar.custom_minimum_size = Vector2(0, 64)
	bar.add_child(round_icon("left", on_back, "ghost", 54))
	var chip := card(NAVY, Color("9fd7ff"), 20, 3, 6)
	chip.custom_minimum_size = Vector2(240, 56)
	bar.add_child(chip)
	var chip_line := row(10, chip)
	var face := card(Color("ffe9b0"), Color.WHITE, 22, 2, 0)
	face.custom_minimum_size = Vector2(44, 44)
	chip_line.add_child(face)
	var face_art := picture("", Vector2(42, 42))
	face.add_child(face_art)
	var who := column(0, chip_line)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := stretch(text("", 17, Color.WHITE, who))
	var lv_line := row(6, who)
	var lv := text("", 13, SUN, lv_line)
	var xp := ProgressBar.new()
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(110, 8)
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp.add_theme_stylebox_override("background", box(Color("1d3359"), Color.TRANSPARENT, 4))
	xp.add_theme_stylebox_override("fill", box(SUN, Color.TRANSPARENT, 4))
	lv_line.add_child(xp)
	var heading := title_text(title, 34)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(heading)
	var gold := wallet_chip(bar, "coin")
	var gem := wallet_chip(bar, "gem")
	bar.add_child(round_icon("mail", func(): notice("HỘP THƯ", "Hộp thư trống. Thư hệ thống sẽ có ở bản online."), "ghost", 50))
	bar.add_child(round_icon("gear", on_settings, "ghost", 50))
	return {"bar": bar, "face": face_art, "name": name_label, "level": lv, "xp": xp, "gold": gold, "gem": gem, "title": heading}

func refresh_top_bar(parts: Dictionary, hero_id: String) -> void:
	(parts.face as TextureRect).texture = HeroPortrait.texture(hero_id)
	(parts.name as Label).text = AuthSession.account_name if AuthSession.has_session() else "Khách"
	(parts.level as Label).text = "Lv.%d" % int(UIState.profile.get("level", 1))
	(parts.xp as ProgressBar).max_value = maxf(1.0, float(UIState.profile.get("xp_max", 1)))
	(parts.xp as ProgressBar).value = float(UIState.profile.get("xp", 0))
	(parts.gold as Label).text = grouped(int(UIState.profile.get("gold", 0)))
	(parts.gem as Label).text = grouped(int(UIState.profile.get("gem", 0)))

func wallet_chip(parent: Control, icon: String) -> Label:
	var holder := card(NAVY, Color("9fd7ff"), 20, 2, 6)
	holder.custom_minimum_size = Vector2(140, 44)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)
	var line := row(8, holder)
	line.add_child(sticker(icon, 30))
	var amount := text("", 18, Color.WHITE, line)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return amount

## Page layout: top bar then an expanding body, both inside a margin.
func page(parent: Control, gap := 14) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	parent.add_child(margin)
	return column(gap, margin)

func box(fill: Color, border := Color.TRANSPARENT, radius := 18, width := 0, pad := 0, bottom := -1) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = border
	value.set_border_width_all(width)
	if bottom >= 0:
		value.border_width_bottom = bottom
	value.set_corner_radius_all(radius)
	value.set_content_margin_all(pad)
	value.anti_aliasing = true
	return value

func card(fill: Color, border := Color.TRANSPARENT, radius := 22, width := 0, pad := 14) -> PanelContainer:
	var node := PanelContainer.new()
	var style := box(fill, border, radius, width, pad)
	style.shadow_color = Color(0.1, 0.25, 0.5, 0.18)
	style.shadow_size = 6 if width >= 3 else 0
	style.shadow_offset = Vector2(0, 4)
	node.add_theme_stylebox_override("panel", style)
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

func text(value: String, font_size := 18, color := INK, parent: Control = null) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(node)
	return node

## Big outlined heading (yellow or white on navy outline) used for titles.
func title_text(value: String, font_size := 34, color := Color.WHITE, parent: Control = null) -> Label:
	var node := text(value, font_size, color, parent)
	node.add_theme_color_override("font_outline_color", NAVY)
	node.add_theme_constant_override("outline_size", maxi(6, font_size / 4))
	return node

func pill(value: String, fill: Color, color := Color.WHITE, font_size := 13, parent: Control = null) -> Label:
	var holder := PanelContainer.new()
	var style := box(fill, Color.TRANSPARENT, 12, 0, 2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	holder.add_theme_stylebox_override("panel", style)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var node := text(value, font_size, color, holder)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if parent:
		parent.add_child(holder)
	return node

## Candy button: the kit's glossy pill in that colour, white words with a dark
## rim, an optional kit glyph (glyph_<name>.png) before them; sinks on press.
func candy(value: String, action: Callable, kind := "sun", font_size := 20, icon := "") -> Button:
	var palette: Array = CANDY.get(kind, CANDY.sun)
	var lip: Color = palette[1]
	var node := Button.new()
	node.text = value
	node.focus_mode = Control.FOCUS_ALL
	node.add_theme_stylebox_override("normal", pill_style(kind))
	node.add_theme_stylebox_override("hover", pill_style(kind, 1.08))
	node.add_theme_stylebox_override("pressed", pill_style(kind, 0.9, 2))
	node.add_theme_stylebox_override("hover_pressed", pill_style(kind, 0.9, 2))
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color(1, 1, 1, 0.9), PILL_CAP, 3, 8))
	node.add_theme_stylebox_override("disabled", pill_style("off"))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(state, palette[2])
	node.add_theme_color_override("font_disabled_color", Color("f2f5fa"))
	node.add_theme_font_size_override("font_size", font_size)
	if kind != "ghost":
		node.add_theme_color_override("font_outline_color", lip.darkened(0.3))
		node.add_theme_constant_override("outline_size", 6)
	if icon != "":
		node.icon = load(KIT + "glyph_%s.png" % icon)
		node.add_theme_constant_override("icon_max_width", int(font_size * 1.5))
		node.add_theme_constant_override("h_separation", 10)
		node.alignment = HORIZONTAL_ALIGNMENT_LEFT
		node.resized.connect(center_icon.bind(node))
		node.draw.connect(center_icon.bind(node))
	node.pressed.connect(action)
	return node

## Keeps an icon button's glyph and words centred together, as in the kit:
## the left padding follows the button width and text (tab counts change).
static func center_icon(node: Button) -> void:
	var font_size := node.get_theme_font_size("font_size")
	var words := node.get_theme_font("font").get_string_size(node.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var group := words + node.get_theme_constant("icon_max_width") + node.get_theme_constant("h_separation")
	var pad := maxf(14.0, floorf((node.size.x - group) / 2))
	var moved := false
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := node.get_theme_stylebox(state)
		if style.content_margin_left != pad:
			style.content_margin_left = pad
			moved = true
	if moved:
		node.queue_redraw()

## Kit pill texture (button_<kind>.png): `tone` lightens or darkens it and
## `sink` moves the words down while pressed.
static func pill_style(kind: String, tone := 1.0, sink := 0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(KIT + "button_%s.png" % kind)
	style.texture_margin_left = PILL_CAP
	style.texture_margin_right = PILL_CAP
	style.texture_margin_top = PILL_EDGE
	style.texture_margin_bottom = PILL_EDGE
	style.modulate_color = Color(tone, tone, tone)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 6 + sink
	style.content_margin_bottom = 10 - sink
	return style

## Kit sticker (icon_<name>.png) as a fixed-size picture.
func sticker(name: String, side := 32.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(KIT + "icon_%s.png" % name)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(side, side)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## Category tab: blue kit pill when idle, the yellow one while pressed (use a
## ButtonGroup); words white on blue, brown on yellow.
func tab(value: String, action: Callable, group: ButtonGroup, icon := "") -> Button:
	var node := candy(value, action, "ghost", 15, icon)
	node.toggle_mode = true
	node.button_group = group
	node.custom_minimum_size = Vector2(0, 40)
	node.add_theme_stylebox_override("normal", pill_style("tab_sky"))
	node.add_theme_stylebox_override("hover", pill_style("tab_sky", 1.08))
	node.add_theme_stylebox_override("pressed", pill_style("sun"))
	node.add_theme_stylebox_override("hover_pressed", pill_style("sun", 1.05))
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		node.add_theme_color_override(state, Color.WHITE)
	node.add_theme_color_override("font_pressed_color", Color("7a3d00"))
	node.add_theme_color_override("font_hover_pressed_color", Color("7a3d00"))
	return node

func lipped(fill: Color, lip: Color, depth: int) -> StyleBoxFlat:
	var style := box(fill, lip, 16, 2, 8, depth)
	style.border_color = lip
	style.content_margin_bottom = 8 + depth
	style.expand_margin_bottom = 0
	return style

## Round icon button. "close" is the kit's red sticker; the others keep a flat
## round candy face with a Glyph.
func round_icon(icon: String, action: Callable, kind := "ghost", side := 50.0) -> Button:
	if icon == "close":
		return sticker_button("close", action, side)
	var palette: Array = CANDY.get(kind, CANDY.sun)
	var node := candy("", action, kind)
	node.custom_minimum_size = Vector2(side, side)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var radius := int(side / 2)
	node.add_theme_stylebox_override("normal", lipped(palette[0], palette[1], 6))
	node.add_theme_stylebox_override("hover", lipped(palette[0].lightened(0.1), palette[1], 6))
	node.add_theme_stylebox_override("pressed", lipped(palette[0].darkened(0.06), palette[1], 2))
	node.add_theme_stylebox_override("hover_pressed", lipped(palette[0].darkened(0.06), palette[1], 2))
	node.add_theme_stylebox_override("disabled", lipped(Color("c3cfe0"), Color("9fb0c8"), 6))
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color(1, 1, 1, 0.9), radius, 3, 8))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		(node.get_theme_stylebox(state) as StyleBoxFlat).set_corner_radius_all(radius)
	var tint: Color = SKY.darkened(0.15) if kind == "ghost" else Color.WHITE
	var glyph := Glyph.new(icon, tint, side * 0.46)
	glyph.position = Vector2(side, side * 0.92) * 0.27
	glyph.size = Vector2(side, side) * 0.46
	node.add_child(glyph)
	return node

## A kit sticker that is itself the button: brighter on hover, smaller on press.
func sticker_button(name: String, action: Callable, side := 50.0) -> Button:
	var node := Button.new()
	node.focus_mode = Control.FOCUS_ALL
	node.custom_minimum_size = Vector2(side, side)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	node.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color(1, 1, 1, 0.9), int(side / 2), 3, 0))
	var art := sticker(name, side)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.pivot_offset = Vector2(side, side) / 2
	node.add_child(art)
	node.mouse_entered.connect(func(): art.modulate = Color(1.1, 1.1, 1.1))
	node.mouse_exited.connect(func(): art.modulate = Color.WHITE)
	node.button_down.connect(func(): art.scale = Vector2.ONE * 0.92)
	node.button_up.connect(func(): art.scale = Vector2.ONE)
	node.pressed.connect(action)
	return node

func sized(control: Control, minimum: Vector2) -> Control:
	control.custom_minimum_size = minimum
	return control

func picture(path: String, side: Vector2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = icon_texture(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = side
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## Item and bomb PNGs are shown whole: items are clean 512 px icons and the
## bomb sprites were repaired and recentred (a trim would cut them again).
static func icon_texture(path: String) -> Texture2D:
	if path == "":
		return null
	# Server art cached by CatalogSync lives in user://; bundled art in res://.
	var source: Texture2D = HeroPortrait.for_path(path)
	if source != null:
		return source
	if path.begins_with("user://"):
		var sync = Engine.get_main_loop().root.get_node_or_null("CatalogSync")
		source = sync.texture(path) if sync else null
	elif ResourceLoader.exists(path):
		source = load(path)
	if source == null:
		return null
	return source

func stretch(node: Label) -> Label:
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text = true
	return node

func spacer(parent: Control, vertical := false) -> Control:
	var node := Control.new()
	if vertical:
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return ("-" if value < 0 else "") + out

func _process(_delta: float) -> void:
	var viewport := size if embedded else get_viewport_rect().size
	sky.position = Vector2.ZERO
	sky.size = viewport
	# Never let content wider/taller than the design (bold fonts, long names) spill
	# past the window: shrink to fit the larger of the two.
	var need := DESIGN
	for child in canvas.get_children():
		if child is Control and child.visible and child != modal:
			need = need.max((child as Control).get_combined_minimum_size())
	var ratio := minf(viewport.x / need.x, viewport.y / need.y)
	if ratio <= 0.0:
		return  # not laid out yet (an embedded page before its first layout)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = Vector2.ZERO
	canvas.size = viewport / ratio
