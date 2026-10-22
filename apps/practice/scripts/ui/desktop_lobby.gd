extends Control
## PC-only home. The grid lists every MAP (built-in and admin-published) with live
## counts of online rooms/players on it (arena GET /rooms/v2). "Vào" joins an open
## room on that map, or the server opens a new one (rooms appear on demand).
## Bot practice stays available offline from its own button; friends and chat use
## the account API, ranked shows an honest empty state.
const PopupHeader := preload("res://scripts/ui/popup_header.gd")
const DESIGN := Vector2(1920, 1080)
const PAGE_SIZE := 8
const INK := Color("345581")
const SKY := Color("1569b3")
const LINE := Color("8fe3f3")
## One palette for every top-menu tab, so all five light up the same way.
## Icon tabs: no box when idle; the open tab gets a soft glow and a yellow caption.
## [fill, border, sparkle tint, caption]
const NAV_ON := [Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.55), Color("ffe17b"), Color("ffe17b")]
const NAV_OFF := [Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color.WHITE]
const NAV_HOME := 0
const NAV_SHOP := 1
const NAV_EQUIPMENT := 2
const NAV_MISSIONS := 3
const NAV_RANKING := 4
const MISSIONS_SECONDS := 60.0
const TIER_COLORS := {"Dễ": Color("4fa8ef"), "Trung bình": Color("ffaa45"), "Khó": Color("f4738d")}
const FOLD := {
	"a": "àáạảãâầấậẩẫăằắặẳẵ", "e": "èéẹẻẽêềếệểễ", "i": "ìíịỉĩ", "o": "òóọỏõôồốộổỗơờớợởỡ",
	"u": "ùúụủũưừứựửữ", "y": "ỳýỵỷỹ", "d": "đ",
}
const ScreenFill := preload("res://scripts/ui/screen_fill.gd")
const SocialClient := preload("res://scripts/ui/social/social_client.gd")
const FriendsPanel := preload("res://scripts/ui/social/friends_panel.gd")
const ChatPanel := preload("res://scripts/ui/social/chat_panel.gd")
const HeroPreview := preload("res://scripts/ui/hero_preview.gd")

