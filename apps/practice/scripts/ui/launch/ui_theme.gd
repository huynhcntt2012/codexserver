extends RefCounted
## Shared style tokens with Shop + Equipment: cream panels, aqua/peach/violet buttons.
const INK := Color("#554B77")
const AQUA := Color("#50CFCB")
const AQUA_DARK := Color("#259FB2")
const CREAM := Color("#FFF9E9")
const PURPLE := Color("#9F8DE0")
const PEACH := Color("#FFB46F")
const CORAL := Color("#F4738D")
const WHITE := Color("#FFFFFF")

static func box(fill: Color, border: Color, radius: int = 22, shadow: int = 0, border_width: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.15, 0.30, 0.52, 0.22)
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0, 6)
	return style

static func apply_button(button: Button, fill: Color, border: Color, font_size: int = 18, radius: int = 22) -> void:
	button.add_theme_stylebox_override("normal", box(fill, border, radius, 3))
	button.add_theme_stylebox_override("hover", box(fill.lightened(0.12), border.lightened(0.15), radius, 5))
	button.add_theme_stylebox_override("pressed", box(fill.darkened(0.11), border, radius, 1))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color("#FFFFFF"), radius, 0, 2))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_font_size_override("font_size", font_size)

static func apply_link(button: Button, color: Color = INK, font_size: int = 16) -> void:
	button.flat = true
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", CORAL)
	button.add_theme_color_override("font_pressed_color", AQUA_DARK)
	button.add_theme_font_size_override("font_size", font_size)

static func apply_label(label: Label, font_size: int = 18, color: Color = INK) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
