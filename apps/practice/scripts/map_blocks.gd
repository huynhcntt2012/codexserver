extends RefCounted
## Block art for a map. A level names one wall prop ("wall") and one crate prop
## ("crate") from assets/obstacles, and may list more in "walls" / "crates": each
## inner cell then picks one of them by its position, so a map mixes props but
## always looks the same. Admin maps with only "wall" / "crate" keep one prop each.
## Props are drawn standing on the tile's bottom edge, scaled to the tile width.

static func names(level: Dictionary, kind: String) -> Array:
	var many = level.get(kind + "s", [])
	if many is Array and not many.is_empty():
		return many
	return [str(level.get(kind, ""))]

## The outer border always uses the first prop, so the frame of the map is even.
static func pick(level: Dictionary, kind: String, cell: Vector2i) -> String:
	var list := names(level, kind)
	var columns := int(level.get("columns", 0))
	var rows := int(level.get("rows", 0))
	if cell.x == 0 or cell.y == 0 or cell.x == columns - 1 or cell.y == rows - 1:
		return str(list[0])
	return str(list[absi(hash(cell)) % list.size()])

static func path(name: String) -> String:
	return "res://assets/obstacles/%s/00.png" % name

static func texture(level: Dictionary, kind: String, cell: Vector2i) -> Texture2D:
	var file := path(pick(level, kind, cell))
	return load(file) if ResourceLoader.exists(file) else null

## A wall ("wall") or crate ("crate") sprite for `cell`, `tile` pixels wide.
static func sprite(level: Dictionary, kind: String, cell: Vector2i, tile: float) -> Sprite2D:
	var block := Sprite2D.new()
	block.texture = texture(level, kind, cell)
	if block.texture:
		block.scale = Vector2.ONE * tile / float(block.texture.get_width())
	return block