## Small vector icons so the lobby needs no unverified icon assets.
class Glyph extends Control:
	var kind := ""
	var tint := Color.WHITE:
		set(value):
			tint = value
			queue_redraw()
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

	## Dark rim that gives the colour icons their sticker look.
	func outline(points: Array) -> void:
		var out := PackedVector2Array()
		for p in points:
			out.append(pt(p[0], p[1]))
		out.append(out[0])
		draw_polyline(out, Color("0d2f5c", 0.55), 0.035 * _s, true)

	## Small twinkle in the tint colour (transparent on idle tabs).
	func sparkle() -> void:
		if tint.a <= 0.01:
			return
		var c := pt(0.9, 0.12)
		var r := 0.1 * _s
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.3, -r * 0.3), c + Vector2(r, 0), c + Vector2(r * 0.3, r * 0.3), c + Vector2(0, r), c + Vector2(-r * 0.3, r * 0.3), c + Vector2(-r, 0), c + Vector2(-r * 0.3, -r * 0.3)]), tint)

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
			"user":
				draw_circle(pt(0.5, 0.3), 0.2 * _s, tint)
				var body := []
				for i in 13:
					body.append([0.5 + cos(PI + i * PI / 12) * 0.36, 0.95 + sin(PI + i * PI / 12) * 0.4])
				poly(body)
			"keyboard":
				draw_rect(Rect2(pt(0.04, 0.24), Vector2(0.92, 0.52) * _s), tint)
				for r in 3:
					for c in 6:
						draw_rect(Rect2(pt(0.1 + c * 0.14, 0.31 + r * 0.13), Vector2(0.1, 0.08) * _s), tint.darkened(0.45))
				draw_rect(Rect2(pt(0.26, 0.66), Vector2(0.48, 0.05) * _s), tint.darkened(0.45))
			"monitor":
				draw_rect(Rect2(pt(0.06, 0.12), Vector2(0.88, 0.58) * _s), tint)
				draw_rect(Rect2(pt(0.13, 0.19), Vector2(0.74, 0.44) * _s), tint.darkened(0.45))
				draw_rect(Rect2(pt(0.43, 0.7), Vector2(0.14, 0.14) * _s), tint)
				draw_rect(Rect2(pt(0.26, 0.84), Vector2(0.48, 0.08) * _s), tint)
			"pad":
				var pad := []
				for i in 25:
					var a := i * TAU / 24
					pad.append([0.5 + cos(a) * 0.44, 0.52 + sin(a) * 0.26])
				poly(pad)
				var ink := tint.darkened(0.55)
				draw_line(pt(0.18, 0.52), pt(0.38, 0.52), ink, 0.08 * _s, true)
				draw_line(pt(0.28, 0.42), pt(0.28, 0.62), ink, 0.08 * _s, true)
				draw_circle(pt(0.68, 0.46), 0.05 * _s, tint.darkened(0.45))
				draw_circle(pt(0.78, 0.56), 0.05 * _s, tint.darkened(0.45))
			"globe":
				draw_arc(pt(0.5, 0.5), 0.4 * _s, 0, TAU, 32, tint, 0.08 * _s, true)
				draw_set_transform(pt(0.5, 0.5), 0.0, Vector2(0.45, 1.0))
				draw_arc(Vector2.ZERO, 0.4 * _s, 0, TAU, 32, tint, 0.07 * _s, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				line([0.1, 0.5], [0.9, 0.5], 0.07)
				line([0.5, 0.1], [0.5, 0.9], 0.07)
			"music":
				line([0.4, 0.2], [0.4, 0.74], 0.09)
				line([0.78, 0.12], [0.78, 0.64], 0.09)
				poly([[0.4, 0.16], [0.82, 0.08], [0.82, 0.24], [0.4, 0.32]])
				draw_circle(pt(0.3, 0.76), 0.13 * _s, tint)
				draw_circle(pt(0.68, 0.66), 0.13 * _s, tint)
			"bell":
				poly([[0.5, 0.1], [0.72, 0.26], [0.76, 0.62], [0.9, 0.76], [0.1, 0.76], [0.24, 0.62], [0.28, 0.26]])
				draw_circle(pt(0.5, 0.86), 0.09 * _s, tint)
			"mic":
				draw_rect(Rect2(pt(0.36, 0.08), Vector2(0.28, 0.5) * _s), tint)
				draw_circle(pt(0.5, 0.1), 0.14 * _s, tint)
				draw_arc(pt(0.5, 0.46), 0.26 * _s, 0, PI, 16, tint, 0.07 * _s, true)
				line([0.5, 0.72], [0.5, 0.9], 0.07)
				line([0.3, 0.92], [0.7, 0.92], 0.07)
			"link":
				for c in [[0.36, 0.64], [0.64, 0.36]]:
					draw_set_transform(pt(c[0], c[1]), -PI / 4, Vector2(1.0, 0.6))
					draw_arc(Vector2.ZERO, 0.24 * _s, 0, TAU, 24, tint, 0.09 * _s, true)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"phone":
				draw_rect(Rect2(pt(0.28, 0.06), Vector2(0.44, 0.88) * _s), tint)
				draw_rect(Rect2(pt(0.33, 0.14), Vector2(0.34, 0.62) * _s), tint.darkened(0.45))
				draw_circle(pt(0.5, 0.85), 0.04 * _s, tint.darkened(0.45))
			"shield":
				poly([[0.5, 0.06], [0.88, 0.2], [0.82, 0.6], [0.5, 0.94], [0.18, 0.6], [0.12, 0.2]])
				draw_circle(pt(0.5, 0.46), 0.12 * _s, tint.darkened(0.45))
			"logout":
				draw_rect(Rect2(pt(0.12, 0.12), Vector2(0.4, 0.76) * _s), tint, false, 0.08 * _s)
				line([0.42, 0.5], [0.9, 0.5], 0.09)
				line([0.74, 0.34], [0.9, 0.5], 0.09)
				line([0.74, 0.66], [0.9, 0.5], 0.09)
			"sun":
				draw_circle(pt(0.5, 0.5), 0.2 * _s, tint)
				for i in 8:
					var a := i * PI / 4
					line([0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3], [0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44], 0.08)
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
			"nav_home":
				draw_rect(Rect2(pt(0.66, 0.1), Vector2(0.12, 0.24) * _s), Color("e2405f"))
				var walls := [[0.18, 0.42], [0.82, 0.42], [0.82, 0.94], [0.18, 0.94]]
				poly(walls, Color("fff3d6"))
				outline(walls)
				var roof := [[0.5, 0.06], [0.98, 0.48], [0.86, 0.53], [0.5, 0.22], [0.14, 0.53], [0.02, 0.48]]
				poly(roof, Color("ff8a3d"))
				outline(roof)
				poly([[0.5, 0.22], [0.86, 0.53], [0.14, 0.53]], Color("ffb36b"))
				draw_rect(Rect2(pt(0.42, 0.62), Vector2(0.18, 0.32) * _s), Color("b5651d"))
				draw_rect(Rect2(pt(0.24, 0.56), Vector2(0.13, 0.13) * _s), Color("7fd3ff"))
				sparkle()
			"nav_shop":
				var body := [[0.13, 0.44], [0.87, 0.44], [0.87, 0.94], [0.13, 0.94]]
				poly(body, Color("4fb7f5"))
				outline(body)
				draw_rect(Rect2(pt(0.4, 0.62), Vector2(0.2, 0.32) * _s), Color.WHITE)
				draw_rect(Rect2(pt(0.08, 0.12), Vector2(0.84, 0.12) * _s), Color("e2405f"))
				for i in 5:
					var x0 := 0.08 + i * 0.168
					var stripe := [[x0, 0.24], [x0 + 0.168, 0.24], [x0 + 0.168, 0.4], [x0, 0.4]]
					poly(stripe, Color("f4627d") if i % 2 == 0 else Color("fff6f0"))
					draw_circle(pt(x0 + 0.084, 0.4), 0.084 * _s, Color("f4627d") if i % 2 == 0 else Color("fff6f0"))
				outline([[0.08, 0.12], [0.92, 0.12], [0.92, 0.4], [0.08, 0.4]])
				sparkle()
			"nav_bag":
				draw_arc(pt(0.5, 0.24), 0.16 * _s, PI, TAU, 16, Color("1d4f8a"), 0.07 * _s, true)
				var bag := [[0.18, 0.3], [0.82, 0.3], [0.88, 0.42], [0.88, 0.9], [0.8, 0.96], [0.2, 0.96], [0.12, 0.9], [0.12, 0.42]]
				poly(bag, Color("3d8ff0"))
				outline(bag)
				poly([[0.18, 0.3], [0.82, 0.3], [0.88, 0.42], [0.88, 0.52], [0.12, 0.52], [0.12, 0.42]], Color("5aa8ff"))
				var pocket := [[0.28, 0.62], [0.72, 0.62], [0.72, 0.86], [0.28, 0.86]]
				poly(pocket, Color("8fd0ff"))
				outline(pocket)
				draw_rect(Rect2(pt(0.45, 0.58), Vector2(0.1, 0.1) * _s), Color("ffc93c"))
				sparkle()
			"nav_trophy":
				draw_arc(pt(0.2, 0.3), 0.13 * _s, PI / 2, PI * 1.5, 12, Color("e39b14"), 0.07 * _s, true)
				draw_arc(pt(0.8, 0.3), 0.13 * _s, -PI / 2, PI / 2, 12, Color("e39b14"), 0.07 * _s, true)
				var cup := [[0.2, 0.1], [0.8, 0.1], [0.74, 0.46], [0.6, 0.6], [0.4, 0.6], [0.26, 0.46]]
				poly(cup, Color("ffc93c"))
				outline(cup)
				poly([[0.3, 0.14], [0.42, 0.14], [0.38, 0.48], [0.3, 0.4]], Color("ffe7a0"))
				draw_rect(Rect2(pt(0.44, 0.58), Vector2(0.12, 0.16) * _s), Color("e39b14"))
				var base := [[0.26, 0.74], [0.74, 0.74], [0.78, 0.94], [0.22, 0.94]]
				poly(base, Color("b5651d"))
				outline(base)
				sparkle()
			"nav_star":
				var points := []
				for i in 10:
					var r := 0.48 if i % 2 == 0 else 0.24
					var a := -PI / 2 + i * PI / 5
					points.append([0.5 + cos(a) * r, 0.54 + sin(a) * r])
				poly(points, Color("ffc93c"))
				outline(points)
				draw_circle(pt(0.5, 0.56), 0.15 * _s, Color("3d8ff0"))
				draw_circle(pt(0.5, 0.56), 0.15 * _s, Color("1d4f8a"), false, 0.03 * _s, true)
				draw_circle(pt(0.45, 0.51), 0.04 * _s, Color(1, 1, 1, 0.8))
				sparkle()
			"edit":
				poly([[0.2, 0.68], [0.62, 0.26], [0.78, 0.42], [0.36, 0.84]])
				poly([[0.66, 0.22], [0.74, 0.14], [0.9, 0.3], [0.82, 0.38]], tint.darkened(0.15))
				poly([[0.2, 0.68], [0.36, 0.84], [0.12, 0.92]], Color("ffd257"))
			"add_user":
				draw_circle(pt(0.38, 0.3), 0.17 * _s, tint)
				var body := []
				for i in 13:
					var a := PI + i * PI / 12
					body.append([0.38 + cos(a) * 0.3, 0.92 + sin(a) * 0.34])
				poly(body)
				line([0.82, 0.3], [0.82, 0.62], 0.11)
				line([0.66, 0.46], [0.98, 0.46], 0.11)

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
var modal_nav := -1
var top_bar: Control
var nav_tabs: Array[Dictionary] = []
var nav_index := -1
var store := Control.new()
var store_title: Label
var store_header: Control
var mail_badge: Label
var store_area: Control
var store_pages: Dictionary = {}
var toast: Label
var toast_tween: Tween
var modal_title: Label
var modal_icon: Glyph
var modal_message: Label
var modal_packs: VBoxContainer
var modal_ok: Button
var modal_extra: Button
var modal_extra_action := Callable()
var social: Node = SocialClient.new()
var chat: Control
var friends_panel: VBoxContainer
var search := LineEdit.new()
var tier_select := OptionButton.new()
var map_select := OptionButton.new()
var profile: Label
var level: Label
var xp: ProgressBar
var xp_percent: Label
var name_input: LineEdit
var hero_line: Label
var portrait: Control
var presence: Label
var summary: Label
var empty: Label
var page_label: Label
var prev_page: Button
var next_page: Button
var speaker: Glyph
var gold: Label
var gem: Label
var hero_list: VBoxContainer
var hero_scroll: ScrollContainer
var hero_buttons: Array[Button] = []
var hero_states: Array[Label] = []
## Eight reusable map cards (one page); filled from `maps` + `rooms` on refresh.
var map_cards: Array[Dictionary] = []
## Raw v2 listings: roomId, number, map, phase, players, maxPlayers, joinable, accountIds.
var rooms: Array = []
var friend_ids: Array = []
## signed_out | loading | ok | error
var rooms_state := "loading"
var rooms_error := ""
var rooms_clock := 0.0
var rooms_busy := false
var friends_clock := 0.0
const ROOMS_SECONDS := 5.0
const FRIENDS_SECONDS := 20.0
var joining := false
var mission_dot: Panel
var missions_clock := 0.0
var missions_busy := false
## The open map-grid popup (title, message, button prefix, action) for refreshes.
var map_grid: Array = []
var only_open := false
var only_friends := false
var open_toggle: Button
var friends_toggle: Button
var maps: Array[Dictionary] = []
var tier_filter := ""
var map_filter := -1
var page := 0
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
	node.texture = CatalogSync.texture(path)
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
	add_child(social)
	social.friend_request_arrived.connect(func(who): show_toast("%s muốn kết bạn với bạn" % who))
	chat = ChatPanel.new(self, social)
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
	chat.build_bar(page_root)
	canvas.add_child(chat)
	build_store()
	build_modal()
	build_toast()
	UIState.toast_requested.connect(show_toast)
	UIState.wallet_changed.connect(refresh)
	UIState.loadout_changed.connect(refresh)
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
	top_bar = bar
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
		["nav_home", "Sảnh chính", go_home],
		["nav_shop", "Cửa hàng", func(): open_shop("shop")],
		["nav_bag", "Trang bị", func(): open_shop("equipment")],
		["nav_trophy", "Nhiệm vụ", func(): open_shop("missions")],
		["nav_star", "Xếp hạng", func(): open_shop("ranking")],
	]
	for i in nav.size():
		var tab := button("", nav[i][2], NAV_OFF[0], INK, 20, 18, NAV_OFF[1])
		tab.name = "Nav_" + nav[i][0]
		tab.custom_minimum_size = Vector2(128, 104)
		line.add_child(tab)
		var stack := column(2, tab)
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glyph := Glyph.new(nav[i][0], NAV_OFF[2], 60)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stack.add_child(glyph)
		var caption := text(nav[i][1], 18, NAV_OFF[3], stack)
		caption.add_theme_color_override("font_outline_color", Color("0d3f78"))
		caption.add_theme_constant_override("outline_size", 6)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nav_tabs.append({"button": tab, "glyph": glyph, "caption": caption})
		if i == NAV_MISSIONS:
			# Red dot: a mission reward is waiting (GET /v1/quests "claimable").
			mission_dot = Panel.new()
			mission_dot.name = "MissionDot"
			mission_dot.add_theme_stylebox_override("panel", box(Color("ff4d6a"), Color.WHITE, 12, 3))
			mission_dot.size = Vector2(24, 24)
			mission_dot.position = Vector2(96, 6)
			mission_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mission_dot.hide()
			tab.add_child(mission_dot)
	set_nav(NAV_HOME)
	spacer(line)
	gold = wallet(line, "coin", 250)
	gem = wallet(line, "gem", 210)
	var mail := icon_button("mail", func(): open_shop("mail"))
	mail.name = "Mail"
	line.add_child(mail)
	mail_badge = Label.new()
	mail_badge.name = "MailBadge"
	mail_badge.add_theme_font_size_override("font_size", 16)
	mail_badge.add_theme_color_override("font_color", Color.WHITE)
	mail_badge.add_theme_stylebox_override("normal", box(Color("ff4d6a"), Color.WHITE, 13, 3, 3))
	mail_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mail_badge.custom_minimum_size = Vector2(28, 28)
	mail_badge.position = Vector2(36, -10)
	mail_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mail_badge.hide()
	mail.add_child(mail_badge)
	line.add_child(icon_button("gear", open_settings))
	# Far right X: quit the game (asks first). Friends live in the left column tab.
	var quit := icon_button("close", confirm_quit, 58, Color("f4738d"), 29)
	quit.name = "QuitGame"
	quit.tooltip_text = "Thoát game"
	line.add_child(quit)

