extends RefCounted
## Shared Game Boom design tokens. UI art can later override these with 9-slice.
const NAVY = Color("082c68")
const DEEP = Color("0e4c9c")
const BLUE = Color("126ec8")
const LIGHT = Color("bdeaff")
const YELLOW = Color("ffca44")
const PINK = Color("f76db5")
const PURPLE = Color("aa68e8")
const MINT = Color("5ed6a0")
const WHITE = Color("f7fbff")

static func box(fill: Color, stroke: Color = LIGHT, radius: int = 16, stroke_width: int = 2) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(stroke_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.02, 0.08, 0.24, 0.26)
	style.shadow_offset = Vector2(0, 4)
	style.shadow_size = 5
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

static func panel(p: PanelContainer, kind: String = "blue") -> void:
	var s: StyleBoxFlat
	match kind:
		"card": s = box(Color("d6f1ff"), Color("54cafa"), 17, 3)
		"gold": s = box(Color("fdbb44"), Color("fff29e"), 20, 3)
		"pink": s = box(Color("bb3e91"), Color("ffbbe5"), 18, 3)
		"hero": s = box(Color("145ea8"), Color("70e0ff"), 24, 3)
		"soft": s = box(Color("11519c"), Color("328ad5"), 13, 1)
		_: s = box(Color("0c408c"), Color("69d6ff"), 20, 3)
	p.add_theme_stylebox_override("panel", s)

static func button(b: Button, kind: String = "blue") -> void:
	var base = BLUE
	var stroke = Color("6cd5ff")
	if kind == "gold":
		base = Color("ffc037"); stroke = Color("fff6ad")
	elif kind == "pink":
		base = PINK; stroke = Color("ffd3ec")
	elif kind == "muted":
		base = Color("4576a7"); stroke = Color("6ba3d5")
	b.add_theme_stylebox_override("normal", box(base, stroke, 14, 2))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.14), stroke.lightened(0.13), 14, 2))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.16), stroke, 14, 2))
	b.add_theme_stylebox_override("disabled", box(Color("647e9e"), Color("889eaf"), 14, 2))
	b.add_theme_color_override("font_color", NAVY if kind == "gold" else WHITE)
	b.add_theme_color_override("font_hover_color", NAVY if kind == "gold" else WHITE)
	b.add_theme_color_override("font_pressed_color", NAVY if kind == "gold" else WHITE)
	b.add_theme_color_override("font_disabled_color", Color("c4d5e3"))
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 44.0)

static func heading(label: Label, size: int = 25, color: Color = WHITE) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare": return PURPLE
		"epic": return PINK
		"legendary": return Color("ff8d3c")
		_: return BLUE
