extends Control
## Popup header (lobby popups, notices, settings overlay, kit notices): a blue
## ribbon with the title in yellow on a dark outline, little stars, and the two
## mascots (Bombo left, Mimi right, animated portraits) holding its ends. An
## optional icon (a Glyph from the caller) sits by Bombo. `compact` is the
## smaller version for small notices.
const HeroPortrait := preload("res://scripts/hero_portrait.gd")

const RIBBON := Color("2f86e8")
const RIBBON_DARK := Color("1b4f9e")
const RIBBON_LIGHT := Color("6fb6ff")
const TITLE := Color("ffe14d")
const TITLE_EDGE := Color("123f86")
const STAR := Color("ffd23c")

var title_label := Label.new()
var compact := false
var _banner := Banner.new()
var _left := TextureRect.new()
var _right := TextureRect.new()
var _icon: Control

## The ribbon itself (drawn): rounded body, darker lip, light top rim, stars.
class Banner extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func star(at: Vector2, r: float, color: Color) -> void:
		var points := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			points.append(at + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(points, color)

	func _draw() -> void:
		var h := size.y
		var body := Rect2(Vector2(0, h * 0.08), Vector2(size.x, h * 0.84))
		var radius := body.size.y * 0.5
		var lip := StyleBoxFlat.new()
		lip.bg_color = RIBBON_DARK
		lip.set_corner_radius_all(int(radius))
		lip.anti_aliasing = true
		draw_style_box(lip, Rect2(body.position + Vector2(0, h * 0.07), body.size))
		var face := StyleBoxFlat.new()
		face.bg_color = RIBBON
		face.border_color = Color.WHITE
		face.set_border_width_all(maxi(3, int(h * 0.05)))
		face.set_corner_radius_all(int(radius))
		face.anti_aliasing = true
		draw_style_box(face, body)
		var shine := StyleBoxFlat.new()
		shine.bg_color = Color(RIBBON_LIGHT, 0.55)
		shine.set_corner_radius_all(int(radius * 0.6))
		shine.anti_aliasing = true
		draw_style_box(shine, Rect2(body.position + Vector2(radius * 0.6, h * 0.14), Vector2(body.size.x - radius * 1.2, body.size.y * 0.26)))
		for s in [[0.16, 0.5, 0.11], [0.84, 0.5, 0.11], [0.07, 0.86, 0.07], [0.93, 0.18, 0.07]]:
			star(Vector2(size.x * s[0], h * s[1]), h * s[2], STAR)

func _init(is_compact := false) -> void:
	compact = is_compact
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 96 if compact else 70)
	add_child(_banner)
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32 if compact else 46)
	title_label.add_theme_color_override("font_color", TITLE)
	title_label.add_theme_color_override("font_outline_color", TITLE_EDGE)
	title_label.add_theme_constant_override("outline_size", 12 if compact else 16)
	title_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.16, 0.4, 0.5))
	title_label.add_theme_constant_override("shadow_offset_y", 3)
	_banner.add_child(title_label)
	for side in [_left, _right]:
		side.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		side.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(side)
	_left.texture = HeroPortrait.texture("bombo")
	_right.texture = HeroPortrait.texture("mimi")
	_right.flip_h = true
	resized.connect(layout)
	title_label.minimum_size_changed.connect(layout)

func set_title(value: String) -> void:
	title_label.text = value
	layout()

## Icon by the left mascot (e.g. a Glyph trophy); null removes it.
func set_icon(node: Control) -> void:
	if _icon and is_instance_valid(_icon):
		_icon.queue_free()
	_icon = node
	if node:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(node)
	layout()

## The ribbon straddles the popup's top edge: everything is drawn `lift` px above
## this control (popups do not clip), as in the design.
func layout() -> void:
	var h := 150.0 if not compact else 110.0
	var lift := h - custom_minimum_size.y + (34.0 if not compact else 10.0)
	var text_width := title_label.get_combined_minimum_size().x
	var width := minf(size.x - h * 1.6, text_width + h * 1.9)
	width = maxf(width, h * 2.4)
	var banner_h := h * 0.66
	_banner.size = Vector2(width, banner_h)
	_banner.position = Vector2((size.x - width) * 0.5, h - banner_h - h * 0.04 - lift)
	title_label.position = Vector2.ZERO
	title_label.size = _banner.size - Vector2(0, banner_h * 0.08)
	var face := h * 1.02
	_left.size = Vector2(face, face)
	_left.position = Vector2(_banner.position.x - face * 0.62, h - face - lift)
	_right.size = Vector2(face, face)
	_right.position = Vector2(_banner.position.x + width - face * 0.38, h - face - lift)
	if _icon:
		var side := h * 0.5
		_icon.size = Vector2(side, side)
		_icon.position = Vector2(_banner.position.x + side * 0.05, h - banner_h - side * 0.55 - lift)
	_banner.queue_redraw()