func wallet(parent: Control, icon: String, width: float) -> Label:
	var holder := card(Color("0f5a9c"), Color("7fd9ef"), 36, 3, 6)
	holder.custom_minimum_size = Vector2(width, 66)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)
	var line := row(10, holder)
	line.add_child(Glyph.new(icon, Color.WHITE, 46))
	var amount := text("", 28, Color.WHITE, line)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(icon_button("plus", open_topup, 40, Color("2fa8ec"), 20))
	return amount

func build_left(parent: Control) -> void:
	var side := column(20, parent)
	side.custom_minimum_size = Vector2(380, 0)
	# Profile card: hero art on the lagoon scene, then rank badge, name (editable),
	# level and XP percentage.
	var me := card(Color("1567ae"), LINE, 26, 4, 10)
	me.name = "ProfileCard"
	side.add_child(me)
	var me_stack := column(10, me)
	var art := card(Color("8fd3f5"), Color.WHITE, 20, 3, 0)
	art.custom_minimum_size = Vector2(0, 236)
	art.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	me_stack.add_child(art)
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(stage)
	var scene := picture("res://assets/ui/launch/bg_lagoon.png", Vector2.ZERO)
	scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(scene)
	portrait = HeroPreview.new()
	portrait.name = "HeroPreview"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_top = 10
	stage.add_child(portrait)
	hero_line = pill("", Color(0.05, 0.18, 0.36, 0.72), Color.WHITE, 15)
	var hero_tag := hero_line.get_parent() as Control
	hero_tag.position = Vector2(10, 10)
	stage.add_child(hero_tag)
	presence = pill("", Color("3fd39a"), Color("0d4b3a"), 14)
	var presence_tag := presence.get_parent() as Control
	presence_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	presence_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	presence_tag.offset_left = -10
	presence_tag.offset_top = 10
	presence_tag.offset_right = -10
	stage.add_child(presence_tag)
	var info := card(Color("0f4f8f"), Color("2f7fc0"), 18, 2, 10)
	me_stack.add_child(info)
	var info_line := row(12, info)
	var badge := Glyph.new("nav_star", Color(1, 1, 1, 0), 58)
	badge.tooltip_text = "Hạng"
	info_line.add_child(badge)
	var facts := column(4, info_line)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_line := row(6, facts)
	profile = stretch(text("", 26, Color.WHITE, name_line))
	profile.name = "ProfileName"
	var rename := icon_button("edit", open_rename, 40, Color("2fa8ec"), 12)
	rename.name = "RenameButton"
	rename.tooltip_text = "Đổi tên hiển thị"
	name_line.add_child(rename)
	var level_line := row(8, facts)
	level = text("", 18, Color("ffd257"), level_line)
	xp = ProgressBar.new()
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(0, 16)
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp.add_theme_stylebox_override("background", box(Color("0a3566"), Color.TRANSPARENT, 8))
	xp.add_theme_stylebox_override("fill", box(Color("ffc93c"), Color.TRANSPARENT, 8))
	level_line.add_child(xp)
	xp_percent = text("", 15, Color("d5f3ff"), level_line)
	var social_box := card(Color("1567ae"), LINE, 26, 4, 14)
	social_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(social_box)
	var social_stack := column(12, social_box)
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
	friends_panel = FriendsPanel.new(self, social)
	social_stack.add_child(friends_panel)
	friends_panel.hide()
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
		["TÌM TRẬN NHANH", "Vào phòng online còn chỗ", Color("ffd56b"), "res://assets/ui/launch/mascot_pip.png", quick_play],
		["TẠO PHÒNG", "Mở phòng online, tối đa 8 người", Color("8fdcf5"), "res://assets/ui/launch/mascot_nop.png", open_create],
		["LUYỆN TẬP", "Chọn bản đồ, chơi offline", Color("d4bdf7"), "", open_practice],
		["SĂN BOSS", "Cả đội 1-8 người hạ Boss sự kiện", Color("ff9ec0"), "", open_boss],
	]
	for spec in mode_specs:
		var big := button("", spec[4], spec[2], INK, 20, 26)
		big.name = "Mode_" + fold(spec[0]).replace(" ", "_")
		big.custom_minimum_size = Vector2(0, 112)
		big.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(big)
		var inner := row(18, big)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 18
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[3] != "":
			inner.add_child(picture(spec[3], Vector2(72, 72)))
		else:
			inner.add_child(Glyph.new("star", Color("ff4d6a") if spec[0] == "SĂN BOSS" else Color("ffd84d"), 66))
		var words := column(4, inner)
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stretch(text(spec[0], 25, Color("8a4b1f") if spec[0] == "TÌM TRẬN NHANH" else INK, words))
		stretch(text(spec[1], 15, Color("6a5a7a"), words))
	var filters := card(Color("1660a6"), LINE, 30, 4, 12)
	main.add_child(filters)
	var bar := row(14, filters)
	MapCatalog.changed.connect(fill_selects)
	style_select(tier_select, "Tất cả độ khó", tiers())
	tier_select.item_selected.connect(func(index): set_tier(tier_select.get_item_text(index) if index > 0 else ""))
	bar.add_child(tier_select)
	var names: Array[String] = []
	for map in maps:
		names.append(str(map.name).capitalize())
	style_select(map_select, "Tất cả bản đồ", names)
	map_select.item_selected.connect(func(index): set_map(index - 1))
	bar.add_child(map_select)
	open_toggle = check_toggle("Chỉ phòng trống", "Chỉ hiện bản đồ đang có phòng còn ghế, vào được ngay", func(on): only_open = on; page = 0; refresh())
	open_toggle.name = "OnlyOpen"
	bar.add_child(open_toggle)
	friends_toggle = check_toggle("Chỉ bạn bè", "Chỉ hiện bản đồ có bạn bè đang ở trong phòng", func(on): only_friends = on; page = 0; refresh())
	friends_toggle.name = "OnlyFriends"
	bar.add_child(friends_toggle)
	var field := card(Color("0f4f8f"), LINE, 26, 3, 4)
	field.custom_minimum_size = Vector2(300, 56)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(field)
	var field_line := row(8, field)
	search.placeholder_text = "Tìm bản đồ…"
	search.tooltip_text = "Số hoặc tên bản đồ (không cần dấu)"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 14))
	search.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 14))
	search.add_theme_font_size_override("font_size", 21)
	search.add_theme_color_override("font_color", Color.WHITE)
	search.add_theme_color_override("font_placeholder_color", Color("b9dcf3"))
	search.text_changed.connect(func(_value): page = 0; refresh())
	search.text_submitted.connect(func(_value): join_first_match())
	field_line.add_child(search)
	field_line.add_child(Glyph.new("search", Color.WHITE, 34))
	var list := column(12, main)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.name = "RoomGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	list.add_child(grid)
	for i in PAGE_SIZE:
		grid.add_child(map_card())
	empty = text("", 22, Color("ffe17b"), list)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.custom_minimum_size = Vector2(0, 120)
	var footer := row(16, main)
	summary = stretch(text("", 20, Color.WHITE, footer))
	summary.size_flags_stretch_ratio = 1.0
	var pager := card(Color("1660a6"), LINE, 34, 3, 6)
	pager.custom_minimum_size = Vector2(300, 0)
	footer.add_child(pager)
	var pager_line := row(10, pager)
	prev_page = icon_button("left", func(): page -= 1; refresh(), 52, Color("3aa6e6"), 26)
	pager_line.add_child(prev_page)
	page_label = text("", 24, Color.WHITE, pager_line)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_page = icon_button("right", func(): page += 1; refresh(), 52, Color("3aa6e6"), 26)
	pager_line.add_child(next_page)
	var balance := spacer(footer)
	balance.size_flags_stretch_ratio = 1.0

