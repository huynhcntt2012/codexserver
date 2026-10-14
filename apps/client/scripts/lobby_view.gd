extends Node2D
## Animated departure lounge. All readiness and occupants come from snapshots.

const Pilot = preload("res://scripts/pilot_art.gd")
const MINT := Color("63e6be")
const MUTED := Color("91aeb9")
var snapshot: Dictionary = {}
var local_id := ""
var connected := false
var elapsed := 0.0
var font := ThemeDB.fallback_font


func _process(delta: float) -> void:
	if visible:
		elapsed += delta
		queue_redraw()


func _text(value: String, pos: Vector2, size: int, color: Color, width := -1.0) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)


func _ellipse(center: Vector2, radius: float, color: Color, line := false) -> void:
	draw_set_transform(center, 0, Vector2(1, 0.3))
	if line:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, color, 2, true)
	else:
		draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	# Perspective deck and slow ambient fireflies, kept inside the board panel.
	for i in range(9):
		draw_line(Vector2(380, 300), Vector2(54 + i * 81, 694), Color("19343f"), 1, true)
	for y in [390, 442, 510, 596, 694]:
		draw_line(Vector2(52, y), Vector2(708, y), Color("1e3b44"), 1, true)
	for i in range(24):
		var pos := Vector2(62 + (i * 139) % 640, 264 + fmod(i * 71.0 - elapsed * (4 + i % 3), 410.0))
		var alpha := 0.15 + (sin(elapsed * 1.4 + i) + 1) * 0.15
		draw_circle(pos, 2 if i % 3 == 0 else 1, Color(MINT, alpha))
	_text("PHI ĐỘI SUNI  /  NEON GARDEN", Vector2(60, 170), 13, MINT)
	_text("Sẵn sàng cho cuộc vui?" if not connected else "Tập hợp phi đội", Vector2(60, 211), 30, Color("edf7f5"))
	_text("Những phi công nhỏ. Những pha thoát hiểm lớn." if not connected else "Cùng sẵn sàng để khởi hành vào Neon Garden.", Vector2(60, 239), 16, MUTED)
	if not connected:
		_draw_welcome()
	else:
		_draw_slots()
	_text("01   NEON GARDEN", Vector2(64, 676), 14, MINT)
	_text("2–8 phi công   ·   180 giây   ·   Sống sót cuối cùng", Vector2(64, 702), 14, MUTED)


func _draw_welcome() -> void:
	_ellipse(Vector2(380, 554), 255, Color(MINT, 0.04))
	_ellipse(Vector2(380, 554), 248, Color(MINT, 0.25), true)
	_ellipse(Vector2(380, 554), 205, Color(MINT, 0.14), true)
	for i in [1, 2, 0]:
		var center: Vector2 = [Vector2(380, 531), Vector2(190, 492), Vector2(570, 492)][i]
		var zoom := 4.5 if i == 0 else 2.8
		var color: Color = Pilot.COLORS[i]
		_ellipse(center + Vector2(0, 24), zoom * 20, Color(color, 0.09))
		_ellipse(center + Vector2(0, 24), zoom * 19, Color(color, 0.6), true)
		_ellipse(center + Vector2(0, 18), zoom * 12, Color("0b1c29"))
		draw_set_transform(center - Vector2(22, 39) * zoom, 0, Vector2.ONE * zoom)
		Pilot.paint(self, i, elapsed, false, Vector2.DOWN, i == 0)
		draw_set_transform(Vector2.ZERO)
	_text("CHƠI CÙNG BẠN BÈ", Vector2(278, 613), 19, Color("edf7f5"))
	_text("Vào phòng  →  Sẵn sàng  →  Bùng nổ!", Vector2(241, 639), 15, MUTED)


func _draw_slots() -> void:
	var players: Array = snapshot.get("players", [])
	for slot in range(8):
		var player: Dictionary = {}
		for candidate in players:
			if int(candidate.slot) == slot:
				player = candidate
				break
		var center := Vector2(140 + (slot % 4) * 160, 405 + (slot / 4) * 192)
		var occupied := not player.is_empty()
		var color: Color = Pilot.COLORS[slot] if occupied else Color("41616e")
		var ready: bool = player.get("ready", false)
		var own: bool = occupied and player.id == local_id
		_ellipse(center, 61, Color(color, 0.12 if occupied else 0.04))
		_ellipse(center, 60, Color(color, 0.8 if ready else 0.3), true)
		_ellipse(center - Vector2(0, 5), 47, Color("112732"))
		if occupied:
			draw_set_transform(center - Vector2(44, 83), 0, Vector2.ONE * 2)
			Pilot.paint(self, slot, elapsed, false, Vector2.DOWN, ready)
			draw_set_transform(Vector2.ZERO)
			var name_text := String(player.name)
			if name_text.length() > 13:
				name_text = name_text.substr(0, 11) + "…"
			var name_width := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			_text(name_text, center + Vector2(-name_width / 2, 33), 14, color)
			_text("SẴN SÀNG" if ready else "ĐANG CHỜ", center + Vector2(-37, 54), 11, MINT if ready else MUTED)
			if own:
				_text("BẠN", center + Vector2(-14, -101), 11, MINT)
		else:
			draw_line(center + Vector2(-7, -7), center + Vector2(7, -7), color, 2, true)
			draw_line(center + Vector2(0, -14), center, color, 2, true)
			_text("CHỜ PHI CÔNG", center + Vector2(-45, 33), 11, color)
