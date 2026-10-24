extends Control
## Boss HP bar of the raid HUD: the fill, a tick at each phase threshold and
## "hp / max". Values come from the server snapshot only.

var hp := 0.0
var max_hp := 1.0
var thresholds: Array = []
var weak := false

func _init() -> void:
	custom_minimum_size = Vector2(420, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(value: float, maximum: float, marks: Array, is_weak: bool) -> void:
	hp = value
	max_hp = maxf(1.0, maximum)
	thresholds = marks
	weak = is_weak
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("2a1640"))
	var share := clampf(hp / max_hp, 0.0, 1.0)
	var fill := Color("ffd84d") if weak else Color("ff4d6a").lerp(Color("8a2a4a"), 1.0 - share)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)), fill)
	for mark in thresholds:
		var x := rect.size.x * float(mark)
		draw_line(Vector2(x, 0), Vector2(x, rect.size.y), Color.WHITE, 3.0)
	draw_rect(rect, Color.WHITE, false, 2.0)
	var font := ThemeDB.fallback_font
	var label := "%d / %d" % [int(hp), int(max_hp)]
	draw_string_outline(font, Vector2(0, rect.size.y - 6), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, 5, Color("1b1030"))
	draw_string(font, Vector2(0, rect.size.y - 6), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color.WHITE)