## Checkbox in the filter bar: white rounded box with a tick, then the label.
func check_toggle(label_text: String, hint: String, action: Callable) -> Button:
	var node := Button.new()
	node.toggle_mode = true
	node.focus_mode = Control.FOCUS_ALL
	node.tooltip_text = hint
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var hover: bool = state.begins_with("hover")
		node.add_theme_stylebox_override(state, box(Color(1, 1, 1, 0.08) if hover else Color.TRANSPARENT, Color("ffe17b") if state == "focus" else Color.TRANSPARENT, 12, 2 if state == "focus" else 0, 6))
	var line := row(10, node)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick_box := card(Color("0f4f8f"), Color.WHITE, 8, 3, 0)
	tick_box.custom_minimum_size = Vector2(32, 32)
	tick_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tick_box)
	var tick := Glyph.new("check", Color("ffe17b"), 24)
	tick.hide()
	tick_box.add_child(tick)
	var label := text(label_text, 21, Color.WHITE, line)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	# Width follows the label once the lobby font applies (bolder on Windows).
	node.custom_minimum_size = Vector2(0, 56)
	line.minimum_size_changed.connect(func(): node.custom_minimum_size.x = line.get_combined_minimum_size().x + 18)
	node.toggled.connect(func(on): tick.visible = on)
	node.toggled.connect(action)
	return node

