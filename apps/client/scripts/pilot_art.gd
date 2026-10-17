extends RefCounted
## User-supplied starter art. Sheet layout: 2 columns × 10 rows, 64px cells.
static var selected := -1
const NAMES := ["BOMBO", "MIMI", "ZIN", "LALA", "KAI"]
const COLORS := [Color("2baaff"), Color("ff6da9"), Color("ff6959"), Color("ffbe3c"), Color("5cdc90"), Color("2baaff"), Color("ff6da9"), Color("ff6959")]
const ART := [preload("res://art/boom/characters/portraits/bombo.png"), preload("res://art/boom/characters/portraits/mimi.png"), preload("res://art/boom/characters/portraits/zin.png"), preload("res://art/boom/characters/portraits/lala.png"), preload("res://art/boom/characters/portraits/kai.png")]
const SHEETS := [preload("res://art/boom/spritesheets/bombo.png"), preload("res://art/boom/spritesheets/mimi.png"), preload("res://art/boom/spritesheets/zin.png"), preload("res://art/boom/spritesheets/lala.png"), preload("res://art/boom/spritesheets/kai.png")]


static func paint(canvas: CanvasItem, slot: int, time: float, walking := false,
		facing := Vector2.DOWN, celebrate := false) -> void:
	var row := 8 if celebrate else 0
	if walking and not celebrate:
		if absf(facing.x) > absf(facing.y):
			row = 4 if facing.x > 0 else 3
		else:
			row = 1 if facing.y >= 0 else 2
	var frame := int(time * 6.0) % 2
	canvas.draw_texture_rect_region(SHEETS[posmod(slot, 5)], Rect2(0, -3, 44, 44), Rect2(frame * 64, row * 64, 64, 64))
