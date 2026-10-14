extends RefCounted
## Shared original vector-pixel pilot, drawn in a 44 × 44 local canvas.

const COLORS := [
	Color("63e6be"), Color("ffbc72"), Color("a995ff"), Color("ff789d"),
	Color("77ccff"), Color("ffe27c"), Color("e0aaff"), Color("c3ed8b")
]


static func paint(canvas: CanvasItem, slot: int, time: float, walking := false,
		facing := Vector2.DOWN, celebrate := false) -> void:
	var color: Color = COLORS[posmod(slot, COLORS.size())]
	var ink := Color("102536")
	var bob := sin(time * (15.0 if walking else 2.8) + slot) * (1.5 if walking else 0.7)
	var step := sin(time * 15.0) * 2.5 if walking else 0.0
	var look := facing.x * 2.0
	var wave := sin(time * 6.0 + slot) * 2.0 if celebrate else 0.0
	# The small asymmetries, scarf and helmet attachments distinguish each pilot.
	canvas.draw_rect(Rect2(4, 20 + bob, 8, 13), ink)
	canvas.draw_rect(Rect2(5, 21 + bob, 4, 9), color.darkened(0.35))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(10, 24 + bob), Vector2(2, 27 + bob),
		Vector2(1 + step, 34 + bob), Vector2(11, 29 + bob)
	]), color.lightened(0.2))
	canvas.draw_rect(Rect2(11, 33 + step, 9, 8), ink)
	canvas.draw_rect(Rect2(25, 33 - step, 9, 8), ink)
	canvas.draw_rect(Rect2(12, 33 + step, 7, 3), color.lightened(0.18))
	canvas.draw_rect(Rect2(26, 33 - step, 7, 3), color.lightened(0.18))
	canvas.draw_rect(Rect2(10, 22 + bob, 25, 14), ink)
	canvas.draw_rect(Rect2(12, 23 + bob, 21, 11), color.darkened(0.18))
	canvas.draw_rect(Rect2(19, 26 + bob, 8, 6), color.lightened(0.35))
	canvas.draw_rect(Rect2(22, 27 + bob, 2, 4), Color("ffffff"))
	canvas.draw_rect(Rect2(6, 26 + bob + step - wave, 6, 8), ink)
	canvas.draw_rect(Rect2(7, 26 + bob + step - wave, 4, 5), color)
	canvas.draw_rect(Rect2(33, 26 + bob - step - absf(wave) * 3, 6, 8), ink)
	canvas.draw_rect(Rect2(34, 26 + bob - step - absf(wave) * 3, 4, 5), color)
	canvas.draw_rect(Rect2(10, 3 + bob, 24, 23), ink)
	canvas.draw_rect(Rect2(6, 7 + bob, 32, 15), ink)
	canvas.draw_rect(Rect2(11, 4 + bob, 22, 21), color)
	canvas.draw_rect(Rect2(8, 8 + bob, 28, 13), color)
	canvas.draw_rect(Rect2(12, 5 + bob, 16, 3), color.lightened(0.45))
	canvas.draw_rect(Rect2(9, 18 + bob, 26, 4), color.darkened(0.15))
	canvas.draw_rect(Rect2(11 + look, 10 + bob, 23, 11), ink)
	canvas.draw_rect(Rect2(13 + look, 11 + bob, 19, 3), Color("2d586b"))
	canvas.draw_rect(Rect2(13 + look, 11 + bob, 7, 1), Color("548994"))
	var blink := fmod(time + float(slot) * 0.37, 4.6) > 4.43
	for eye in [17, 27]:
		canvas.draw_rect(Rect2(eye + look, 15 + bob, 3, 1 if blink or celebrate else 4), Color("e7fff9"))
		if celebrate:
			canvas.draw_rect(Rect2(eye - 1 + look, 16 + bob, 1, 2), Color("e7fff9"))
	canvas.draw_rect(Rect2(8, 11 + bob, 3, 7), color.lightened(0.3))
	match posmod(slot, 4):
		0:
			canvas.draw_line(Vector2(27, 3 + bob), Vector2(30, -2 + bob), ink, 2)
			canvas.draw_circle(Vector2(30, -3 + bob), 2, color.lightened(0.4))
		1:
			canvas.draw_rect(Rect2(14, 1 + bob, 5, 5), color.lightened(0.35))
			canvas.draw_rect(Rect2(25, 1 + bob, 5, 5), color.lightened(0.35))
		2:
			canvas.draw_rect(Rect2(19, -1 + bob, 5, 8), color.lightened(0.4))
			canvas.draw_rect(Rect2(20, -2 + bob, 3, 3), Color("fff0b5"))
		3:
			canvas.draw_line(Vector2(10, 8 + bob), Vector2(6, 2 + bob), color.lightened(0.3), 3)
			canvas.draw_line(Vector2(33, 8 + bob), Vector2(37, 2 + bob), color.lightened(0.3), 3)