func style_select(select: OptionButton, all: String, entries: Array[String]) -> void:
	select.add_item(all)
	for entry in entries:
		select.add_item(entry)
	select.custom_minimum_size = Vector2(250, 56)
	select.add_theme_font_size_override("font_size", 21)
	select.add_theme_stylebox_override("normal", box(Color("2a86d0"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("hover", box(Color("3596df"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("pressed", box(Color("1f75bb"), LINE, 16, 3, 14))
	select.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color("ffe17b"), 16, 3, 14))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		select.add_theme_color_override(state, Color.WHITE)
	select.get_popup().add_theme_font_size_override("font_size", 20)

## One reusable slot of the map grid: thumbnail, number, map name, difficulty,
## people and open rooms on that map, "Mới" for admin maps, and "Vào".
func map_card() -> PanelContainer:
	var slot := map_cards.size()
	var holder := card(Color("e9fbff"), Color("b8e9f7"), 22, 4, 10)
	holder.name = "Map%d" % slot
	holder.custom_minimum_size = Vector2(0, 118)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var line := row(14, holder)
	var thumb := card(Color("bfeeff"), Color("2f8fd0"), 12, 3, 2)
	thumb.custom_minimum_size = Vector2(132, 92)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(thumb)
	var art := picture("", Vector2(126, 86))
	thumb.add_child(art)
	var facts := column(8, line)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := row(10, facts)
	var number := pill("000", Color("1d78bd"), Color.WHITE, 17, head)
	var title := stretch(text("", 24, INK, head))
	var meta := row(10, facts)
	var mode := pill("", Color("4fa8ef"), Color.WHITE, 16, meta)
	meta.add_child(Glyph.new("people", Color("2f7fc0"), 24))
	var count := stretch(text("", 19, INK, meta))
	count.name = "Players"
	var fresh := pill("Mới", Color("ff7083"), Color.WHITE, 14, meta)
	fresh.tooltip_text = "Bản đồ do admin thêm"
	var choice := button("Vào", func(): enter_slot(slot), Color("ffcb52"), Color("8a4b1f"), 22, 16)
	choice.name = "Join"
	choice.custom_minimum_size = Vector2(124, 58)
	choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choice.add_theme_stylebox_override("disabled", box(Color("9fc6e3"), Color("d6ecfa"), 16, 3, 8))
	choice.add_theme_color_override("font_disabled_color", Color.WHITE)
	line.add_child(choice)
	map_cards.append({"holder": holder, "art": art, "number": number, "title": title, "mode": mode, "count": count, "fresh": fresh, "button": choice, "map": {}})
	return holder

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
	var modal_header := PopupHeader.new(true)
	head.add_child(modal_header)
	modal_title = modal_header.title_label
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
	modal_packs = column(10, stack)
	name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.max_length = 24
	name_input.custom_minimum_size = Vector2(600, 60)
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.add_theme_color_override("font_color", INK)
	name_input.add_theme_stylebox_override("normal", box(Color.WHITE, Color("b8e9f7"), 16, 3, 14))
	name_input.add_theme_stylebox_override("focus", box(Color.WHITE, SKY, 16, 3, 14))
	name_input.text_submitted.connect(func(_value): save_name())
	name_input.hide()
	stack.add_child(name_input)
	var actions := row(16, stack)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_extra = button("", func(): var action := modal_extra_action; close_modal(); action.call(), Color("3fd39a"), Color("0d4b3a"), 24, 22)
	modal_extra.name = "ModalAction"
	modal_extra.custom_minimum_size = Vector2(300, 66)
	actions.add_child(modal_extra)
	modal_ok = button("ĐÃ HIỂU", close_modal, Color("ffcb52"), Color("8a4b1f"), 24, 22)
	modal_ok.custom_minimum_size = Vector2(260, 66)
	actions.add_child(modal_ok)

func open_modal(title: String, icon: String, message: String, with_settings := false, nav := -1) -> void:
	modal_nav = nav
	modal_title.text = title
	modal_icon.set_kind(icon)
	modal_message.text = message
	modal_message.visible = message != ""
	modal_icon.get_parent().show()
	modal_packs.hide()
	name_input.hide()
	modal_ok.text = "ĐÓNG" if with_settings else "ĐÃ HIỂU"
	modal_extra.hide()
	modal_extra_action = Callable()
	tint_extra(Color("3fd39a"), Color("0d4b3a"))
	modal.show()
	modal_ok.grab_focus()
	sync_nav()

## Second, highlighted button on the open popup (e.g. "KẾT BẠN" on a profile).
func modal_action(label: String, action: Callable) -> void:
	modal_extra.text = label
	modal_extra_action = action
	modal_extra.show()
	modal_ok.text = "ĐÓNG"
	modal_extra.grab_focus()

func close_modal() -> void:
	modal.hide()
	sync_nav()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if modal.visible:
		close_modal()
		get_viewport().set_input_as_handled()
	elif store.visible:
		close_store()
		get_viewport().set_input_as_handled()
	elif chat.visible:
		chat.close()
		get_viewport().set_input_as_handled()
	else:
		confirm_quit()
		get_viewport().set_input_as_handled()

## Quit popup: "Ở LẠI" is focused, so Enter/Esc never quits by accident.
func confirm_quit() -> void:
	open_modal("THOÁT GAME", "close", "Bạn có chắc muốn thoát BỤP BỤP không?")
	modal_action("THOÁT", quit_game)
	tint_extra(Color("f4738d"), Color.WHITE)
	modal_ok.text = "Ở LẠI"
	modal_ok.grab_focus()

## Colours the popup's second button (green by default, coral for quitting).
func tint_extra(fill: Color, color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var style := modal_extra.get_theme_stylebox(state) as StyleBoxFlat
		style.bg_color = fill.lightened(0.15) if state == "hover" else (fill.darkened(0.12) if state == "pressed" else fill)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		modal_extra.add_theme_color_override(state, color)

func quit_game() -> void:
	if OnlineArena.connected:
		OnlineArena.leave()
	get_tree().quit()

## Lights the tab for whatever is open: a notice's own tab, the store page, else home.
func sync_nav() -> void:
	if modal.visible and modal_nav >= 0:
		set_nav(modal_nav)
	elif store.visible:
		var shown := ""
		for key in store_pages:
			if store_pages[key].visible:
				shown = key
		set_nav({"equipment": NAV_EQUIPMENT, "missions": NAV_MISSIONS, "ranking": NAV_RANKING, "boss": NAV_HOME, "settings": NAV_HOME, "mail": NAV_HOME}.get(shown, NAV_SHOP))
	else:
		set_nav(NAV_HOME)

## Fades the old tab out and the new one in, with a small bounce on its icon.
func set_nav(index: int) -> void:
	if index == nav_index:
		return
	var first := nav_index < 0
	nav_index = index
	for i in nav_tabs.size():
		var tab: Dictionary = nav_tabs[i]
		var colors: Array = NAV_ON if i == index else NAV_OFF
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var time := 0.0 if first else 0.22
		for state in ["normal", "hover", "pressed"]:
			var style := (tab.button as Button).get_theme_stylebox(state) as StyleBoxFlat
			var fill: Color = colors[0]
			if state == "hover":
				fill = Color(1, 1, 1, maxf(fill.a, 0.1))
			elif state == "pressed":
				fill = fill.darkened(0.12)
			tween.tween_property(style, "bg_color", fill, time)
			tween.tween_property(style, "border_color", colors[1], time)
		tween.tween_property(tab.glyph, "tint", colors[2], time)
		tween.tween_property(tab.caption, "theme_override_colors/font_color", colors[3], time)
		var glyph: Glyph = tab.glyph
		glyph.pivot_offset = glyph.custom_minimum_size / 2
		if i == index and not first:
			glyph.scale = Vector2.ONE * 1.3
			tween.set_trans(Tween.TRANS_BACK).tween_property(glyph, "scale", Vector2.ONE, 0.32)
		else:
			glyph.scale = Vector2.ONE

func go_home() -> void:
	close_modal()
	close_store()
	refresh()

## Shop and equipment open as a popup over the lobby, framed like the notices.
func build_store() -> void:
	store.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	store.mouse_filter = Control.MOUSE_FILTER_STOP
	store.hide()
	canvas.add_child(store)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.16, 0.36, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: close_store())
	store.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	store.add_child(center)
	var sheet := card(Color("fff9e9"), Color.WHITE, 34, 6, 22)
	var frame := sheet.get_theme_stylebox("panel") as StyleBoxFlat
	frame.shadow_color = Color(0.02, 0.12, 0.3, 0.45)
	frame.shadow_size = 18
	frame.shadow_offset = Vector2(0, 10)
	center.add_child(sheet)
	var stack := column(14, sheet)
	var head := row(12, stack)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(54, 0)
	head.add_child(balance)
	store_header = PopupHeader.new()
	head.add_child(store_header)
	store_title = store_header.title_label
	head.add_child(icon_button("close", close_store, 54, Color("f4738d"), 27))
	store_area = Control.new()
	store_area.custom_minimum_size = Vector2(1700, 760)
	stack.add_child(store_area)

## Pages are built on first use; the kit scales them to the popup's rect.
func store_page(target: String) -> Control:
	if not store_pages.has(target):
		var scripts := {"shop": preload("res://scripts/ui/pc/pc_shop.gd"), "equipment": preload("res://scripts/ui/pc/pc_equipment.gd"), "missions": preload("res://scripts/ui/pc/pc_missions.gd"), "ranking": preload("res://scripts/ui/pc/pc_leaderboard.gd"), "settings": preload("res://scripts/ui/pc/pc_settings.gd"), "mail": preload("res://scripts/ui/pc/pc_mail.gd"), "boss": preload("res://scripts/ui/pc/pc_boss.gd")}
		var page_node = scripts[target].new()
		if target == "missions":
			page_node.claimable_changed.connect(set_mission_dot)
		if target == "mail":
			page_node.unread_changed.connect(set_mail_badge)
		if target == "boss":
			page_node.play.connect(play_boss)
		page_node.embedded = true
		page_node.navigate.connect(_on_store_navigate)
		store_area.add_child(page_node)
		store_pages[target] = page_node
	return store_pages[target]

func _on_store_navigate(destination: String) -> void:
	if destination == "logout":
		leave()
	elif destination == "home":
		close_store()
	else:
		open_shop(destination)

func open_shop(target: String) -> void:
	modal.hide()
	var shown := store_page(target)
	if target == "settings":
		shown.hero_id = game.HEROES[game.selected_hero]
	for key in store_pages:
		store_pages[key].visible = store_pages[key] == shown
	store_header.set_icon(Glyph.new({"shop": "shop", "equipment": "nav_bag", "missions": "nav_trophy", "ranking": "trophy", "settings": "gear", "mail": "mail", "boss": "star"}.get(target, "star"), Color("ffc93c"), 56))
	store_title.text = {"shop": "CỬA HÀNG", "equipment": "TRANG BỊ", "missions": "NHIỆM VỤ & SỰ KIỆN", "ranking": "BẢNG XẾP HẠNG", "settings": "CÀI ĐẶT", "mail": "HỘP THƯ", "boss": "ĐẠI CHIẾN BOSS"}[target]
	store.show()
	sync_nav()

func close_store() -> void:
	store.hide()
	sync_nav()
	refresh()

func build_toast() -> void:
	toast = pill("", Color("2d4a7a", 0.92), Color.WHITE, 22)
	var holder := toast.get_parent() as Control
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_bottom = -120
	holder.hide()
	canvas.add_child(holder)

func show_toast(message: String) -> void:
	if is_instance_valid(toast_tween):
		toast_tween.kill()
	var holder := toast.get_parent() as Control
	toast.text = message
	holder.modulate.a = 1.0
	holder.reset_size()
	holder.show()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.0)
	toast_tween.tween_property(holder, "modulate:a", 0.0, 0.4)
	toast_tween.tween_callback(holder.hide)

func guest_name() -> String:
	var prefs := ConfigFile.new()
	prefs.load("user://launch_preferences.cfg")
	return str(prefs.get_value("profile", "guest_name", "Khách"))

## Pencil next to the name: signed-in players rename on the server (others see it);
## guests keep a nickname on this computer only.
func open_rename() -> void:
	var signed_in := AuthSession.has_session()
	open_modal("ĐỔI TÊN HIỂN THỊ", "edit", "2–24 ký tự: chữ, số, khoảng trắng, dấu . _ -" + ("" if signed_in else "\nChế độ khách: chỉ lưu trên máy này."))
	name_input.text = profile.text
	name_input.show()
	modal_action("LƯU TÊN", save_name)
	name_input.grab_focus()
	name_input.select_all()

func save_name() -> void:
	var value := " ".join(name_input.text.strip_edges().split(" ", false))
	# Length only here (Godot regex \\w is ASCII); the API checks the characters.
	if value.length() < 2 or value.length() > 24 or Array("<>{}\"'`\\/".split("")).any(func(c): return value.contains(c)):
		open_rename()
		modal_message.text = "Tên chưa hợp lệ: cần 2–24 ký tự gồm chữ, số, khoảng trắng hoặc . _ -"
		name_input.text = value
		return
	close_modal()
	if AuthSession.has_session():
		var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_PATCH, "/v1/me", {"display_name": value})
		if reply.status != 200 or not reply.data is Dictionary:
			show_toast("Chưa đổi được tên: " + str(reply.error))
			return
		AuthSession.account_name = str(reply.data.get("name", value))
	else:
		var prefs := ConfigFile.new()
		prefs.load("user://launch_preferences.cfg")
		prefs.set_value("profile", "guest_name", value)
		prefs.save("user://launch_preferences.cfg")
	show_toast("Đã đổi tên thành " + value)
	refresh()

## Wallet "+": sandbox packs from the API (no payment provider, nothing charged).
func open_topup() -> void:
	if not AuthSession.has_session():
		notice("Đăng nhập tài khoản để nạp kim cương và đổi vàng. Chế độ khách dùng ví demo trên máy.", "NẠP", "gem")
		return
	open_modal("NẠP KIM CƯƠNG / ĐỔI VÀNG", "gem", "Đang tải gói nạp…")
	modal_ok.text = "ĐÓNG"
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/topup/packs")
	if not modal.visible:
		return
	if reply.status != 200 or not reply.data is Dictionary:
		modal_message.text = "Chưa tải được gói nạp: " + str(reply.error)
		return
	modal_message.text = "Bản thử nghiệm: không có thanh toán thật, không thu tiền. Giao dịch được ghi vào lịch sử tài khoản."
	for child in modal_packs.get_children():
		modal_packs.remove_child(child)
		child.queue_free()
	for pack in reply.data.get("packs", []):
		var id := str(pack.id)
		var price := ("%s đ" % grouped(int(pack.vnd))) if pack.has("vnd") else ("%d kim cương" % int(pack.gem_cost))
		var option := button("%s  —  %s" % [pack.name, price], func(): buy_pack(id, str(pack.name)), Color("e4f7ff"), INK, 22, 18, Color("b8e9f7"))
		option.name = "Pack_" + id
		option.custom_minimum_size = Vector2(600, 60)
		modal_packs.add_child(option)
	modal_packs.show()

func buy_pack(pack_id: String, pack_name: String) -> void:
	for option in modal_packs.get_children():
		(option as Button).disabled = true
	var ok: bool = await UIState.topup(pack_id)
	for option in modal_packs.get_children():
		(option as Button).disabled = false
	if ok:
		show_toast("Đã nạp " + pack_name)
		refresh()

## Gear: the settings window (scripts/ui/pc/pc_settings.gd) in the store popup.
func open_settings() -> void:
	open_shop("settings")

func show_social(tab: int) -> void:
	hero_scroll.visible = tab == 0
	friends_panel.visible = tab == 1

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
## Map list for filters, cards and "Tạo phòng": the built-in levels plus maps an
## admin published (MapCatalog); rebuilt whenever that list changes.
func load_maps() -> void:
	maps.clear()
	for data in MapCatalog.all():
		var subtitle := str(data.get("subtitle", ""))
		var map := {
			"id": str(data.get("id", "")),
			"name": str(data.get("name", "")),
			"subtitle": subtitle,
			"tier": subtitle.get_slice("•", 0).strip_edges(),
			"columns": int(data.get("columns", 15)),
			"rows": int(data.get("rows", 11)),
			"story": str(data.get("story", "")),
			"custom": bool(data.get("custom", false)),
		}
		map.keywords = fold(" ".join([map.id, map.name, subtitle, str(data.get("theme", ""))]))
		maps.append(map)

## Refills the difficulty and map dropdowns, keeping the chosen filters.
func fill_selects() -> void:
	var map_id: String = maps[map_filter].id if map_filter >= 0 and map_filter < maps.size() else ""
	load_maps()
	tier_select.clear()
	tier_select.add_item("Tất cả độ khó")
	for tier in tiers():
		tier_select.add_item(tier)
	tier_select.select(maxi(0, tiers().find(tier_filter) + 1))
	map_select.clear()
	map_select.add_item("Tất cả bản đồ")
	for map in maps:
		map_select.add_item(str(map.name).capitalize())
	map_filter = map_index(map_id) if map_id != "" else -1
	map_select.select(map_filter + 1)
	if modal.visible and modal_packs.find_child("MapGrid", true, false) and not map_grid.is_empty():
		open_map_grid(map_grid[0], map_grid[1], map_grid[2], map_grid[3])
	refresh()

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

func map_index(map_id: String) -> int:
	for i in maps.size():
		if maps[i].id == map_id:
			return i
	return -1

## Online activity on one map: people, open rooms, a friend seated, and the room
## "Vào" should join (a friend's open room first, then the fullest open one).
func map_stats(map_id: String) -> Dictionary:
	var stats := {"players": 0, "rooms": 0, "open": 0, "friend": false, "join": {}}
	var best_score := -1
	for room in rooms:
		if not room is Dictionary or str(room.get("map", "")) != map_id:
			continue
		stats.players += int(room.get("players", 0))
		stats.rooms += 1
		var friend := has_friend(room)
		stats.friend = stats.friend or friend
		if bool(room.get("joinable", false)):
			stats.open += 1
			var score := int(room.get("players", 0)) + (100 if friend else 0)
			if score > best_score:
				best_score = score
				stats.join = room
	return stats

## Filters, all combined: difficulty, map, "Chỉ phòng trống" (the map has an open
## room with a free seat), "Chỉ bạn bè" (an accepted friend is in a room on it) and
## the search words (map number or name, diacritics ignored).
func map_matches(index: int) -> bool:
	var map: Dictionary = maps[index]
	if tier_filter != "" and map.tier != tier_filter:
		return false
	if map_filter >= 0 and map_filter != index:
		return false
	var stats := map_stats(map.id)
	if only_open and int(stats.open) == 0:
		return false
	if only_friends and not stats.friend:
		return false
	var haystack := "%03d %d %s" % [index + 1, index + 1, map.keywords]
	for word in fold(search.text).split(" ", false):
		if not haystack.contains(word):
			return false
	return true

func has_friend(room: Dictionary) -> bool:
	for id in room.get("accountIds", []):
		if friend_ids.has(str(id)):
			return true
	return false

func visible_maps() -> Array[int]:
	var found: Array[int] = []
	for i in maps.size():
		if map_matches(i):
			found.append(i)
	return found

## Enter in the search box enters the first matching map.
func join_first_match() -> void:
	var found := visible_maps()
	if not found.is_empty():
		enter_map(str(maps[found[0]].id))

func page_count() -> int:
	return maxi(1, ceili(visible_maps().size() / float(PAGE_SIZE)))

func fill_card(slot: Dictionary, index: int) -> void:
	var map: Dictionary = maps[index]
	slot.map = map
	slot.art.texture = MapCatalog.preview(map.id)
	slot.number.text = "%03d" % (index + 1)
	slot.title.text = str(map.name).capitalize()
	slot.title.tooltip_text = "%s · %s\n%s" % [slot.title.text, map.subtitle, map.story]
	slot.mode.text = map.tier if map.tier != "" else "Đấu thường"
	(slot.mode.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).bg_color = TIER_COLORS.get(map.tier, Color("4fa8ef"))
	(slot.fresh as Label).get_parent().visible = bool(map.get("custom", false))
	var stats := map_stats(map.id)
	var button: Button = slot.button
	button.disabled = joining
	if rooms_state != "ok":
		slot.count.text = "%d×%d" % [map.columns, map.rows]
		button.tooltip_text = "Đăng nhập để chơi online trên bản đồ này"
	elif int(stats.rooms) == 0:
		slot.count.text = "Chưa có phòng"
		button.tooltip_text = "Mở phòng mới trên bản đồ này"
	else:
		slot.count.text = "%d người · %d phòng" % [stats.players, stats.rooms]
		var room: Dictionary = stats.join
		button.tooltip_text = ("Vào phòng %03d (%d/%d)" % [int(room.number), int(room.players), int(room.maxPlayers)]) if not room.is_empty() else "Các phòng đang chơi hoặc đã đầy: mở phòng mới"
	slot.count.tooltip_text = button.tooltip_text
	var frame := slot.holder.get_theme_stylebox("panel") as StyleBoxFlat
	frame.border_color = Color("ffc93c") if stats.friend else Color("b8e9f7")

func refresh() -> void:
	var hero: int = game.selected_hero
	profile.text = AuthSession.account_name if AuthSession.has_session() else guest_name()
	profile.tooltip_text = profile.text
	level.text = "Lv. %d" % int(UIState.profile.get("level", 1))
	xp.max_value = maxf(1.0, float(UIState.profile.get("xp_max", 1)))
	xp.value = float(UIState.profile.get("xp", 0))
	xp_percent.text = "%d%%" % int(round(100.0 * xp.value / xp.max_value))
	hero_line.text = game.HERO_NAMES[hero].capitalize()
	portrait.show_hero(game.HEROES[hero], UIState.profile.get("loadout", {}))
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
	for i in map_cards.size():
		map_cards[i].holder.visible = i < shown.size()
		if i < shown.size():
			fill_card(map_cards[i], shown[i])
	empty.visible = shown.is_empty()
	empty.text = "Chưa có bản đồ nào có phòng còn chỗ hoặc có bạn bè. Bỏ bớt bộ lọc, hoặc bấm Vào để mở phòng mới." if only_open or only_friends else "Không có bản đồ khớp bộ lọc. Bỏ bớt bộ lọc hoặc đổi từ khóa."
	var people := 0
	for room in rooms:
		people += int(room.get("players", 0))
	match rooms_state:
		"ok": summary.text = "%d/%d bản đồ · %d phòng đang mở · %d người" % [found.size(), maps.size(), rooms.size(), people]
		"signed_out": summary.text = "%d/%d bản đồ · Đăng nhập để chơi online" % [found.size(), maps.size()]
		"error": summary.text = "%d/%d bản đồ · %s" % [found.size(), maps.size(), rooms_error]
		_: summary.text = "%d/%d bản đồ · Đang tải phòng…" % [found.size(), maps.size()]
	page_label.text = "%d / %d" % [page + 1, page_count()]
	prev_page.disabled = page == 0
	next_page.disabled = page >= page_count() - 1
	speaker.set_kind("speaker" if game.music_enabled else "mute")
	chat.set_system("[Hệ thống] Chào mừng bạn đến với BỤP BỤP! • Nhân vật: %s • Âm thanh: %s" % [game.HERO_NAMES[hero].capitalize(), "Bật" if game.music_enabled else "Tắt"])

static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return ("-" if value < 0 else "") + out

## Offline practice: matchmaking seats three bots, then the bot room opens.
func practice() -> void:
	game.show_pc_screen("matchmaking")

func hero_id() -> String:
	return game.HEROES[game.selected_hero]

func can_play_online() -> bool:
	if AuthSession.has_session():
		return true
	notice("Đăng nhập tài khoản để chơi phòng online với người khác. Chế độ khách chơi LUYỆN TẬP trên máy được.", "PHÒNG ONLINE", "people")
	return false

func enter_slot(slot: int) -> void:
	var map: Dictionary = map_cards[slot].map
	if not map.is_empty():
		enter_map(str(map.id))

## "Vào" on a map: an open room on it (a friend's first), else the server opens one.
func enter_map(map_id: String) -> void:
	if not can_play_online():
		return
	var room: Dictionary = map_stats(map_id).join
	if not room.is_empty():
		await enter_room(str(room.roomId))
	else:
		await go_online(func(): return await OnlineArena.quick_join(map_id, hero_id()), "Đang mở phòng…")

func enter_room(room_id: String) -> void:
	await go_online(func(): return await OnlineArena.join_room(room_id, hero_id()), "Đang vào phòng…")

## Quick play: the first open room (on the map filter, if one is set), else the
## server's joinOrCreate on that map (or the last chosen map).
func quick_play() -> void:
	for room in rooms:
		if bool(room.get("joinable", false)) and map_index(str(room.map)) >= 0 and (map_filter < 0 or map_index(str(room.map)) == map_filter):
			enter_room(str(room.roomId))
			return
	var map_id: String = maps[map_filter if map_filter >= 0 else clampi(game.selected_level, 0, maps.size() - 1)].id
	await go_online(func(): return await OnlineArena.quick_join(map_id, hero_id()), "Đang tìm phòng…")

## Map picker for a new online room: every map as a card (preview, name,
## difficulty, size), five per row; built-in and admin-published maps alike.
func open_create() -> void:
	if not can_play_online():
		return
	open_map_grid("TẠO PHÒNG ONLINE", "Chọn bản đồ. Phòng tối đa 8 người; ván bắt đầu khi mọi người đã Sẵn sàng (ít nhất 2 người).", "Create_", create_room)

## Offline practice starts by choosing the map (admin maps included).
func open_practice() -> void:
	open_map_grid("LUYỆN TẬP · CHỌN BẢN ĐỒ", "Chơi trên máy này: 1 người + 3 bot. Bản đồ “Mới” do admin thêm.", "Practice_", practice_on)

func practice_on(map_id: String) -> void:
	game._select_level(maxi(0, MapCatalog.index_of(map_id)))
	practice()

## Shared grid popup; reopened with the same action when the map list changes.
func open_map_grid(title: String, message: String, prefix: String, action: Callable) -> void:
	MapCatalog.refresh()
	map_grid = [title, message, prefix, action]
	open_modal(title, "people", message)
	modal_icon.get_parent().hide()
	modal_ok.text = "ĐÓNG"
	for child in modal_packs.get_children():
		modal_packs.remove_child(child)
		child.queue_free()
	var grid := GridContainer.new()
	grid.name = "MapGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	# Admins can keep adding maps: show three rows and scroll the rest.
	var scroll := ScrollContainer.new()
	scroll.name = "MapScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(5 * 228 + 4 * 12 + 16, mini(3, ceili(maps.size() / 5.0)) * (196 + 12))
	scroll.add_child(grid)
	modal_packs.add_child(scroll)
	for map in maps:
		grid.add_child(map_choice(map, prefix, action))
	modal_packs.show()

func map_choice(map: Dictionary, prefix: String, action: Callable) -> Button:
	var map_id: String = map.id
	var option := button("", func(): close_modal(); action.call(map_id), Color("e4f7ff"), INK, 18, 16, Color("b8e9f7"))
	option.name = prefix + map_id
	option.custom_minimum_size = Vector2(228, 196)
	option.tooltip_text = "%s · %s\n%s" % [str(map.name).capitalize(), map.subtitle, map.story]
	var stack := column(4, option)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 8
	stack.offset_right = -8
	stack.offset_top = 8
	stack.offset_bottom = -8
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := picture("", Vector2(200, 122))
	art.texture = MapCatalog.preview(map_id)
	stack.add_child(art)
	var title := stretch(text(str(map.name).capitalize(), 18, INK, stack))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var meta := row(6, stack)
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	pill(map.tier if map.tier != "" else "Đấu thường", TIER_COLORS.get(map.tier, Color("4fa8ef")), Color.WHITE, 14, meta)
	text("%d×%d" % [map.columns, map.rows], 14, Color("4b6a8a"), meta)
	if map.custom:
		pill("Mới", Color("ff7083"), Color.WHITE, 13, meta).tooltip_text = "Bản đồ do admin thêm"
	return option

## SĂN BOSS (docs/BOSS.md): the event page; Solo / Ghép đội / Phòng riêng from it.
func open_boss() -> void:
	if not can_play_online():
		return
	open_shop("boss")

func play_boss(event_id: String, mode: String) -> void:
	close_store()
	var message: String = {"solo": "Đang mở phòng Boss…", "team": "Đang ghép đội săn Boss…", "private": "Đang tạo phòng Boss riêng…"}.get(mode, "Đang vào phòng Boss…")
	await go_online(func(): return await OnlineArena.boss_room(event_id, hero_id(), mode == "team", mode == "private"), message)

func create_room(map_id: String) -> void:
	await go_online(func(): return await OnlineArena.create_room(map_id, hero_id()), "Đang tạo phòng…")

func go_online(attempt: Callable, message: String) -> void:
	if joining or not can_play_online():
		return
	joining = true
	refresh()
	show_toast(message)
	var ok: bool = await attempt.call()
	joining = false
	if ok:
		game.show_pc_screen("online")
	else:
		notice(OnlineArena.last_error, "PHÒNG ONLINE", "people")
		rooms_clock = 0.0
	refresh()


func notice(message: String, title := "THÔNG BÁO", icon := "star", nav := -1) -> void:
	open_modal(title, icon, message, false, nav)

func leave() -> void:
	UIState.remove_meta("from_desktop_lobby")
	AuthSession.logout()
	get_tree().change_scene_to_file("res://scenes/ui/launch/launch_screen.tscn")

func _exit_tree() -> void:
	ScreenFill.set_fill(get_tree(), false)

func set_mail_badge(count: int) -> void:
	if mail_badge:
		mail_badge.text = str(count) if count < 100 else "99+"
		mail_badge.visible = count > 0

func set_mission_dot(count: int) -> void:
	if mission_dot:
		mission_dot.visible = count > 0
		mission_dot.tooltip_text = "%d phần thưởng chờ nhận" % count

## Mission rewards waiting? Asked every minute while signed in (also the day's check-in).
func fetch_missions() -> void:
	if missions_busy or not AuthSession.has_session():
		set_mission_dot(0)
		set_mail_badge(0)
		return
	missions_busy = true
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/quests")
	if reply.status == 200 and reply.data is Dictionary:
		set_mission_dot(int(reply.data.get("claimable", 0)))
	# Unread mail for the badge on the mail button, on the same minute clock.
	var mail_reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/mail")
	missions_busy = false
	if mail_reply.status == 200 and mail_reply.data is Dictionary:
		set_mail_badge(int(mail_reply.data.get("unread", 0)))

## Live room list from the arena (every 5 s while the lobby shows) plus the
## accepted friends list for "Chỉ bạn bè" (every 20 s).
func fetch_rooms() -> void:
	if rooms_busy:
		return
	if not AuthSession.has_session():
		apply_rooms({"ok": false})
		return
	rooms_busy = true
	if friends_clock <= 0.0:
		friends_clock = FRIENDS_SECONDS
		friend_ids = await OnlineArena.friend_ids()
	var reply: Dictionary = await OnlineArena.list_rooms()
	rooms_busy = false
	apply_rooms(reply)

func apply_rooms(reply: Dictionary) -> void:
	if reply.get("ok", false):
		rooms = reply.rooms
		rooms_state = "ok"
		# A room on a map published after this app last asked: refresh the catalog.
		if rooms.any(func(room): return room is Dictionary and map_index(str(room.get("map", ""))) < 0):
			MapCatalog.refresh()
	else:
		rooms = []
		rooms_state = "error" if AuthSession.has_session() else "signed_out"
		rooms_error = str(reply.get("error", ""))
	if is_inside_tree():
		refresh()

func _process(delta: float) -> void:
	if is_visible_in_tree() and not store.visible:
		friends_clock -= delta
		rooms_clock -= delta
		if rooms_clock <= 0.0:
			rooms_clock = ROOMS_SECONDS
			fetch_rooms()
		missions_clock -= delta
		if missions_clock <= 0.0:
			missions_clock = MISSIONS_SECONDS
			fetch_missions()
	var viewport := get_viewport_rect().size
	backdrop.position = Vector2.ZERO
	backdrop.size = viewport
	# Fit the design size, or the content's minimum size when it is larger (wider
	# system fonts, long names), so the page is never cut off at the edges.
	var need := DESIGN
	for child in canvas.get_children():
		if child is Control and child.visible:
			need = need.max((child as Control).get_combined_minimum_size())
	var ratio := minf(viewport.x / need.x, viewport.y / need.y)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = Vector2.ZERO
	canvas.size = viewport / ratio
	# Popups dim the page but leave the top menu lit and clickable.
	for overlay in [modal, store]:
		overlay.offset_top = top_bar.size.y
	if is_visible_in_tree() and signed_in_on_entry and not AuthSession.has_session():
		leave()
