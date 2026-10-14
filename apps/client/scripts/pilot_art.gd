extends RefCounted
## Original vector companions, shared with the browser client.

static var selected := -1

const COLORS := [Color("ff95b8"), Color("83caf3"), Color("98ddb3"), Color("ffd57e"),
	Color("ff95b8"), Color("83caf3"), Color("98ddb3"), Color("ffd57e")]
const ART := [preload("res://art/bong.svg"), preload("res://art/may.svg"),
	preload("res://art/la.svg"), preload("res://art/nang.svg")]


static func paint(canvas: CanvasItem, slot: int, time: float, walking := false,
		_facing := Vector2.DOWN, celebrate := false) -> void:
	var bob := sin(time * (15.0 if walking else 2.8) + slot) * (1.5 if walking or celebrate else 0.5)
	canvas.draw_texture_rect(ART[posmod(slot, 4)], Rect2(3, -9 + bob, 38, 50), false)
